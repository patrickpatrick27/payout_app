import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app_installer/flutter_app_installer.dart';

class GithubUpdateService {
  // ---------------- CONFIG ----------------
  static const String _owner = "patrickpatrick27";
  static const String _repo = "payout_app"; // Make sure your repo name matches this!
  // ----------------------------------------

  static Future<void> checkForUpdate(BuildContext context, {bool showNoUpdateMsg = false}) async {
    print("🔍 [UpdateService] Checking for updates...");
    
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      print("📱 Current Version: $currentVersion");

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String tagName = data['tag_name']; 
        
        // Clean version string (v1.0.1 -> 1.0.1)
        String latestVersion = tagName.replaceAll('v', '');
        print("☁️ GitHub Version: $latestVersion");

        // Find APK Asset
        String? apkUrl;
        List<dynamic> assets = data['assets'];
        
        for (var asset in assets) {
          if (asset['name'].toString().endsWith('.apk')) {
            apkUrl = asset['browser_download_url']; 
            break;
          }
        }

        if (apkUrl == null) {
          print("❌ No APK found in release");
          return;
        }

        bool isNewer = _isNewer(latestVersion, currentVersion);

        if (isNewer) {
          if (context.mounted) _showUpdateDialog(context, latestVersion, apkUrl);
        } else {
          if (showNoUpdateMsg && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("You are on the latest version!"), backgroundColor: Colors.green)
            );
          }
        }
      } else {
        print("❌ GitHub API Error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Update Check Failed: $e");
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      List<int> l = latest.split('.').map(int.parse).toList();
      List<int> c = current.split('.').map(int.parse).toList();

      for (int i = 0; i < l.length; i++) {
        if (i >= c.length) return true;
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
    } catch (e) {
      print("⚠️ Version parse error: $e");
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String version, String apkUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _UpdateProgressDialog(version: version, apkUrl: apkUrl);
      },
    );
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final String version;
  final String apkUrl;

  const _UpdateProgressDialog({required this.version, required this.apkUrl});

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  String _status = "Ready to download";
  double _progress = 0.0;
  bool _isDownloading = false;
  final Dio _dio = Dio();
  final FlutterAppInstaller _installer = FlutterAppInstaller();

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _status = "Downloading...";
    });

    try {
      Directory tempDir = await getTemporaryDirectory();
      String savePath = "${tempDir.path}/update.apk";

      await _dio.download(
        widget.apkUrl, 
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
              _status = "Downloading: ${(_progress * 100).toStringAsFixed(0)}%";
            });
          }
        },
      );

      setState(() => _status = "Installing...");
      await _installer.installApk(filePath: savePath);
      
      if (mounted) Navigator.pop(context);

    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Text("Update Available 🚀", style: TextStyle(color: textColor)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Version ${widget.version} is ready to install.", style: TextStyle(color: textColor)),
          const SizedBox(height: 20),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
            Text(_status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later", style: TextStyle(color: Colors.grey)),
          ),
        if (!_isDownloading)
          FilledButton(
            onPressed: _startDownload,
            child: const Text("Update Now"),
          ),
      ],
    );
  }
}