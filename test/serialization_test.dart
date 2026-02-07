import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_app/models/data_models.dart';
import 'dart:convert';

void main() {
  group('Data Serialization Tests', () {
    test('Shift Model survives JSON encoding and decoding', () {
      final originalShift = Shift(
        id: 'test-id-123',
        date: DateTime(2026, 2, 7),
        rawTimeIn: const TimeOfDay(hour: 8, minute: 30),
        rawTimeOut: const TimeOfDay(hour: 17, minute: 45),
        isManualPay: false,
        remarks: 'Safety Check',
        isHoliday: true,
        holidayMultiplier: 30.0,
      );

      final jsonString = jsonEncode(originalShift.toJson());
      final Map<String, dynamic> decodedMap = jsonDecode(jsonString);
      final restoredShift = Shift.fromJson(decodedMap);

      expect(restoredShift.id, originalShift.id);
      expect(restoredShift.remarks, 'Safety Check');
      expect(restoredShift.rawTimeIn.hour, 8);
      expect(restoredShift.rawTimeIn.minute, 30);
      expect(restoredShift.isHoliday, true);
      expect(restoredShift.holidayMultiplier, 30.0);
    });

    test('PayPeriod Model handles empty shift lists', () {
      final period = PayPeriod(
        id: 'period-1',
        name: 'Test Period',
        start: DateTime.now(),
        end: DateTime.now(),
        lastEdited: DateTime.now(),
        hourlyRate: 50.0,
        shifts: [],
      );

      final jsonString = jsonEncode(period.toJson());
      final restoredPeriod = PayPeriod.fromJson(jsonDecode(jsonString));

      expect(restoredPeriod.shifts.isEmpty, true);
      expect(restoredPeriod.hourlyRate, 50.0);
    });

    test('Sync Logic detects differences', () {
      // 1. Local Data (1 Shift)
      final localData = [
        Shift(id: '1', date: DateTime.now(), rawTimeIn: const TimeOfDay(hour: 8, minute:0), rawTimeOut: const TimeOfDay(hour: 17, minute:0), remarks: '').toJson()
      ];
      
      // 2. Cloud Data (2 Shifts)
      final cloudData = [
        Shift(id: '1', date: DateTime.now(), rawTimeIn: const TimeOfDay(hour: 8, minute:0), rawTimeOut: const TimeOfDay(hour: 17, minute:0), remarks: '').toJson(),
        Shift(id: '2', date: DateTime.now(), rawTimeIn: const TimeOfDay(hour: 9, minute:0), rawTimeOut: const TimeOfDay(hour: 18, minute:0), remarks: '').toJson()
      ];

      // 3. Compare JSON strings (Simulating your sync check)
      bool isDifferent = jsonEncode(localData) != jsonEncode(cloudData);
      
      expect(isDifferent, true);
    });
  });
}