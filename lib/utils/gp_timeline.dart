import 'dart:math';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../models/master_bar_event.dart';
import 'pitch_curve.dart';

/// Event kinds. The enum order is the dispatch priority for events that share
/// a timestamp: note-offs first, then pitch resets, then note-ons, then
/// markers. A marker makes no sound; it only reports [ScheduledMidiEvent.beatIndex]
/// to the UI (used for rests in the studio, so they highlight too).
enum MidiEventType { noteOff, pitchBend, noteOn, marker }

/// Pre-calculated absolute MIDI event (times are at 100% speed).
class ScheduledMidiEvent implements Comparable<ScheduledMidiEvent> {
  final double timeMs;
  final MidiEventType type;
  final int channel;

  /// note_on / note_off: MIDI key. pitch_bend: 14-bit value (0..16383).
  final int data1;

  /// note_on: velocity.
  final int data2;
  final int trackIndex;
  final int beatIndex;
  final bool isMainTrack;

  /// Groups a note's on / off / bend events (used when slicing a window).
  final int noteId;

  const ScheduledMidiEvent({
    required this.timeMs,
    required this.type,
    required this.channel,
    required this.data1,
    this.data2 = 0,
    required this.trackIndex,
    required this.beatIndex,
    required this.isMainTrack,
    required this.noteId,
  });

  ScheduledMidiEvent copyWith({double? timeMs}) => ScheduledMidiEvent(
        timeMs: timeMs ?? this.timeMs,
        type: type,
        channel: channel,
        data1: data1,
        data2: data2,
        trackIndex: trackIndex,
        beatIndex: beatIndex,
        isMainTrack: isMainTrack,
        noteId: noteId,
      );

  @override
  int compareTo(ScheduledMidiEvent other) {
    final int cmp = timeMs.compareTo(other.timeMs);
    if (cmp != 0) return cmp;
    final int t = type.index.compareTo(other.type.index);
    if (t != 0) return t;
    return trackIndex.compareTo(other.trackIndex);
  }
}

/// Offsets (in quarter notes from the bar start) of every beat of a track.
class BeatLayout {
  final List<double> offsetQ;
  const BeatLayout(this.offsetQ);

  factory BeatLayout.of(GpTrack track) {
    final List<double> off = List<double>.filled(track.beats.length, 0.0);
    for (int bar = 0; bar < track.measureEndIndices.length; bar++) {
      final int first = track.barStartIndex(bar);
      final int last = track.measureEndIndices[bar];
      double acc = 0.0;
      for (int i = first; i <= last && i < track.beats.length; i++) {
        off[i] = acc;
        acc += track.beats[i].duration;
      }
    }
    return BeatLayout(off);
  }
}

/// Absolute start time of every step of a play order. Beats are anchored to
/// this grid, so a bar whose beats do not add up to the bar length can never
/// shift the bars that follow it, and all tracks stay in sync.
class BarGrid {
  final List<MasterBarEvent> bars;
  final List<int> order;
  final List<double> stepStartMs;
  final double totalMs;

  BarGrid._(this.bars, this.order, this.stepStartMs, this.totalMs);

  factory BarGrid(List<MasterBarEvent> bars, List<int> order) {
    final List<int> valid = order.where((b) => b >= 0 && b < bars.length).toList();
    final List<double> starts = [];
    double acc = 0.0;
    for (final int b in valid) {
      starts.add(acc);
      acc += bars[b].durationMs;
    }
    return BarGrid._(bars, valid, starts, acc);
  }

  factory BarGrid.linear(List<MasterBarEvent> bars) =>
      BarGrid(bars, List<int>.generate(bars.length, (i) => i));

  /// First step of the play order that plays [bar], or -1.
  int firstStepOfBar(int bar) => order.indexOf(bar);
}

class _Spec {
  final int noteId;
  final int beatIndex;
  final GpNote note;
  final int pitch;
  final int velocity;
  final double startMs;
  double nominalEndMs; // end of the written value (used to link ties / slides)
  double endMs;
  final double firstSegmentMs;
  double? slideTarget;

  _Spec({
    required this.noteId,
    required this.beatIndex,
    required this.note,
    required this.pitch,
    required this.velocity,
    required this.startMs,
    required this.nominalEndMs,
    required this.endMs,
    required this.firstSegmentMs,
    this.slideTarget,
  });
}

class GpTimelineBuilder {
  GpTimelineBuilder._();

  static double roundMs(double ms) => (ms * 10).round() / 10.0;

  /// Builds the sorted MIDI timeline of one track over [grid].
  static List<ScheduledMidiEvent> buildTrack({
    required GpTrack track,
    required BarGrid grid,
    required int trackIndex,
    required int channel,
    required bool isMainTrack,
  }) {
    final List<ScheduledMidiEvent> events = [];
    if (track.beats.isEmpty) return events;

    final BeatLayout layout = BeatLayout.of(track);
    final List<_Spec> specs = [];
    final Map<int, _Spec> lastByPitch = {};
    final Map<int, _Spec> pendingLegato = {}; // display string -> spec
    int nextId = trackIndex * 1000000;

    for (int k = 0; k < grid.order.length; k++) {
      final int bar = grid.order[k];
      final MasterBarEvent mb = grid.bars[bar];
      if (bar >= track.measureEndIndices.length) continue;
      final int first = track.barStartIndex(bar);
      final int last = min(track.measureEndIndices[bar], track.beats.length - 1);
      final double barStart = grid.stepStartMs[k];

      for (int i = first; i <= last; i++) {
        final GpBeat beat = track.beats[i];
        if (beat.isRest) continue;
        final double offQ = layout.offsetQ[i];
        final double startMs = barStart + mb.quartersToMs(offQ);
        final double endMs = barStart + mb.quartersToMs(offQ + beat.duration);
        final double durMs = endMs - startMs;
        if (durMs <= 0) continue;

        for (final GpNote note in beat.notes) {
          if (note.isRest) continue;
          final int pitch = (note.pitch != -1 ? note.pitch : 60).clamp(0, 127);

          // 1. Tie destination: extend the previous attack, never re-strike.
          if (note.isTie) {
            final _Spec? prev = lastByPitch[pitch];
            if (prev != null && (startMs - prev.nominalEndMs).abs() < 3.0) {
              prev.nominalEndMs = endMs;
              prev.endMs = max(prev.startMs + 1.0, endMs - 1.0);
              continue;
            }
            // Orphan tie: play it normally rather than silently dropping it.
          }

          // 2. Destination of a legato slide: the previous note keeps
          //    sounding and glides here, so no new attack.
          final _Spec? gliding = pendingLegato[note.stringNum];
          if (gliding != null && (startMs - gliding.nominalEndMs).abs() < 3.0) {
            gliding.slideTarget = (pitch - gliding.pitch).toDouble();
            gliding.nominalEndMs = endMs;
            gliding.endMs = max(gliding.startMs + 1.0, endMs - 1.0);
            pendingLegato.remove(note.stringNum);
            lastByPitch[pitch] = gliding;
            continue;
          }

          // 3. Normal attack.
          int vel = isMainTrack ? 110 : 80;
          double dur = durMs;
          if (note.isPercussion) {
            vel = 100;
            dur = min(dur, 150.0);
          } else {
            if (note.isGhost) vel = (vel * 0.70).round();
            if (note.isLegato) vel = (vel * 0.80).round();
            if (note.isMuted) {
              vel = (vel * 0.80).round();
              dur = min(dur, 90.0);
            } else if (note.isPalmMute) {
              vel = (vel * 0.65).round();
              dur *= 0.5;
            }
            if (note.isLetRing) dur *= 1.5;
            if (!note.isLegato) dur = max(1.0, dur - 1.0);
          }
          vel = vel.clamp(20, 127);

          // A previous note on the same key that is still ringing must end
          // before this attack, otherwise its late note_off kills this one.
          final _Spec? ringing = lastByPitch[pitch];
          if (ringing != null && ringing.endMs > startMs) {
            ringing.endMs = max(ringing.startMs + 1.0, startMs - 0.5);
          }

          final _Spec spec = _Spec(
            noteId: nextId++,
            beatIndex: i,
            note: note,
            pitch: pitch,
            velocity: vel,
            startMs: startMs,
            nominalEndMs: endMs,
            endMs: startMs + dur,
            firstSegmentMs: durMs,
          );

          // Slide destination lookahead (shift & legato slides).
          if (note.slideType == SlideType.shift || note.slideType == SlideType.legato) {
            final GpNote? target = _nextNoteOnString(track, i, note.stringNum);
            if (target != null) {
              spec.slideTarget = (target.pitch - pitch).toDouble();
              if (note.slideType == SlideType.legato) pendingLegato[note.stringNum] = spec;
            }
          }

          specs.add(spec);
          lastByPitch[pitch] = spec;
        }
      }
    }

    // ---- Specs -> events ----
    for (final _Spec s in specs) {
      events.add(ScheduledMidiEvent(
        timeMs: roundMs(s.startMs),
        type: MidiEventType.noteOn,
        channel: channel,
        data1: s.pitch,
        data2: s.velocity,
        trackIndex: trackIndex,
        beatIndex: s.beatIndex,
        isMainTrack: isMainTrack,
        noteId: s.noteId,
      ));
      events.add(ScheduledMidiEvent(
        timeMs: roundMs(s.endMs),
        type: MidiEventType.noteOff,
        channel: channel,
        data1: s.pitch,
        trackIndex: trackIndex,
        beatIndex: s.beatIndex,
        isMainTrack: isMainTrack,
        noteId: s.noteId,
      ));

      final List<PitchSample> curve = _curveFor(s);
      for (final PitchSample p in curve) {
        events.add(ScheduledMidiEvent(
          timeMs: roundMs(s.startMs + p.tMs),
          type: MidiEventType.pitchBend,
          channel: channel,
          data1: PitchCurve.toBendValue(p.semitones),
          trackIndex: trackIndex,
          beatIndex: s.beatIndex,
          isMainTrack: isMainTrack,
          noteId: s.noteId,
        ));
      }
    }

    events.sort();
    return _dropRedundantBends(events);
  }

  static List<PitchSample> _curveFor(_Spec s) {
    final double dur = s.endMs - s.startMs;
    final GpNote n = s.note;
    if (n.bend != null) return PitchCurve.bend(n.bend!, dur);
    if (n.slideType != SlideType.none) {
      final List<PitchSample> c = PitchCurve.slide(
        n.slideType,
        dur,
        firstSegmentMs: s.firstSegmentMs,
        targetSemitones: s.slideTarget,
      );
      if (c.isNotEmpty) return c;
    }
    if (n.vibrato != null) return PitchCurve.vibrato(n.vibrato!, dur);
    return const [];
  }

  static GpNote? _nextNoteOnString(GpTrack track, int beatIndex, int stringNum) {
    for (int j = beatIndex + 1; j < track.beats.length && j <= beatIndex + 2; j++) {
      final GpBeat b = track.beats[j];
      if (b.isRest) continue;
      final GpNote? n = b.noteOnString(stringNum);
      if (n != null && !n.isRest) return n;
      return null;
    }
    return null;
  }

  /// Removes pitch_bend events that repeat the previous value on the same
  /// channel (keeps the native call rate low).
  static List<ScheduledMidiEvent> _dropRedundantBends(List<ScheduledMidiEvent> sorted) {
    final Map<int, int> lastValue = {};
    final List<ScheduledMidiEvent> out = [];
    for (final ScheduledMidiEvent e in sorted) {
      if (e.type == MidiEventType.pitchBend) {
        if (lastValue[e.channel] == e.data1) continue;
        lastValue[e.channel] = e.data1;
      }
      out.add(e);
    }
    return out;
  }

  /// Keeps the notes that START inside [fromMs, toMs) and shifts them so the
  /// window starts at 0. Note-offs are clamped to the window end.
  static List<ScheduledMidiEvent> slice(List<ScheduledMidiEvent> events, double fromMs, double toMs) {
    final Set<int> kept = {};
    for (final ScheduledMidiEvent e in events) {
      if (e.type == MidiEventType.noteOn && e.timeMs >= fromMs - 0.05 && e.timeMs < toMs - 0.05) {
        kept.add(e.noteId);
      }
    }
    final double len = toMs - fromMs;
    final List<ScheduledMidiEvent> out = [];
    for (final ScheduledMidiEvent e in events) {
      if (!kept.contains(e.noteId)) continue;
      final double t = roundMs(e.timeMs - fromMs);
      if (e.type == MidiEventType.noteOn) {
        out.add(e.copyWith(timeMs: max(0.0, t)));
      } else if (e.type == MidiEventType.noteOff) {
        out.add(e.copyWith(timeMs: min(max(0.0, t), len)));
      } else if (t < len) {
        out.add(e.copyWith(timeMs: max(0.0, t)));
      }
    }
    out.sort();
    return out;
  }
}

/// A ready-to-play schedule (all times at 100% speed).
class GpPlaybackPlan {
  final List<ScheduledMidiEvent> events;
  final double durationMs;

  /// Main-track beat the plan starts at (for highlighting before the first note).
  final int startBeat;
  const GpPlaybackPlan(this.events, this.durationMs, this.startBeat);
}

class GpPlaybackPlanner {
  GpPlaybackPlanner._();

  /// MIDI channel of the General MIDI drum kit.
  static const int drumChannel = 9;

  static const List<int> _legacyChannels = [12, 1, 3, 7, 10];
  static const List<int> _spareChannels = [0, 2, 4, 5, 6, 8, 11, 13, 14, 15];

  /// One channel per track so pitch bends / note tracking never collide.
  static List<int> assignChannels(List<GpTrack> tracks) {
    final List<int> out = [];
    int spare = 0;
    for (int i = 0; i < tracks.length; i++) {
      if (tracks[i].isPercussion) {
        out.add(drumChannel);
      } else if (i < _legacyChannels.length) {
        out.add(_legacyChannels[i]);
      } else {
        out.add(_spareChannels[spare++ % _spareChannels.length]);
      }
    }
    return out;
  }

  /// Plans playback.
  ///
  /// * no range: whole song in PLAY order (repeats unrolled);
  /// * [fromBeat] only: from that beat to the end (repeats unrolled);
  /// * [fromBeat] + [toBeat] (inclusive, main-track indices): exactly that
  ///   range, played once.
  ///
  /// [tailRestSixteenths] appends silence (used between loops).
  static GpPlaybackPlan plan({
    required GpScore score,
    required int mainTrack,
    int fromBeat = -1,
    int toBeat = -1,
    int tailRestSixteenths = 0,
  }) {
    final List<MasterBarEvent> bars = score.masterBars;
    final List<GpTrack> tracks = score.tracks;
    if (bars.isEmpty || tracks.isEmpty) return const GpPlaybackPlan([], 0, 0);

    final GpTrack main = tracks[mainTrack];
    final bool isRange = fromBeat >= 0 && toBeat >= fromBeat;
    final List<int> order = isRange || score.playOrder.isEmpty
        ? List<int>.generate(bars.length, (i) => i)
        : score.playOrder;
    final BarGrid grid = BarGrid(bars, order);
    final List<int> channels = assignChannels(tracks);

    final List<ScheduledMidiEvent> all = [];
    for (int t = 0; t < tracks.length; t++) {
      all.addAll(GpTimelineBuilder.buildTrack(
        track: tracks[t],
        grid: grid,
        trackIndex: t,
        channel: channels[t],
        isMainTrack: t == mainTrack,
      ));
    }
    all.sort();

    double startMs = 0.0;
    double endMs = grid.totalMs;
    int startBeat = 0;

    if (fromBeat >= 0 && fromBeat < main.beats.length) {
      startBeat = fromBeat;
      final int bar = main.barOfBeat(fromBeat);
      final int step = grid.firstStepOfBar(bar);
      if (step >= 0) {
        final double offQ = BeatLayout.of(main).offsetQ[fromBeat];
        startMs = grid.stepStartMs[step] + bars[bar].quartersToMs(offQ);
      }
      if (isRange) {
        final int toIdx = min(toBeat, main.beats.length - 1);
        final int endBar = main.barOfBeat(toIdx);
        final int endStep = grid.firstStepOfBar(endBar);
        if (endStep >= 0) {
          final double offQ = BeatLayout.of(main).offsetQ[toIdx];
          endMs = grid.stepStartMs[endStep] + bars[endBar].quartersToMs(offQ + main.beats[toIdx].duration);
        }
      }
    }

    List<ScheduledMidiEvent> events = all;
    if (startMs > 0.0 || endMs < grid.totalMs) {
      events = GpTimelineBuilder.slice(all, startMs, endMs);
    }
    double duration = max(0.0, endMs - startMs);

    if (tailRestSixteenths > 0) {
      final double tempo = bars[bars.length - 1].endTempo;
      duration += tailRestSixteenths * 0.25 * (60000.0 / (tempo <= 0 ? 120.0 : tempo));
    }
    return GpPlaybackPlan(events, duration, startBeat);
  }
}