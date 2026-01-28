import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard_screen.dart'; // Ensure this matches your file structure
import 'services/update_service.dart';
import 'services/data_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    // 1. INJECT THE DATA MANAGER
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DataManager()..loadData()),
      ],
      child: const PayTrackerApp(),
    ),
  );
}

class PayTrackerApp extends StatefulWidget {
  const PayTrackerApp({super.key});

  @override
  State<PayTrackerApp> createState() => _PayTrackerAppState();
}

class _PayTrackerAppState extends State<PayTrackerApp> {

  @override
  void initState() {
    super.initState();
    // Auto-check for updates (UI must build first)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GithubUpdateService.checkForUpdate(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 2. LISTEN TO SETTINGS CHANGES
    final dataManager = Provider.of<DataManager>(context);

    if (dataManager.isLoading) {
      // Show simple loader while fetching settings
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pay Tracker Pro',
      
      // 3. USE DATA MANAGER SETTINGS
      themeMode: dataManager.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
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

      // 4. PASS DATA MANAGER TO DASHBOARD
      home: PayPeriodListScreen(
        // We pass the values directly from our Provider
        use24HourFormat: dataManager.use24HourFormat,
        isDarkMode: dataManager.isDarkMode,
        shiftStart: dataManager.shiftStart,
        shiftEnd: dataManager.shiftEnd,
        
        // When settings change, we call the Provider method
        onUpdateSettings: ({isDark, is24h, shiftStart, shiftEnd}) {
          dataManager.updateSettings(
            isDark: isDark,
            is24h: is24h,
            shiftStart: shiftStart,
            shiftEnd: shiftEnd,
          );
        },
      ),
    );
  }
}