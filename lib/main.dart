import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/constants.dart';
import 'screens/dashboard_screen.dart';
import 'services/update_service.dart'; // Import Update Service

void main() {
  runApp(const PayTrackerApp());
}

class PayTrackerApp extends StatefulWidget {
  const PayTrackerApp({super.key});

  @override
  State<PayTrackerApp> createState() => _PayTrackerAppState();
}

class _PayTrackerAppState extends State<PayTrackerApp> {
  // Global App Settings
  bool use24HourFormat = false;
  bool isDarkMode = false;
  TimeOfDay globalShiftStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay globalShiftEnd = const TimeOfDay(hour: 17, minute: 0); 

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Auto-check for updates after UI builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GithubUpdateService.checkForUpdate(context);
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      use24HourFormat = prefs.getBool(kSetting24h) ?? false;
      isDarkMode = prefs.getBool(kSettingDarkMode) ?? false;
      
      String? startStr = prefs.getString(kSettingShiftStart);
      if (startStr != null) {
        final parts = startStr.split(':');
        globalShiftStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      String? endStr = prefs.getString(kSettingShiftEnd);
      if (endStr != null) {
        final parts = endStr.split(':');
        globalShiftEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    });
  }

  void _updateSettings({
    bool? isDark, 
    bool? is24h, 
    TimeOfDay? shiftStart, 
    TimeOfDay? shiftEnd
  }) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (isDark != null) {
        isDarkMode = isDark;
        prefs.setBool(kSettingDarkMode, isDark);
      }
      if (is24h != null) {
        use24HourFormat = is24h;
        prefs.setBool(kSetting24h, is24h);
      }
      if (shiftStart != null) {
        globalShiftStart = shiftStart;
        prefs.setString(kSettingShiftStart, "${shiftStart.hour}:${shiftStart.minute}");
      }
      if (shiftEnd != null) {
        globalShiftEnd = shiftEnd;
        prefs.setString(kSettingShiftEnd, "${shiftEnd.hour}:${shiftEnd.minute}");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pay Tracker Pro',
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        cardColor: Colors.white,
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF536DFE),
          onPrimary: Colors.white,
          secondary: Color(0xFF00BFA5),
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
          background: Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),

      home: PayPeriodListScreen(
        use24HourFormat: use24HourFormat,
        isDarkMode: isDarkMode,
        shiftStart: globalShiftStart,
        shiftEnd: globalShiftEnd,
        onUpdateSettings: _updateSettings,
      ),
    );
  }
}