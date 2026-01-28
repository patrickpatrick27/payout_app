import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class DriveService {
  // Use the 'appDataFolder' scope. This is a special hidden folder in Drive
  // that users can't see or mess with, but your app can use.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  drive.DriveApi? _api;

  // 1. SILENT LOGIN (Get Access to Drive)
  Future<bool> init() async {
    try {
      // Try to sign in silently first (if user is already logged in)
      var googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        // If not, force interactive sign in
        googleUser = await _googleSignIn.signIn();
      }
      
      if (googleUser == null) return false; // User cancelled

      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) return false;

      _api = drive.DriveApi(httpClient);
      return true;
    } catch (e) {
      print("Drive Init Error: $e");
      return false;
    }
  }

  // 2. DOWNLOAD (Load on Startup)
  Future<List<Map<String, dynamic>>?> fetchCloudData() async {
    if (_api == null) await init();
    if (_api == null) return null;

    try {
      // Find our specific file
      final fileId = await _findFileId();
      if (fileId == null) return null; // No backup exists yet

      // Download content
      final media = await _api!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Decode stream to String
      final List<int> dataStore = [];
      await media.stream.forEach((element) => dataStore.addAll(element));
      final String jsonString = utf8.decode(dataStore);

      // Convert JSON back to List
      final List<dynamic> rawList = jsonDecode(jsonString);
      return rawList.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print("Download Error: $e");
      return null;
    }
  }

  // 3. UPLOAD (Save on Change)
  Future<void> syncToCloud(List<Map<String, dynamic>> localData) async {
    if (_api == null) await init();
    if (_api == null) return;

    try {
      // Convert your data list to JSON
      final String jsonString = jsonEncode(localData);
      final List<int> fileBytes = utf8.encode(jsonString);
      final media = drive.Media(Stream.value(fileBytes), fileBytes.length);

      final fileId = await _findFileId();

      if (fileId != null) {
        // UPDATE existing file
        await _api!.files.update(
          drive.File(),
          fileId,
          uploadMedia: media,
        );
        print("☁️ Cloud Updated Successfully");
      } else {
        // CREATE new file (First time)
        final fileMetadata = drive.File()
          ..name = 'pay_tracker_data.json'
          ..parents = ['appDataFolder']; // <--- HIDDEN FOLDER

        await _api!.files.create(
          fileMetadata,
          uploadMedia: media,
        );
        print("☁️ Cloud Backup Created");
      }
    } catch (e) {
      print("Upload Error: $e");
    }
  }

  // Helper: Find file ID by name
  Future<String?> _findFileId() async {
    final list = await _api!.files.list(
      spaces: 'appDataFolder',
      q: "name = 'pay_tracker_data.json' and trashed = false",
    );
    return (list.files?.isNotEmpty == true) ? list.files!.first.id : null;
  }
  
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}