import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/data_manager.dart';
import 'services/update_service.dart';
import 'services/audio_service.dart'; // <--- IMPORTANT: Audio Import

// --- SCREEN IMPORTS ---
import 'screens/dashboard_screen.dart'; // <--- FIX: Ensure this file exists and contains PayPeriodListScreen
import 'screens/login_screen.dart';

// 1. GLOBAL NAVIGATOR KEY - This allows dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async { // <--- UPDATED: Must be async for audio preload
  WidgetsFlutterBinding.ensureInitialized();
  
  // <--- ADDED: Preload sounds for instant playback
  await AudioService().init(); 

  runApp(
    MultiProvider(
      providers: [
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
    // Auto-update check on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use the global key's context if available, otherwise fallback to local
      final contextToUse = navigatorKey.currentContext ?? context;
      if (contextToUse != null) {
        GithubUpdateService.checkForUpdate(contextToUse);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataManager = Provider.of<DataManager>(context);

    if (!dataManager.isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      // 2. REGISTER THE KEY HERE
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      title: kDebugMode ? 'Pay Tracker (Dev)' : 'Pay Tracker',
      themeMode: dataManager.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF536DFE),
          surface: Color(0xFF1E1E1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), 
      ),

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