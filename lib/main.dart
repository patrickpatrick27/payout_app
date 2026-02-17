import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/data_manager.dart';
import 'services/update_service.dart';
import 'services/audio_service.dart'; 

import 'screens/dashboard_screen.dart'; 
import 'screens/login_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService().init(); 

  runApp(
    // DIRECTLY RUN MULTIPROVIDER (No DevicePreview wrapper)
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contextToUse = navigatorKey.currentContext; 
      if (contextToUse != null) {
        GithubUpdateService.checkForUpdate(contextToUse, showNoUpdateMsg: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataManager>(
      builder: (context, dataManager, child) {
        
        if (!dataManager.isInitialized) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return MaterialApp(
          // REMOVED: useInheritedMediaQuery, locale, and builder
          
          navigatorKey: navigatorKey, 
          debugShowCheckedModeBanner: false,
          title: kDebugMode ? 'Pay Tracker (Dev)' : 'Pay Tracker',
          
          themeMode: dataManager.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
            scaffoldBackgroundColor: const Color(0xFFF5F7FA),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F7FA),
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
            ),
            cardColor: Colors.white,
          ),

          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF536DFE),
              onPrimary: Colors.white, 
              secondary: Color(0xFF82B1FF),
              surface: Color(0xFF1E1E1E),
            ),
            scaffoldBackgroundColor: const Color(0xFF121212), 
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
            ),
            cardColor: const Color(0xFF1E1E1E),
          ),

          home: dataManager.isAuthenticated 
            ? PayPeriodListScreen(
                use24HourFormat: dataManager.use24HourFormat,
                isDarkMode: dataManager.isDarkMode,
                shiftStart: dataManager.shiftStart,
                shiftEnd: dataManager.shiftEnd,
                onUpdateSettings: ({
                  isDark, is24h, hideMoney, currencySymbol, 
                  shiftStart, shiftEnd, enableLate, enableOt, defaultRate,
                  snapToGrid
                }) {
                  dataManager.updateSettings(
                    isDark: isDark,
                    is24h: is24h,
                    enableLate: enableLate,
                    enableOt: enableOt,
                    defaultRate: defaultRate,
                    shiftStart: shiftStart,
                    shiftEnd: shiftEnd,
                    snapToGrid: snapToGrid,
                  );
                },
              )
            : const LoginScreen(),
        );
      },
    );
  }
}