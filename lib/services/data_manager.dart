import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'drive_service.dart';

class DataManager extends ChangeNotifier {
  final DriveService _driveService = DriveService();
  
  // --- STATE ---
  bool _isInitialized = false;
  bool _isGuest = false;
  List<dynamic> _currentPayrollData = []; // Buffer for payroll records

  // Settings
  bool _use24HourFormat = false;
  bool _isDarkMode = false;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  // --- GETTERS ---
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _driveService.currentUser != null || _isGuest;
  bool get isGuest => _isGuest;
  
  String? get userEmail => _driveService.currentUser?.email;
  String? get userName => _driveService.currentUser?.displayName;
  String? get userPhoto => _driveService.currentUser?.photoUrl;

  bool get use24HourFormat => _use24HourFormat;
  bool get isDarkMode => _isDarkMode;
  TimeOfDay get shiftStart => _shiftStart;
  TimeOfDay get shiftEnd => _shiftEnd;

  // --- 1. APP STARTUP ---
  Future<void> initApp() async {
    final prefs = await SharedPreferences.getInstance();
    _isGuest = prefs.getBool('isGuest') ?? false;

    // If NOT Guest, try Silent Login & Pull Data
    if (!_isGuest) {
      bool success = await _driveService.trySilentLogin();
      if (success) {
        await _pullAllFromCloud(); 
      }
    }

    await _loadLocalSettings(prefs);
    _isInitialized = true;
    notifyListeners();
  }

  // --- 2. AUTH ACTIONS ---
  
  Future<bool> loginWithGoogle() async {
    bool success = await _driveService.signIn();
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isGuest', false);
      _isGuest = false;
      
      // Merge: Cloud overwrites local on fresh login
      await _pullAllFromCloud();
      notifyListeners();
    }
    return success;
  }

  Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    
    // CRITICAL: Wipe any previous user data so guest starts fresh
    await _clearLocalData(); 

    await prefs.setBool('isGuest', true);
    _isGuest = true;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    
    // CRITICAL: Wipe local data on logout
    await _clearLocalData();
    
    await prefs.remove('isGuest');
    _isGuest = false;
    
    await _driveService.signOut();
    notifyListeners();
  }

  // Helper to completely wipe data keys from phone storage
  Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    // 'pay_tracker_data' is the main key used by Dashboard (kStorageKey)
    await prefs.remove('pay_tracker_data'); 
    await prefs.remove('pay_periods_data'); 
    _currentPayrollData = [];
  }

  // --- 3. SYNC ENGINE ---

  // Called by Dashboard. Returns a status string for the UI.
  Future<String> syncPayrollToCloud(List<Map<String, dynamic>> data) async {
    _currentPayrollData = data;
    
    if (_isGuest) return "Saved locally (Guest Mode)";

    bool success = await _syncAllToCloud();
    return success ? "Cloud Backup Complete" : "Cloud Sync Failed";
  }

  Future<void> _pullAllFromCloud() async {
    if (_isGuest) return;
    try {
      final cloudData = await _driveService.fetchCloudData();
      if (cloudData != null && cloudData.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();

        // A. Restore Data
        final payrollMap = cloudData.firstWhere(
          (element) => element.containsKey('payroll_data'),
          orElse: () => {},
        );

        if (payrollMap.isNotEmpty && payrollMap['payroll_data'] != null) {
          _currentPayrollData = List<dynamic>.from(payrollMap['payroll_data']);
          
          // SAVE TO THE KEY DASHBOARD READS
          await prefs.setString('pay_tracker_data', jsonEncode(_currentPayrollData));
        }

        // B. Restore Settings
        final settingsMap = cloudData.firstWhere(
          (element) => element.containsKey('settings'), 
          orElse: () => {},
        );

        if (settingsMap.isNotEmpty && settingsMap['settings'] != null) {
          final s = settingsMap['settings'];
          _use24HourFormat = s['use24HourFormat'] ?? _use24HourFormat;
          _isDarkMode = s['isDarkMode'] ?? _isDarkMode;
          
          if (s['shiftStart'] != null) {
            final parts = s['shiftStart'].split(':');
            _shiftStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
          if (s['shiftEnd'] != null) {
            final parts = s['shiftEnd'].split(':');
            _shiftEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
          
          // Persist settings locally
          await prefs.setBool('use24HourFormat', _use24HourFormat);
          await prefs.setBool('isDarkMode', _isDarkMode);
          await prefs.setString('shiftStart', s['shiftStart']);
          await prefs.setString('shiftEnd', s['shiftEnd']);
        }
        
        notifyListeners();
      }
    } catch (e) {
      print("Cloud Pull Error: $e");
    }
  }

  Future<bool> _syncAllToCloud() async {
    if (_isGuest) return false;
    
    final Map<String, dynamic> settingsData = {
      'use24HourFormat': _use24HourFormat,
      'isDarkMode': _isDarkMode,
      'shiftStart': "${_shiftStart.hour}:${_shiftStart.minute}",
      'shiftEnd': "${_shiftEnd.hour}:${_shiftEnd.minute}",
    };

    final List<Map<String, dynamic>> fullBackup = [
      {'settings': settingsData},
      {'payroll_data': _currentPayrollData},
    ];

    return await _driveService.syncToCloud(fullBackup);
  }

  // --- SETTINGS HELPERS ---
  Future<void> _loadLocalSettings(SharedPreferences prefs) async {
    _use24HourFormat = prefs.getBool('use24HourFormat') ?? false;
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    String? startStr = prefs.getString('shiftStart');
    if (startStr != null) {
      final parts = startStr.split(':');
      _shiftStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    String? endStr = prefs.getString('shiftEnd');
    if (endStr != null) {
      final parts = endStr.split(':');
      _shiftEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
  }

  Future<void> updateSettings({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) async {
    final prefs = await SharedPreferences.getInstance();
    if (isDark != null) { _isDarkMode = isDark; await prefs.setBool('isDarkMode', isDark); }
    if (is24h != null) { _use24HourFormat = is24h; await prefs.setBool('use24HourFormat', is24h); }
    if (shiftStart != null) { _shiftStart = shiftStart; await prefs.setString('shiftStart', "${shiftStart.hour}:${shiftStart.minute}"); }
    if (shiftEnd != null) { _shiftEnd = shiftEnd; await prefs.setString('shiftEnd', "${shiftEnd.hour}:${shiftEnd.minute}"); }
    notifyListeners();
    _syncAllToCloud();
  }
}