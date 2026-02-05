import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class DataManager extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? _currentUser;
  bool _isInitialized = false;
  bool _isGuestMode = false;
  
  // Settings
  bool _isDarkMode = false;
  bool _use24HourFormat = false;
  bool _enableLateDeductions = true;
  bool _enableOvertime = true;
  double _defaultHourlyRate = 50.0; 
  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _currentUser != null;
  bool get isGuest => _isGuestMode; 
  String? get userEmail => _currentUser?.email;
  String? get userPhoto => _currentUser?.photoUrl;
  
  bool get isDarkMode => _isDarkMode;
  bool get use24HourFormat => _use24HourFormat;
  bool get enableLateDeductions => _enableLateDeductions;
  bool get enableOvertime => _enableOvertime;
  double get defaultHourlyRate => _defaultHourlyRate; 
  TimeOfDay get shiftStart => _shiftStart;
  TimeOfDay get shiftEnd => _shiftEnd;

  Future<void> initApp() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Settings
    _isDarkMode = prefs.getBool(kSettingDarkMode) ?? false;
    _use24HourFormat = prefs.getBool(kSetting24h) ?? false;
    _isGuestMode = prefs.getBool('is_guest_mode') ?? false;
    _enableLateDeductions = prefs.getBool('enable_late') ?? true;
    _enableOvertime = prefs.getBool('enable_ot') ?? true;
    _defaultHourlyRate = prefs.getDouble('default_hourly_rate') ?? 50.0;
    
    int startH = prefs.getInt('${kSettingShiftStart}_h') ?? 8;
    int startM = prefs.getInt('${kSettingShiftStart}_m') ?? 0;
    _shiftStart = TimeOfDay(hour: startH, minute: startM);

    int endH = prefs.getInt('${kSettingShiftEnd}_h') ?? 17;
    int endM = prefs.getInt('${kSettingShiftEnd}_m') ?? 0;
    _shiftEnd = TimeOfDay(hour: endH, minute: endM);

    if (!_isGuestMode) {
      try {
        _currentUser = await _googleSignIn.signInSilently();
      } catch (e) {
        print("Silent Login Failed: $e");
      }
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  // --- AUTHENTICATION ---

  Future<void> login() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      
      if (_currentUser != null) {
        _isGuestMode = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_guest_mode', false);

        // Auto-fetch data on login
        String? cloudJson = await fetchCloudDataOnly();
        if (cloudJson != null && cloudJson.isNotEmpty) {
           await prefs.setString('pay_tracker_data', cloudJson);
           await prefs.setString(kStorageKey, cloudJson);
        }
      }
      notifyListeners();
    } catch (e) {
      print("Login Error: $e");
      rethrow; 
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn.disconnect(); 
    } catch (_) {
      await _googleSignIn.signOut();
    }
    
    _currentUser = null;
    _isGuestMode = false; 
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest_mode', false);
    await clearLocalData();
    
    notifyListeners();
  }

  // UPDATED: Updates UI instantly, saves to disk in background
  void continueAsGuest() {
    _currentUser = null;
    _isGuestMode = true;
    notifyListeners(); // Immediate UI update

    // Fire and forget storage update
    _saveGuestModePreference();
  }

  Future<void> _saveGuestModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest_mode', true);
  }

  // --- DATA MANAGEMENT ---

  Future<void> clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pay_tracker_data');
    await prefs.remove(kStorageKey);
    await prefs.remove('is_unsynced');
  }

  Future<bool> deleteCloudData() async {
    if (_currentUser == null) return false;
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return false;
      
      final fileList = await driveApi.files.list(
        q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents",
        spaces: 'appDataFolder',
      );

      if (fileList.files != null) {
        for (var file in fileList.files!) {
          await driveApi.files.delete(file.id!);
        }
      }
      return true;
    } catch (e) {
      print("Delete Cloud Error: $e");
      return false;
    }
  }

  void updateSettings({
    bool? isDark, bool? is24h, bool? enableLate, bool? enableOt,
    double? defaultRate,
    TimeOfDay? shiftStart, TimeOfDay? shiftEnd
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (isDark != null) { _isDarkMode = isDark; prefs.setBool(kSettingDarkMode, isDark); }
    if (is24h != null) { _use24HourFormat = is24h; prefs.setBool(kSetting24h, is24h); }
    if (enableLate != null) { _enableLateDeductions = enableLate; prefs.setBool('enable_late', enableLate); }
    if (enableOt != null) { _enableOvertime = enableOt; prefs.setBool('enable_ot', enableOt); }
    if (defaultRate != null) { _defaultHourlyRate = defaultRate; prefs.setDouble('default_hourly_rate', defaultRate); }
    
    if (shiftStart != null) { 
      _shiftStart = shiftStart; 
      prefs.setInt('${kSettingShiftStart}_h', shiftStart.hour);
      prefs.setInt('${kSettingShiftStart}_m', shiftStart.minute);
    }
    if (shiftEnd != null) { 
      _shiftEnd = shiftEnd; 
      prefs.setInt('${kSettingShiftEnd}_h', shiftEnd.hour);
      prefs.setInt('${kSettingShiftEnd}_m', shiftEnd.minute);
    }
    notifyListeners();
  }

  // --- GOOGLE DRIVE LOGIC ---
  Future<drive.DriveApi?> _getDriveApi() async {
    if (_currentUser == null) return null;
    final headers = await _currentUser!.authHeaders;
    final client = GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  Future<String?> fetchCloudDataOnly() async {
    if (_currentUser == null) return null;
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;
      final fileList = await driveApi.files.list(q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents", spaces: 'appDataFolder');
      if (fileList.files?.isNotEmpty == true) {
        final fileId = fileList.files!.first.id!;
        final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final List<int> dataStore = [];
        await media.stream.listen((data) => dataStore.addAll(data)).asFuture();
        return utf8.decode(dataStore);
      }
    } catch (e) { print(e); }
    return null;
  }

  Future<bool> syncPayrollToCloud(List<Map<String, dynamic>> localData) async {
    if (_currentUser == null) return false;
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return false;
      final jsonString = jsonEncode(localData);
      final mediaContent = drive.Media(Stream.value(utf8.encode(jsonString)), utf8.encode(jsonString).length);
      final fileList = await driveApi.files.list(q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents", spaces: 'appDataFolder');
      if (fileList.files?.isNotEmpty == true) {
        await driveApi.files.update(drive.File(), fileList.files!.first.id!, uploadMedia: mediaContent);
      } else {
        await driveApi.files.create(drive.File(name: 'pay_tracker_backup.json', parents: ['appDataFolder']), uploadMedia: mediaContent);
      }
      return true;
    } catch (e) { return false; }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._headers);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}