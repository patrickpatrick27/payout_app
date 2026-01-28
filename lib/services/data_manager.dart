import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'drive_service.dart'; // Make sure you have the DriveService file we created earlier

class DataManager extends ChangeNotifier {
  final DriveService _driveService = DriveService();
  
  // --- STATE ---
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  // Settings
  bool _use24HourFormat = false;
  bool _isDarkMode = false;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  // Getters for UI
  bool get use24HourFormat => _use24HourFormat;
  bool get isDarkMode => _isDarkMode;
  TimeOfDay get shiftStart => _shiftStart;
  TimeOfDay get shiftEnd => _shiftEnd;

  // --- INIT ---
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    // 1. Load Local Settings
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

    // 2. ATTEMPT CLOUD SYNC (Silent Background Sync)
    // This pulls the latest settings/data from Drive without blocking the user
    try {
      final cloudData = await _driveService.fetchCloudData();
      if (cloudData != null && cloudData.isNotEmpty) {
        // Example: Only restoring settings for now. You can expand this to sync logs too!
        final settings = cloudData.firstWhere(
          (element) => element.containsKey('settings'), 
          orElse: () => {},
        );

        if (settings.isNotEmpty && settings['settings'] != null) {
          final s = settings['settings'];
          _use24HourFormat = s['use24HourFormat'] ?? _use24HourFormat;
          _isDarkMode = s['isDarkMode'] ?? _isDarkMode;
          // You would parse TimeOfDay here similarly
          notifyListeners(); // Update UI instantly with Cloud Data
        }
      }
    } catch (e) {
      print("Cloud Sync Warning: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  // --- UPDATE METHODS ---
  
  Future<void> updateSettings({
    bool? isDark,
    bool? is24h,
    TimeOfDay? shiftStart,
    TimeOfDay? shiftEnd,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (isDark != null) {
      _isDarkMode = isDark;
      await prefs.setBool('isDarkMode', isDark);
    }
    if (is24h != null) {
      _use24HourFormat = is24h;
      await prefs.setBool('use24HourFormat', is24h);
    }
    if (shiftStart != null) {
      _shiftStart = shiftStart;
      await prefs.setString('shiftStart', "${shiftStart.hour}:${shiftStart.minute}");
    }
    if (shiftEnd != null) {
      _shiftEnd = shiftEnd;
      await prefs.setString('shiftEnd', "${shiftEnd.hour}:${shiftEnd.minute}");
    }

    notifyListeners(); // Update UI immediately
    
    // Trigger Background Cloud Sync
    _syncToCloud(); 
  }

  // --- SYNC ENGINE ---
  Future<void> _syncToCloud() async {
    // Construct the full data packet
    final Map<String, dynamic> settingsData = {
      'use24HourFormat': _use24HourFormat,
      'isDarkMode': _isDarkMode,
      'shiftStart': "${_shiftStart.hour}:${_shiftStart.minute}",
      'shiftEnd': "${_shiftEnd.hour}:${_shiftEnd.minute}",
    };

    final List<Map<String, dynamic>> fullBackup = [
      {'settings': settingsData},
      // You can add {'logs': yourLogsList} here later!
    ];

    await _driveService.syncToCloud(fullBackup);
  }
}