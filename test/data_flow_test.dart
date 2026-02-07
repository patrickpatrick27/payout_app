import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_app/models/data_models.dart'; 

void main() {
  group('Integration: Pay Period & Shifts', () {
    
    test('Adding a Holiday Shift correctly increases Total Pay', () {
      // 1. Setup the Pay Period (Rate: 100/hr)
      final period = PayPeriod(
        id: '1', 
        name: 'Integration Test', 
        start: DateTime.now(), 
        end: DateTime.now(),
        lastEdited: DateTime.now(), 
        hourlyRate: 100.0, 
        shifts: []
      );

      // 2. Create a Shift (8 hours work)
      final shift = Shift(
        id: 's1',
        date: DateTime.now(),
        rawTimeIn: const TimeOfDay(hour: 8, minute: 0),
        rawTimeOut: const TimeOfDay(hour: 17, minute: 0), // 9 hrs - 1 hr lunch = 8 hrs
        isHoliday: true,
        holidayMultiplier: 50.0, // 50% Increase
      );

      // 3. Add shift to period
      period.shifts.add(shift);

      // 4. Calculate Total
      // Base Pay: 8 hours * 100 = 800
      // Holiday Bonus: 50% of 800 = 400
      // Expected Total: 1200
      
      double total = period.getTotalPay(
        const TimeOfDay(hour: 8, minute: 0), // Shift Start
        const TimeOfDay(hour: 17, minute: 0), // Shift End
        hourlyRate: 100.0,
        enableLate: true,
        enableOt: true
      );

      // 5. Verify
      expect(total, 1200.0);
    });
  });
}