import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/data_models.dart';
import '../utils/helpers.dart'; 
import '../utils/calculations.dart';
import '../services/data_manager.dart'; 
import '../services/audio_service.dart';
import '../widgets/shift_form_sheet.dart'; 

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

class _PeriodDetailScreenState extends State<PeriodDetailScreen> with TickerProviderStateMixin {
  final NumberFormat currencyFormatter = NumberFormat("#,##0.00", "en_US");

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)))]),
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

  double _calculateShiftPay(Shift s, double hourlyRate, bool snapToGrid) {
    if (s.isManualPay) return s.manualAmount;

    double regHours = s.getRegularHours(
      widget.shiftStart, 
      widget.shiftEnd, 
      isLateEnabled: widget.enableLate, 
      snapToGrid: snapToGrid
    );
    
    double otHours = widget.enableOt ? s.getOvertimeHours(widget.shiftStart, widget.shiftEnd, snapToGrid: snapToGrid) : 0.0;
    
    double pay = (regHours * hourlyRate) + (otHours * hourlyRate * 1.25);

    if (s.isHoliday && s.holidayMultiplier > 0) {
      pay += pay * (s.holidayMultiplier / 100.0);
    }
    
    return pay > 0 ? pay : 0.0;
  }

  void _saveChanges() {
    widget.period.lastEdited = DateTime.now();
    widget.onSave(); 
  }

  void _openShiftModal({Shift? existingShift}) async {
    AudioService().playClick();
    DateTime defaultDate = existingShift?.date ?? widget.period.start;
    if (existingShift == null) {
      DateTime now = DateTime.now();
      if (now.isAfter(widget.period.start) && now.isBefore(widget.period.end)) defaultDate = now;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final result = await showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => ShiftFormSheet(
        existingShift: existingShift,
        defaultDate: defaultDate,
        defaultStart: widget.shiftStart,
        defaultEnd: widget.shiftEnd,
        use24HourFormat: widget.use24HourFormat,
        currencySymbol: widget.currencySymbol,
        currentShifts: widget.period.shifts,
      ),
    );

    if (result == "INVALID_TIME") {
      _showErrorSnackBar("Time In must be earlier than Time Out.");
    } else if (result == "DUPLICATE_DATE") {
      _showErrorSnackBar("Error: Date already exists!");
    } else if (result is Shift) {
      setState(() {
        if (existingShift != null) {
           int index = widget.period.shifts.indexWhere((s) => s.id == existingShift.id);
           if (index != -1) widget.period.shifts[index] = result;
        } else {
           widget.period.shifts.add(result);
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
    final bool snapToGrid = dataManager.snapToGrid; 
    
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    
    final double totalPay = widget.period.getTotalPay(
      widget.shiftStart, 
      widget.shiftEnd, 
      hourlyRate: hourlyRate, 
      enableLate: widget.enableLate, 
      enableOt: widget.enableOt,
      snapToGrid: snapToGrid,
    );

    final double totalReg = widget.period.shifts.fold(0.0, (sum, s) => 
        sum + s.getRegularHours(widget.shiftStart, widget.shiftEnd, snapToGrid: snapToGrid, isLateEnabled: widget.enableLate));
        
    final double totalOT = widget.enableOt ? widget.period.shifts.fold(0.0, (sum, s) => 
        sum + s.getOvertimeHours(widget.shiftStart, widget.shiftEnd, snapToGrid: snapToGrid)) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.period.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
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
                  child: Text("Global Rate: ${widget.currencySymbol}${hourlyRate.toStringAsFixed(0)}/hr", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: subTextColor)),
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
                    
                    double regHours = s.getRegularHours(widget.shiftStart, widget.shiftEnd, isLateEnabled: widget.enableLate, snapToGrid: snapToGrid);
                    double otHours = s.getOvertimeHours(widget.shiftStart, widget.shiftEnd, snapToGrid: snapToGrid);
                    double shiftPay = _calculateShiftPay(s, hourlyRate, snapToGrid);
                    
                    bool isLate = widget.enableLate && lateMins > 0;
                    
                    final Color dateTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

                    return Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      confirmDismiss: (d) async { bool confirm = false; await showConfirmationDialog(context: context, title: "Delete Shift?", content: "Remove this work day?", isDestructive: true, onConfirm: () => confirm = true); return confirm; },
                      onDismissed: (d) { AudioService().playDelete(); setState(() { widget.period.shifts.removeAt(i); _saveChanges(); }); },
                      child: GestureDetector(
                        onTap: () => _openShiftModal(existingShift: s), 
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,2))]),
                          child: Row(
                            children: [
                              Container(
                                width: 50, 
                                padding: const EdgeInsets.symmetric(vertical: 8), 
                                decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], borderRadius: BorderRadius.circular(10)), 
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 1. Month
                                    Text(DateFormat('MMM').format(s.date).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: dateTextColor)), 
                                    const SizedBox(height: 2),
                                    // 2. Date Number
                                    Text(DateFormat('dd').format(s.date), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.0, color: isDark ? Colors.white : Colors.black87)),
                                    const SizedBox(height: 2),
                                    // 3. Day Name (Title case, No Italic)
                                    Text(DateFormat('E').format(s.date), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: dateTextColor)),
                                  ]
                                )
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    if (s.isManualPay) Text("Flat Pay: ${_getMoneyText(s.manualAmount)}", style: const TextStyle(fontWeight: FontWeight.bold))
                                    else ...[
                                      Text("${formatTime(context, s.rawTimeIn, widget.use24HourFormat)} - ${formatTime(context, s.rawTimeOut, widget.use24HourFormat)}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                      if (s.remarks.isNotEmpty) ...[const SizedBox(height: 2), Text(s.remarks, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic)), const SizedBox(height: 4)] else const SizedBox(height: 4),
                                      Wrap(spacing: 6, runSpacing: 4, children: [
                                          _buildTag("Reg: ${_formatDuration(regHours)}", Colors.grey, isDark),
                                          if (widget.enableOt && otHours > 0) _buildTag("OT: ${_formatDuration(otHours)}", Colors.blue, isDark),
                                          if (isLate) _buildTag("Late: ${lateMins}m", Colors.redAccent, isDark),
                                          if (s.isHoliday && s.holidayMultiplier > 0) _buildHolidayTag(context, "+${s.holidayMultiplier.toStringAsFixed(0)}% Pay"),
                                      ]),
                                    ]
                                ]),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 90, padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(50), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_getMoneyText(shiftPay), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.primary)))),
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'detailFab',
        onPressed: () => _openShiftModal(),
        label: const Text("Add Shift", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(CupertinoIcons.add),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: primaryColor,
        elevation: 6,
        shape: StadiumBorder(side: BorderSide(color: primaryColor, width: 2.0)),
      ),
    );
  }

  Widget _buildStatPill(BuildContext context, String text) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(50), border: Border.all(color: color, width: 1.5)), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)));
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)));
  }

  Widget _buildHolidayTag(BuildContext context, String text) {
    return Container(
      margin: const EdgeInsets.only(right: 6), // Matches _buildTag
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // Matches _buildTag
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1), // Matches _buildTag
        borderRadius: BorderRadius.circular(6), // Matches _buildTag
        // REMOVED: Border property that was causing extra height
      ), 
      child: Row(
        mainAxisSize: MainAxisSize.min, 
        children: [
          const Icon(Icons.star, size: 10, color: Colors.orange), 
          const SizedBox(width: 4), 
          Text(text, style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold))
        ]
      )
    );
  }
}