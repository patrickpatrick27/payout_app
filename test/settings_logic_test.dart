import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_app/services/data_manager.dart';
import 'package:work_app/utils/constants.dart'; 

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // Required for SharedPreferences mock

  group('Settings Logic Tests', () {
    late DataManager manager;

    setUp(() async {
      // Clear mocks before every test
      SharedPreferences.setMockInitialValues({});
      manager = DataManager();
      await manager.initApp();
    });

    test('Settings update toggles correctly', () async {
      // Verify initial state (False by default in mock)
      expect(manager.use24HourFormat, false);
      expect(manager.isDarkMode, false);

      // ACTION: Toggle 24h format
      await manager.updateSettings(is24h: true);

      // VERIFY: State updated
      expect(manager.use24HourFormat, true);
      
      // VERIFY: Saved to Disk (Check against the constant key)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSetting24h), true);
    });

    test('Settings update hourly rate', () async {
      // ACTION: Change rate
      await manager.updateSettings(defaultRate: 75.50);

      // VERIFY
      expect(manager.defaultHourlyRate, 75.50);
      
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('default_hourly_rate'), 75.50);
    });

    test('Settings update Shift Times', () async {
      const newStart = TimeOfDay(hour: 9, minute: 30);
      
      // ACTION: Update Shift Start
      await manager.updateSettings(shiftStart: newStart);

      // VERIFY
      expect(manager.shiftStart.hour, 9);
      expect(manager.shiftStart.minute, 30);
    });
  });
}