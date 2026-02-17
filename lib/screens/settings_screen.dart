import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:provider/provider.dart';
import '../services/update_service.dart';
import '../utils/helpers.dart';
import '../widgets/custom_pickers.dart';
import '../services/data_manager.dart';
import '../services/audio_service.dart'; 

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final bool use24HourFormat;
  final bool hideMoney;
  final String currencySymbol;
  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final bool snapToGrid;
  
  final Function({
    bool? isDark, bool? is24h, bool? hideMoney, 
    String? currencySymbol, TimeOfDay? shiftStart, TimeOfDay? shiftEnd,
    bool? enableLate, bool? enableOt, double? defaultRate,
    bool? snapToGrid 
  }) onUpdate;

  final VoidCallback onDeleteAll; 
  final VoidCallback onExportReport; // Exports CSV
  final VoidCallback onBackup;       // Exports JSON
  final VoidCallback onRestore;      // Triggers File Picker (Import)

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.use24HourFormat,
    required this.hideMoney,
    required this.currencySymbol,
    required this.shiftStart,
    required this.shiftEnd,
    required this.snapToGrid,
    required this.onUpdate,
    required this.onDeleteAll,
    required this.onExportReport,
    required this.onBackup,
    required this.onRestore,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TimeOfDay _localShiftStart;
  late TimeOfDay _localShiftEnd;
  late TextEditingController _rateController; 
  final List<String> _currencies = ['₱', '\$', '€', '£', '¥', '₩', '₹', 'Rp'];
  bool _updateAvailable = false; 
  bool _isMuted = false; 

  @override
  void initState() {
    super.initState();
    _localShiftStart = widget.shiftStart;
    _localShiftEnd = widget.shiftEnd;
    
    final manager = Provider.of<DataManager>(context, listen: false);
    _rateController = TextEditingController(text: manager.defaultHourlyRate.toStringAsFixed(0));
    _isMuted = AudioService().isMuted;
    _checkForUpdates();
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    bool available = await GithubUpdateService.isUpdateAvailable();
    if (mounted) {
      setState(() {
        _updateAvailable = available;
      });
    }
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

  void _confirmClearLocal(BuildContext context) {
    AudioService().playClick();
    showConfirmationDialog(
      context: context, 
      title: "Clear Device Data?", 
      content: "This will remove all payrolls from THIS phone only. Your Google Drive backup will remain safe.", 
      isDestructive: true,
      onConfirm: () async {
        final manager = Provider.of<DataManager>(context, listen: false);
        await manager.clearLocalData();
        widget.onDeleteAll(); 
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device data cleared.")));
      }
    );
  }

  void _confirmDeleteCloud(BuildContext context) {
    AudioService().playClick();
    showConfirmationDialog(
      context: context, 
      title: "Delete Cloud Backup?", 
      content: "WARNING: This will permanently delete your data from Google Drive. If you lose your phone, this data is gone forever.", 
      isDestructive: true,
      onConfirm: () async {
        final manager = Provider.of<DataManager>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleting from Drive..."), duration: Duration(seconds: 1)));
        
        bool success = await manager.deleteCloudData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          if (success) {
            await manager.logout();
            widget.onDeleteAll();
            Navigator.pop(context); 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cloud backup deleted."), backgroundColor: Colors.red));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete cloud data. Check internet.")));
          }
        }
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = Provider.of<DataManager>(context);
    final Color bg = Theme.of(context).cardColor;
    
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader("WORK SCHEDULE"),
          _buildTimeTile("Shift Start Time", _localShiftStart, (t) => _updateTime(true, t)),
          _buildTimeTile("Shift End Time", _localShiftEnd, (t) => _updateTime(false, t)),
          
          const SizedBox(height: 20),
          _buildSectionHeader("CALCULATIONS"),
          
          ListTile(
            tileColor: bg,
            leading: const Icon(CupertinoIcons.money_dollar_circle),
            title: const Text("Base Pay (Hourly)"),
            trailing: SizedBox(
              width: 80,
              child: TextField(
                controller: _rateController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                decoration: const InputDecoration(border: InputBorder.none, hintText: "0"),
                onChanged: (val) {
                  double? rate = double.tryParse(val);
                  if (rate != null) {
                    widget.onUpdate(defaultRate: rate);
                  }
                },
              ),
            ),
          ),
          
          SwitchListTile(
            title: const Text("Smart Rounding (30m)"),
            subtitle: const Text("7:47 → 8:00 • 5:03 → 5:00"),
            secondary: const Icon(Icons.av_timer, color: Colors.purple),
            value: widget.snapToGrid,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(snapToGrid: val),
          ),

          SwitchListTile(
            title: const Text("Deduct Late Minutes"),
            subtitle: const Text("Subtract pay for late arrivals"),
            secondary: const Icon(Icons.timer_off, color: Colors.orange),
            value: manager.enableLateDeductions,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(enableLate: val),
          ),
          SwitchListTile(
            title: const Text("Calculate Overtime"),
            subtitle: const Text("Add 1.25x for hours after shift end"),
            secondary: const Icon(Icons.more_time, color: Colors.green),
            value: manager.enableOvertime,
            tileColor: bg,
            onChanged: (val) => widget.onUpdate(enableOt: val),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("SOUNDS"),
          SwitchListTile(
            title: const Text("Mute Sound Effects"),
            subtitle: const Text("Disable clicks and success sounds"),
            secondary: Icon(
              _isMuted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill,
              color: Theme.of(context).iconTheme.color,
            ),
            value: _isMuted,
            tileColor: bg,
            onChanged: (val) async {
              AudioService().playClick();
              await AudioService().toggleMute();
              setState(() {
                _isMuted = val;
              });
            },
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("DISPLAY & PRIVACY"),
          SwitchListTile(title: const Text("Dark Mode"), value: widget.isDarkMode, tileColor: bg, onChanged: (val) => widget.onUpdate(isDark: val)),
          SwitchListTile(title: const Text("24-Hour Format"), value: widget.use24HourFormat, tileColor: bg, onChanged: (val) => widget.onUpdate(is24h: val)),
          SwitchListTile(title: const Text("Privacy Mode"), subtitle: const Text("Hide money amounts (****.**)"), secondary: const Icon(CupertinoIcons.eye_slash), value: widget.hideMoney, tileColor: bg, onChanged: (val) => widget.onUpdate(hideMoney: val)),
          ListTile(
            tileColor: bg, leading: const Icon(CupertinoIcons.money_dollar), title: const Text("Currency Symbol"),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.currencySymbol,
                items: _currencies.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                onChanged: (String? newValue) { if (newValue != null) widget.onUpdate(currencySymbol: newValue); },
              ),
            ),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("DATA MANAGEMENT"),
          ListTile(
            tileColor: bg, 
            leading: const Icon(Icons.system_update, color: Colors.blue), 
            title: const Text("Check for Updates"), 
            trailing: _updateAvailable 
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), 
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)), 
                    child: const Text("NEW", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                  ) 
                : null,
            onTap: () { 
              AudioService().playClick(); 
              GithubUpdateService.checkForUpdate(context, showNoUpdateMsg: true); 
            },
          ),
          
          ListTile(
            tileColor: bg, 
            leading: const Icon(Icons.table_chart, color: Colors.green), 
            title: const Text("Export CSV Report"), 
            subtitle: const Text("Share Excel file"), 
            onTap: () {
               AudioService().playClick();
               widget.onExportReport(); 
            }
          ),
          ListTile(
            tileColor: bg, 
            leading: const Icon(Icons.file_upload, color: Colors.teal), 
            title: const Text("Export Backup (JSON)"), 
            subtitle: const Text("Save backup file to storage"), 
            onTap: () {
              AudioService().playClick();
              widget.onBackup(); 
            }
          ),
          ListTile(
            tileColor: bg, 
            leading: const Icon(Icons.file_download, color: Colors.orange), 
            title: const Text("Import Backup"), 
            subtitle: const Text("Select .json file to restore"),
            onTap: () { 
              AudioService().playClick(); 
              widget.onRestore(); 
            }
          ),
          
          const SizedBox(height: 20),
          _buildSectionHeader("DANGER ZONE"),
          
          ListTile(
            tileColor: bg, 
            leading: const Icon(Icons.delete_outline, color: Colors.red), 
            title: const Text("Clear Device Data", style: TextStyle(color: Colors.red)),
            subtitle: const Text("Removes data from this phone only", style: TextStyle(fontSize: 10, color: Colors.grey)),
            onTap: () => _confirmClearLocal(context),
          ),
          
          if (manager.isAuthenticated && !manager.isGuest)
            ListTile(
              tileColor: bg, 
              leading: const Icon(Icons.cloud_off, color: Colors.red), 
              title: const Text("Delete Cloud Backup", style: TextStyle(color: Colors.red)),
              subtitle: const Text("Permanently removes data from Drive", style: TextStyle(fontSize: 10, color: Colors.grey)),
              onTap: () => _confirmDeleteCloud(context),
            ),
            
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 12)));
  }

  Widget _buildTimeTile(String title, TimeOfDay current, Function(TimeOfDay) onSelect) {
    return ListTile(
      tileColor: Theme.of(context).cardColor, title: Text(title),
      trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(formatTime(context, current, widget.use24HourFormat), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
      onTap: () async { 
        AudioService().playClick(); 
        final t = await showFastTimePicker(context, current, widget.use24HourFormat); 
        if (t != null) onSelect(t); 
      },
    );
  }
}