import 'dart:convert';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/data_models.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../widgets/custom_pickers.dart';
import '../services/data_manager.dart'; 
import 'period_detail_screen.dart';
import 'settings_screen.dart';

class PayPeriodListScreen extends StatefulWidget {
  final bool use24HourFormat;
  final bool isDarkMode;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  
  final Function({
    bool? isDark, 
    bool? is24h, 
    bool? hideMoney,
    String? currencySymbol,
    TimeOfDay? shiftStart, 
    TimeOfDay? shiftEnd
  }) onUpdateSettings;

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
  final NumberFormat currencyFormatter = NumberFormat("#,##0.00", "en_US");
  bool _isUnsynced = false; 

  // Settings State
  bool _hideMoney = false;
  String _currencySymbol = '₱';

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final manager = Provider.of<DataManager>(context, listen: false);
      manager.addListener(() {
        if (mounted) _loadData();
      });
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _hideMoney = prefs.getBool('setting_hide_money') ?? false;
      _currencySymbol = prefs.getString('setting_currency_symbol') ?? '₱';
    });

    String? data = prefs.getString('pay_tracker_data');
    if (data == null) data = prefs.getString(kStorageKey); 

    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
        });
      } catch (e) { }
    } else {
      setState(() { periods = []; });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = periods.map((e) => e.toJson()).toList();
    final String jsonData = jsonEncode(jsonList);
    
    await prefs.setString(kStorageKey, jsonData);
    await prefs.setString('pay_tracker_data', jsonData);
    setState(() { _isUnsynced = true; });
  }

  String _getMoneyText(double amount) {
    if (_hideMoney) return "****.**";
    return "$_currencySymbol${currencyFormatter.format(amount)}";
  }

  void _performManualSync() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Row(children: [CircularProgressIndicator(strokeWidth: 2), SizedBox(width: 10), Text("Syncing...")]), duration: Duration(seconds: 1))
    );
    final List<Map<String, dynamic>> localJson = periods.map((e) => e.toJson()).toList();
    String result = await manager.smartSync(localJson);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!result.contains("Error")) setState(() => _isUnsynced = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: result.contains("Error") ? Colors.red : Colors.green));
    }
  }

  void _confirmDeletePeriod(int index) {
    showConfirmationDialog(context: context, title: "Delete Cutoff?", content: "Are you sure you want to delete ${periods[index].name}?", isDestructive: true, onConfirm: () {
      playClickSound(context);
      setState(() { periods.removeAt(index); });
      _saveData();
    });
  }

  void _editPeriodDates(PayPeriod period) async {
    playClickSound(context);
    DateTime? newStart = await showFastDatePicker(context, period.start);
    if (newStart == null) return;
    if (!mounted) return;
    DateTime? newEnd = await showFastDatePicker(context, period.end, minDate: newStart);
    if (newEnd == null) return;
    setState(() {
      period.start = newStart; period.end = newEnd;
      period.updateName(); period.lastEdited = DateTime.now();
    });
    _saveData();
  }

  void _openSettings() {
    playClickSound(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
      isDarkMode: widget.isDarkMode,
      use24HourFormat: widget.use24HourFormat,
      hideMoney: _hideMoney,
      currencySymbol: _currencySymbol,
      shiftStart: widget.shiftStart,
      shiftEnd: widget.shiftEnd,
      onUpdate: ({isDark, is24h, hideMoney, currencySymbol, shiftStart, shiftEnd}) async {
        final prefs = await SharedPreferences.getInstance();
        if (hideMoney != null) {
          setState(() => _hideMoney = hideMoney);
          prefs.setBool('setting_hide_money', hideMoney);
        }
        if (currencySymbol != null) {
          setState(() => _currencySymbol = currencySymbol);
          prefs.setString('setting_currency_symbol', currencySymbol);
        }
        widget.onUpdateSettings(isDark: isDark, is24h: is24h, shiftStart: shiftStart, shiftEnd: shiftEnd);
      },
      onDeleteAll: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(kStorageKey); await prefs.remove('pay_tracker_data');
          setState(() { periods = []; });
          if (mounted) Provider.of<DataManager>(context, listen: false).syncPayrollToCloud([]);
      },
      onExportReport: () {}, onBackup: () {}, onRestore: (s) {},
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
    final newPeriod = PayPeriod(id: const Uuid().v4(), name: "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}", start: start, end: end, lastEdited: DateTime.now(), hourlyRate: 50.0, shifts: []);
    setState(() { periods.insert(0, newPeriod); periods.sort((a, b) => b.start.compareTo(a.start)); });
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
      shiftStart: widget.shiftStart, shiftEnd: widget.shiftEnd,
      hideMoney: _hideMoney,
      currencySymbol: _currencySymbol,
    )));
    _saveData();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataManager>(
      builder: (context, dataManager, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Payroll", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            centerTitle: false, elevation: 0,
            actions: [
              // 1. SYNC BUTTON
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: Icon(CupertinoIcons.cloud_upload, color: Theme.of(context).iconTheme.color), 
                    onPressed: (!dataManager.isGuest) ? _performManualSync : () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login required to sync."))); },
                  ),
                  if (_isUnsynced && !dataManager.isGuest)
                    Positioned(right: 8, top: 8, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                ],
              ),
              // 2. SETTINGS
              IconButton(icon: const Icon(CupertinoIcons.settings), onPressed: _openSettings),

              // 3. LOGOUT / PROFILE (RESTORED)
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: dataManager.userPhoto != null ? NetworkImage(dataManager.userPhoto!) : null,
                  child: dataManager.userPhoto == null ? const Icon(CupertinoIcons.person_solid, size: 16, color: Colors.white) : null,
                ),
                itemBuilder: (context) {
                  if (dataManager.isGuest) {
                    return [const PopupMenuItem(value: 'login', child: Text("Log In to Sync"))];
                  }
                  return [
                    PopupMenuItem(enabled: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Signed in as:", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(dataManager.userEmail ?? "User", style: TextStyle(fontWeight: FontWeight.bold))])),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, color: Colors.red, size: 20), SizedBox(width: 8), Text("Logout", style: TextStyle(color: Colors.red))])),
                  ];
                },
                onSelected: (value) {
                  if (value == 'logout') {
                    dataManager.logout().then((_) { if (mounted) _loadData(); });
                  } else if (value == 'login') {
                     dataManager.logout(); 
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: periods.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.money_dollar_circle, size: 80, color: Colors.grey[300]), const SizedBox(height: 20), Text("No Payrolls Yet", style: TextStyle(color: Colors.grey[600], fontSize: 16)), const SizedBox(height: 10), CupertinoButton(color: Theme.of(context).colorScheme.primary, onPressed: _createNewPeriod, child: const Text("Create New"))]))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 80),
                  itemCount: periods.length,
                  itemBuilder: (context, index) {
                    final p = periods[index];
                    final totalPay = p.getTotalPay(widget.shiftStart, widget.shiftEnd);

                    return Dismissible(
                      key: Key(p.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (dir) async { bool delete = false; await showConfirmationDialog(context: context, title: "Delete?", content: "Remove ${p.name}?", isDestructive: true, onConfirm: () => delete = true); return delete; },
                      onDismissed: (d) => _confirmDeletePeriod(index),
                      child: GestureDetector(
                        onTap: () => _openPeriod(p),
                        onLongPress: () { HapticFeedback.mediumImpact(); _editPeriodDates(p); },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left Side: Just Name and Shifts Count (CLEANER)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 6),
                                    Text(
                                      "${p.shifts.length} Shifts", 
                                      style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Right Side: Money
                              Container(
                                width: 110,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _getMoneyText(totalPay),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.green),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(onPressed: _createNewPeriod, backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(CupertinoIcons.add, color: Colors.white)),
        );
      },
    );
  }
}