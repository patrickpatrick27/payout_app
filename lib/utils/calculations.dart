import 'package:flutter/material.dart';

class PayrollCalculator {
  
  static double timeToDouble(TimeOfDay t) => t.hour + t.minute / 60.0;

  static TimeOfDay roundTime(TimeOfDay time, {required bool isStart}) {
    int totalMinutes = time.hour * 60 + time.minute;
    int remainder = totalMinutes % 30;
    int roundedMinutes = (remainder != 0) 
        ? (isStart ? totalMinutes + (30 - remainder) : totalMinutes - remainder)
        : totalMinutes;

    return TimeOfDay(hour: (roundedMinutes ~/ 60) % 24, minute: roundedMinutes % 60);
  }

  static int calculateLateMinutes(TimeOfDay actualIn, TimeOfDay shiftStart) {
    // VALIDATION: If inputs are null or somehow invalid, return 0 safety
    if (actualIn.hour < 0 || shiftStart.hour < 0) return 0;

    double actualVal = timeToDouble(actualIn);
    double startVal = timeToDouble(shiftStart);

    if (actualVal > startVal) {
      int startMins = shiftStart.hour * 60 + shiftStart.minute;
      int inMins = actualIn.hour * 60 + actualIn.minute;
      return inMins - startMins;
    }
    return 0;
  }

  static double calculateRegularHours({
    required TimeOfDay rawIn, 
    required TimeOfDay rawOut, 
    required TimeOfDay shiftStart, 
    required TimeOfDay shiftEnd,
    required bool isLateEnabled,
    bool roundEndTime = true, 
  }) {
    // 1. SAFETY VALIDATION: Prevent crash if times are identical
    if (rawIn == rawOut) return 0.0;

    TimeOfDay effectiveIn;
    if (isLateEnabled) {
      effectiveIn = shiftStart; 
      if (timeToDouble(rawIn) < timeToDouble(shiftStart)) {
        effectiveIn = shiftStart; 
      }
    } else {
      effectiveIn = roundTime(rawIn, isStart: true);
      if (timeToDouble(effectiveIn) < timeToDouble(shiftStart)) {
        effectiveIn = shiftStart;
      }
    }

    TimeOfDay effectiveOut = roundEndTime ? roundTime(rawOut, isStart: false) : rawOut;

    double start = timeToDouble(effectiveIn);
    double end = timeToDouble(effectiveOut);
    double limit = timeToDouble(shiftEnd);

    double actualEnd = (end > limit) ? limit : end;
    
    // VALIDATION: Handle Overnight Shifts (e.g. 22:00 to 06:00)
    if (actualEnd < start) actualEnd += 24;

    double duration = actualEnd - start;

    // VALIDATION: Ensure logic implies lunch only if duration > 4 hours
    if (duration > 4.0 && start <= 12.0 && actualEnd >= 13.0) duration -= 1.0;

    // FINAL SAFETY: Never return negative hours
    return duration > 0 ? duration : 0;
  }

  static double calculateOvertimeHours(TimeOfDay rawOut, TimeOfDay shiftEnd) {
    TimeOfDay paidOut = roundTime(rawOut, isStart: false);
    double end = timeToDouble(paidOut);
    double limit = timeToDouble(shiftEnd);
    
    // VALIDATION: Handle overnight OT (e.g. shift ends 22:00, worked til 01:00)
    if (end < limit) end += 24;

    if (end > limit) {
      return end - limit;
    }
    return 0.0;
  }
}