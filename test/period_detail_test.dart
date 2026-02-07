import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// IMPORTS (Replace 'work_app' with your actual package name from pubspec.yaml)
import 'package:work_app/screens/period_detail_screen.dart';
import 'package:work_app/models/data_models.dart';
import 'package:work_app/services/data_manager.dart';

void main() {
  // Setup Mock Data before tests run
  setUp(() {
    SharedPreferences.setMockInitialValues({}); // Fake the storage
  });

  testWidgets('Holiday toggle slides open the Percent Increase input', (WidgetTester tester) async {
    // 1. Create Dummy Data
    final dummyPeriod = PayPeriod(
      id: 'test_id',
      name: 'Test Period',
      start: DateTime.now(),
      end: DateTime.now().add(const Duration(days: 15)),
      lastEdited: DateTime.now(),
      hourlyRate: 100.0,
      shifts: [],
    );

    // 2. Build the Screen (Wrapped in Providers & MaterialApp)
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DataManager()),
        ],
        child: MaterialApp(
          home: PeriodDetailScreen(
            period: dummyPeriod,
            use24HourFormat: false,
            shiftStart: const TimeOfDay(hour: 8, minute: 0),
            shiftEnd: const TimeOfDay(hour: 17, minute: 0),
            hideMoney: false,
            currencySymbol: '₱',
            onSave: () {},
            enableLate: true,
            enableOt: true,
          ),
        ),
      ),
    );

    // 3. Open the "Add Shift" dialog
    // We tap the Floating Action Button (FAB)
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(); // Wait for the bottom sheet to slide up

    // 4. Verify "Percent Increase" is HIDDEN initially
    expect(find.text('Percent Increase (%)'), findsNothing);

    // 5. Tap the "Holiday / Rest" toggle
    await tester.tap(find.text('Holiday / Rest'));
    
    // 6. Pump frames to allow the animation to complete
    await tester.pumpAndSettle();

    // 7. Verify "Percent Increase" is NOW VISIBLE
    expect(find.text('Percent Increase (%)'), findsOneWidget);
    
    // 8. Test the reverse: Tap "Regular"
    await tester.tap(find.text('Regular'));
    await tester.pumpAndSettle();
    
    // 9. Verify it is HIDDEN again
    expect(find.text('Percent Increase (%)'), findsNothing);
  });
}