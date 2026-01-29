import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/data_models.dart';

void playClickSound(BuildContext context) {
  Feedback.forTap(context);
  SystemSound.play(SystemSoundType.click);
}

double timeToDouble(TimeOfDay t) => t.hour + t.minute / 60.0;

String formatTime(BuildContext context, TimeOfDay time, bool use24h) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return DateFormat(use24h ? 'HH:mm' : 'h:mm a').format(dt);
}

TimeOfDay roundTime(TimeOfDay time, {required bool isStart}) {
  int totalMinutes = time.hour * 60 + time.minute;
  int remainder = totalMinutes % 30;

  int roundedMinutes;
  if (remainder != 0) {
    if (isStart) {
      roundedMinutes = totalMinutes + (30 - remainder);
    } else {
      roundedMinutes = totalMinutes - remainder;
    }
  } else {
    roundedMinutes = totalMinutes;
  }

  int h = (roundedMinutes ~/ 60) % 24;
  int m = roundedMinutes % 60;
  return TimeOfDay(hour: h, minute: m);
}

// --- MISSING FUNCTIONS FIXED BELOW ---

/// Checks if a shift already exists for a specific date in the list
bool isDuplicateShift(List<Shift> existingShifts, DateTime newDate) {
  return existingShifts.any((s) => 
    s.date.year == newDate.year &&
    s.date.month == newDate.month &&
    s.date.day == newDate.day
  );
}

/// Checks if a new payroll period overlaps with existing ones
bool hasDateOverlap(DateTime start, DateTime end, List<PayPeriod> existingPeriods, {String? excludeId}) {
  for (var period in existingPeriods) {
    if (excludeId != null && period.id == excludeId) continue; // Skip self if editing

    // Overlap Logic: (StartA <= EndB) and (EndA >= StartB)
    // We use isBefore/isAfter, so we check the inverse
    if (start.isBefore(period.end) && end.isAfter(period.start)) {
      return true;
    }
    
    // Check exact boundary matches (inclusive dates)
    if (isSameDay(start, period.end) || isSameDay(end, period.start) || isSameDay(start, period.start)) {
      return true; 
    }
  }
  return false;
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// Reusable Dialog
Future<void> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  required VoidCallback onConfirm,
  bool isDestructive = false,
}) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text(
              isDestructive ? 'Delete' : 'Confirm', 
              style: TextStyle(color: isDestructive ? Colors.red : Colors.blue, fontWeight: FontWeight.bold)
            ),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
          ),
        ],
      );
    },
  );
}