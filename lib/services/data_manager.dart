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
  bool _isGuestMode = false; // NEW: Explicit Guest State
  
  // Settings State
  bool _isDarkMode = false;
  bool _use24HourFormat = false;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  // Getters
  bool get isInitialized => _isInitialized;
  // User is authenticated if logged in OR in guest mode
  bool get isAuthenticated => _currentUser != null || _isGuestMode;
  bool get isGuest => _isGuestMode; 
  
  String? get userEmail => _currentUser?.email;
  String? get userPhoto => _currentUser?.photoUrl;
  
  bool get isDarkMode => _isDarkMode;
  bool get use24HourFormat => _use24HourFormat;
  TimeOfDay get shiftStart => _shiftStart;
  TimeOfDay get shiftEnd => _shiftEnd;

  // --- 1. INITIALIZATION ---
  Future<void> initApp() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Local Settings
    _isDarkMode = prefs.getBool(kSettingDarkMode) ?? false;
    _use24HourFormat = prefs.getBool(kSetting24h) ?? false;
    _isGuestMode = prefs.getBool('is_guest_mode') ?? false; // Restore Guest State
    
    int startH = prefs.getInt('${kSettingShiftStart}_h') ?? 8;
    int startM = prefs.getInt('${kSettingShiftStart}_m') ?? 0;
    _shiftStart = TimeOfDay(hour: startH, minute: startM);

    int endH = prefs.getInt('${kSettingShiftEnd}_h') ?? 17;
    int endM = prefs.getInt('${kSettingShiftEnd}_m') ?? 0;
    _shiftEnd = TimeOfDay(hour: endH, minute: endM);

    // Try Silent Login (only if not in guest mode)
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

  // --- 2. AUTHENTICATION ---
  Future<bool> loginWithGoogle() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      
      if (_currentUser != null) {
        // Turn off guest mode
        _isGuestMode = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_guest_mode', false);

        // AUTO-FETCH: Pull cloud data immediately
        String? cloudJson = await fetchCloudDataOnly();
        if (cloudJson != null && cloudJson.isNotEmpty) {
           await prefs.setString('pay_tracker_data', cloudJson);
           // Also save to legacy key for compatibility
           await prefs.setString(kStorageKey, cloudJson);
        }
      }

      notifyListeners(); // Updates UI to Dashboard
      return _currentUser != null;
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _isGuestMode = false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest_mode', false);
    
    // Clear local data for privacy protection
    await prefs.remove('pay_tracker_data');
    await prefs.remove(kStorageKey);
    await prefs.remove('is_unsynced');
    
    notifyListeners();
  }

  void continueAsGuest() async {
    _currentUser = null;
    _isGuestMode = true;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest_mode', true);
    
    notifyListeners(); // Updates UI to Dashboard
  }

  // --- 3. SETTINGS & SYNC ---
  void updateSettings({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) async {
    final prefs = await SharedPreferences.getInstance();
    if (isDark != null) { _isDarkMode = isDark; prefs.setBool(kSettingDarkMode, isDark); }
    if (is24h != null) { _use24HourFormat = is24h; prefs.setBool(kSetting24h, is24h); }
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

      final fileList = await driveApi.files.list(
        q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents",
        spaces: 'appDataFolder',
      );

      if (fileList.files?.isNotEmpty == true) {
        final fileId = fileList.files!.first.id!;
        final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final List<int> dataStore = [];
        await media.stream.listen((data) => dataStore.addAll(data)).asFuture();
        return utf8.decode(dataStore);
      }
    } catch (e) {
      print("Fetch Cloud Error: $e");
    }
    return null;
  }

  Future<bool> syncPayrollToCloud(List<Map<String, dynamic>> localData) async {
    if (_currentUser == null) return false;
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return false;

      final jsonString = jsonEncode(localData);
      final mediaContent = drive.Media(
        Stream.value(utf8.encode(jsonString)),
        utf8.encode(jsonString).length,
      );

      final fileList = await driveApi.files.list(
        q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents",
        spaces: 'appDataFolder',
      );

      if (fileList.files?.isNotEmpty == true) {
        await driveApi.files.update(drive.File(), fileList.files!.first.id!, uploadMedia: mediaContent);
      } else {
        await driveApi.files.create(
          drive.File(name: 'pay_tracker_backup.json', parents: ['appDataFolder']),
          uploadMedia: mediaContent,
        );
      }
      return true;
    } catch (e) {
      print("Sync Upload Error: $e");
      return false;
    }
  }

  Future<String> smartSync(List<Map<String, dynamic>> localData) async {
    try {
      String? cloudJson = await fetchCloudDataOnly();
      if (cloudJson == null) {
        bool success = await syncPayrollToCloud(localData);
        return success ? "Cloud backup created." : "Offline: Saved to device.";
      }
      return "Cloud data found.";
    } catch (e) {
      return "Error: $e";
    }
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