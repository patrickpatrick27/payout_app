import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:work_app/main.dart'; 
import 'package:work_app/services/data_manager.dart';
import 'package:work_app/services/audio_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Master Test: Settings -> 2 Payrolls -> Specific Shift Scenarios -> Manual Takeover', (tester) async {
    
    // =========================================================================
    // 1. SETUP & INITIALIZATION
    // =========================================================================
    print("🔹 STEP 1: INITIALIZING FRESH APP...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Wipe previous data
    
    await AudioService().init();
    final dataManager = DataManager();
    await dataManager.initApp(); 

    // Launch App
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: dataManager)],
        child: const PayTrackerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Guest Login
    print("🔹 STEP 2: GUEST LOGIN");
    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(find.text('Pay Tracker'), findsOneWidget);


    // =========================================================================
    // 2. TOGGLE ALL SETTINGS
    // =========================================================================
    print("🔹 STEP 3: TESTING SETTINGS TOGGLES");
    // Use CupertinoIcons.settings
    await tester.tap(find.byIcon(CupertinoIcons.settings));
    await tester.pumpAndSettle();

    // Toggle all switches found on screen
    final switches = find.byType(Switch);
    for (int i = 0; i < switches.evaluate().length; i++) {
      await tester.tap(find.byType(Switch).at(i));
      await tester.pumpAndSettle(const Duration(milliseconds: 30)); 
    }
    
    // Scroll down to see bottom settings
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Go back to Dashboard
    await tester.pageBack();
    await tester.pumpAndSettle();


    // =========================================================================
    // 3. CREATE PAYROLL A (Feb 1 - 15)
    // =========================================================================
    print("🔹 STEP 4: CREATING PAYROLL A (Feb 1 - 15)");
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Payroll'));
    await tester.pumpAndSettle();

    // Confirm Start/End (Default dates)
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();


    // =========================================================================
    // 4. POPULATE PAYROLL A (Normal Shifts Loop)
    // =========================================================================
    print("🔹 STEP 5: FILLING PAYROLL A");
    
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byType(FloatingActionButton)); 
      await tester.pumpAndSettle();

      // Open Date Picker
      await tester.tap(find.byIcon(CupertinoIcons.calendar).first); 
      await tester.pumpAndSettle();

      // Scroll the MIDDLE column (Day) to pick different days
      final pickerLocation = tester.getCenter(find.byType(CupertinoDatePicker));
      await tester.dragFrom(pickerLocation, Offset(0, 40.0 * (i + 1))); 
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm')); 
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Shift'));
      await tester.pumpAndSettle();
    }
    
    await tester.pageBack(); // Back to Dashboard
    await tester.pumpAndSettle();


    // =========================================================================
    // 5. CREATE PAYROLL B (Feb 16 - 28)
    // =========================================================================
    print("🔹 STEP 6: CREATING PAYROLL B (Next Period)");
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Payroll'));
    await tester.pumpAndSettle();

    // Scroll Start Date (Move Month/Day significantly)
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, -100)); 
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Scroll End Date
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, -100)); 
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();


    // =========================================================================
    // 6. COMPLEX SCENARIOS (Late, OT+30%, Double Pay)
    // =========================================================================
    print("🔹 STEP 7: ADDING COMPLEX SHIFTS");

    // --- SCENARIO 1: LATE SHIFT ---
    print("   -> Adding Late Shift");
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    
    // Tap "IN" time
    await tester.tap(find.text('IN')); 
    await tester.pumpAndSettle();
    
    // Scroll Hour Column (Left side of picker)
    final timePickerCenter = tester.getCenter(find.byType(CupertinoDatePicker));
    await tester.dragFrom(timePickerCenter + const Offset(-50, 0), const Offset(0, -50)); 
    await tester.pumpAndSettle();
    
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    
    // Add Remark
    await tester.enterText(find.byType(TextField).last, "Late Test");
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Shift'));
    await tester.pumpAndSettle();


    // --- SCENARIO 2: OVERTIME + 30% HOLIDAY ---
    print("   -> Adding OT + 30% Shift");
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Change Date
    await tester.tap(find.byIcon(CupertinoIcons.calendar).first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, 50)); 
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Tap "OUT" time
    await tester.tap(find.text('OUT'));
    await tester.pumpAndSettle();
    // Drag Hour forward
    await tester.dragFrom(tester.getCenter(find.byType(CupertinoDatePicker)) + const Offset(-50, 0), const Offset(0, -100)); 
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Enable Holiday & Set 30%
    await tester.tap(find.text('Holiday / Rest')); 
    await tester.pumpAndSettle();
    
    // Find input by exact label
    await tester.enterText(find.widgetWithText(TextField, 'Percent Increase (%)'), '30');
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Remarks (Optional)'), "OT + 30%");
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Shift'));
    await tester.pumpAndSettle();


    // --- SCENARIO 3: DOUBLE PAY (100%) ---
    print("   -> Adding Double Pay (100%) Shift");
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Change Date
    await tester.tap(find.byIcon(CupertinoIcons.calendar).first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, 100)); 
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Enable Holiday & Set 100%
    await tester.tap(find.text('Holiday / Rest')); 
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Percent Increase (%)'), '100');
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Remarks (Optional)'), "Double Pay");
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Shift'));
    await tester.pumpAndSettle();


    // =========================================================================
    // 7. VERIFY & MANUAL TAKEOVER
    // =========================================================================
    print("🔹 STEP 8: VERIFICATION");
    
    expect(find.text('Late Test'), findsOneWidget);
    expect(find.text('OT + 30%'), findsOneWidget);
    expect(find.text('Double Pay'), findsOneWidget);

    await tester.pageBack(); // Back to Dashboard
    await tester.pumpAndSettle();
    
    print("✅ TEST PASSED.");
    print("🟢 YOU CAN NOW USE THE APP MANUALLY!");
    print("   (Data was NOT deleted. Press 'q' in terminal to stop.)");

    // --- INFINITE LOOP TO KEEP APP ALIVE ---
    while (true) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}