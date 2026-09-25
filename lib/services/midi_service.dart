import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

/// Centralized, thread-safe MIDI manager that prevents duplicate JNI initializations.
class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;
  MidiService._internal();

  final MidiPro midiPro = MidiPro();
  int? _soundfontId;

  bool _isInitializing = false;
  bool _isReady = false;

  bool get isReady => _isReady && _soundfontId != null;
  int? get soundfontId => _soundfontId;

  Future<void> init() async {
    if (_isReady || _isInitializing) return;
    _isInitializing = true;

    try {
      if (!midiPro.isInitialized) {
        await midiPro.init(sampleRate: 44100, bufferSize: 64, polyphony: 64);
      }
      
      _soundfontId = await midiPro.loadSoundfontAsset(
        assetPath: 'assets/guitar.sf2',
        program: 27,
      );
      
      _isReady = true;
      debugPrint('[MIDI_SERVICE] Native MIDI engine & SoundFont initialized successfully.');
    } catch (e) {
      debugPrint('[MIDI_SERVICE] Setup Error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> sendPitchBend(int value, {int channel = 0}) async {
    if (!_isReady || _soundfontId == null) return;
    
    final int clamped = value.clamp(0, 16383);
    final int lsb = clamped & 0x7F;
    final int msb = (clamped >> 7) & 0x7F;
    
    await midiPro.sendMidiEvent(
      status: 0xE0 | (channel & 0x0F),
      data1: lsb,
      data2: msb,
      sfId: _soundfontId!,
    );
  }

  Future<void> resetPitchBend({int channel = 0}) async {
    await sendPitchBend(8192, channel: channel);
  }

  void playNote({required int key, required int velocity, int channel = 0}) {
    if (_isReady && _soundfontId != null) {
      midiPro.playNote(key: key, velocity: velocity, channel: channel, sfId: _soundfontId!);
    }
  }

  void stopNote({required int key, int channel = 0}) {
    if (_isReady && _soundfontId != null) {
      midiPro.stopNote(key: key, channel: channel, sfId: _soundfontId!);
    }
  }

  Future<void> selectInstrument(int program, {int channel = 0}) async {
    if (_isReady && _soundfontId != null) {
      await midiPro.selectInstrument(sfId: _soundfontId!, program: program);
    }
  }
}