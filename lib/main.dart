import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// --- DATA KEY ---
const String kStorageKey = 'pay_tracker_final_db';

void main() {
  runApp(const PayTrackerApp());
}

class PayTrackerApp extends StatelessWidget {
  const PayTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pay Tracker Pro',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5), // Indigo
          brightness: Brightness.light,
          primary: const Color(0xFF304FFE),
          secondary: const Color(0xFF00BFA5),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const PayPeriodListScreen(),
    );
  }
}

// --- SOUND HELPER ---
void playClickSound(BuildContext context) {
  Feedback.forTap(context);
  SystemSound.play(SystemSoundType.click);
}

// --- LOGIC HELPERS ---

TimeOfDay roundTime(TimeOfDay time, {required bool isStart}) {
  int totalMinutes = time.hour * 60 + time.minute;
  int remainder = totalMinutes % 30;
  int roundedMinutes = totalMinutes;

  if (remainder != 0) {
    if (isStart) {
      roundedMinutes = totalMinutes + (30 - remainder);
    } else {
      roundedMinutes = totalMinutes - remainder;
    }
  }

  int h = (roundedMinutes ~/ 60) % 24;
  int m = roundedMinutes % 60;
  
  if (isStart && h < 8) {
    return const TimeOfDay(hour: 8, minute: 0);
  }

  return TimeOfDay(hour: h, minute: m);
}

// --- DATA MODELS ---

class Shift {
  String id;
  DateTime date;
  TimeOfDay rawTimeIn;
  TimeOfDay rawTimeOut;
  bool isManualPay; 
  double manualAmount;

  Shift({
    required this.id,
    required this.date,
    required this.rawTimeIn,
    required this.rawTimeOut,
    this.isManualPay = false,
    this.manualAmount = 0.0,
  });

  TimeOfDay get paidTimeIn => roundTime(rawTimeIn, isStart: true);
  TimeOfDay get paidTimeOut => roundTime(rawTimeOut, isStart: false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'rawTimeIn': '${rawTimeIn.hour}:${rawTimeIn.minute}',
        'rawTimeOut': '${rawTimeOut.hour}:${rawTimeOut.minute}',
        'isManualPay': isManualPay,
        'manualAmount': manualAmount,
      };

  factory Shift.fromJson(Map<String, dynamic> json) {
    final tIn = json['rawTimeIn'].split(':');
    final tOut = json['rawTimeOut'].split(':');
    return Shift(
      id: json['id'],
      date: DateTime.parse(json['date']),
      rawTimeIn: TimeOfDay(hour: int.parse(tIn[0]), minute: int.parse(tIn[1])),
      rawTimeOut: TimeOfDay(hour: int.parse(tOut[0]), minute: int.parse(tOut[1])),
      isManualPay: json['isManualPay'] ?? false,
      manualAmount: (json['manualAmount'] ?? 0.0).toDouble(),
    );
  }

  double get hoursWorked {
    if (isManualPay) return 0; 

    double start = paidTimeIn.hour + paidTimeIn.minute / 60.0;
    double end = paidTimeOut.hour + paidTimeOut.minute / 60.0;
    if (end < start) end += 24; 

    double duration = end - start;
    if (start <= 12.0 && end >= 13.0) duration -= 1.0; 

    return duration > 0 ? duration : 0;
  }

  double get regularHours => hoursWorked > 8 ? 8 : hoursWorked;
  double get overtimeHours => hoursWorked > 8 ? hoursWorked - 8 : 0;
}

class PayPeriod {
  String id;
  String name;
  DateTime start;
  DateTime end;
  DateTime lastEdited; 
  double hourlyRate;
  List<Shift> shifts;

  PayPeriod({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.lastEdited,
    required this.hourlyRate,
    required this.shifts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'lastEdited': lastEdited.toIso8601String(),
        'hourlyRate': hourlyRate,
        'shifts': shifts.map((s) => s.toJson()).toList(),
      };

  factory PayPeriod.fromJson(Map<String, dynamic> json) {
    return PayPeriod(
      id: json['id'],
      name: json['name'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      lastEdited: json['lastEdited'] != null ? DateTime.parse(json['lastEdited']) : DateTime.now(),
      hourlyRate: json['hourlyRate'].toDouble(),
      shifts: (json['shifts'] as List).map((s) => Shift.fromJson(s)).toList(),
    );
  }

  double get totalRegularHours {
    double sum = 0;
    for (var shift in shifts) if(!shift.isManualPay) sum += shift.regularHours;
    return sum;
  }

  double get totalOvertimeHours {
    double sum = 0;
    for (var shift in shifts) if(!shift.isManualPay) sum += shift.overtimeHours;
    return sum;
  }

  double get totalPay {
    double total = 0;
    for (var shift in shifts) {
      if (shift.isManualPay) {
        total += shift.manualAmount;
      } else {
        total += (shift.regularHours * hourlyRate) + 
                 (shift.overtimeHours * hourlyRate * 1.25);
      }
    }
    return total;
  }
  
  void updateName() {
    name = "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}";
  }
}

// --- FAST DATE PICKER ---
Future<DateTime?> showFastDatePicker(BuildContext context, DateTime initial, {DateTime? minDate, DateTime? maxDate}) async {
  playClickSound(context);
  DateTime safeInitial = initial;
  if (minDate != null && initial.isBefore(minDate)) safeInitial = minDate;
  if (maxDate != null && initial.isAfter(maxDate)) safeInitial = maxDate;

  DateTime tempDate = safeInitial;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (BuildContext builder) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.red)), onPressed: () => Navigator.of(context).pop()),
                  const Text("Select Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(
                    child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)), 
                    onPressed: () {
                      playClickSound(context);
                      Navigator.of(context).pop(tempDate);
                    }
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: safeInitial,
                minimumDate: minDate ?? DateTime(2020),
                maximumDate: maxDate ?? DateTime(2030),
                onDateTimeChanged: (DateTime newDate) => tempDate = newDate,
              ),
            ),
          ],
        ),
      );
    }
  );
}

Future<TimeOfDay?> showFastTimePicker(BuildContext context, TimeOfDay initial) async {
  playClickSound(context);
  Duration tempDuration = Duration(hours: initial.hour, minutes: initial.minute);
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (BuildContext builder) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(child: const Text('Cancel', style: TextStyle(color: Colors.red)), onPressed: () => Navigator.of(context).pop()),
                  const Text("Select Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(
                    child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)), 
                    onPressed: () {
                       playClickSound(context);
                       Navigator.of(context).pop(TimeOfDay(hour: tempDuration.inHours % 24, minute: tempDuration.inMinutes % 60));
                    }
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: tempDuration,
                onTimerDurationChanged: (Duration newDuration) => tempDuration = newDuration,
              ),
            ),
          ],
        ),
      );
    }
  );
}

// --- SCREEN 1: DASHBOARD ---

class PayPeriodListScreen extends StatefulWidget {
  const PayPeriodListScreen({super.key});

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
      } catch (e) {
        // ignore error
      }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(periods.map((e) => e.toJson()).toList());
    await prefs.setString(kStorageKey, data);
  }

  // --- SETTINGS ACTIONS ---
  
  void _exportData() {
    StringBuffer sb = StringBuffer();

    for (var p in periods) {
      sb.writeln("CUTOFF: ${p.name}");
      sb.writeln("TOTAL PAY: ₱ ${currency.format(p.totalPay)}");
      sb.writeln("--------------------------------");
      
      // Sort shifts by date for cleaner export
      List<Shift> sortedShifts = List.from(p.shifts);
      sortedShifts.sort((a,b) => a.date.compareTo(b.date));

      for (var s in sortedShifts) {
        String dateStr = DateFormat('MMM d').format(s.date);
        
        if (s.isManualPay) {
          sb.writeln("$dateStr: Flat Pay (₱ ${currency.format(s.manualAmount)})");
        } else {
          String tIn = s.rawTimeIn.format(context);
          String tOut = s.rawTimeOut.format(context);
          sb.writeln("$dateStr: $tIn to $tOut (REG: ${s.regularHours}h, OT: ${s.overtimeHours}h)");
        }
      }
      sb.writeln("\n"); // Empty line between periods
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Formatted Report copied to clipboard!"), backgroundColor: Colors.green)
    );
  }

  void _deleteAllData() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Everything?"),
        content: const Text("This will permanently wipe all your data. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DELETE ALL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      )
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kStorageKey);
      setState(() {
        periods.clear();
      });
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All data deleted."), backgroundColor: Colors.red)
      );
    }
  }

  // --- SORTING ---
  void _sortPeriods(String type) {
    playClickSound(context);
    setState(() {
      if (type == 'newest') {
        periods.sort((a, b) => b.start.compareTo(a.start)); // Newest (Jan) First
      } else if (type == 'oldest') {
        periods.sort((a, b) => a.start.compareTo(b.start)); // Oldest (Dec) First
      } else if (type == 'edited') {
        periods.sort((a, b) => b.lastEdited.compareTo(a.lastEdited)); // Recently Edited First
      }
    });
    _saveData();
  }

  void _createNewPeriod() async {
    DateTime now = DateTime.now();
    DateTime defaultStart;
    
    if (now.day <= 15) {
      defaultStart = DateTime(now.year, now.month, 1);
    } else {
      defaultStart = DateTime(now.year, now.month, 16);
    }

    playClickSound(context);
    DateTime? start = await showFastDatePicker(context, defaultStart);
    if (start == null) return;

    if (!mounted) return;
    DateTime defaultEnd;
    int lastDayOfMonth = DateTime(start.year, start.month + 1, 0).day;

    if (start.day <= 15) {
      defaultEnd = DateTime(start.year, start.month, 15);
      if (defaultEnd.isBefore(start) || start.day == 15) {
         defaultEnd = DateTime(start.year, start.month, lastDayOfMonth);
      }
    } else {
      defaultEnd = DateTime(start.year, start.month, lastDayOfMonth);
    }

    DateTime? end = await showFastDatePicker(context, defaultEnd, minDate: start);
    if (end == null) return;

    final newPeriod = PayPeriod(
      id: const Uuid().v4(),
      name: "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}",
      start: start,
      end: end,
      lastEdited: DateTime.now(),
      hourlyRate: 50.0, 
      shifts: [],
    );
    setState(() {
      periods.insert(0, newPeriod);
      // Default sort to Newest First
      periods.sort((a, b) => b.start.compareTo(a.start));
    });
    _saveData();
    _openPeriod(newPeriod);
  }

  void _openPeriod(PayPeriod period) async {
    playClickSound(context);
    period.lastEdited = DateTime.now();
    _saveData();

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeriodDetailScreen(period: period)),
    );
    _saveData(); 
    setState(() {});
  }

  void _editPeriodDates(PayPeriod p) async {
    playClickSound(context);
    DateTime? newStart = await showFastDatePicker(context, p.start);
    if (newStart == null) return;

    if (!mounted) return;
    DateTime? newEnd = await showFastDatePicker(context, p.end, minDate: newStart);
    if (newEnd == null) return;

    setState(() {
      p.start = newStart;
      p.end = newEnd;
      p.updateName();
      p.lastEdited = DateTime.now();
      // Re-sort after edit
      periods.sort((a, b) => b.start.compareTo(a.start)); 
    });
    _saveData();
  }

  void _deletePeriod(int index) {
    playClickSound(context);
    setState(() {
      periods.removeAt(index);
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pay Dashboard"),
        actions: [
          // SORT MENU
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: _sortPeriods,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'newest', child: Text('Newest First (Default)')),
              const PopupMenuItem<String>(value: 'oldest', child: Text('Oldest First')),
              const PopupMenuItem<String>(value: 'edited', child: Text('Recent Edits')),
            ],
          ),
          // SETTINGS MENU (Export / Delete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (val) {
              if (val == 'export') _exportData();
              if (val == 'delete') _deleteAllData();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'export', child: Row(children: [Icon(Icons.copy, color: Colors.grey), SizedBox(width: 8), Text("Copy Report to Clipboard")])),
              const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, color: Colors.red), SizedBox(width: 8), Text("Delete All Data", style: TextStyle(color: Colors.red))])),
            ],
          ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
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
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    playClickSound(context);
                    return await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Delete Tracker?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                        ],
                      )
                    );
                  },
                  onDismissed: (direction) => _deletePeriod(index),
                  child: GestureDetector(
                    onLongPress: () => _editPeriodDates(p), 
                    onTap: () => _openPeriod(p),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(width: 5),
                                    Icon(Icons.edit, size: 12, color: Colors.grey[400])
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text("${p.shifts.length} shifts", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("TOTAL PAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                Text(
                                  "₱${currency.format(p.totalPay)}",
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

// --- SCREEN 2: DETAILS ---

class PeriodDetailScreen extends StatefulWidget {
  final PayPeriod period;
  const PeriodDetailScreen({super.key, required this.period});

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  late TextEditingController _rateController;
  final NumberFormat currency = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(text: widget.period.hourlyRate.toString());
  }

  void _editPeriodDates() async {
    playClickSound(context);
    DateTime? newStart = await showFastDatePicker(context, widget.period.start);
    if (newStart == null) return;

    if (!mounted) return;
    DateTime? newEnd = await showFastDatePicker(context, widget.period.end, minDate: newStart);
    if (newEnd == null) return;

    setState(() {
      widget.period.start = newStart;
      widget.period.end = newEnd;
      widget.period.updateName();
      widget.period.lastEdited = DateTime.now();
    });
  }

  void _showShiftDialog({Shift? existingShift}) async {
    playClickSound(context);

    DateTime tempDate = existingShift?.date ?? widget.period.start;
    if (existingShift == null) {
       DateTime now = DateTime.now();
       if (now.isAfter(widget.period.start) && now.isBefore(widget.period.end)) {
         tempDate = now;
       }
    }

    TimeOfDay tIn = existingShift?.rawTimeIn ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay tOut = existingShift?.rawTimeOut ?? const TimeOfDay(hour: 17, minute: 0);
    bool isManual = existingShift?.isManualPay ?? false;
    TextEditingController manualCtrl = TextEditingController(text: existingShift?.manualAmount.toString() ?? "0");

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(existingShift == null ? "Add Shift" : "Edit Shift", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))
                    ],
                  ),
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTap: () async {
                      DateTime? picked = await showFastDatePicker(context, tempDate);
                      if (picked != null) setModalState(() => tempDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.blue),
                          const SizedBox(width: 12),
                          Text("Date: ", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                          Text(DateFormat('MMM d, yyyy').format(tempDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          const Icon(Icons.edit, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("I don't know my time", style: TextStyle(fontWeight: FontWeight.w500)),
                      Switch(
                        value: isManual, 
                        activeColor: Colors.blue,
                        onChanged: (val) {
                          playClickSound(context);
                          setModalState(() => isManual = val);
                        }
                      ),
                    ],
                  ),
                  
                  const Divider(height: 24),

                  if (!isManual) ...[
                     Row(
                       children: [
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tIn);
                               if (t!=null) setModalState(() => tIn = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("TIME IN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(tIn.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                               ),
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tOut);
                               if (t!=null) setModalState(() => tOut = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("TIME OUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(tOut.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                               ),
                             ),
                           ),
                         ),
                       ],
                     ),
                  ] else ...[
                     TextField(
                       controller: manualCtrl,
                       keyboardType: TextInputType.number,
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                       decoration: const InputDecoration(
                         labelText: "Enter Amount",
                         border: OutlineInputBorder(),
                         prefixText: "₱ "
                       ),
                     )
                  ],

                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary, 
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: const Text("SAVE SHIFT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      onPressed: () {
                         playClickSound(context);
                         Navigator.pop(context, true);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      }
    ).then((saved) {
      if (saved == true) {
        bool isDuplicate = widget.period.shifts.any((s) => 
          s.id != (existingShift?.id ?? "") && 
          s.date.year == tempDate.year && 
          s.date.month == tempDate.month && 
          s.date.day == tempDate.day
        );

        if (isDuplicate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Date overlap! Please edit the existing shift."), backgroundColor: Colors.red),
          );
          return;
        }

        setState(() {
          if (existingShift != null) {
            existingShift.date = tempDate;
            existingShift.rawTimeIn = tIn;
            existingShift.rawTimeOut = tOut;
            existingShift.isManualPay = isManual;
            existingShift.manualAmount = double.tryParse(manualCtrl.text) ?? 0.0;
          } else {
            widget.period.shifts.add(Shift(
              id: const Uuid().v4(),
              date: tempDate,
              rawTimeIn: tIn,
              rawTimeOut: tOut,
              isManualPay: isManual,
              manualAmount: double.tryParse(manualCtrl.text) ?? 0.0,
            ));
          }
          widget.period.shifts.sort((a, b) => b.date.compareTo(a.date));
          widget.period.lastEdited = DateTime.now();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editPeriodDates,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.period.name),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // FIXED HEADER
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("HOURLY RATE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _rateController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(border: InputBorder.none, prefixText: "₱ "),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            setState(() {
                              widget.period.hourlyRate = double.tryParse(val) ?? 50;
                              widget.period.lastEdited = DateTime.now();
                            });
                          },
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                Text("₱ ${currency.format(widget.period.totalPay)}", 
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)
                ),
                const Text("TOTAL PAYOUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                
                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatBox("REGULAR HRS", widget.period.totalRegularHours.toStringAsFixed(1), Colors.black87),
                    Container(width: 1, height: 30, color: Colors.grey[300]),
                    _buildStatBox("OVERTIME HRS", widget.period.totalOvertimeHours.toStringAsFixed(1), Colors.blue),
                  ],
                )
              ],
            ),
          ),

          // LIST VIEW
          Expanded(
            child: widget.period.shifts.isEmpty 
              ? Center(child: Text("Tap '+' to add a work day", style: TextStyle(color: Colors.grey[400])))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 20, bottom: 100, left: 16, right: 16),
                  itemCount: widget.period.shifts.length,
                  itemBuilder: (ctx, i) {
                    final s = widget.period.shifts[i];
                    bool isInside = !s.date.isBefore(widget.period.start) && !s.date.isAfter(widget.period.end);
                    
                    return Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        playClickSound(context);
                        setState(() {
                          widget.period.shifts.removeAt(i);
                          widget.period.lastEdited = DateTime.now();
                        });
                      },
                      child: GestureDetector(
                        onTap: () => _showShiftDialog(existingShift: s), 
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isInside ? Colors.white : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: isInside ? null : Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isInside ? Theme.of(context).colorScheme.secondary.withOpacity(0.1) : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Text(DateFormat('MMM').format(s.date).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isInside ? Theme.of(context).colorScheme.secondary : Colors.grey)),
                                    Text(DateFormat('dd').format(s.date), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isInside ? Theme.of(context).colorScheme.secondary : Colors.grey)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.isManualPay)
                                      Row(
                                        children: [
                                          Icon(Icons.edit_note, color: Colors.orange[800], size: 18),
                                          const SizedBox(width: 4),
                                          Text("Manual Adjustment", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
                                        ],
                                      )
                                    else
                                      Row(
                                        children: [
                                          Text("${s.rawTimeIn.format(context)} - ${s.rawTimeOut.format(context)}", 
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[800])
                                          ),
                                          if (s.paidTimeIn != s.rawTimeIn || s.paidTimeOut != s.rawTimeOut)
                                            const Padding(
                                              padding: EdgeInsets.only(left: 6),
                                              child: Icon(Icons.auto_fix_high, size: 14, color: Colors.amber),
                                            )
                                        ],
                                      ),
                                    const SizedBox(height: 4),
                                    if (s.isManualPay)
                                      Text("Flat Pay: ₱${currency.format(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                                    else
                                      RichText(
                                        text: TextSpan(
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          children: [
                                            TextSpan(text: "Reg: ${s.regularHours.toStringAsFixed(1)}"),
                                            if (s.overtimeHours > 0)
                                              TextSpan(text: " • OT: ${s.overtimeHours.toStringAsFixed(1)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                          ]
                                        ),
                                      )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShiftDialog(), 
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Shift", style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }
}