import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/calculations.dart';

class Shift {
  String id;
  DateTime date;
  TimeOfDay rawTimeIn;
  TimeOfDay rawTimeOut;
  bool isManualPay;
  double manualAmount;
  String remarks;
  bool isHoliday;
  double holidayMultiplier;

  Shift({
    required this.id,
    required this.date,
    required this.rawTimeIn,
    required this.rawTimeOut,
    this.isManualPay = false,
    this.manualAmount = 0.0,
    this.remarks = '',
    this.isHoliday = false,
    this.holidayMultiplier = 30.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'timeIn': '${rawTimeIn.hour}:${rawTimeIn.minute}',
    'timeOut': '${rawTimeOut.hour}:${rawTimeOut.minute}',
    'isManualPay': isManualPay,
    'manualAmount': manualAmount,
    'remarks': remarks,
    'isHoliday': isHoliday,
    'holidayMultiplier': holidayMultiplier,
  };

  factory Shift.fromJson(Map<String, dynamic> json) {
    TimeOfDay parseTime(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return Shift(
      id: json['id'],
      date: DateTime.parse(json['date']),
      rawTimeIn: parseTime(json['timeIn']),
      rawTimeOut: parseTime(json['timeOut']),
      isManualPay: json['isManualPay'] ?? false,
      manualAmount: (json['manualAmount'] ?? 0.0).toDouble(),
      remarks: json['remarks'] ?? '',
      isHoliday: json['isHoliday'] ?? false,
      holidayMultiplier: (json['holidayMultiplier'] ?? 30.0).toDouble(),
    );
  }

  // --- CRITICAL FIX: SMART DATE LOGIC ---
  DateTime get _startDateTime {
    return DateTime(date.year, date.month, date.day, rawTimeIn.hour, rawTimeIn.minute);
  }

  DateTime get _endDateTime {
    DateTime start = _startDateTime;
    DateTime end = DateTime(date.year, date.month, date.day, rawTimeOut.hour, rawTimeOut.minute);

    // FIX: Only treat as "Next Day" if Out is strictly BEFORE In.
    // Example 1 (Undertime): In 8:00 AM, Out 11:00 AM. 11 > 8. Same Day.
    // Example 2 (Overnight): In 8:00 PM, Out 5:00 AM. 5 < 20. Next Day.
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  double getRegularHours(TimeOfDay shiftStart, TimeOfDay shiftEnd, {bool isLateEnabled = true, bool roundEndTime = true}) {
    if (isManualPay) return 0.0;

    // 1. Calculate Actual Work Duration
    Duration worked = _endDateTime.difference(_startDateTime);
    double workedHours = worked.inMinutes / 60.0;

    // 2. Adjust Start Time (Late Logic)
    DateTime standardStart = DateTime(date.year, date.month, date.day, shiftStart.hour, shiftStart.minute);
    DateTime effectiveStart = _startDateTime;
    
    // If late deductions are ENABLED, we start counting from when they arrived.
    // If late deductions are DISABLED, and they arrived late, we pretend they arrived at 8:00 (for pay purposes), 
    // unless they arrived so late it's after the shift ended.
    if (!isLateEnabled && effectiveStart.isAfter(standardStart)) {
      // Only apply grace if they actually arrived within the shift window
      effectiveStart = standardStart; 
    }

    // 3. Adjust End Time (Undertime Logic)
    // We compare Actual Out vs Standard Out
    DateTime standardEnd = DateTime(date.year, date.month, date.day, shiftEnd.hour, shiftEnd.minute);
    // If standard end is before standard start (e.g. night shift 8pm-5am), move standard end to next day
    if (standardEnd.isBefore(standardStart)) {
      standardEnd = standardEnd.add(const Duration(days: 1));
    }

    DateTime effectiveEnd = _endDateTime;

    // Cap the "Regular Hours" at the Standard End time.
    // Anything after standardEnd is Overtime, not Regular.
    if (effectiveEnd.isAfter(standardEnd)) {
      effectiveEnd = standardEnd;
    }

    // 4. Calculate Duration
    Duration regularDuration = effectiveEnd.difference(effectiveStart);
    double hours = regularDuration.inMinutes / 60.0;

    // 5. Safety Checks
    if (hours < 0) return 0.0; 
    
    // If they worked LESS than the regular shift (Undertime), 'hours' will naturally be lower (e.g. 3.0)
    // If they worked MORE, the 'effectiveEnd' cap ensures this function returns max 8.0 (or whatever shift length is)
    
    return hours;
  }

  double getOvertimeHours(TimeOfDay shiftStart, TimeOfDay shiftEnd) {
    if (isManualPay) return 0.0;

    DateTime standardEnd = DateTime(date.year, date.month, date.day, shiftEnd.hour, shiftEnd.minute);
    DateTime standardStart = DateTime(date.year, date.month, date.day, shiftStart.hour, shiftStart.minute);
    
    // Handle overnight standard shift
    if (standardEnd.isBefore(standardStart)) {
      standardEnd = standardEnd.add(const Duration(days: 1));
    }

    DateTime actualEnd = _endDateTime;

    // Overtime is simply: Did you stay past the standard end?
    if (actualEnd.isAfter(standardEnd)) {
      Duration ot = actualEnd.difference(standardEnd);
      return ot.inMinutes / 60.0;
    }
    
    return 0.0;
  }
}

class PayPeriod {
  String id;
  String name;
  DateTime start;
  DateTime end;
  DateTime lastEdited;
  double hourlyRate; // Default 50.0
  List<Shift> shifts;

  PayPeriod({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.lastEdited,
    required this.hourlyRate,
    required this.shifts,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'lastEdited': lastEdited.toIso8601String(),
    'hourlyRate': hourlyRate,
    'shifts': shifts.map((s) => s.toJson()).toList(),
  };

  factory PayPeriod.fromJson(Map<String, dynamic> json) {
    return PayPeriod(
      id: json['id'],
      name: json['name'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      lastEdited: DateTime.parse(json['lastEdited']),
      hourlyRate: (json['hourlyRate'] ?? 50.0).toDouble(),
      shifts: (json['shifts'] as List).map((s) => Shift.fromJson(s)).toList(),
    );
  }
  
  void updateName() {
    name = "${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}";
  }

  double getTotalRegularHours(TimeOfDay shiftStart, TimeOfDay shiftEnd) {
    return shifts.fold(0.0, (sum, s) => sum + s.getRegularHours(shiftStart, shiftEnd));
  }

  double getTotalOvertimeHours(TimeOfDay shiftStart, TimeOfDay shiftEnd) {
    return shifts.fold(0.0, (sum, s) => sum + s.getOvertimeHours(shiftStart, shiftEnd));
  }
  
  double getTotalPay(TimeOfDay shiftStart, TimeOfDay shiftEnd, {double? hourlyRate, bool enableLate = true, bool enableOt = true}) {
    double rate = hourlyRate ?? this.hourlyRate;
    double total = 0.0;
    
    for (var s in shifts) {
      if (s.isManualPay) {
        total += s.manualAmount;
        continue;
      }

      double reg = s.getRegularHours(shiftStart, shiftEnd, isLateEnabled: enableLate);
      double ot = enableOt ? s.getOvertimeHours(shiftStart, shiftEnd) : 0.0;
      
      // Base Pay
      double dailyPay = (reg * rate) + (ot * rate * 1.25);

      // Late Deductions (Minute-by-minute)
      if (enableLate) {
         int lateMins = PayrollCalculator.calculateLateMinutes(s.rawTimeIn, shiftStart);
         if (lateMins > 0) {
           dailyPay -= (lateMins / 60.0) * rate;
         }
      }
      
      // Holiday/Double Pay Multiplier
      if (s.isHoliday && s.holidayMultiplier > 0) {
        dailyPay += dailyPay * (s.holidayMultiplier / 100.0);
      }
      
      total += (dailyPay > 0 ? dailyPay : 0);
    }
    return total;
  }
}