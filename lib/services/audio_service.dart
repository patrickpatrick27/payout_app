import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW: To save mute state

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isMuted = false; // NEW: Mute state

  // Getters
  bool get isMuted => _isMuted;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isMuted = prefs.getBool('app_muted') ?? false; // Load saved mute state
    
    await _player.setReleaseMode(ReleaseMode.stop);
    // Attempt to preload. If it fails on some Androids, it's fine, we catch it later.
    try {
      await _player.setSource(AssetSource('sounds/payroll.wav')); 
    } catch (e) {
      print("Audio Init Error: $e");
    }
  }

  // NEW: Toggle Mute
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_muted', _isMuted);
    
    // If we just muted and it was playing, stop it.
    if (_isMuted) {
      await _player.stop();
    }
  }

  Future<void> playClick() async {
    if (_isMuted) return; // Check mute
    if (_player.state == PlayerState.playing) await _player.stop();
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.5);
  }

  Future<void> playDelete() async {
    if (_isMuted) return; // Check mute
    if (_player.state == PlayerState.playing) await _player.stop();
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.6);
  }

  Future<void> playSuccess() async {
    if (_isMuted) return; // Check mute
    if (_player.state == PlayerState.playing) await _player.stop();
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.7);
  }
}