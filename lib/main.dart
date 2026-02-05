import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/data_manager.dart';
import 'services/update_service.dart';
import 'services/audio_service.dart'; 

// --- SCREEN IMPORTS ---
import 'screens/dashboard_screen.dart'; 
import 'screens/login_screen.dart';

// 1. GLOBAL NAVIGATOR KEY - This allows dialogs from anywhere (updates, alerts)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Preload sounds for instant playback
  // Ensure your AudioService.init() method exists and handles exceptions internally
  await AudioService().init(); 

  runApp(
    MultiProvider(
      providers: [
        // Initialize DataManager immediately
        ChangeNotifierProvider(create: (_) => DataManager()..initApp()),
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
    // 3. Auto-update check on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use the global key's context if available, otherwise fallback to local
      // This ensures the update dialog can show up even during navigation
      final contextToUse = navigatorKey.currentContext; 
      if (contextToUse != null) {
        GithubUpdateService.checkForUpdate(contextToUse, showNoUpdateMsg: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to DataManager for changes (Auth status, Theme, etc.)
    final dataManager = Provider.of<DataManager>(context);

    // 4. Show loading screen while SharedPrefs/GoogleSignIn initializes
    if (!dataManager.isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      // 5. REGISTER THE GLOBAL KEY
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      title: kDebugMode ? 'Pay Tracker (Dev)' : 'Pay Tracker',
      
      // 6. Theme Switching Logic
      themeMode: dataManager.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FA),
          surfaceTintColor: Colors.transparent, // Fix for washed out appbars
        ),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF536DFE),
          onPrimary: Colors.white, // Ensures text on buttons is readable
          secondary: Color(0xFF82B1FF),
          surface: Color(0xFF1E1E1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          surfaceTintColor: Colors.transparent,
        ),
      ),

      // 7. AUTH WRAPPER LOGIC
      // This decides which screen to show based on login status.
      // Since we wrap MaterialApp with Consumer<DataManager>, this rebuilds automatically.
      home: dataManager.isAuthenticated 
        ? PayPeriodListScreen(
            use24HourFormat: dataManager.use24HourFormat,
            isDarkMode: dataManager.isDarkMode,
            shiftStart: dataManager.shiftStart,
            shiftEnd: dataManager.shiftEnd,
            onUpdateSettings: ({
              isDark, is24h, hideMoney, currencySymbol, 
              shiftStart, shiftEnd, enableLate, enableOt, defaultRate
            }) {
              // Bridge Settings Screen -> Data Manager
              dataManager.updateSettings(
                isDark: isDark,
                is24h: is24h,
                enableLate: enableLate,
                enableOt: enableOt,
                defaultRate: defaultRate,
                shiftStart: shiftStart,
                shiftEnd: shiftEnd,
              );
            },
          )
        : const LoginScreen(),
    );
  }
}