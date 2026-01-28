import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/data_models.dart';
import '../utils/helpers.dart';
import '../utils/calculations.dart';
import '../widgets/custom_pickers.dart';

class PeriodDetailScreen extends StatefulWidget {
  final PayPeriod period;
  final bool use24HourFormat;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final bool hideMoney; 
  final String currencySymbol; 
  
  const PeriodDetailScreen({
    super.key, 
    required this.period, 
    required this.use24HourFormat,
    required this.shiftStart,
    required this.shiftEnd,
    required this.hideMoney,
    required this.currencySymbol,
  });

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  late TextEditingController _rateController;
  final NumberFormat currencyFormatter = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(text: widget.period.hourlyRate.toString());
  }

  String _getMoneyText(double amount) {
    if (widget.hideMoney) return "****.**";
    return "${widget.currencySymbol}${currencyFormatter.format(amount)}";
  }

  void _showShiftDialog({Shift? existingShift}) async {
    playClickSound(context);

    DateTime tempDate = existingShift?.date ?? widget.period.start;
    if (existingShift == null) {
      DateTime now = DateTime.now();
      if (now.isAfter(widget.period.start) && now.isBefore(widget.period.end)) tempDate = now;
    }

    TimeOfDay tIn = existingShift?.rawTimeIn ?? widget.shiftStart;
    TimeOfDay tOut = existingShift?.rawTimeOut ?? widget.shiftEnd;
    
    bool isManual = existingShift?.isManualPay ?? false;
    TextEditingController manualCtrl = TextEditingController(text: existingShift?.manualAmount.toString() ?? "0");

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dlgBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: dlgBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(existingShift == null ? "Add Shift" : "Edit Shift", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.grey))
                    ],
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () async {
                      DateTime? picked = await showFastDatePicker(context, tempDate);
                      if (picked != null) setModalState(() => tempDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.calendar, color: Colors.blue),
                          const SizedBox(width: 12),
                          Text(DateFormat('MMM d, yyyy').format(tempDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Manual Pay Override", style: TextStyle(fontWeight: FontWeight.w500)),
                      CupertinoSwitch(value: isManual, activeColor: Colors.blue, onChanged: (val) { playClickSound(context); setModalState(() => isManual = val); }),
                    ],
                  ),
                  const Divider(height: 24),
                  if (!isManual) ...[
                     Row(
                       children: [
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tIn, widget.use24HourFormat);
                               if (t!=null) setModalState(() => tIn = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("IN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(formatTime(context, tIn, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                                ),
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: GestureDetector(
                             onTap: () async {
                               final t = await showFastTimePicker(context, tOut, widget.use24HourFormat);
                               if (t!=null) setModalState(() => tOut = t);
                             },
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                               child: Column(
                                 children: [
                                   const Text("OUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                   const SizedBox(height: 4),
                                   Text(formatTime(context, tOut, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                 ],
                               ),
                             ),
                           ),
                         ),
                       ],
                     ),
                  ] else ...[
                     TextField(
                       controller: manualCtrl, keyboardType: TextInputType.number,
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                       decoration: InputDecoration(labelText: "Amount", border: const OutlineInputBorder(), prefixText: "${widget.currencySymbol} "),
                     )
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text("Save Shift", style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () { playClickSound(context); Navigator.pop(context, true); },
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
        if (existingShift == null && isDuplicateShift(widget.period.shifts, tempDate)) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Date already exists!"), backgroundColor: Colors.red));
           return;
        }
        setState(() {
          if (existingShift != null) {
            existingShift.date = tempDate; existingShift.rawTimeIn = tIn; existingShift.rawTimeOut = tOut;
            existingShift.isManualPay = isManual; existingShift.manualAmount = double.tryParse(manualCtrl.text) ?? 0.0;
          } else {
            widget.period.shifts.add(Shift(id: const Uuid().v4(), date: tempDate, rawTimeIn: tIn, rawTimeOut: tOut, isManualPay: isManual, manualAmount: double.tryParse(manualCtrl.text) ?? 0.0));
          }
          widget.period.shifts.sort((a, b) => b.date.compareTo(a.date));
          widget.period.lastEdited = DateTime.now();
        });
      }
    });
  }

  void _confirmDeleteShift(int index) {
    showConfirmationDialog(context: context, title: "Delete Shift?", content: "Remove this work day?", isDestructive: true, onConfirm: () {
      playClickSound(context);
      setState(() { widget.period.shifts.removeAt(index); widget.period.lastEdited = DateTime.now(); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final double totalPay = widget.period.getTotalPay(widget.shiftStart, widget.shiftEnd);
    
    // Calculate Totals for Header
    final double totalReg = widget.period.getTotalRegularHours(widget.shiftStart, widget.shiftEnd);
    final double totalOT = widget.period.getTotalOvertimeHours(widget.shiftStart, widget.shiftEnd);

    return Scaffold(
      appBar: AppBar(title: Text(widget.period.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
            child: Column(
              children: [
                // HUGE TOTAL
                if (widget.hideMoney)
                   Text("****.**", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))
                else 
                   Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(widget.currencySymbol, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                      Text(currencyFormatter.format(totalPay).split('.')[0], style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                      Text(".${currencyFormatter.format(totalPay).split('.')[1]}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary.withOpacity(0.7))),
                    ],
                  ),
                
                const SizedBox(height: 12),
                
                // HOURS SUMMARY ROW (Below Money)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatPill("Regular: ${totalReg.toStringAsFixed(1)}h", Colors.grey, isDark),
                    const SizedBox(width: 10),
                    _buildStatPill("Overtime: ${totalOT.toStringAsFixed(1)}h", Colors.blue, isDark),
                  ],
                ),

                const SizedBox(height: 12),

                // RATE EDITOR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Rate: ", style: TextStyle(color: subTextColor, fontSize: 12)),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: _rateController, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                          onChanged: (val) {
                            setState(() {
                              widget.period.hourlyRate = double.tryParse(val) ?? 50;
                              widget.period.lastEdited = DateTime.now();
                            });
                          },
                        ),
                      ),
                      Text("/hr", style: TextStyle(color: subTextColor, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.period.shifts.isEmpty 
              ? Center(child: Text("No shifts added", style: TextStyle(color: subTextColor)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 20, bottom: 100, left: 16, right: 16),
                  itemCount: widget.period.shifts.length,
                  itemBuilder: (ctx, i) {
                    final s = widget.period.shifts[i];
                    int lateMins = PayrollCalculator.calculateLateMinutes(s.rawTimeIn, widget.shiftStart);
                    double lateHours = lateMins / 60.0;

                    return Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (d) async { bool confirm = false; await showConfirmationDialog(context: context, title: "Delete Shift?", content: "Remove this work day?", isDestructive: true, onConfirm: () => confirm = true); return confirm; },
                      onDismissed: (d) => _confirmDeleteShift(i),
                      child: GestureDetector(
                        onTap: () => _showShiftDialog(existingShift: s), 
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,2))]),
                          child: Row(
                            children: [
                              Container(
                                width: 50, padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                                child: Column(children: [
                                    Text(DateFormat('MMM').format(s.date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)),
                                    Text(DateFormat('dd').format(s.date), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
                                ]),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.isManualPay)
                                      Text("Flat Pay: ${_getMoneyText(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold))
                                    else ...[
                                      Text("${formatTime(context, s.rawTimeIn, widget.use24HourFormat)} - ${formatTime(context, s.rawTimeOut, widget.use24HourFormat)}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                          _buildTag("Reg: ${s.getRegularHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1)}h", Colors.grey, isDark),
                                          if (s.getOvertimeHours(widget.shiftStart, widget.shiftEnd) > 0)
                                            _buildTag("OT: ${s.getOvertimeHours(widget.shiftStart, widget.shiftEnd).toStringAsFixed(1)}h", Colors.blue, isDark),
                                          if (lateHours > 0)
                                            _buildTag("Late: ${lateHours.toStringAsFixed(1)}h", Colors.redAccent, isDark),
                                      ]),
                                    ]
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showShiftDialog(), backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(CupertinoIcons.add, color: Colors.white)),
    );
  }

  Widget _buildStatPill(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3))
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}