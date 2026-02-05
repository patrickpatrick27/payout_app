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
  
  // NEW: Holiday Fields
  bool isHoliday; 
  double holidayMultiplier; // e.g., 30.0 for 30% increase

  Shift({
    required this.id,
    required this.date,
    required this.rawTimeIn,
    required this.rawTimeOut,
    this.isManualPay = false,
    this.manualAmount = 0.0,
    this.remarks = "",
    this.isHoliday = false,
    this.holidayMultiplier = 0.0,
  });

  @override
  bool operator ==(Object other) =>
      other is Shift &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => date.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'rawTimeIn': '${rawTimeIn.hour}:${rawTimeIn.minute}',
        'rawTimeOut': '${rawTimeOut.hour}:${rawTimeOut.minute}',
        'isManualPay': isManualPay,
        'manualAmount': manualAmount,
        'remarks': remarks,
        'isHoliday': isHoliday,
        'holidayMultiplier': holidayMultiplier,
      };

  factory Shift.fromJson(Map<String, dynamic> json) {
    final tIn = json['rawTimeIn'].split(':');
    final tOut = json['rawTimeOut'].split(':');
    return Shift(
      id: json['id'],
      date: DateTime.parse(json['date']),
      rawTimeIn: TimeOfDay(hour: int.parse(tIn[0]), minute: int.parse(tIn[1])),
      rawTimeOut: TimeOfDay(hour: int.parse(tOut[0]), minute: int.parse(tOut[1])),
      isManualPay: json['isManualPay'] ?? false,
      manualAmount: (json['manualAmount'] ?? 0.0).toDouble(),
      remarks: json['remarks'] ?? "",
      isHoliday: json['isHoliday'] ?? false,
      holidayMultiplier: (json['holidayMultiplier'] ?? 0.0).toDouble(),
    );
  }

  // Helper delegates to Calculator
  double getRegularHours(TimeOfDay globalStart, TimeOfDay globalEnd, {
    required bool isLateEnabled, 
    bool roundEndTime = true
  }) {
    return PayrollCalculator.calculateRegularHours(
      rawIn: rawTimeIn, 
      rawOut: rawTimeOut, 
      shiftStart: globalStart, 
      shiftEnd: globalEnd,
      isLateEnabled: isLateEnabled,
      roundEndTime: roundEndTime 
    );
  }

  double getOvertimeHours(TimeOfDay globalStart, TimeOfDay globalEnd) {
    return PayrollCalculator.calculateOvertimeHours(rawTimeOut, globalEnd);
  }
}

class PayPeriod {
  String id;
  String name;
  DateTime start;
  DateTime end;
  DateTime lastEdited; 
  double hourlyRate; 
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
        'id': id, 'name': name, 'start': start.toIso8601String(), 'end': end.toIso8601String(),
        'lastEdited': lastEdited.toIso8601String(), 'hourlyRate': hourlyRate,
        'shifts': shifts.map((s) => s.toJson()).toList(),
      };

  factory PayPeriod.fromJson(Map<String, dynamic> json) {
    return PayPeriod(
      id: json['id'], name: json['name'],
      start: DateTime.parse(json['start']), end: DateTime.parse(json['end']),
      lastEdited: json['lastEdited'] != null ? DateTime.parse(json['lastEdited']) : DateTime.now(),
      hourlyRate: (json['hourlyRate'] as num).toDouble(),
      shifts: (json['shifts'] as List).map((s) => Shift.fromJson(s)).toList(),
    );
  }

  double getTotalPay(TimeOfDay shiftStart, TimeOfDay shiftEnd, {
    required double hourlyRate, 
    bool enableLate = true, 
    bool enableOt = true
  }) {
    double total = 0;
    for (var shift in shifts) {
      if (shift.isManualPay) {
        total += shift.manualAmount;
        continue;
      }
      double hours = shift.getRegularHours(shiftStart, shiftEnd, isLateEnabled: enableLate, roundEndTime: true);
      double ot = enableOt ? shift.getOvertimeHours(shiftStart, shiftEnd) : 0.0;
      
      // 1. Base Pay Calculation
      double pay = (hours * hourlyRate) + (ot * hourlyRate * 1.25);

      // 2. Late Deductions
      if (enableLate) {
        int lateMins = PayrollCalculator.calculateLateMinutes(shift.rawTimeIn, shiftStart);
        if (lateMins > 0) {
          pay -= (lateMins / 60.0) * hourlyRate;
        }
      }

      // 3. NEW: Holiday Multiplier
      // Example: If multiplier is 30, we add 30% of the calculated pay
      if (shift.isHoliday && shift.holidayMultiplier > 0) {
        pay += pay * (shift.holidayMultiplier / 100.0);
      }

      total += (pay > 0 ? pay : 0.0);
    }
    return total;
  }

  double getTotalRegularHours(TimeOfDay shiftStart, TimeOfDay shiftEnd) {
    return shifts.fold(0, (sum, s) => sum + s.getRegularHours(shiftStart, shiftEnd, isLateEnabled: true, roundEndTime: true));
  }
  
  double getTotalOvertimeHours(TimeOfDay shiftStart, TimeOfDay shiftEnd) {
    return shifts.fold(0, (sum, s) => sum + s.getOvertimeHours(shiftStart, shiftEnd));
  }

  void updateName() {
    final dateFormat = DateFormat('MMM d, yyyy');
    name = "${dateFormat.format(start)} - ${dateFormat.format(end)}";
  }
}