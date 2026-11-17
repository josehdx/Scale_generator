import 'dart:async';

import '../utils/gp_timeline.dart';

/// Where MIDI messages go. The real implementation wraps `MidiService`; tests
/// use a fake.
abstract class MidiSink {
  void noteOn(int key, int velocity, int channel);
  void noteOff(int key, int channel);

  /// [value] is the 14-bit pitch-bend value (8192 = neutral).
  void pitchBend(int value, int channel);

  /// Optional hard stop for a channel (CC 123). Default: no-op.
  void allNotesOff(int channel) {}
}

/// One scheduler for every screen.
///
///  * a single [Stopwatch] clock; every event time is compared against it, so
///    delays never accumulate (no chained `Future.delayed` drift);
///  * every sounding note is tracked per (channel, key) with its track, so
///    pause / stop / mute / loop-wrap always send the matching note-offs on
///    the right channel;
///  * the playback speed is a clock multiplier and can change while playing;
///  * a run token makes stale runs exit immediately, so two overlapping
///    `start` calls can never stop each other's notes.
class PlaybackScheduler {
  PlaybackScheduler(this._sink);

  final MidiSink _sink;

  /// Whether notes of this track should be heard (mute / solo state).
  bool Function(int trackIndex) isAudible = (_) => true;

  /// Called (on every main-track note-on) with the beat index to highlight.
  void Function(int beatIndex)? onBeat;

  /// Called once when a non-looping run reaches its end.
  void Function()? onFinished;

  List<ScheduledMidiEvent> _events = const [];
  double _durationMs = 0.0;
  bool _loop = false;
  double _speed = 1.0;

  final Stopwatch _clock = Stopwatch();
  double _basePosMs = 0.0;
  int _next = 0;
  int _token = 0;
  bool _running = false;
  int _lastBeat = -1;

  // (channel << 7 | key) -> track index that started the note
  final Map<int, int> _active = {};
  final Set<int> _bentChannels = {};
  final Set<int> _usedChannels = {};

  Timer? _sleepTimer;
  Completer<void>? _wake;

  DateTime? _lastStoppedAt;
  double maxDriftMs = 0.0;

  bool get isRunning => _running;
  double get speed => _speed;
  double get durationMs => _durationMs;
  bool get loop => _loop;

  /// Current musical position (ms at 100% speed).
  double get positionMs {
    // While paused / stopped the (stopped) clock still holds its old elapsed
    // time, so only the stored base position is valid.
    if (!_running) return _basePosMs > _durationMs ? _durationMs : _basePosMs;
    final double p = _basePosMs + _clock.elapsedMicroseconds / 1000.0 * _speed;
    return p > _durationMs ? _durationMs : p;
  }

  set loop(bool v) => _loop = v;

  /// Changes speed immediately, even in the middle of a run.
  set speed(double v) {
    final double clamped = v.clamp(0.1, 4.0).toDouble();
    if (clamped == _speed) return;
    if (_running) {
      _basePosMs = positionMs;
      _clock
        ..reset()
        ..start();
    }
    _speed = clamped;
    _poke();
  }

  static int _key(int channel, int pitch) => (channel << 7) | (pitch & 0x7F);

  /// Loads a schedule and starts it at [fromMs].
  Future<void> start({
    required List<ScheduledMidiEvent> events,
    required double durationMs,
    double fromMs = 0.0,
    bool loop = false,
    Duration warmUp = const Duration(milliseconds: 100),
  }) async {
    final int token = _invalidate();
    _silenceAll(); // never leave the previous run's notes hanging
    _events = events;
    _durationMs = durationMs;
    _loop = loop;
    _basePosMs = fromMs.clamp(0.0, durationMs).toDouble();
    _next = _indexAtOrAfter(_basePosMs);
    _lastBeat = -1;
    _running = true;

    // Wake the native audio engine after a long pause (it swallows the first
    // note otherwise). Done once, and the token is re-checked afterwards so a
    // newer start() cannot be killed by this one.
    final bool cold = _lastStoppedAt == null ||
        DateTime.now().difference(_lastStoppedAt!).inSeconds > 8;
    if (cold && warmUp > Duration.zero) {
      _sink.noteOn(12, 1, 0);
      await Future<void>.delayed(warmUp);
      _sink.noteOff(12, 0);
      if (token != _token) return;
    }

    _clock
      ..reset()
      ..start();
    unawaited(_run(token));
  }

  /// Loads a schedule without starting it (position 0, paused). [resume]
  /// then plays it, and [seekMs] works before the first note sounds.
  void load({required List<ScheduledMidiEvent> events, required double durationMs, bool loop = false}) {
    _invalidate();
    _silenceAll();
    _events = events;
    _durationMs = durationMs;
    _loop = loop;
    _running = false;
    _basePosMs = 0.0;
    _next = 0;
    _lastBeat = -1;
  }

  /// Jumps to [ms] (musical time at 100% speed). Works while playing, paused
  /// or loaded. Sounding notes are released, and the playhead is moved to the
  /// beat at that position.
  void seekMs(double ms) {
    final double target = ms.clamp(0.0, _durationMs).toDouble();
    final bool wasRunning = _running;
    final int token = _invalidate();
    _silenceAll();
    _basePosMs = target;
    _next = _indexAtOrAfter(target);
    _lastBeat = -1;
    // Move the highlight even when nothing sounds yet (paused / loaded).
    for (int i = _next - 1; i >= 0; i--) {
      final ScheduledMidiEvent e = _events[i];
      if (e.isMainTrack && (e.type == MidiEventType.noteOn || e.type == MidiEventType.marker)) {
        _lastBeat = e.beatIndex;
        onBeat?.call(e.beatIndex);
        break;
      }
    }
    if (wasRunning) {
      _running = true;
      _clock
        ..reset()
        ..start();
      unawaited(_run(token));
    }
  }

  /// True when a schedule is loaded (playing, paused or merely loaded).
  bool get hasSchedule => _events.isNotEmpty || _durationMs > 0;

  /// Pauses and remembers the position; [resume] continues from there.
  void pause() {
    if (!_running) return;
    _basePosMs = positionMs;
    _invalidate();
    _running = false;
    _silenceAll();
  }

  Future<void> resume() async {
    if (_running || _events.isEmpty) return;
    final int token = _invalidate();
    _next = _indexAtOrAfter(_basePosMs);
    _running = true;
    _clock
      ..reset()
      ..start();
    unawaited(_run(token));
  }

  /// Stops and rewinds to the start.
  void stop() {
    _invalidate();
    _running = false;
    _basePosMs = 0.0;
    _next = 0;
    _lastBeat = -1;
    _silenceAll();
  }

  /// Call after mute / solo changed: cuts notes that must no longer be heard.
  void refreshAudibility() {
    final List<MapEntry<int, int>> toStop =
        _active.entries.where((e) => !isAudible(e.value)).toList();
    final Set<int> channels = {};
    for (final MapEntry<int, int> e in toStop) {
      final int channel = e.key >> 7;
      _sink.noteOff(e.key & 0x7F, channel);
      _active.remove(e.key);
      channels.add(channel);
    }
    for (final int ch in channels) {
      if (_bentChannels.remove(ch)) _sink.pitchBend(8192, ch);
    }
  }

  void dispose() {
    _invalidate();
    _running = false;
    _silenceAll();
  }

  // ---------------------------------------------------------------------------

  int _invalidate() {
    _token++;
    _sleepTimer?.cancel();
    _clock.stop();
    _poke();
    return _token;
  }

  void _poke() {
    final Completer<void>? w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _sleep(Duration d) {
    final Completer<void> c = Completer<void>();
    _wake = c;
    _sleepTimer?.cancel();
    _sleepTimer = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  int _indexAtOrAfter(double ms) {
    int lo = 0;
    int hi = _events.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_events[mid].timeMs < ms - 0.05) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Future<void> _run(int token) async {
    while (token == _token) {
      final double pos = positionMs;

      // Fire everything that is due (2 ms look-ahead groups chords).
      while (_next < _events.length && _events[_next].timeMs <= pos + 2.0) {
        final ScheduledMidiEvent e = _events[_next++];
        final double drift = pos - e.timeMs;
        if (drift > maxDriftMs) maxDriftMs = drift;
        _dispatch(e);
        if (token != _token) return;
      }

      if (_next >= _events.length && pos >= _durationMs - 0.5) {
        _silenceAll();
        if (_loop && token == _token && _durationMs > 0) {
          _basePosMs = 0.0;
          _next = 0;
          _lastBeat = -1;
          _clock
            ..reset()
            ..start();
          continue;
        }
        _running = false;
        _basePosMs = 0.0;
        _next = 0;
        _lastBeat = -1;
        _clock.stop();
        _lastStoppedAt = DateTime.now();
        onFinished?.call();
        return;
      }

      final double targetMs = _next < _events.length ? _events[_next].timeMs : _durationMs;
      final double waitMusicalMs = targetMs - positionMs;
      final double waitWallMs = waitMusicalMs / _speed;
      if (waitWallMs > 0.5) {
        await _sleep(Duration(microseconds: (waitWallMs * 1000).round()));
      } else {
        await Future<void>.delayed(Duration.zero); // yield to the UI thread
      }
    }
  }

  void _dispatch(ScheduledMidiEvent e) {
    switch (e.type) {
      case MidiEventType.noteOn:
        if (e.isMainTrack && e.beatIndex != _lastBeat) {
          _lastBeat = e.beatIndex;
          onBeat?.call(e.beatIndex);
        }
        if (!isAudible(e.trackIndex)) return;
        final int k = _key(e.channel, e.data1);
        if (_active.containsKey(k)) _sink.noteOff(e.data1, e.channel);
        _active[k] = e.trackIndex;
        _usedChannels.add(e.channel);
        _sink.noteOn(e.data1, e.data2, e.channel);
        break;
      case MidiEventType.noteOff:
        // Always honoured for notes we started, even if the track has been
        // muted since (that used to leave notes stuck).
        if (_active.remove(_key(e.channel, e.data1)) != null) {
          _sink.noteOff(e.data1, e.channel);
        }
        break;
      case MidiEventType.marker:
        if (e.isMainTrack && e.beatIndex != _lastBeat) {
          _lastBeat = e.beatIndex;
          onBeat?.call(e.beatIndex);
        }
        break;
      case MidiEventType.pitchBend:
        if (!isAudible(e.trackIndex)) return;
        _sink.pitchBend(e.data1, e.channel);
        if (e.data1 == 8192) {
          _bentChannels.remove(e.channel);
        } else {
          _bentChannels.add(e.channel);
        }
        break;
    }
  }

  /// Note-off for every sounding note on every channel it was started on,
  /// reset pitch bend, and hard-stop the channels used.
  void _silenceAll() {
    for (final int k in _active.keys.toList()) {
      _sink.noteOff(k & 0x7F, k >> 7);
    }
    _active.clear();
    for (final int ch in _bentChannels) {
      _sink.pitchBend(8192, ch);
    }
    _bentChannels.clear();
    for (final int ch in _usedChannels) {
      _sink.allNotesOff(ch);
    }
    _lastStoppedAt = DateTime.now();
  }
}
