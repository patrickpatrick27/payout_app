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
  String _currentSort = 'newest'; 

  // --- FLUID SCROLL STATE ---
  final ScrollController _scrollController = ScrollController();
  double _appBarOpacity = 0.0;

  // --- OFFLINE SESSION CACHE ---
  String? _cachedEmail;
  String? _cachedPhoto;

  @override
  void initState() {
    super.initState();
    // 1. Force load local data immediately (Offline Support)
    _loadLocalData();
    
    // 2. Setup Scroll Listener for Fluid AppBar
    _scrollController.addListener(_onScroll);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final manager = Provider.of<DataManager>(context, listen: false);
      manager.addListener(() {
        if (mounted) {
           // If manager connects, refresh data AND cache the session
           if (manager.isAuthenticated) {
             _cacheUserSession(manager);
           }
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
    const double transitionDistance = 100.0; 
    final double offset = _scrollController.offset;
    final double newOpacity = (offset / transitionDistance).clamp(0.0, 1.0);

    if ((newOpacity - _appBarOpacity).abs() > 0.01) {
      setState(() {
        _appBarOpacity = newOpacity;
      });
    }
  }

  // --- OFFLINE SESSION LOGIC ---
  Future<void> _cacheUserSession(DataManager manager) async {
    final prefs = await SharedPreferences.getInstance();
    if (manager.userEmail != null) {
      await prefs.setString('cached_user_email', manager.userEmail!);
      if (manager.userPhoto != null) {
        await prefs.setString('cached_user_photo', manager.userPhoto!);
      }
    }
  }

  Future<void> _loadCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedEmail = prefs.getString('cached_user_email');
      _cachedPhoto = prefs.getString('cached_user_photo');
    });
  }

  // --- LOCAL DATA HANDLING ---
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load session info alongside data
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
      } catch (e) {
        print("Error loading local data: $e");
      }
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
    
    await prefs.setBool('is_unsynced', true);
    
    if (mounted) {
      setState(() { _isUnsynced = true; });
    }
  }

  // --- SYNC WITH CONFLICT RESOLUTION ---
  void _performManualSync() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [CircularProgressIndicator(strokeWidth: 2), SizedBox(width: 10), Text("Checking Cloud...")]), 
        duration: Duration(seconds: 1)
      )
    );

    try {
      // Try to connect first if we are in "Cached Mode"
      if (!manager.isAuthenticated) {
         // FIXED: Changed .signIn() to .login()
         try { await manager.login(); } catch (_) {}
      }

      String? cloudJson = await manager.fetchCloudDataOnly(); 
      
      if (cloudJson == null || cloudJson.isEmpty) {
        await _uploadLocalToCloud();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      String localJson = prefs.getString('pay_tracker_data') ?? "[]";

      if (localJson != cloudJson) {
        if (mounted) {
           ScaffoldMessenger.of(context).hideCurrentSnackBar();
           _showConflictDialog(localJson, cloudJson);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data is already in sync."), backgroundColor: Colors.green));
          setState(() { _isUnsynced = false; });
          await prefs.setBool('is_unsynced', false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sync failed. You might be offline."), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _uploadLocalToCloud() async {
    final manager = Provider.of<DataManager>(context, listen: false);
    
    // Try to connect if offline
    if (!manager.isAuthenticated) {
         // FIXED: Changed .signIn() to .login()
         try { await manager.login(); } catch (_) {}
    }

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

  int _countTotalShifts(List<dynamic> periodList) {
    int total = 0;
    for (var p in periodList) {
      if (p['shifts'] != null) {
        total += (p['shifts'] as List).length;
      }
    }
    return total;
  }

  void _showConflictDialog(String localJson, String cloudJson) {
    List localList = jsonDecode(localJson);
    List cloudList = jsonDecode(cloudJson);

    int localShifts = _countTotalShifts(localList);
    int cloudShifts = _countTotalShifts(cloudList);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Sync Conflict"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("The data on your device is different from the Cloud."),
            const SizedBox(height: 16),
            _buildConflictRow(Icons.phone_android, "This Device", "${localList.length} Cutoffs • $localShifts Shifts", Colors.blue),
            const SizedBox(height: 8),
            _buildConflictRow(Icons.cloud, "Google Drive", "${cloudList.length} Cutoffs • $cloudShifts Shifts", Colors.orange),
            const SizedBox(height: 16),
            const Text("Which version do you want to keep?", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final List<dynamic> decoded = jsonDecode(cloudJson);
              setState(() {
                periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
                _applySort(); 
              });
              await _saveData(); 
              setState(() => _isUnsynced = false); 
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restored from Cloud"), backgroundColor: Colors.blue));
            },
            child: const Text("Keep Cloud"),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _uploadLocalToCloud();
            },
            child: const Text("Keep Device"),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictRow(IconData icon, String label, String sub, Color color) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        )
      ],
    );
  }

  String _getMoneyText(double amount) {
    if (_hideMoney) return "****.**";
    return "$_currencySymbol${currencyFormatter.format(amount)}";
  }

  // --- CRUD OPERATIONS ---

  void _confirmDeletePeriod(int index) {
    showConfirmationDialog(
      context: context, 
      title: "Delete Cutoff?", 
      content: "Are you sure you want to delete ${periods[index].name}?", 
      isDestructive: true, 
      onConfirm: () {
        AudioService().playDelete(); 
        setState(() { periods.removeAt(index); });
        _saveData();
      }
    );
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
    
    setState(() {
      _currentSort = type;
      _applySort();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('setting_sort_order', type);
  }

  void _applySort() {
    if (_currentSort == 'newest') {
      periods.sort((a, b) => b.start.compareTo(a.start));
    } else if (_currentSort == 'oldest') {
      periods.sort((a, b) => a.start.compareTo(b.start)); 
    } else if (_currentSort == 'edited') {
      periods.sort((a, b) => b.lastEdited.compareTo(a.lastEdited));
    }
  }

  void _openSettings() {
    AudioService().playClick(); 
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
      isDarkMode: widget.isDarkMode,
      use24HourFormat: widget.use24HourFormat,
      hideMoney: _hideMoney,
      currencySymbol: _currencySymbol,
      shiftStart: widget.shiftStart,
      shiftEnd: widget.shiftEnd,
      onUpdate: ({isDark, is24h, hideMoney, currencySymbol, shiftStart, shiftEnd, enableLate, enableOt, defaultRate}) async {
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
        );
      },
      onDeleteAll: () async {
          setState(() { periods = []; });
          _saveData();
      },
      onExportReport: () {}, onBackup: () {}, onRestore: (s) {},
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

    final newPeriod = PayPeriod(
      id: const Uuid().v4(), 
      name: "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}", 
      start: start, 
      end: end, 
      lastEdited: DateTime.now(), 
      hourlyRate: 50.0, 
      shifts: []
    );
    
    setState(() { 
      periods.insert(0, newPeriod); 
      _applySort(); 
    });
    
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
      shiftStart: widget.shiftStart, 
      shiftEnd: widget.shiftEnd,
      hideMoney: _hideMoney,
      currencySymbol: _currencySymbol,
      onSave: _saveData, 
      enableLate: manager.enableLateDeductions,
      enableOt: manager.enableOvertime,
    )));
    
    _saveData();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Primary Color (Violet)
    final primaryColor = Theme.of(context).colorScheme.primary;
    // Check Brightness directly
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<DataManager>(
      builder: (context, dataManager, child) {
        
        // --- OFFLINE SESSION LOGIC ---
        // If manager has data, use it. If not (offline), use cached data.
        final String? displayEmail = dataManager.userEmail ?? _cachedEmail;
        final String? displayPhoto = dataManager.userPhoto ?? _cachedPhoto;
        final bool isOfflineButRemembered = (!dataManager.isAuthenticated && displayEmail != null);
        final bool isTrulyGuest = (displayEmail == null);

        return Scaffold(
          // 1. Extend body so content scrolls behind AppBar
          extendBodyBehindAppBar: true, 
          
          appBar: AppBar(
            // Ensures status bar icons change color correctly (Dark icons on light bg, Light on dark)
            systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            title: const Text("Pay Tracker", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            centerTitle: false, 
            elevation: 0,
            
            // 2. FLUID BACKGROUND: Transparent to Solid Theme Color
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            flexibleSpace: Container(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(_appBarOpacity),
            ),
            
            actions: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    // Change icon color if we are in "Offline but Remembered" mode
                    icon: Icon(
                      isOfflineButRemembered ? Icons.cloud_off : CupertinoIcons.cloud_upload, 
                      color: isOfflineButRemembered ? Colors.grey : Theme.of(context).iconTheme.color
                    ), 
                    onPressed: () {
                      if (isTrulyGuest) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login required to sync.")));
                      } else {
                         _performManualSync();
                      }
                    },
                  ),
                  if (_isUnsynced && !isTrulyGuest)
                    Positioned(right: 8, top: 8, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
                ],
              ),
              
              PopupMenuButton<String>(
                icon: const Icon(CupertinoIcons.sort_down),
                onSelected: _sortPeriods,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'newest', child: Text("Newest First")),
                  const PopupMenuItem(value: 'oldest', child: Text("Oldest First")),
                  const PopupMenuItem(value: 'edited', child: Text("Recently Edited")),
                ],
              ),
              
              IconButton(icon: const Icon(CupertinoIcons.settings), onPressed: _openSettings),
              
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: displayPhoto != null ? NetworkImage(displayPhoto) : null,
                  child: displayPhoto == null ? const Icon(CupertinoIcons.person_solid, size: 16, color: Colors.white) : null,
                ),
                itemBuilder: (context) {
                  if (isTrulyGuest) {
                    return [const PopupMenuItem(value: 'login', child: Text("Log In to Sync"))];
                  }
                  return [
                    PopupMenuItem(enabled: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("Signed in as:", style: TextStyle(fontSize: 10, color: Colors.grey)), 
                      Text(displayEmail ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isOfflineButRemembered) const Text("(Offline Mode)", style: TextStyle(fontSize: 10, color: Colors.orange))
                    ])),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, color: Colors.red, size: 20), SizedBox(width: 8), Text("Logout", style: TextStyle(color: Colors.red))])),
                  ];
                },
                onSelected: (value) async {
                  if (value == 'logout') {
                    // Clear the cache on manual logout
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('cached_user_email');
                    await prefs.remove('cached_user_photo');
                    
                    dataManager.logout().then((_) { if (mounted) _loadLocalData(); });
                  } else if (value == 'login') {
                     dataManager.logout(); 
                  }
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
                  // UPDATED: Oval, Outlined, Theme-Aware FAB
                  FloatingActionButton.extended(
                    heroTag: 'dashboardFabEmpty', // Unique tag for empty state FAB
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
                  // 3. Attach controller for scroll detection
                  controller: _scrollController,
                  // 4. Add Top Padding so items aren't hidden behind AppBar initially
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight + 20, 
                    left: 16, 
                    right: 16, 
                    bottom: 80
                  ),
                  itemCount: periods.length,
                  itemBuilder: (context, index) {
                    final p = periods[index];
                    final totalPay = p.getTotalPay(
                      widget.shiftStart, 
                      widget.shiftEnd, 
                      hourlyRate: dataManager.defaultHourlyRate,
                      enableLate: dataManager.enableLateDeductions, 
                      enableOt: dataManager.enableOvertime
                    );

                    return Dismissible(
                      key: Key(p.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (dir) async { 
                        bool delete = false; 
                        await showConfirmationDialog(context: context, title: "Delete?", content: "Remove ${p.name}?", isDestructive: true, onConfirm: () => delete = true); 
                        return delete; 
                      },
                      onDismissed: (d) { 
                        AudioService().playDelete(); 
                        setState(() { periods.removeAt(index); });
                        _saveData();
                      },
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
                              Container(
                                width: 110,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer, 
                                  borderRadius: BorderRadius.circular(50), 
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _getMoneyText(totalPay),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700, 
                                        fontSize: 15, 
                                        color: Theme.of(context).colorScheme.onPrimaryContainer
                                      ),
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
          // UPDATED: Oval, Outlined, Theme-Aware FAB with Label
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'dashboardFab', // <--- FIXED: Added Unique Hero Tag
            onPressed: _createNewPeriod,
            label: const Text("Add Payroll", style: TextStyle(fontWeight: FontWeight.bold)),
            icon: const Icon(CupertinoIcons.add),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            foregroundColor: primaryColor,
            elevation: 6,
            shape: StadiumBorder(
              side: BorderSide(color: primaryColor, width: 2.0)
            ),
          ),
        );
      },
    );
  }
}