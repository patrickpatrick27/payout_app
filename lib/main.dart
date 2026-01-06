import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const PayTrackerApp());
}

class PayTrackerApp extends StatelessWidget {
  const PayTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pay Tracker Pro',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5), // Indigo
          brightness: Brightness.light,
          primary: const Color(0xFF304FFE),
          secondary: const Color(0xFF00BFA5),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const PayPeriodListScreen(),
    );
  }
}

// --- LOGIC HELPERS ---

TimeOfDay roundTime(TimeOfDay time, {required bool isStart}) {
  int totalMinutes = time.hour * 60 + time.minute;
  int remainder = totalMinutes % 30;
  int roundedMinutes = totalMinutes;

  if (remainder != 0) {
    if (isStart) {
      roundedMinutes = totalMinutes + (30 - remainder);
    } else {
      roundedMinutes = totalMinutes - remainder;
    }
  }

  int h = (roundedMinutes ~/ 60) % 24;
  int m = roundedMinutes % 60;
  
  // Strict 8:00 AM Rule
  if (isStart && h < 8) {
    return const TimeOfDay(hour: 8, minute: 0);
  }

  return TimeOfDay(hour: h, minute: m);
}

// --- DATA MODELS ---

class Shift {
  String id;
  DateTime date;
  TimeOfDay rawTimeIn;
  TimeOfDay rawTimeOut;
  bool isManualPay; // New: If true, ignore time
  double manualAmount; // New: User types pay directly

  Shift({
    required this.id,
    required this.date,
    required this.rawTimeIn,
    required this.rawTimeOut,
    this.isManualPay = false,
    this.manualAmount = 0.0,
  });

  TimeOfDay get paidTimeIn => roundTime(rawTimeIn, isStart: true);
  TimeOfDay get paidTimeOut => roundTime(rawTimeOut, isStart: false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'rawTimeIn': '${rawTimeIn.hour}:${rawTimeIn.minute}',
        'rawTimeOut': '${rawTimeOut.hour}:${rawTimeOut.minute}',
        'isManualPay': isManualPay,
        'manualAmount': manualAmount,
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
    );
  }

  double get hoursWorked {
    if (isManualPay) return 0; // Not calculated by time

    double start = paidTimeIn.hour + paidTimeIn.minute / 60.0;
    double end = paidTimeOut.hour + paidTimeOut.minute / 60.0;
    if (end < start) end += 24; 

    double duration = end - start;
    if (start <= 12.0 && end >= 13.0) duration -= 1.0; 

    return duration > 0 ? duration : 0;
  }

  double get regularHours => hoursWorked > 8 ? 8 : hoursWorked;
  double get overtimeHours => hoursWorked > 8 ? hoursWorked - 8 : 0;
}

class PayPeriod {
  String id;
  String name;
  DateTime start;
  DateTime end;
  double hourlyRate;
  List<Shift> shifts;

  PayPeriod({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.hourlyRate,
    required this.shifts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'hourlyRate': hourlyRate,
        'shifts': shifts.map((s) => s.toJson()).toList(),
      };

  factory PayPeriod.fromJson(Map<String, dynamic> json) {
    return PayPeriod(
      id: json['id'],
      name: json['name'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      hourlyRate: json['hourlyRate'].toDouble(),
      shifts: (json['shifts'] as List).map((s) => Shift.fromJson(s)).toList(),
    );
  }

  double get totalRegularHours {
    double sum = 0;
    for (var shift in shifts) if(!shift.isManualPay) sum += shift.regularHours;
    return sum;
  }

  double get totalOvertimeHours {
    double sum = 0;
    for (var shift in shifts) if(!shift.isManualPay) sum += shift.overtimeHours;
    return sum;
  }

  double get totalPay {
    double total = 0;
    for (var shift in shifts) {
      if (shift.isManualPay) {
        total += shift.manualAmount;
      } else {
        total += (shift.regularHours * hourlyRate) + 
                 (shift.overtimeHours * hourlyRate * 1.25);
      }
    }
    return total;
  }
}

// --- FAST DATE PICKER (CUPERTINO WHEEL) ---
Future<DateTime?> showFastDatePicker(BuildContext context, DateTime initial, {DateTime? minDate, DateTime? maxDate}) async {
  DateTime tempDate = initial;
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (BuildContext builder) {
      return Container(
        height: 250,
        color: Colors.white,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
                CupertinoButton(
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)), 
                  onPressed: () => Navigator.of(context).pop(tempDate)
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                minimumDate: minDate ?? DateTime(2020),
                maximumDate: maxDate ?? DateTime(2030),
                onDateTimeChanged: (DateTime newDate) {
                  tempDate = newDate;
                },
              ),
            ),
          ],
        ),
      );
    }
  );
}

// --- SCREEN 1: DASHBOARD ---

class PayPeriodListScreen extends StatefulWidget {
  const PayPeriodListScreen({super.key});

  @override
  State<PayPeriodListScreen> createState() => _PayPeriodListScreenState();
}

class _PayPeriodListScreenState extends State<PayPeriodListScreen> {
  List<PayPeriod> periods = [];
  final NumberFormat currency = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('pay_periods_v3'); 
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      setState(() {
        periods = decoded.map((e) => PayPeriod.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(periods.map((e) => e.toJson()).toList());
    await prefs.setString('pay_periods_v3', data);
  }

  void _createNewPeriod() async {
    DateTime? start = await showFastDatePicker(context, DateTime.now());
    if (start == null) return;

    if (!mounted) return;
    DateTime? end = await showFastDatePicker(context, start.add(const Duration(days: 15)), minDate: start);
    if (end == null) return;

    final newPeriod = PayPeriod(
      id: const Uuid().v4(),
      name: "${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}",
      start: start,
      end: end,
      hourlyRate: 50.0, 
      shifts: [],
    );
    setState(() {
      periods.insert(0, newPeriod);
    });
    _saveData();
    _openPeriod(newPeriod);
  }

  void _openPeriod(PayPeriod period) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeriodDetailScreen(period: period)),
    );
    _saveData();
    setState(() {});
  }

  void _deletePeriod(int index) {
    setState(() {
      periods.removeAt(index);
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pay Dashboard")),
      body: periods.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  Text("No Pay Trackers Found", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _createNewPeriod,
                    icon: const Icon(Icons.add),
                    label: const Text("Create New Tracker"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  )
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: periods.length,
              itemBuilder: (context, index) {
                final p = periods[index];
                return Dismissible(
                  key: Key(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Delete Tracker?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                        ],
                      )
                    );
                  },
                  onDismissed: (direction) => _deletePeriod(index),
                  child: GestureDetector(
                    onTap: () => _openPeriod(p),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                const SizedBox(height: 4),
                                Text("${p.shifts.length} shifts", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("TOTAL PAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                Text(
                                  "₱${currency.format(p.totalPay)}", // Shows exact decimals
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewPeriod,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// --- SCREEN 2: DETAILS ---

class PeriodDetailScreen extends StatefulWidget {
  final PayPeriod period;
  const PeriodDetailScreen({super.key, required this.period});

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  late TextEditingController _rateController;
  final NumberFormat currency = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(text: widget.period.hourlyRate.toString());
  }

  void _showShiftDialog({Shift? existingShift}) async {
    DateTime initialDate = existingShift?.date ?? widget.period.start;
    if (existingShift == null && DateTime.now().isBefore(widget.period.end)) {
      initialDate = DateTime.now();
      if (initialDate.isBefore(widget.period.start)) initialDate = widget.period.start;
    }

    DateTime? pickedDate = await showFastDatePicker(
      context, 
      initialDate,
      minDate: DateTime(2020),
      maxDate: DateTime(2030)
    );
    if (pickedDate == null) return;

    // Duplicate Check
    bool isDuplicate = widget.period.shifts.any((s) => 
      s.id != (existingShift?.id ?? "") && 
      s.date.year == pickedDate.year && 
      s.date.month == pickedDate.month && 
      s.date.day == pickedDate.day
    );

    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Date already exists! Edit the existing one instead."), backgroundColor: Colors.red),
      );
      return;
    }

    // STATE FOR DIALOG
    TimeOfDay tIn = existingShift?.rawTimeIn ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay tOut = existingShift?.rawTimeOut ?? const TimeOfDay(hour: 17, minute: 0);
    bool isManual = existingShift?.isManualPay ?? false;
    TextEditingController manualCtrl = TextEditingController(text: existingShift?.manualAmount.toString() ?? "0");

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(existingShift == null ? "Add Shift" : "Edit Shift", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),
                  
                  // TOGGLE MANUAL
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("I don't know my time (Enter amount)"),
                      Switch(value: isManual, onChanged: (val) => setModalState(() => isManual = val)),
                    ],
                  ),
                  const Divider(),

                  if (!isManual) ...[
                     ListTile(
                       title: const Text("Time In"),
                       trailing: Text(tIn.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                       onTap: () async {
                         final t = await showTimePicker(context: context, initialTime: tIn);
                         if (t!=null) setModalState(() => tIn = t);
                       },
                     ),
                     ListTile(
                       title: const Text("Time Out"),
                       trailing: Text(tOut.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                       onTap: () async {
                         final t = await showTimePicker(context: context, initialTime: tOut);
                         if (t!=null) setModalState(() => tOut = t);
                       },
                     ),
                  ] else ...[
                     TextField(
                       controller: manualCtrl,
                       keyboardType: TextInputType.number,
                       decoration: const InputDecoration(
                         labelText: "Total Pay Amount (₱)",
                         border: OutlineInputBorder(),
                         prefixText: "₱ "
                       ),
                     )
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                      child: const Text("Save"),
                      onPressed: () {
                         Navigator.pop(context, true);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      }
    ).then((saved) {
      if (saved == true) {
        setState(() {
          if (existingShift != null) {
            existingShift.date = pickedDate;
            existingShift.rawTimeIn = tIn;
            existingShift.rawTimeOut = tOut;
            existingShift.isManualPay = isManual;
            existingShift.manualAmount = double.tryParse(manualCtrl.text) ?? 0.0;
          } else {
            widget.period.shifts.add(Shift(
              id: const Uuid().v4(),
              date: pickedDate,
              rawTimeIn: tIn,
              rawTimeOut: tOut,
              isManualPay: isManual,
              manualAmount: double.tryParse(manualCtrl.text) ?? 0.0,
            ));
          }
          widget.period.shifts.sort((a, b) => b.date.compareTo(a.date));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.period.name)),
      body: Column(
        children: [
          // NEW FIXED HEADER
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            child: Column(
              children: [
                // Clean Hourly Rate Input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("HOURLY RATE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _rateController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(border: InputBorder.none, prefixText: "₱ "),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            setState(() {
                              widget.period.hourlyRate = double.tryParse(val) ?? 50;
                            });
                          },
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // TOTAL PAY
                Text("₱ ${currency.format(widget.period.totalPay)}", 
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)
                ),
                const Text("TOTAL PAYOUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                
                const SizedBox(height: 20),
                
                // NEW STATS ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatBox("REGULAR HRS", widget.period.totalRegularHours.toStringAsFixed(1), Colors.black87),
                    Container(width: 1, height: 30, color: Colors.grey[300]),
                    _buildStatBox("OVERTIME HRS", widget.period.totalOvertimeHours.toStringAsFixed(1), Colors.blue),
                  ],
                )
              ],
            ),
          ),

          Expanded(
            child: widget.period.shifts.isEmpty 
              ? Center(child: Text("Tap '+' to add a work day", style: TextStyle(color: Colors.grey[400])))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.period.shifts.length,
                  itemBuilder: (ctx, i) {
                    final s = widget.period.shifts[i];
                    bool isInside = !s.date.isBefore(widget.period.start) && !s.date.isAfter(widget.period.end);
                    
                    return GestureDetector(
                      onTap: () => _showShiftDialog(existingShift: s), 
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isInside ? Colors.white : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: isInside ? null : Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            // DATE BOX
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isInside ? Theme.of(context).colorScheme.secondary.withOpacity(0.1) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(DateFormat('MMM').format(s.date).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isInside ? Theme.of(context).colorScheme.secondary : Colors.grey)),
                                  Text(DateFormat('dd').format(s.date), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isInside ? Theme.of(context).colorScheme.secondary : Colors.grey)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // DETAILS
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (s.isManualPay)
                                    Row(
                                      children: [
                                        Icon(Icons.edit_note, color: Colors.orange[800], size: 18),
                                        const SizedBox(width: 4),
                                        Text("Manual Adjustment", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        Text("${s.rawTimeIn.format(context)} - ${s.rawTimeOut.format(context)}", 
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[800])
                                        ),
                                        if (s.paidTimeIn != s.rawTimeIn || s.paidTimeOut != s.rawTimeOut)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Icon(Icons.auto_fix_high, size: 14, color: Colors.amber),
                                          )
                                      ],
                                    ),
                                  
                                  const SizedBox(height: 4),
                                  
                                  if (s.isManualPay)
                                    Text("Flat Pay: ₱${currency.format(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                                  else
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        children: [
                                          TextSpan(text: "Reg: ${s.regularHours.toStringAsFixed(1)}"),
                                          if (s.overtimeHours > 0)
                                            TextSpan(text: " • OT: ${s.overtimeHours.toStringAsFixed(1)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                        ]
                                      ),
                                    )
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () => setState(() => widget.period.shifts.removeAt(i)),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShiftDialog(), 
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Shift", style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }
}