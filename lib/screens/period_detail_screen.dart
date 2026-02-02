import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/data_models.dart';
import '../utils/helpers.dart'; 
import '../utils/calculations.dart';
import '../widgets/custom_pickers.dart';
import '../services/data_manager.dart'; 
import '../services/audio_service.dart';

class PeriodDetailScreen extends StatefulWidget {
  final PayPeriod period;
  final bool use24HourFormat;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final bool hideMoney; 
  final String currencySymbol;
  final VoidCallback onSave;
  final bool enableLate; 
  final bool enableOt;   
  
  const PeriodDetailScreen({
    super.key, 
    required this.period, 
    required this.use24HourFormat,
    required this.shiftStart,
    required this.shiftEnd,
    required this.hideMoney,
    required this.currencySymbol,
    required this.onSave,
    required this.enableLate,
    required this.enableOt,
  });

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  final NumberFormat currencyFormatter = NumberFormat("#,##0.00", "en_US");

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      )
    );
  }

  String _getMoneyText(double amount) {
    if (widget.hideMoney) return "****.**";
    return "${widget.currencySymbol}${currencyFormatter.format(amount)}";
  }

  String _formatDuration(double hours) {
    if (hours < 1.0 && hours > 0) {
      int minutes = (hours * 60).round();
      return "${minutes}m";
    }
    return "${hours.toStringAsFixed(1)}h";
  }

  double _calculateShiftPay(Shift s, double hourlyRate) {
    if (s.isManualPay) return s.manualAmount;

    double regHours = s.getRegularHours(
      widget.shiftStart, 
      widget.shiftEnd, 
      isLateEnabled: widget.enableLate, 
      roundEndTime: true
    );
    
    double otHours = widget.enableOt ? s.getOvertimeHours(widget.shiftStart, widget.shiftEnd) : 0.0;
    
    double pay = (regHours * hourlyRate) + (otHours * hourlyRate * 1.25);

    if (widget.enableLate) {
      int lateMins = PayrollCalculator.calculateLateMinutes(s.rawTimeIn, widget.shiftStart);
      if (lateMins > 0) {
        pay -= (lateMins / 60.0) * hourlyRate;
      }
    }
    
    return pay > 0 ? pay : 0.0;
  }

  void _saveChanges() {
    widget.period.lastEdited = DateTime.now();
    widget.onSave(); 
  }

  void _showShiftDialog({Shift? existingShift}) async {
    AudioService().playClick();
    DateTime tempDate = existingShift?.date ?? widget.period.start;
    if (existingShift == null) {
      DateTime now = DateTime.now();
      if (now.isAfter(widget.period.start) && now.isBefore(widget.period.end)) tempDate = now;
    }
    TimeOfDay tIn = existingShift?.rawTimeIn ?? widget.shiftStart;
    TimeOfDay tOut = existingShift?.rawTimeOut ?? widget.shiftEnd;
    bool isManual = existingShift?.isManualPay ?? false;
    TextEditingController manualCtrl = TextEditingController(text: existingShift?.manualAmount.toString() ?? "0");
    TextEditingController remarksCtrl = TextEditingController(text: existingShift?.remarks ?? ""); 
    
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dlgBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    var result = await showModalBottomSheet(
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
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(existingShift == null ? "Add Shift" : "Edit Shift", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.grey))]),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () async {
                      DateTime? picked = await showFastDatePicker(context, tempDate);
                      if (picked != null) setModalState(() => tempDate = picked);
                    },
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(CupertinoIcons.calendar, color: Colors.blue), const SizedBox(width: 12), Text(DateFormat('MMM d, yyyy').format(tempDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Manual Pay Override", style: TextStyle(fontWeight: FontWeight.w500)), CupertinoSwitch(value: isManual, activeColor: Colors.blue, onChanged: (val) { AudioService().playClick(); setModalState(() => isManual = val); })]),
                  const Divider(height: 24),
                  if (!isManual) ...[
                     Row(children: [
                         Expanded(child: GestureDetector(onTap: () async { final t = await showFastTimePicker(context, tIn, widget.use24HourFormat); if (t!=null) setModalState(() => tIn = t); }, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))), child: Column(children: [const Text("IN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)), const SizedBox(height: 4), Text(formatTime(context, tIn, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])))),
                         const SizedBox(width: 12),
                         Expanded(child: GestureDetector(onTap: () async { final t = await showFastTimePicker(context, tOut, widget.use24HourFormat); if (t!=null) setModalState(() => tOut = t); }, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))), child: Column(children: [const Text("OUT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)), const SizedBox(height: 4), Text(formatTime(context, tOut, widget.use24HourFormat), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])))),
                     ]),
                  ] else ...[
                     TextField(controller: manualCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), decoration: InputDecoration(labelText: "Amount", border: const OutlineInputBorder(), prefixText: "${widget.currencySymbol} "))
                  ],
                  
                  const SizedBox(height: 16),
                  TextField(
                    controller: remarksCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: "Remarks (Optional)",
                      prefixIcon: const Icon(CupertinoIcons.text_bubble, size: 20, color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                    ),
                  ),

                  const SizedBox(height: 30),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                    onPressed: () { 
                      AudioService().playClick(); 
                      if (!isManual) {
                        double inVal = tIn.hour + tIn.minute / 60.0;
                        double outVal = tOut.hour + tOut.minute / 60.0;
                        if (inVal >= outVal) { Navigator.pop(context, "INVALID_TIME"); return; }
                      }
                      Navigator.pop(context, true); 
                    }, 
                    child: const Text("Save Shift", style: TextStyle(fontWeight: FontWeight.bold))
                  )),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      }
    );

    if (result == "INVALID_TIME") {
      _showErrorSnackBar("Time In must be earlier than Time Out.");
    } 
    else if (result == true) {
      if (existingShift == null && isDuplicateShift(widget.period.shifts, tempDate)) {
           _showErrorSnackBar("Error: Date already exists!");
           return;
      }
      setState(() {
        if (existingShift != null) {
          existingShift.date = tempDate; existingShift.rawTimeIn = tIn; existingShift.rawTimeOut = tOut;
          existingShift.isManualPay = isManual; 
          existingShift.manualAmount = double.tryParse(manualCtrl.text) ?? 0.0;
          existingShift.remarks = remarksCtrl.text.trim(); 
        } else {
          widget.period.shifts.add(Shift(
            id: const Uuid().v4(), 
            date: tempDate, 
            rawTimeIn: tIn, 
            rawTimeOut: tOut, 
            isManualPay: isManual, 
            manualAmount: double.tryParse(manualCtrl.text) ?? 0.0,
            remarks: remarksCtrl.text.trim()
          ));
        }
        widget.period.shifts.sort((a, b) => b.date.compareTo(a.date));
        _saveChanges();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataManager = Provider.of<DataManager>(context);
    final double hourlyRate = dataManager.defaultHourlyRate;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    // Primary Color (Violet)
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    final double totalPay = widget.period.getTotalPay(
      widget.shiftStart, widget.shiftEnd, 
      hourlyRate: hourlyRate, 
      enableLate: widget.enableLate, 
      enableOt: widget.enableOt
    );

    final double totalReg = widget.period.getTotalRegularHours(widget.shiftStart, widget.shiftEnd);
    final double totalOT = widget.enableOt ? widget.period.getTotalOvertimeHours(widget.shiftStart, widget.shiftEnd) : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.period.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
            child: Column(
              children: [
                if (widget.hideMoney)
                   Text("****.**", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))
                else 
                   Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text(widget.currencySymbol, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                      Text(currencyFormatter.format(totalPay).split('.')[0], style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                      Text(".${currencyFormatter.format(totalPay).split('.')[1]}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary.withOpacity(0.7))),
                   ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _buildStatPill(context, "Regular: ${_formatDuration(totalReg)}"),
                    if (widget.enableOt && totalOT > 0) ...[
                      const SizedBox(width: 10),
                      _buildStatPill(context, "Overtime: ${_formatDuration(totalOT)}"),
                    ]
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    "Global Rate: ${widget.currencySymbol}${hourlyRate.toStringAsFixed(0)}/hr",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: subTextColor),
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
                    
                    double regHours = s.getRegularHours(
                      widget.shiftStart, widget.shiftEnd, 
                      isLateEnabled: widget.enableLate, roundEndTime: false 
                    );
                    double otHours = s.getOvertimeHours(widget.shiftStart, widget.shiftEnd);
                    double shiftPay = _calculateShiftPay(s, hourlyRate);

                    return Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (d) async { 
                        bool confirm = false; 
                        await showConfirmationDialog(context: context, title: "Delete Shift?", content: "Remove this work day?", isDestructive: true, onConfirm: () => confirm = true); 
                        return confirm; 
                      },
                      onDismissed: (d) {
                        AudioService().playDelete();
                        setState(() { widget.period.shifts.removeAt(i); _saveChanges(); });
                      },
                      child: GestureDetector(
                        onTap: () => _showShiftDialog(existingShift: s), 
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,2))]),
                          child: Row(
                            children: [
                              // Left: Date
                              Container(width: 50, padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(DateFormat('MMM').format(s.date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)), Text(DateFormat('dd').format(s.date), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87))])),
                              const SizedBox(width: 16),
                              
                              // Middle: Info
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    if (s.isManualPay) Text("Flat Pay: ${_getMoneyText(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold))
                                    else ...[
                                      Text("${formatTime(context, s.rawTimeIn, widget.use24HourFormat)} - ${formatTime(context, s.rawTimeOut, widget.use24HourFormat)}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                      
                                      if (s.remarks.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          s.remarks,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
                                        ),
                                        const SizedBox(height: 4),
                                      ] else ...[
                                        const SizedBox(height: 4),
                                      ],
                                      
                                      Row(children: [
                                          _buildTag("Reg: ${_formatDuration(regHours)}", Colors.grey, isDark),
                                          if (widget.enableOt && otHours > 0) _buildTag("OT: ${_formatDuration(otHours)}", Colors.blue, isDark),
                                          if (widget.enableLate && lateHours > 0) _buildTag("Late: ${_formatDuration(lateHours)}", Colors.redAccent, isDark),
                                      ]),
                                    ]
                                ]),
                              ),

                              // Right Side Money Pill (FIXED: OUTLINED + THEME COLOR)
                              const SizedBox(width: 8),
                              Container(
                                width: 90, 
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  // Replaced hardcoded Green with Transparent + Outlined Theme Color
                                  color: Colors.transparent, 
                                  borderRadius: BorderRadius.circular(50), 
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary, 
                                    width: 1.5
                                  )
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _getMoneyText(shiftPay),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700, 
                                        fontSize: 14, 
                                        color: Theme.of(context).colorScheme.primary // Theme Color
                                      ),
                                    ),
                                  ),
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
      // UPDATED: Oval, Outlined, Theme-Aware FAB with Label
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShiftDialog(),
        label: const Text("Add Shift", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(CupertinoIcons.add),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: primaryColor,
        elevation: 6,
        shape: StadiumBorder(
          side: BorderSide(color: primaryColor, width: 2.0)
        ),
      ),
    );
  }

  Widget _buildStatPill(BuildContext context, String text) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
      decoration: BoxDecoration(
        color: Colors.transparent, 
        borderRadius: BorderRadius.circular(50), 
        border: Border.all(color: color, width: 1.5) 
      ), 
      child: Text(
        text, 
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)
      )
    );
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)));
  }
}