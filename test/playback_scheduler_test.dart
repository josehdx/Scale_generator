import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/services/playback_scheduler.dart';
import 'package:tab_generator/utils/gp_timeline.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.

class FakeSink extends MidiSink {
  final log = <String>[];
  @override
  void noteOn(int key, int velocity, int channel) => log.add('on:$channel:$key');
  @override
  void noteOff(int key, int channel) => log.add('off:$channel:$key');
  @override
  void pitchBend(int value, int channel) => log.add('bend:$channel:$value');
}

ScheduledMidiEvent ev(double t, MidiEventType type, int key, {int track = 0, int ch = 1, int beat = 0, int vel = 100, bool main = true}) =>
    ScheduledMidiEvent(timeMs: t, type: type, channel: ch, data1: key, data2: vel, trackIndex: track, beatIndex: beat, isMainTrack: main, noteId: key);

void main() {
  test('plays events in order and finishes', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    final beats = <int>[];
    var finished = false;
    s.onBeat = beats.add;
    s.onFinished = () => finished = true;
    await s.start(
      events: [ev(0, MidiEventType.noteOn, 60), ev(50, MidiEventType.noteOff, 60), ev(60, MidiEventType.noteOn, 62, beat: 1), ev(110, MidiEventType.noteOff, 62, beat: 1)],
      durationMs: 130,
      warmUp: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(sink.log, ['on:1:60', 'off:1:60', 'on:1:62', 'off:1:62']);
    expect(beats, [0, 1]);
    expect(finished, isTrue);
  });

  test('stop sends note-off on the note\'s own channel', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    await s.start(events: [ev(0, MidiEventType.noteOn, 60, ch: 5), ev(5000, MidiEventType.noteOff, 60, ch: 5)], durationMs: 6000, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.stop();
    expect(sink.log, contains('off:5:60'));
  });

  test('muting a track mid-play cuts its notes and never leaves them stuck', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    var muted = false;
    s.isAudible = (t) => !(muted && t == 1);
    await s.start(events: [ev(0, MidiEventType.noteOn, 64, track: 1, ch: 3), ev(5000, MidiEventType.noteOff, 64, track: 1, ch: 3)], durationMs: 6000, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    muted = true;
    s.refreshAudibility();
    expect(sink.log, contains('off:3:64'));
    s.stop();
  });

  test('pause keeps the position, resume continues', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    await s.start(events: [ev(0, MidiEventType.noteOn, 60), ev(200, MidiEventType.noteOff, 60), ev(300, MidiEventType.noteOn, 62), ev(350, MidiEventType.noteOff, 62)], durationMs: 400, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    s.pause();
    final p = s.positionMs;
    expect(p, greaterThan(50));
    expect(sink.log, contains('off:1:60'));
    await s.resume();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(sink.log, contains('on:1:62'));
  });

  test('speed can change while playing', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    await s.start(events: [ev(0, MidiEventType.noteOn, 60), ev(10, MidiEventType.noteOff, 60), ev(1000, MidiEventType.noteOn, 62), ev(1010, MidiEventType.noteOff, 62)], durationMs: 1100, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.speed = 4.0; // 1000 ms of music now needs ~250 ms
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(sink.log, contains('on:1:62'));
    s.stop();
  });

  test('markers highlight silent steps (rests) without sound', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    final beats = <int>[];
    s.onBeat = beats.add;
    await s.start(
      events: [ev(0, MidiEventType.marker, 0, beat: 0), ev(40, MidiEventType.marker, 0, beat: 1)],
      durationMs: 100,
      warmUp: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(beats, [0, 1]);
    expect(sink.log, isEmpty);
  });

  test('seek on a loaded schedule moves the position and highlight; resume plays from there', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    final beats = <int>[];
    s.onBeat = beats.add;
    s.load(
      events: [
        ev(0, MidiEventType.noteOn, 60, beat: 0), ev(50, MidiEventType.noteOff, 60, beat: 0),
        ev(200, MidiEventType.noteOn, 62, beat: 1), ev(250, MidiEventType.noteOff, 62, beat: 1),
      ],
      durationMs: 300,
    );
    expect(s.hasSchedule, isTrue);
    s.seekMs(150);
    expect(s.positionMs, 150);
    expect(beats, [0]); // highlight follows the seek, nothing sounded
    expect(sink.log, isEmpty);
    await s.resume();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(sink.log, ['on:1:62', 'off:1:62']);
  });

  test('positionMs is stable while paused', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    await s.start(events: [ev(0, MidiEventType.noteOn, 60), ev(5000, MidiEventType.noteOff, 60)], durationMs: 6000, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    s.pause();
    final p1 = s.positionMs;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(s.positionMs, p1);
    s.stop();
    expect(s.positionMs, 0);
  });

  test('looping wraps with note-offs', () async {
    final sink = FakeSink();
    final s = PlaybackScheduler(sink);
    await s.start(events: [ev(0, MidiEventType.noteOn, 60), ev(30, MidiEventType.noteOff, 60)], durationMs: 60, loop: true, warmUp: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    s.stop();
    expect(sink.log.where((l) => l == 'on:1:60').length, greaterThan(2));
  });
}
