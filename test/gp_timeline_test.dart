import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/gp_note.dart';
import 'package:tab_generator/services/gpx_parser_service.dart';
import 'package:tab_generator/utils/gp_timeline.dart';

import 'support/gpif_fixture.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.

List<ScheduledMidiEvent> build(String xml, {bool useOrder = true}) {
  final score = GpxParserService.parseGpifXml(xml);
  final grid = useOrder ? BarGrid(score.masterBars, score.playOrder) : BarGrid.linear(score.masterBars);
  return GpTimelineBuilder.buildTrack(
    track: score.tracks.first,
    grid: grid,
    trackIndex: 0,
    channel: 1,
    isMainTrack: true,
  );
}

Iterable<ScheduledMidiEvent> ons(List<ScheduledMidiEvent> e) => e.where((x) => x.type == MidiEventType.noteOn);

void main() {
  test('1.8 a short / odd bar cannot shift the following bars', () {
    final xml = buildGpif(bars: [
      const FxBar([FxBeat('q', [FxNote(0, 1)])]), // padded to 4 quarters
      const FxBar([FxBeat('q', [FxNote(0, 2)])]),
    ]);
    final on = ons(build(xml)).toList();
    expect(on[0].timeMs, 0);
    expect(on[1].timeMs, closeTo(2000, 0.2)); // exactly one 4/4 bar @120
  });

  test('1.2 tie destination extends the note instead of re-attacking', () {
    final xml = buildGpif(bars: [
      const FxBar([
        FxBeat('q', [FxNote(0, 7, extraChildren: '<Tie origin="true" destination="false"/>')]),
        FxBeat('q', [FxNote(0, 7, extraChildren: '<Tie origin="false" destination="true"/>')]),
        FxBeat('h'),
      ]),
    ]);
    final e = build(xml);
    expect(ons(e).length, 1);
    final off = e.firstWhere((x) => x.type == MidiEventType.noteOff);
    expect(off.timeMs, closeTo(1000 - 1, 1.0)); // two quarters @120 minus the 1 ms gap
  });

  test('1.7 repeats are unrolled in the timeline', () {
    final xml = buildGpif(bars: [
      const FxBar([FxBeat('w', [FxNote(0, 1)])], masterExtra: '<Repeat start="true" end="true" count="2"/>'),
    ]);
    final on = ons(build(xml)).toList();
    expect(on.length, 2);
    expect(on[1].timeMs - on[0].timeMs, closeTo(2000, 0.2));
    expect(on[1].beatIndex, on[0].beatIndex); // highlights the same written beat
  });

  test('1.3 slides produce pitch-bend events', () {
    final xml = buildGpif(bars: [
      const FxBar([
        FxBeat('q', [FxNote(0, 5, extraProps: '<Property name="Slide"><Flags>1</Flags></Property>')]),
        FxBeat('q', [FxNote(0, 9)]),
        FxBeat('h'),
      ]),
    ]);
    final bends = build(xml).where((x) => x.type == MidiEventType.pitchBend).toList();
    expect(bends, isNotEmpty);
    expect(bends.last.data1, 8192); // returns to neutral
    expect(bends.any((b) => b.data1 > 8192), isTrue); // glides up towards fret 9
  });

  test('3.4 slice excludes the first note after the window', () {
    final xml = buildGpif(bars: [
      const FxBar([
        FxBeat('q', [FxNote(0, 1)]),
        FxBeat('q', [FxNote(0, 2)]),
        FxBeat('q', [FxNote(0, 3)]),
        FxBeat('q', [FxNote(0, 4)]),
      ]),
    ]);
    final all = build(xml);
    final win = GpTimelineBuilder.slice(all, 500, 1000); // second beat only
    expect(ons(win).length, 1);
    expect(ons(win).first.data1, 42);
    expect(ons(win).first.timeMs, 0);
  });

  test('every note_on has a note_off', () {
    final xml = buildGpif(bars: [
      const FxBar([FxBeat('q', [FxNote(0, 1), FxNote(1, 2)]), FxBeat('q', [FxNote(0, 3)]), FxBeat('h')]),
    ]);
    final e = build(xml);
    expect(ons(e).length, e.where((x) => x.type == MidiEventType.noteOff).length);
  });
}
