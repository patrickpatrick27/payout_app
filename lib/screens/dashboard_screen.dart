import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/data_models.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../widgets/custom_pickers.dart';
import 'period_detail_screen.dart';
import 'settings_screen.dart';

class PayPeriodListScreen extends StatefulWidget {
  final bool use24HourFormat;
  final bool isDarkMode;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final Function({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) onUpdateSettings;

  const PayPeriodListScreen({
    super.key, 
    required this.use24HourFormat, 
    required this.isDarkMode,
    required this.shiftStart,
    required this.shiftEnd,
    required this.onUpdateSettings,
  });

  @override
  State<PayPeriodListScreen> createState() => _PayPeriodListScreenState();
}

class _PayPeriodListScreenState extends State<PayPeriodListScreen> {
  List<PayPeriod> periods = [];
  final NumberFormat currency = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(kStorageKey);
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
        });
      } catch (e) { }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(periods.map((e) => e.toJson()).toList());
    await prefs.setString(kStorageKey, data);
  }

  // --- EXPORT FOR HUMANS ---
  void _exportReportText() {
    StringBuffer sb = StringBuffer();
    for (var p in periods) {
      sb.writeln("${p.name} (Total: ₱ ${currency.format(p.getTotalPay(widget.shiftStart, widget.shiftEnd))})");
      List<Shift> sortedShifts = List.from(p.shifts);
      sortedShifts.sort((a,b) => a.date.compareTo(b.date));

      for (var s in sortedShifts) {
        String dateStr = DateFormat('MMM d').format(s.date);
        if (s.isManualPay) {
          sb.writeln("$dateStr: Flat Pay (₱ ${currency.format(s.manualAmount)})");
        } else {
          String tIn = formatTime(context, s.rawTimeIn, widget.use24HourFormat);
          String tOut = formatTime(context, s.rawTimeOut, widget.use24HourFormat);
          double reg = s.getRegularHours(widget.shiftStart, widget.shiftEnd);
          double ot = s.getOvertimeHours(widget.shiftStart, widget.shiftEnd);
          sb.writeln("$dateStr: $tIn to $tOut (REG: ${reg.toStringAsFixed(1)}h, OT: ${ot.toStringAsFixed(1)}h)");
        }
      }
      sb.writeln("\n"); 
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Readable Report copied!"), backgroundColor: Colors.green));
  }

  // --- BACKUP FOR APP TRANSFER (JSON) ---
  void _backupDataJSON() {
    // 1. Encode the entire list of objects to JSON
    String jsonString = jsonEncode(periods.map((e) => e.toJson()).toList());
    
    // 2. Copy to clipboard
    Clipboard.setData(ClipboardData(text: jsonString));
    
    // 3. Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Backup Code copied! Paste this into the new app."), 
        backgroundColor: Colors.teal
      )
    );
  }

  // --- RESTORE FROM BACKUP ---
  void _restoreDataJSON(String jsonString) {
    try {
      // 1. Try decoding the string
      final List<dynamic> decoded = jsonDecode(jsonString);
      
      // 2. Convert to Objects
      List<PayPeriod> importedPeriods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
      
      // 3. Merge Logic (Avoid duplicates based on ID)
      int addedCount = 0;
      for (var imported in importedPeriods) {
        // Check if we already have this period (by ID)
        bool exists = periods.any((existing) => existing.id == imported.id);
        if (!exists) {
          periods.add(imported);
          addedCount++;
        }
      }

      // 4. Save and Sort
      if (addedCount > 0) {
        _sortPeriods('newest'); // This saves internally
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully restored $addedCount records!"), backgroundColor: Colors.green)
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No new data found in backup (Duplicate IDs)."), backgroundColor: Colors.orange)
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invalid Backup Code! Error: $e"), backgroundColor: Colors.red)
      );
    }
  }

  void _deleteAllData() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Everything?"),
        content: const Text("This will permanently wipe all your data."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kStorageKey);
      setState(() { periods.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All data deleted."), backgroundColor: Colors.red));
    }
  }

  void _sortPeriods(String type) {
    // Only play sound if context is valid (prevents errors during background sorting)
    if (mounted) playClickSound(context); 
    
    setState(() {
      if (type == 'newest') periods.sort((a, b) => b.start.compareTo(a.start));
      else if (type == 'oldest') periods.sort((a, b) => a.start.compareTo(b.start)); 
      else if (type == 'edited') periods.sort((a, b) => b.lastEdited.compareTo(a.lastEdited));
    });
    _saveData();
  }

  void _openSettings() {
    playClickSound(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
      isDarkMode: widget.isDarkMode,
      use24HourFormat: widget.use24HourFormat,
      shiftStart: widget.shiftStart,
      shiftEnd: widget.shiftEnd,
      onUpdate: widget.onUpdateSettings,
      onDeleteAll: _deleteAllData,
      onExportReport: _exportReportText,
      onBackup: _backupDataJSON,
      onRestore: _restoreDataJSON,
    )));
  }

  void _createNewPeriod() async {
    DateTime now = DateTime.now();
    DateTime defaultStart = (now.day <= 15) ? DateTime(now.year, now.month, 1) : DateTime(now.year, now.month, 16);
    playClickSound(context);
    DateTime? start = await showFastDatePicker(context, defaultStart);
    if (start == null) return;
    if (!mounted) return;
    
    int lastDayOfMonth = DateTime(start.year, start.month + 1, 0).day;
    DateTime defaultEnd = (start.day <= 15) ? DateTime(start.year, start.month, 15) : DateTime(start.year, start.month, lastDayOfMonth);
    if (defaultEnd.isBefore(start)) defaultEnd = DateTime(start.year, start.month, lastDayOfMonth);

    DateTime? end = await showFastDatePicker(context, defaultEnd, minDate: start);
    if (end == null) return;

    final newPeriod = PayPeriod(
      id: const Uuid().v4(),
      name: "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}",
      start: start, end: end, lastEdited: DateTime.now(), hourlyRate: 50.0, shifts: [],
    );
    setState(() {
      periods.insert(0, newPeriod);
      periods.sort((a, b) => b.start.compareTo(a.start));
    });
    _saveData();
    _openPeriod(newPeriod);
  }

  void _openPeriod(PayPeriod period) async {
    playClickSound(context);
    period.lastEdited = DateTime.now();
    _saveData();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PeriodDetailScreen(
      period: period, 
      use24HourFormat: widget.use24HourFormat,
      shiftStart: widget.shiftStart,
      shiftEnd: widget.shiftEnd,
    )));
    _saveData();
    setState(() {});
  }
  
  void _deletePeriod(int index) {
    playClickSound(context);
    setState(() { periods.removeAt(index); });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payroll Cutoffs"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: _sortPeriods,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest First')),
              PopupMenuItem(value: 'oldest', child: Text('Oldest First')),
              PopupMenuItem(value: 'edited', child: Text('Recent Edits')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          )
        ],
      ),
      body: periods.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  Text("No Pay Trackers Found", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _createNewPeriod,
                    icon: const Icon(Icons.add),
                    label: const Text("Create New Tracker"),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                  )
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: periods.length,
              onReorder: (oldIndex, newIndex) {
                playClickSound(context);
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = periods.removeAt(oldIndex);
                  periods.insert(newIndex, item);
                });
                _saveData();
              },
              itemBuilder: (context, index) {
                final p = periods[index];
                return Dismissible(
                  key: Key(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    playClickSound(context);
                    return await showDialog(context: context, builder: (ctx) => AlertDialog(
                      title: const Text("Delete Tracker?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                      ],
                    ));
                  },
                  onDismissed: (direction) => _deletePeriod(index),
                  child: GestureDetector(
                    onTap: () => _openPeriod(p),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                const SizedBox(height: 4),
                                Text("${p.shifts.length} shifts", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("TOTAL PAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                Text("₱${currency.format(p.getTotalPay(widget.shiftStart, widget.shiftEnd))}",
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewPeriod,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}