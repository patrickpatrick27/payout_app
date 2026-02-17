import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart'; // <--- ADDED THIS

import '../models/data_models.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';
import '../utils/calculations.dart'; 
import '../widgets/custom_pickers.dart';
import '../widgets/sync_conflict_dialog.dart';
import '../services/data_manager.dart'; 
import '../services/audio_service.dart';
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
    TimeOfDay? shiftEnd,
    bool? enableLate,
    bool? enableOt,
    double? defaultRate,
    bool? snapToGrid,
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

  bool _hideMoney = false;
  String _currencySymbol = '₱';
  String _currentSort = 'newest'; 

  final ScrollController _scrollController = ScrollController();
  double _appBarOpacity = 0.0;

  String? _cachedEmail;
  String? _cachedPhoto;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final manager = Provider.of<DataManager>(context, listen: false);
      manager.addListener(() {
        if (mounted && manager.isAuthenticated) {
           _cacheUserSession(manager);
           _loadLocalData();
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final double newOpacity = (_scrollController.offset / 100.0).clamp(0.0, 1.0);
    if ((newOpacity - _appBarOpacity).abs() > 0.01) setState(() => _appBarOpacity = newOpacity);
  }

  Future<void> _cacheUserSession(DataManager manager) async {
    final prefs = await SharedPreferences.getInstance();
    if (manager.userEmail != null) await prefs.setString('cached_user_email', manager.userEmail!);
    if (manager.userPhoto != null) await prefs.setString('cached_user_photo', manager.userPhoto!);
  }

  Future<void> _loadCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedEmail = prefs.getString('cached_user_email');
      _cachedPhoto = prefs.getString('cached_user_photo');
    });
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadCachedSession();

    setState(() {
      _hideMoney = prefs.getBool('setting_hide_money') ?? false;
      _currencySymbol = prefs.getString('setting_currency_symbol') ?? '₱';
      _isUnsynced = prefs.getBool('is_unsynced') ?? false;
      _currentSort = prefs.getString('setting_sort_order') ?? 'newest';
    });

    String? data = prefs.getString('pay_tracker_data');
    if (data == null) data = prefs.getString(kStorageKey);

    if (data != null && data.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
          _applySort(); 
        });
      } catch (e) { print("Error loading local data: $e"); }
    } else {
      setState(() { periods = []; });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonData = jsonEncode(periods.map((e) => e.toJson()).toList());
    await prefs.setString(kStorageKey, jsonData);
    await prefs.setString('pay_tracker_data', jsonData);
    await prefs.setBool('is_unsynced', true);
    if (mounted) setState(() { _isUnsynced = true; });
  }

  // --- CSV EXPORT LOGIC ---
  Future<void> _exportAllCsv() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    
    // Build CSV Rows
    List<List<dynamic>> rows = [];
    rows.add(["Period Name", "Date", "Day", "Time In", "Time Out", "Regular Hours", "OT Hours", "Late Minutes", "Daily Pay"]);

    for (var p in periods) {
      for (var s in p.shifts) {
        double reg = s.getRegularHours(
          widget.shiftStart, 
          widget.shiftEnd, 
          isLateEnabled: manager.enableLateDeductions, 
          snapToGrid: manager.snapToGrid
        );
        
        double ot = manager.enableOvertime 
            ? s.getOvertimeHours(widget.shiftStart, widget.shiftEnd, snapToGrid: manager.snapToGrid) 
            : 0.0;
            
        int lateMins = PayrollCalculator.calculateLateMinutes(s.rawTimeIn, widget.shiftStart);
        
        double rate = p.hourlyRate > 0 ? p.hourlyRate : manager.defaultHourlyRate;
        double pay = (reg * rate) + (ot * rate * 1.25);
        if (s.isHoliday && s.holidayMultiplier > 0) {
           pay += pay * (s.holidayMultiplier / 100.0);
        }

        rows.add([
          p.name,
          DateFormat('yyyy-MM-dd').format(s.date),
          DateFormat('EEEE').format(s.date),
          s.isManualPay ? "MANUAL" : formatTime(context, s.rawTimeIn, widget.use24HourFormat),
          s.isManualPay ? "-" : formatTime(context, s.rawTimeOut, widget.use24HourFormat),
          reg.toStringAsFixed(2),
          ot.toStringAsFixed(2),
          lateMins,
          pay.toStringAsFixed(2)
        ]);
      }
    }

    String csvData = const ListToCsvConverter().convert(rows);
    
    // Save to Temp File
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/pay_tracker_full_export.csv";
    final File file = File(path);
    await file.writeAsString(csvData);

    // Share File
    await Share.shareXFiles([XFile(path)], text: 'Pay Tracker Full Report');
  }

  // --- JSON EXPORT (BACKUP) LOGIC ---
  Future<void> _exportBackupJson() async {
    final String jsonData = jsonEncode(periods.map((e) => e.toJson()).toList());
    
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/pay_tracker_backup.json";
    final File file = File(path);
    await file.writeAsString(jsonData);
    
    await Share.shareXFiles([XFile(path)], text: 'Pay Tracker Backup File (JSON)');
  }

  // --- JSON IMPORT (RESTORE) LOGIC ---
  Future<void> _pickAndRestoreJson() async {
    try {
      // Open File Picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'], // Allowing txt just in case
      );

      if (result != null) {
        // Read file content
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        
        // Restore
        final List<dynamic> decoded = jsonDecode(content);
        setState(() {
          periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
          _applySort();
        });
        _saveData();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data imported successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import Failed: Invalid File"), backgroundColor: Colors.red));
    }
  }

  void _performManualSync() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking Cloud..."), duration: Duration(seconds: 1)));

    try {
      if (!manager.isAuthenticated) { try { await manager.login(); } catch (_) {} }
      String? cloudJson = await manager.fetchCloudDataOnly(); 
      
      if (cloudJson == null || cloudJson.isEmpty) {
        await _uploadLocalToCloud();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      String localJson = prefs.getString('pay_tracker_data') ?? "[]";

      if (localJson != cloudJson && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SyncConflictDialog(
            localJson: localJson,
            cloudJson: cloudJson,
            onKeepCloud: () async {
               final List<dynamic> decoded = jsonDecode(cloudJson);
               setState(() { periods = decoded.map((e) => PayPeriod.fromJson(e)).toList(); _applySort(); });
               await _saveData(); 
               setState(() => _isUnsynced = false); 
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restored from Cloud"), backgroundColor: Colors.blue));
            },
            onKeepDevice: () async {
               await _uploadLocalToCloud();
            },
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data is already in sync."), backgroundColor: Colors.green));
        setState(() => _isUnsynced = false);
        await prefs.setBool('is_unsynced', false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sync failed. You might be offline."), backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadLocalToCloud() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    if (!manager.isAuthenticated) { try { await manager.login(); } catch (_) {} }
    final List<Map<String, dynamic>> jsonList = periods.map((e) => e.toJson()).toList();
    bool success = await manager.syncPayrollToCloud(jsonList);
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_unsynced', false);
        setState(() => _isUnsynced = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cloud Updated Successfully"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Failed. Saved Locally."), backgroundColor: Colors.orange));
      }
    }
  }

  String _getMoneyText(double amount) {
    if (_hideMoney) return "****.**";
    return "$_currencySymbol${currencyFormatter.format(amount)}";
  }

  void _editPeriodDates(PayPeriod period) async {
    AudioService().playClick(); 
    DateTime? newStart = await showFastDatePicker(context, period.start);
    if (newStart == null) return;
    if (!mounted) return;
    DateTime? newEnd = await showFastDatePicker(context, period.end, minDate: newStart);
    if (newEnd == null) return;

    if (hasDateOverlap(newStart, newEnd, periods, excludeId: period.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dates overlap with another payroll!"), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      period.start = newStart; period.end = newEnd;
      period.updateName(); period.lastEdited = DateTime.now();
    });
    _saveData();
  }

  void _sortPeriods(String type) async {
    AudioService().playClick(); 
    setState(() { _currentSort = type; _applySort(); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('setting_sort_order', type);
  }

  void _applySort() {
    if (_currentSort == 'newest') periods.sort((a, b) => b.start.compareTo(a.start));
    else if (_currentSort == 'oldest') periods.sort((a, b) => a.start.compareTo(b.start)); 
    else if (_currentSort == 'edited') periods.sort((a, b) => b.lastEdited.compareTo(a.lastEdited));
  }

  void _openSettings() {
    AudioService().playClick(); 
    final manager = Provider.of<DataManager>(context, listen: false);

    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
      isDarkMode: widget.isDarkMode,
      use24HourFormat: widget.use24HourFormat,
      hideMoney: _hideMoney,
      currencySymbol: _currencySymbol,
      shiftStart: widget.shiftStart,
      shiftEnd: widget.shiftEnd,
      snapToGrid: manager.snapToGrid, 
      
      onUpdate: ({
        isDark, is24h, hideMoney, currencySymbol, shiftStart, shiftEnd, 
        enableLate, enableOt, defaultRate, snapToGrid 
      }) async {
        final prefs = await SharedPreferences.getInstance();
        
        if (hideMoney != null) { 
          setState(() => _hideMoney = hideMoney); 
          prefs.setBool('setting_hide_money', hideMoney); 
        }
        if (currencySymbol != null) { 
          setState(() => _currencySymbol = currencySymbol); 
          prefs.setString('setting_currency_symbol', currencySymbol); 
        }
        
        Provider.of<DataManager>(context, listen: false).updateSettings(
          isDark: isDark, 
          is24h: is24h, 
          shiftStart: shiftStart, 
          shiftEnd: shiftEnd, 
          enableLate: enableLate, 
          enableOt: enableOt, 
          defaultRate: defaultRate,
          snapToGrid: snapToGrid,
        );
      },
      onDeleteAll: () async { setState(() { periods = []; }); _saveData(); },
      onExportReport: _exportAllCsv, 
      onBackup: _exportBackupJson,   
      onRestore: _pickAndRestoreJson, // <--- Passing the File Picker Logic here
    )));
  }

  void _createNewPeriod() async {
    DateTime now = DateTime.now();
    DateTime defaultStart = (now.day <= 15) ? DateTime(now.year, now.month, 1) : DateTime(now.year, now.month, 16);
    AudioService().playClick(); 
    
    DateTime? start = await showFastDatePicker(context, defaultStart);
    if (start == null) return;
    if (!mounted) return;
    
    int lastDayOfMonth = DateTime(start.year, start.month + 1, 0).day;
    DateTime defaultEnd = (start.day <= 15) ? DateTime(start.year, start.month, 15) : DateTime(start.year, start.month, lastDayOfMonth);
    if (defaultEnd.isBefore(start)) defaultEnd = DateTime(start.year, start.month, lastDayOfMonth);
    
    DateTime? end = await showFastDatePicker(context, defaultEnd, minDate: start);
    if (end == null) return;

    if (hasDateOverlap(start, end, periods)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Overlaps with existing payroll."), backgroundColor: Colors.red));
      return;
    }

    final newPeriod = PayPeriod(id: const Uuid().v4(), name: "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}", start: start, end: end, lastEdited: DateTime.now(), hourlyRate: 50.0, shifts: []);
    setState(() { periods.insert(0, newPeriod); _applySort(); });
    AudioService().playSuccess();
    _saveData(); 
    _openPeriod(newPeriod);
  }

  void _openPeriod(PayPeriod period) async {
    AudioService().playClick(); 
    period.lastEdited = DateTime.now();
    _saveData(); 
    final manager = Provider.of<DataManager>(context, listen: false);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PeriodDetailScreen(
      period: period, 
      use24HourFormat: widget.use24HourFormat,
      shiftStart: widget.shiftStart, shiftEnd: widget.shiftEnd,
      hideMoney: _hideMoney, currencySymbol: _currencySymbol,
      onSave: _saveData, enableLate: manager.enableLateDeductions, enableOt: manager.enableOvertime,
    )));
    _saveData();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<DataManager>(
      builder: (context, dataManager, child) {
        final String? displayEmail = dataManager.userEmail ?? _cachedEmail;
        final String? displayPhoto = dataManager.userPhoto ?? _cachedPhoto;
        final bool isOfflineButRemembered = (!dataManager.isAuthenticated && displayEmail != null);
        final bool isTrulyGuest = (displayEmail == null);

        return Scaffold(
          extendBodyBehindAppBar: true, 
          appBar: AppBar(
            systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            title: const Text("Pay Tracker", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            centerTitle: false, 
            elevation: 0,
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            flexibleSpace: Container(color: Theme.of(context).scaffoldBackgroundColor.withOpacity(_appBarOpacity)),
            actions: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: Icon(isOfflineButRemembered ? Icons.cloud_off : CupertinoIcons.cloud_upload, color: isOfflineButRemembered ? Colors.grey : Theme.of(context).iconTheme.color), 
                    onPressed: () => isTrulyGuest ? ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login required to sync."))) : _performManualSync(),
                  ),
                  if (_isUnsynced && !isTrulyGuest)
                    Positioned(right: 8, top: 8, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                ],
              ),
              PopupMenuButton<String>(
                icon: const Icon(CupertinoIcons.sort_down),
                onSelected: _sortPeriods,
                itemBuilder: (context) => [const PopupMenuItem(value: 'newest', child: Text("Newest First")), const PopupMenuItem(value: 'oldest', child: Text("Oldest First")), const PopupMenuItem(value: 'edited', child: Text("Recently Edited"))],
              ),
              IconButton(icon: const Icon(CupertinoIcons.settings), onPressed: _openSettings),
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                icon: CircleAvatar(radius: 14, backgroundColor: Theme.of(context).colorScheme.primary, backgroundImage: displayPhoto != null ? NetworkImage(displayPhoto) : null, child: displayPhoto == null ? const Icon(CupertinoIcons.person_solid, size: 16, color: Colors.white) : null),
                itemBuilder: (context) {
                  if (isTrulyGuest) return [const PopupMenuItem(value: 'login', child: Text("Log In to Sync"))];
                  return [
                    PopupMenuItem(enabled: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Signed in as:", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(displayEmail ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)), if (isOfflineButRemembered) const Text("(Offline Mode)", style: TextStyle(fontSize: 10, color: Colors.orange))])),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, color: Colors.red, size: 20), SizedBox(width: 8), Text("Logout", style: TextStyle(color: Colors.red))])),
                  ];
                },
                onSelected: (value) async {
                  if (value == 'logout') {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('cached_user_email');
                    await prefs.remove('cached_user_photo');
                    dataManager.logout().then((_) { if (mounted) _loadLocalData(); });
                  } else if (value == 'login') { dataManager.logout(); }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: periods.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(CupertinoIcons.money_dollar_circle, size: 80, color: Colors.grey[300]), 
                  const SizedBox(height: 20), 
                  Text("No Payrolls Yet", style: TextStyle(color: Colors.grey[600], fontSize: 16)), 
                  const SizedBox(height: 10), 
                  FloatingActionButton.extended(
                    heroTag: 'dashboardFabEmpty',
                    onPressed: _createNewPeriod,
                    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    foregroundColor: primaryColor,
                    elevation: 6,
                    shape: StadiumBorder(side: BorderSide(color: primaryColor, width: 2.0)),
                    icon: const Icon(CupertinoIcons.add),
                    label: const Text("Create New", style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ]))
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 20, left: 16, right: 16, bottom: 80),
                  itemCount: periods.length,
                  itemBuilder: (context, index) {
                    final p = periods[index];
                    
                    final totalPay = p.getTotalPay(
                      widget.shiftStart, 
                      widget.shiftEnd, 
                      hourlyRate: dataManager.defaultHourlyRate, 
                      enableLate: dataManager.enableLateDeductions, 
                      enableOt: dataManager.enableOvertime,
                      snapToGrid: dataManager.snapToGrid 
                    );

                    return Dismissible(
                      key: Key(p.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (dir) async { bool delete = false; await showConfirmationDialog(context: context, title: "Delete?", content: "Remove ${p.name}?", isDestructive: true, onConfirm: () => delete = true); return delete; },
                      onDismissed: (d) { AudioService().playDelete(); setState(() { periods.removeAt(index); }); _saveData(); },
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
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 6), Text("${p.shifts.length} Shifts", style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500))])),
                              Container(
                                width: 110, padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(50)),
                                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_getMoneyText(totalPay), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onPrimaryContainer)))),
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'dashboardFab',
            onPressed: _createNewPeriod,
            label: const Text("Add Payroll", style: TextStyle(fontWeight: FontWeight.bold)),
            icon: const Icon(CupertinoIcons.add),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            foregroundColor: primaryColor,
            elevation: 6,
            shape: StadiumBorder(side: BorderSide(color: primaryColor, width: 2.0)),
          ),
        );
      },
    );
  }
}