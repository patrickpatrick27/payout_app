import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// --- DATA KEYS ---
const String kStorageKey = 'pay_tracker_final_db';
const String kSetting24h = 'setting_24h';
const String kSettingDarkMode = 'setting_dark_mode';
const String kSettingShiftStart = 'setting_shift_start';
const String kSettingShiftEnd = 'setting_shift_end';

void main() {
  runApp(const PayTrackerApp());
}

class PayTrackerApp extends StatefulWidget {
  const PayTrackerApp({super.key});

  @override
  State<PayTrackerApp> createState() => _PayTrackerAppState();
}

class _PayTrackerAppState extends State<PayTrackerApp> {
  // Global App Settings
  bool use24HourFormat = false;
  bool isDarkMode = false;
  TimeOfDay globalShiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay globalShiftEnd = const TimeOfDay(hour: 17, minute: 0); // 5:00 PM

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      use24HourFormat = prefs.getBool(kSetting24h) ?? false;
      isDarkMode = prefs.getBool(kSettingDarkMode) ?? false;
      
      String? startStr = prefs.getString(kSettingShiftStart);
      if (startStr != null) {
        final parts = startStr.split(':');
        globalShiftStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      String? endStr = prefs.getString(kSettingShiftEnd);
      if (endStr != null) {
        final parts = endStr.split(':');
        globalShiftEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    });
  }

  void _updateSettings({
    bool? isDark, 
    bool? is24h, 
    TimeOfDay? shiftStart, 
    TimeOfDay? shiftEnd
  }) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (isDark != null) {
        isDarkMode = isDark;
        prefs.setBool(kSettingDarkMode, isDark);
      }
      if (is24h != null) {
        use24HourFormat = is24h;
        prefs.setBool(kSetting24h, is24h);
      }
      if (shiftStart != null) {
        globalShiftStart = shiftStart;
        prefs.setString(kSettingShiftStart, "${shiftStart.hour}:${shiftStart.minute}");
      }
      if (shiftEnd != null) {
        globalShiftEnd = shiftEnd;
        prefs.setString(kSettingShiftEnd, "${shiftEnd.hour}:${shiftEnd.minute}");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pay Tracker Pro',
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        cardColor: Colors.white,
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF536DFE),
          onPrimary: Colors.white,
          secondary: Color(0xFF00BFA5),
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
          background: Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),

      home: PayPeriodListScreen(
        use24HourFormat: use24HourFormat,
        isDarkMode: isDarkMode,
        shiftStart: globalShiftStart,
        shiftEnd: globalShiftEnd,
        onUpdateSettings: _updateSettings,
      ),
    );
  }
}

// --- HELPER FUNCTIONS ---

void playClickSound(BuildContext context) {
  Feedback.forTap(context);
  SystemSound.play(SystemSoundType.click);
}

double timeToDouble(TimeOfDay t) => t.hour + t.minute / 60.0;

String formatTime(BuildContext context, TimeOfDay time, bool use24h) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return DateFormat(use24h ? 'HH:mm' : 'h:mm a').format(dt);
}

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

  TimeOfDay getPaidTimeIn(TimeOfDay globalShiftStart) {
    TimeOfDay rounded = roundTime(rawTimeIn, isStart: true);
    double rVal = timeToDouble(rounded);
    double sVal = timeToDouble(globalShiftStart);
    return (rVal < sVal) ? globalShiftStart : rounded; 
  }

  TimeOfDay getPaidTimeOut() => roundTime(rawTimeOut, isStart: false);

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

  double getRegularHours(TimeOfDay globalStart, TimeOfDay globalEnd) {
    if (isManualPay) return 0;
    double start = timeToDouble(getPaidTimeIn(globalStart));
    double end = timeToDouble(getPaidTimeOut());
    double shiftEnd = timeToDouble(globalEnd);
    double actualRegularEnd = (end > shiftEnd) ? shiftEnd : end;
    if (actualRegularEnd < start) actualRegularEnd += 24;
    double duration = actualRegularEnd - start;
    if (start <= 12.0 && actualRegularEnd >= 13.0) duration -= 1.0; 
    return duration > 0 ? duration : 0;
  }

  double getOvertimeHours(TimeOfDay globalStart, TimeOfDay globalEnd) {
    if (isManualPay) return 0;
    double end = timeToDouble(getPaidTimeOut());
    double shiftEnd = timeToDouble(globalEnd);
    if (end > shiftEnd) return end - shiftEnd;
    return 0;
  }
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
        'id': id, 'name': name, 'start': start.toIso8601String(), 'end': end.toIso8601String(),
        'lastEdited': lastEdited.toIso8601String(), 'hourlyRate': hourlyRate,
        'shifts': shifts.map((s) => s.toJson()).toList(),
      };

  factory PayPeriod.fromJson(Map<String, dynamic> json) {
    return PayPeriod(
      id: json['id'], name: json['name'],
      start: DateTime.parse(json['start']), end: DateTime.parse(json['end']),
      lastEdited: json['lastEdited'] != null ? DateTime.parse(json['lastEdited']) : DateTime.now(),
      hourlyRate: json['hourlyRate'].toDouble(),
      shifts: (json['shifts'] as List).map((s) => Shift.fromJson(s)).toList(),
    );
  }

  double getTotalPay(TimeOfDay start, TimeOfDay end) {
    double total = 0;
    for (var shift in shifts) {
      if (shift.isManualPay) {
        total += shift.manualAmount;
      } else {
        total += (shift.getRegularHours(start, end) * hourlyRate) + 
                 (shift.getOvertimeHours(start, end) * hourlyRate * 1.25);
      }
    }
    return total;
  }

  double getTotalRegularHours(TimeOfDay start, TimeOfDay end) {
    double sum = 0;
    for(var s in shifts) if(!s.isManualPay) sum += s.getRegularHours(start, end);
    return sum;
  }
  
  double getTotalOvertimeHours(TimeOfDay start, TimeOfDay end) {
    double sum = 0;
    for(var s in shifts) if(!s.isManualPay) sum += s.getOvertimeHours(start, end);
    return sum;
  }

  void updateName() {
    name = "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}";
  }
}

// --- SETTINGS SCREEN ---

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final bool use24HourFormat;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final Function({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) onUpdate;
  final VoidCallback onDeleteAll;
  final VoidCallback onExport;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.use24HourFormat,
    required this.shiftStart,
    required this.shiftEnd,
    required this.onUpdate,
    required this.onDeleteAll,
    required this.onExport,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TimeOfDay _localShiftStart;
  late TimeOfDay _localShiftEnd;

  @override
  void initState() {
    super.initState();
    _localShiftStart = widget.shiftStart;
    _localShiftEnd = widget.shiftEnd;
  }

  void _updateTime(bool isStart, TimeOfDay newTime) {
    setState(() {
      if (isStart) _localShiftStart = newTime;
      else _localShiftEnd = newTime;
    });
    widget.onUpdate(
      shiftStart: isStart ? newTime : null,
      shiftEnd: !isStart ? newTime : null
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = Theme.of(context).cardColor;
    
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader("WORK SCHEDULE"),
          _buildTimeTile("Shift Start Time", _localShiftStart, (t) => _updateTime(true, t)),
          _buildTimeTile("Shift End Time", _localShiftEnd, (t) => _updateTime(false, t)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "Note: Hours worked after the Shift End Time are counted as Overtime. Arrivals before Shift Start Time are not counted.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          
          const SizedBox(height: 20),
          _buildSectionHeader("PREFERENCES"),
          SwitchListTile(
            title: const Text("Dark Mode"),
            value: widget.isDarkMode,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(isDark: val),
          ),
          SwitchListTile(
            title: const Text("24-Hour Format"),
            value: widget.use24HourFormat,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(is24h: val),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("DATA MANAGEMENT"),
          ListTile(
            tileColor: bg,
            leading: const Icon(Icons.copy),
            title: const Text("Copy Data Report"),
            onTap: widget.onExport,
          ),
          ListTile(
            tileColor: bg,
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text("Delete All Data", style: TextStyle(color: Colors.red)),
            onTap: widget.onDeleteAll,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 12)),
    );
  }

  Widget _buildTimeTile(String title, TimeOfDay current, Function(TimeOfDay) onSelect) {
    return ListTile(
      tileColor: Theme.of(context).cardColor,
      title: Text(title),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(
          formatTime(context, current, widget.use24HourFormat),
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      onTap: () async {
        playClickSound(context);
        final t = await showFastTimePicker(context, current, widget.use24HourFormat);
        if (t != null) onSelect(t);
      },
    );
  }
}

// --- PICKERS ---

Future<TimeOfDay?> showFastTimePicker(BuildContext context, TimeOfDay initial, bool use24h) async {
  playClickSound(context);
  final now = DateTime.now();
  DateTime tempDate = DateTime(now.year, now.month, now.day, initial.hour, initial.minute);
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (BuildContext builder) {
      return SizedBox(
        height: 280,
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
                    onPressed: () => Navigator.of(context).pop(TimeOfDay.fromDateTime(tempDate))
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: tempDate,
                  use24hFormat: use24h,
                  onDateTimeChanged: (DateTime newDate) => tempDate = newDate,
                ),
              ),
            ),
          ],
        ),
      );
    }
  );
}

Future<DateTime?> showFastDatePicker(BuildContext context, DateTime initial, {DateTime? minDate, DateTime? maxDate}) async {
  playClickSound(context);
  DateTime safeInitial = initial;
  if (minDate != null && initial.isBefore(minDate)) safeInitial = minDate;
  
  DateTime tempDate = safeInitial;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (BuildContext builder) {
      return SizedBox(
        height: 280,
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
                    onPressed: () => Navigator.of(context).pop(tempDate)
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: safeInitial,
                  minimumDate: minDate ?? DateTime(2020),
                  maximumDate: maxDate ?? DateTime(2030),
                  onDateTimeChanged: (DateTime newDate) => tempDate = newDate,
                ),
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

  void _exportData() {
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
          sb.writeln("$dateStr: $tIn to $tOut (REG: ${reg}h, OT: ${ot}h)");
        }
      }
      sb.writeln("\n"); 
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report copied to clipboard!"), backgroundColor: Colors.green));
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
    playClickSound(context);
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
      onExport: _exportData,
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
        title: const Text("Pay Dashboard"),
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

// --- SCREEN 2: DETAILS ---

class PeriodDetailScreen extends StatefulWidget {
  final PayPeriod period;
  final bool use24HourFormat;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  
  const PeriodDetailScreen({
    super.key, 
    required this.period, 
    required this.use24HourFormat,
    required this.shiftStart,
    required this.shiftEnd,
  });

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
      if (now.isAfter(widget.period.start) && now.isBefore(widget.period.end)) tempDate = now;
    }

    TimeOfDay tIn = existingShift?.rawTimeIn ?? widget.shiftStart;
    TimeOfDay tOut = existingShift?.rawTimeOut ?? widget.shiftEnd;
    
    bool isManual = existingShift?.isManualPay ?? false;
    TextEditingController manualCtrl = TextEditingController(text: existingShift?.manualAmount.toString() ?? "0");

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dlgBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: dlgBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
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
                      decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.blue),
                          const SizedBox(width: 12),
                          const Text("Date: ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text(DateFormat('MMM d, yyyy').format(tempDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("I don't know my time", style: TextStyle(fontWeight: FontWeight.w500)),
                      Switch(value: isManual, activeColor: Colors.blue, onChanged: (val) { playClickSound(context); setModalState(() => isManual = val); }),
                    ],
                  ),
                  const Divider(height: 24),
                  if (!isManual) ...[
                     Row(
                       children: [
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tIn, widget.use24HourFormat);
                               if (t!=null) setModalState(() => tIn = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("TIME IN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(formatTime(context, tIn, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                                ),
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tOut, widget.use24HourFormat);
                               if (t!=null) setModalState(() => tOut = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("TIME OUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(formatTime(context, tOut, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                               ),
                             ),
                           ),
                         ),
                       ],
                     ),
                  ] else ...[
                     TextField(
                       controller: manualCtrl, keyboardType: TextInputType.number,
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                       decoration: const InputDecoration(labelText: "Enter Amount", border: OutlineInputBorder(), prefixText: "₱ "),
                     )
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text("SAVE SHIFT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      onPressed: () { playClickSound(context); Navigator.pop(context, true); },
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
        setState(() {
          if (existingShift != null) {
            existingShift.date = tempDate;
            existingShift.rawTimeIn = tIn; existingShift.rawTimeOut = tOut;
            existingShift.isManualPay = isManual; existingShift.manualAmount = double.tryParse(manualCtrl.text) ?? 0.0;
          } else {
            widget.period.shifts.add(Shift(
              id: const Uuid().v4(), date: tempDate, rawTimeIn: tIn, rawTimeOut: tOut,
              isManualPay: isManual, manualAmount: double.tryParse(manualCtrl.text) ?? 0.0,
            ));
          }
          widget.period.shifts.sort((a, b) => b.date.compareTo(a.date));
          widget.period.lastEdited = DateTime.now();
        });
        final prefs = SharedPreferences.getInstance().then((p) {}); 
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editPeriodDates,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.period.name),
              const SizedBox(width: 8),
              Icon(Icons.edit, size: 16, color: subTextColor),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("HOURLY RATE", style: TextStyle(fontWeight: FontWeight.bold, color: subTextColor)),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _rateController, keyboardType: TextInputType.number, textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
                          decoration: const InputDecoration(border: InputBorder.none, prefixText: "₱ "),
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
                Text("₱ ${currency.format(widget.period.getTotalPay(widget.shiftStart, widget.shiftEnd))}", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                Text("TOTAL PAYOUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 1.5)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatBox("REGULAR HRS", widget.period.getTotalRegularHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1), Theme.of(context).textTheme.bodyLarge!.color!, subTextColor),
                    Container(width: 1, height: 30, color: Colors.grey[300]),
                    _buildStatBox("OVERTIME HRS", widget.period.getTotalOvertimeHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1), Colors.blue, subTextColor),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: widget.period.shifts.isEmpty 
              ? Center(child: Text("Tap '+' to add a work day", style: TextStyle(color: subTextColor)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 20, bottom: 100, left: 16, right: 16),
                  itemCount: widget.period.shifts.length,
                  itemBuilder: (ctx, i) {
                    final s = widget.period.shifts[i];
                    return Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.delete, color: Colors.white)),
                      confirmDismiss: (direction) async {
                          playClickSound(context);
                          return await showDialog(context: context, builder: (ctx) => AlertDialog(
                            title: const Text("Delete Shift?"), content: const Text("Are you sure you want to remove this work day?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                            ],
                          ));
                      },
                      onDismissed: (direction) { playClickSound(context); setState(() { widget.period.shifts.removeAt(i); widget.period.lastEdited = DateTime.now(); }); },
                      child: GestureDetector(
                        onTap: () => _showShiftDialog(existingShift: s), 
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                  children: [
                                    Text(DateFormat('MMM').format(s.date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    Text(DateFormat('dd').format(s.date), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.isManualPay)
                                      Text("Flat Pay: ₱${currency.format(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold))
                                    else ...[
                                      Text("${formatTime(context, s.rawTimeIn, widget.use24HourFormat)} - ${formatTime(context, s.rawTimeOut, widget.use24HourFormat)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      RichText(
                                        text: TextSpan(
                                          style: TextStyle(color: subTextColor, fontSize: 12),
                                          children: [
                                            TextSpan(text: "Reg: ${s.getRegularHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1)}"),
                                            if (s.getOvertimeHours(widget.shiftStart, widget.shiftEnd) > 0)
                                              TextSpan(text: " • OT: ${s.getOvertimeHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                          ]
                                        ),
                                      )
                                    ]
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
        icon: const Icon(Icons.add, color: Colors.white), label: const Text("Add Shift", style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color valueColor, Color labelColor) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: labelColor)),
    ]);
  }
}