import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class DriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  drive.DriveApi? _api;
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<bool> trySilentLogin() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _initializeClient();
        return true;
      }
    } catch (e) {
      print("Silent Login Error: $e");
    }
    return false;
  }

  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _initializeClient();
        return true;
      }
    } catch (e) {
      print("Sign In Error: $e");
    }
    return false;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _api = null;
  }

  Future<void> _initializeClient() async {
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient != null) {
      _api = drive.DriveApi(httpClient);
    }
  }

  // --- DRIVE OPERATIONS ---

  Future<List<Map<String, dynamic>>?> fetchCloudData() async {
    if (_api == null) return null;
    try {
      final fileId = await _findFileId();
      if (fileId == null) {
        print("No backup file found on Drive.");
        return null;
      }

      final media = await _api!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataStore = [];
      await media.stream.forEach((element) => dataStore.addAll(element));
      
      if (dataStore.isEmpty) return null;
      
      final String jsonString = utf8.decode(dataStore);
      final List<dynamic> rawList = jsonDecode(jsonString);
      return rawList.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print("Fetch Error: $e");
      return null;
    }
  }

  // Returns TRUE if success, FALSE if failed
  Future<bool> syncToCloud(List<Map<String, dynamic>> data) async {
    if (_api == null) return false; 
    try {
      final String jsonString = jsonEncode(data);
      final List<int> fileBytes = utf8.encode(jsonString);
      final media = drive.Media(Stream.value(fileBytes), fileBytes.length);

      final fileId = await _findFileId();

      if (fileId != null) {
        // Update existing file
        await _api!.files.update(drive.File(), fileId, uploadMedia: media);
        print("Updated existing Drive file: $fileId");
      } else {
        // Create new file
        final fileMetadata = drive.File()
          ..name = 'pay_tracker_data.json'
          ..parents = ['appDataFolder']; // HIDDEN FOLDER
        
        await _api!.files.create(fileMetadata, uploadMedia: media);
        print("Created new Drive file");
      }
      return true;
    } catch (e) {
      print("Sync Error: $e");
      return false;
    }
  }

  Future<String?> _findFileId() async {
    if (_api == null) return null;
    try {
      final list = await _api!.files.list(
        spaces: 'appDataFolder',
        q: "name = 'pay_tracker_data.json' and trashed = false",
        $fields: "files(id, name)",
      );
      return (list.files?.isNotEmpty == true) ? list.files!.first.id : null;
    } catch (e) {
      print("Find File Error: $e");
      return null;
    }
  }
}