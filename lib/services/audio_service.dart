import 'package:audioplayers/audioplayers.dart';

class AudioService {
  // 1. Singleton Pattern
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // 2. Define player
  // We keep one player for UI sounds to prevent memory leaks from creating too many instances.
  final AudioPlayer _player = AudioPlayer();

  // 3. Preload/Init
  Future<void> init() async {
    // strict: prevents the audio from being interrupted by other apps (optional)
    await _player.setReleaseMode(ReleaseMode.stop);
    
    // OPTIONAL: Preload the sound to memory to reduce initial lag
    // Note: AudioPlayers usually handles this well on-the-fly for small assets,
    // but setting the source ahead of time can help.
    await _player.setSource(AssetSource('sounds/payroll.wav'));
  }

  // 4. Play Methods
  // Note: I noticed you are using 'payroll.wav' for all three methods. 
  // I kept it that way, but you might want to switch the filenames later.

  Future<void> playClick() async {
    // forceful stop not strictly necessary for SFX, but ensures clean restart
    if (_player.state == PlayerState.playing) await _player.stop(); 
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.1);
  }

  Future<void> playDelete() async {
    if (_player.state == PlayerState.playing) await _player.stop();
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.1);
  }

  Future<void> playSuccess() async {
    if (_player.state == PlayerState.playing) await _player.stop();
    await _player.play(AssetSource('sounds/payroll.wav'), volume: 0.1);
  }
}