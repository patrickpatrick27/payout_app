import 'package:flutter/material.dart';
import '../utils/helpers.dart';
import '../widgets/custom_pickers.dart';
import '../utils/constants.dart';
import '../services/update_service.dart'; // Import Update Service

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final bool use24HourFormat;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final Function({bool? isDark, bool? is24h, TimeOfDay? shiftStart, TimeOfDay? shiftEnd}) onUpdate;
  final VoidCallback onDeleteAll;
  final VoidCallback onExport;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.use24HourFormat,
    required this.shiftStart,
    required this.shiftEnd,
    required this.onUpdate,
    required this.onDeleteAll,
    required this.onExport,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TimeOfDay _localShiftStart;
  late TimeOfDay _localShiftEnd;

  @override
  void initState() {
    super.initState();
    _localShiftStart = widget.shiftStart;
    _localShiftEnd = widget.shiftEnd;
  }

  void _updateTime(bool isStart, TimeOfDay newTime) {
    setState(() {
      if (isStart) _localShiftStart = newTime;
      else _localShiftEnd = newTime;
    });
    widget.onUpdate(
      shiftStart: isStart ? newTime : null,
      shiftEnd: !isStart ? newTime : null
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(context).cardColor;
    
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader("WORK SCHEDULE"),
          _buildTimeTile("Shift Start Time", _localShiftStart, (t) => _updateTime(true, t)),
          _buildTimeTile("Shift End Time", _localShiftEnd, (t) => _updateTime(false, t)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "Note: Hours worked after the Shift End Time are counted as Overtime. Arrivals before Shift Start Time are not counted.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          
          const SizedBox(height: 20),
          _buildSectionHeader("PREFERENCES"),
          SwitchListTile(
            title: const Text("Dark Mode"),
            value: widget.isDarkMode,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(isDark: val),
          ),
          SwitchListTile(
            title: const Text("24-Hour Format"),
            value: widget.use24HourFormat,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(is24h: val),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("DATA MANAGEMENT"),
          ListTile(
            tileColor: bg,
            leading: const Icon(Icons.system_update, color: Colors.blue),
            title: const Text("Check for Updates"),
            onTap: () {
              playClickSound(context);
              // Show message if no update found
              GithubUpdateService.checkForUpdate(context, showNoUpdateMsg: true);
            },
          ),
          ListTile(
            tileColor: bg,
            leading: const Icon(Icons.copy),
            title: const Text("Copy Data Report"),
            onTap: widget.onExport,
          ),
          ListTile(
            tileColor: bg,
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text("Delete All Data", style: TextStyle(color: Colors.red)),
            onTap: widget.onDeleteAll,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 12)),
    );
  }

  Widget _buildTimeTile(String title, TimeOfDay current, Function(TimeOfDay) onSelect) {
    return ListTile(
      tileColor: Theme.of(context).cardColor,
      title: Text(title),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(
          formatTime(context, current, widget.use24HourFormat),
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      onTap: () async {
        playClickSound(context);
        final t = await showFastTimePicker(context, current, widget.use24HourFormat);
        if (t != null) onSelect(t);
      },
    );
  }
}