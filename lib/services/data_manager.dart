import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class DataManager extends ChangeNotifier {
  // Scope required for App Data Folder (Hidden storage in user's Drive)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? _currentUser;
  bool _isInitialized = false;
  
  // Settings State
  bool _isDarkMode = false;
  bool _use24HourFormat = false;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _currentUser != null;
  bool get isGuest => _currentUser == null;
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
    
    int startH = prefs.getInt('${kSettingShiftStart}_h') ?? 8;
    int startM = prefs.getInt('${kSettingShiftStart}_m') ?? 0;
    _shiftStart = TimeOfDay(hour: startH, minute: startM);

    int endH = prefs.getInt('${kSettingShiftEnd}_h') ?? 17;
    int endM = prefs.getInt('${kSettingShiftEnd}_m') ?? 0;
    _shiftEnd = TimeOfDay(hour: endH, minute: endM);

    // Try Silent Login (Restore session if online)
    try {
      _currentUser = await _googleSignIn.signInSilently();
    } catch (e) {
      print("Silent Login Failed (Offline?): $e");
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  // --- 2. AUTHENTICATION ---
  Future<bool> loginWithGoogle() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    
    // Clear local data for privacy on logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pay_tracker_data');
    await prefs.remove(kStorageKey);
    await prefs.remove('is_unsynced');
    
    notifyListeners();
  }

  void continueAsGuest() {
    _currentUser = null; 
    notifyListeners();
  }

  // --- 3. SETTINGS MANAGEMENT ---
  void updateSettings({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) async {
    final prefs = await SharedPreferences.getInstance();
    if (isDark != null) {
      _isDarkMode = isDark;
      prefs.setBool(kSettingDarkMode, isDark);
    }
    if (is24h != null) {
      _use24HourFormat = is24h;
      prefs.setBool(kSetting24h, is24h);
    }
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

  // --- 4. CLOUD SYNC LOGIC ---

  // Authenticated HTTP Client for Drive API
  Future<drive.DriveApi?> _getDriveApi() async {
    if (_currentUser == null) return null;
    final headers = await _currentUser!.authHeaders;
    final client = GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  /// METHOD A: Read Cloud Data (Returns Raw JSON String)
  /// Used for comparing Cloud vs Local data
  Future<String?> fetchCloudDataOnly() async {
    if (_currentUser == null) return null;
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      // Find the backup file in AppData folder
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

  /// METHOD B: Upload Local Data to Cloud (Overwrite)
  /// Returns TRUE if successful, FALSE if failed
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

      // Check if file exists
      final fileList = await driveApi.files.list(
        q: "name = 'pay_tracker_backup.json' and 'appDataFolder' in parents",
        spaces: 'appDataFolder',
      );

      if (fileList.files?.isNotEmpty == true) {
        // Update existing file
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(
          drive.File(),
          fileId,
          uploadMedia: mediaContent,
        );
      } else {
        // Create new file
        await driveApi.files.create(
          drive.File(
            name: 'pay_tracker_backup.json',
            parents: ['appDataFolder'],
          ),
          uploadMedia: mediaContent,
        );
      }
      return true; // Sync Success
    } catch (e) {
      print("Sync Upload Error: $e");
      return false; // Sync Failed
    }
  }

  /// METHOD C: Smart Sync (Legacy / Quick Merge)
  /// Returns a status message string
  Future<String> smartSync(List<Map<String, dynamic>> localData) async {
    try {
      String? cloudJson = await fetchCloudDataOnly();
      if (cloudJson == null) {
        // No cloud data? Upload what we have.
        bool success = await syncPayrollToCloud(localData);
        return success ? "Cloud backup created." : "Offline: Saved to device.";
      }
      
      // If cloud data exists, the Dashboard UI will usually handle the conflict logic.
      // But if we call this directly, we just report that data exists.
      return "Cloud data found.";
    } catch (e) {
      return "Error: $e";
    }
  }
}

// Helper Client for Google Auth Headers
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