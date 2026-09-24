import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

/// Centralized, thread-safe MIDI manager that prevents duplicate JNI initializations.
class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;

  MidiService._internal();

  final MidiPro midiPro = MidiPro();
  int? _soundfontId;
  bool _isReady = false;
  Completer<bool>? _initCompleter;

  bool get isReady => _isReady && _soundfontId != null;
  int? get soundfontId => _soundfontId;

  Future<bool> init() async {
    if (_isReady) return true;

    // Thread safety: Prevent concurrent initialization calls across multiple screens
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<bool>();

    try {
      // Allow Android AAudio / Surface Flinger 1000ms to settle after app boot
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!midiPro.isInitialized) {
        bool initialized = false;

        // Attempt 1: Native device auto-negotiation
        try {
          debugPrint('[MIDI_SERVICE] Attempt 1: Default native init...');
          await midiPro.init();
          initialized = true;
        } catch (e) {
          debugPrint('[MIDI_SERVICE] Attempt 1 failed: $e. Cleaning JNI handles...');
          try {
            await midiPro.dispose();
          } catch (_) {}
        }

        // Attempt 2: Explicit 48000Hz / 512 buffer fallback
        if (!initialized) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            debugPrint('[MIDI_SERVICE] Attempt 2: Fallback 48000Hz (bufferSize: 512)...');
            await midiPro.init(sampleRate: 48000, bufferSize: 512, polyphony: 32);
            initialized = true;
          } catch (e) {
            debugPrint('[MIDI_SERVICE] Attempt 2 failed: $e. Cleaning JNI handles...');
            try {
              await midiPro.dispose();
            } catch (_) {}
          }
        }

        // Attempt 3: Conservative 44100Hz / 1024 buffer fallback
        if (!initialized) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            debugPrint('[MIDI_SERVICE] Attempt 3: Fallback 44100Hz (bufferSize: 1024)...');
            await midiPro.init(sampleRate: 44100, bufferSize: 1024, polyphony: 32);
            initialized = true;
          } catch (e) {
            debugPrint('[MIDI_SERVICE] Attempt 3 failed: $e.');
          }
        }
      }

      if (midiPro.isInitialized && _soundfontId == null) {
        _soundfontId = await midiPro.loadSoundfontAsset(
          assetPath: 'assets/guitar.sf2',
          program: 27,
        );

        if (_soundfontId != null) {
          await configurePitchBendSensitivity();
          _isReady = true;
          debugPrint('[MIDI_SERVICE] Native MIDI engine & SoundFont initialized successfully.');
        } else {
          debugPrint('[MIDI_SERVICE] SoundFont asset failed to load.');
        }
      }

      _initCompleter!.complete(_isReady);
      return _isReady;
    } catch (e) {
      debugPrint('[MIDI_SERVICE] Setup Exception: $e');
      _isReady = false;
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete(false);
      }
      return false;
    } finally {
      _initCompleter = null;
    }
  }

  Future<void> configurePitchBendSensitivity() async {
    if (_soundfontId == null) return;

    for (int ch = 0; ch < 16; ch++) {
      try {
        await midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 101, data2: 0, sfId: _soundfontId!);
        await midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 100, data2: 0, sfId: _soundfontId!);
        await midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 6, data2: 12, sfId: _soundfontId!);
      } catch (_) {}
    }
  }

  Future<void> sendPitchBend(int value, {int channel = 0}) async {
    if (!_isReady || _soundfontId == null) return;

    final int clamped = value.clamp(0, 16383);
    final int lsb = clamped & 0x7F;
    final int msb = (clamped >> 7) & 0x7F;

    try {
      await midiPro.sendMidiEvent(
        status: 0xE0 | (channel & 0x0F),
        data1: lsb,
        data2: msb,
        sfId: _soundfontId!,
      );
    } catch (_) {}
  }

  Future<void> resetPitchBend({int channel = 0}) async {
    await sendPitchBend(8192, channel: channel);
  }

  void playNote({required int key, required int velocity, int channel = 0}) {
    if (_isReady && _soundfontId != null) {
      try {
        midiPro.playNote(key: key, velocity: velocity, channel: channel, sfId: _soundfontId!);
      } catch (_) {}
    }
  }

  void stopNote({required int key, int channel = 0}) {
    if (_isReady && _soundfontId != null) {
      try {
        midiPro.stopNote(key: key, channel: channel, sfId: _soundfontId!);
      } catch (_) {}
    }
  }

  Future<void> selectInstrument(int program, {int channel = 0}) async {
    if (_isReady && _soundfontId != null) {
      try {
        await midiPro.selectInstrument(sfId: _soundfontId!, program: program);
      } catch (_) {}
    }
  }
}