import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/gp_note.dart';
import 'package:tab_generator/services/gpx_parser_service.dart';
import 'package:tab_generator/utils/play_order.dart';

import 'support/gpif_fixture.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.

GpNote firstNote(String xml, {int bar = 0}) {
  final score = GpxParserService.parseGpifXml(xml);
  final track = score.tracks.first;
  return track.beats[track.barStartIndex(bar)].notes.first;
}

List<FxBar> oneBar(FxNote n) => [
      FxBar([FxBeat('q', [n]), const FxBeat('q'), const FxBeat('h')]),
    ];

void main() {
  group('1.1 tuning / pitch', () {
    test('standard guitar', () {
      final n = firstNote(buildGpif(bars: oneBar(const FxNote(0, 0))));
      expect(n.pitch, 40);
      expect(n.stringNum, 6);
    });

    test('4-string bass is not an octave high and uses lines 1..4', () {
      final low = firstNote(buildGpif(tuning: [28, 33, 38, 43], bars: oneBar(const FxNote(0, 0))));
      final high = firstNote(buildGpif(tuning: [28, 33, 38, 43], bars: oneBar(const FxNote(3, 0))));
      expect(low.pitch, 28);
      expect(low.stringNum, 4);
      expect(high.pitch, 43);
      expect(high.stringNum, 1);
    });

    test('7-string guitar', () {
      final n = firstNote(buildGpif(tuning: [35, 40, 45, 50, 55, 59, 64], bars: oneBar(const FxNote(0, 3))));
      expect(n.pitch, 38);
      expect(n.stringNum, 7);
    });

    test('open G tuning', () {
      final n = firstNote(buildGpif(tuning: [38, 43, 50, 55, 59, 62], bars: oneBar(const FxNote(5, 0))));
      expect(n.pitch, 62);
    });

    test('drum track yields GM pitch, fret 0 and a lane', () {
      final xml = buildGpif(
        drums: true,
        bars: oneBar(const FxNote(0, 0, extraProps: '<Property name="Midi"><Number>36</Number></Property>')),
      );
      final n = firstNote(xml);
      expect(n.isPercussion, isTrue);
      expect(n.pitch, 36);
      expect(n.fretNum, 0);
      expect(n.stringNum, 6);
    });
  });

  group('1.2 ties', () {
    test('origin attacks, destination is the tie', () {
      final xml = buildGpif(bars: [
        const FxBar([
          FxBeat('q', [FxNote(0, 7, extraChildren: '<Tie origin="true" destination="false"/>')]),
          FxBeat('q', [FxNote(0, 7, extraChildren: '<Tie origin="false" destination="true"/>')]),
          FxBeat('h'),
        ]),
      ]);
      final beats = GpxParserService.parseGpifXml(xml).tracks.first.beats;
      expect(beats[0].notes.first.isTie, isFalse);
      expect(beats[0].notes.first.isTieOrigin, isTrue);
      expect(beats[1].notes.first.isTie, isTrue);
    });
  });

  group('1.3 - 1.6 techniques', () {
    test('slide flags', () {
      expect(firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="Slide"><Flags>2</Flags></Property>')))).slideType, SlideType.legato);
      expect(firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="Slide"><Flags>1</Flags></Property>')))).slideType, SlideType.shift);
      expect(firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="Slide"><Flags>16</Flags></Property>')))).slideType, SlideType.intoFromBelow);
      expect(firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="Slide"><Flags>4</Flags></Property>')))).slideType, SlideType.outDownwards);
    });

    test('hammer-on / pull-off', () {
      final origin = firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="HopoOrigin"><Enable/></Property>'))));
      final dest = firstNote(buildGpif(bars: oneBar(const FxNote(0, 7, extraProps: '<Property name="HopoDestination"><Enable/></Property>'))));
      expect(origin.isHopoOrigin, isTrue);
      expect(origin.isLegato, isFalse);
      expect(dest.isLegato, isTrue);
    });

    test('natural harmonics use the harmonic fret', () {
      final h7 = firstNote(buildGpif(bars: oneBar(const FxNote(0, 7, extraProps: '<Property name="HarmonicType"><HType>Natural</HType></Property><Property name="HarmonicFret"><HFret>7</HFret></Property>'))));
      final h12 = firstNote(buildGpif(bars: oneBar(const FxNote(0, 12, extraProps: '<Property name="HarmonicType"><HType>Natural</HType></Property><Property name="HarmonicFret"><HFret>12</HFret></Property>'))));
      expect(h7.pitch, 40 + 19);
      expect(h12.pitch, 40 + 12);
      expect(h7.harmonicType, HarmonicType.natural);
    });

    test('artificial harmonic adds the interval to the fretted note', () {
      final n = firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraProps: '<Property name="HarmonicType"><HType>Artificial</HType></Property><Property name="HarmonicFret"><HFret>12</HFret></Property>'))));
      expect(n.pitch, 40 + 5 + 12);
      expect(n.harmonicType, HarmonicType.artificial);
    });

    test('small bends stay small, full bends are 2 semitones', () {
      String bend(int v) =>
          '<Property name="Bended"><Enable/></Property>'
          '<Property name="BendOriginValue"><Float>0</Float></Property>'
          '<Property name="BendOriginOffset"><Float>0</Float></Property>'
          '<Property name="BendDestinationValue"><Float>$v</Float></Property>'
          '<Property name="BendDestinationOffset"><Float>100</Float></Property>';
      final quarter = firstNote(buildGpif(bars: oneBar(FxNote(0, 5, extraProps: bend(25)))));
      final full = firstNote(buildGpif(bars: oneBar(FxNote(0, 5, extraProps: bend(100)))));
      expect(quarter.bend!.maximumPitchOffset, closeTo(0.5, 1e-9));
      expect(full.bend!.maximumPitchOffset, closeTo(2.0, 1e-9));
      expect(full.bend!.envelope.last.position, 1.0);
    });

    test('ghost note comes from AntiAccent', () {
      final n = firstNote(buildGpif(bars: oneBar(const FxNote(0, 5, extraChildren: '<AntiAccent>Normal</AntiAccent>'))));
      expect(n.isGhost, isTrue);
    });
  });

  group('1.7 repeats and tempo map', () {
    test('simple repeat is played twice', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="true" end="false" count="1"/>'),
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="false" end="true" count="2"/>'),
        const FxBar([FxBeat('w')]),
      ]);
      expect(GpxParserService.parseGpifXml(xml).playOrder, [0, 1, 0, 1, 2]);
    });

    test('alternate endings', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="true" end="false" count="1"/>'),
        const FxBar([FxBeat('w')], masterExtra: '<AlternateEndings>1</AlternateEndings><Repeat start="false" end="true" count="2"/>'),
        const FxBar([FxBeat('w')], masterExtra: '<AlternateEndings>2</AlternateEndings>'),
        const FxBar([FxBeat('w')]),
      ]);
      expect(GpxParserService.parseGpifXml(xml).playOrder, [0, 1, 0, 2, 3]);
    });

    test('volta bracket: only the first bar is tagged (as in real GP7/8 files)', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="true" end="false" count="0"/>'),
        const FxBar([FxBeat('w')], masterExtra: '<AlternateEndings>1</AlternateEndings>'),
        const FxBar([FxBeat('w')]),
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="false" end="true" count="2"/>'),
        const FxBar([FxBeat('w')], masterExtra: '<AlternateEndings>2</AlternateEndings>'),
        const FxBar([FxBeat('w')]),
      ]);
      // ending 1 = bars 1..3 (pass 1 only), ending 2 = bar 4, then bar 5
      expect(GpxParserService.parseGpifXml(xml).playOrder, [0, 1, 2, 3, 0, 4, 5]);
    });

    test('drum placeholder notes (Midi 0, articulation -1) are not hits', () {
      final xml = buildGpif(
        drums: true,
        bars: [
          const FxBar([
            FxBeat('q', [FxNote(0, 0, extraProps: '<Property name="Midi"><Number>0</Number></Property>', extraChildren: '<InstrumentArticulation>-1</InstrumentArticulation>')]),
            FxBeat('q', [FxNote(0, 0, extraProps: '<Property name="Midi"><Number>38</Number></Property>', extraChildren: '<InstrumentArticulation>0</InstrumentArticulation>')]),
            FxBeat('h'),
          ]),
        ],
      );
      final beats = GpxParserService.parseGpifXml(xml).tracks.first.beats;
      expect(beats[0].isRest, isTrue);
      expect(beats[1].notes.first.pitch, 38);
    });

    test('computePlayOrder is bounded for malformed files', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('w')], masterExtra: '<Repeat start="false" end="true" count="999999"/>'),
      ]);
      final score = GpxParserService.parseGpifXml(xml);
      expect(computePlayOrder(score.masterBars, maxBars: 50).length, lessThanOrEqualTo(50));
    });

    test('tempo automation honours Position inside the bar', () {
      final xml = buildGpif(
        automations:
            '<Automation><Type>Tempo</Type><Bar>0</Bar><Position>0</Position><Value>120 2</Value></Automation>'
            '<Automation><Type>Tempo</Type><Bar>0</Bar><Position>0.5</Position><Value>60 2</Value></Automation>',
        bars: [
          const FxBar([FxBeat('w')]),
          const FxBar([FxBeat('w')]),
        ],
      );
      final bars = GpxParserService.parseGpifXml(xml).masterBars;
      // 2 quarters @120 (1000 ms) + 2 quarters @60 (2000 ms)
      expect(bars[0].durationMs, closeTo(3000, 0.01));
      // the slower tempo is carried into the next bar: 4 quarters @60
      expect(bars[1].durationMs, closeTo(4000, 0.01));
      expect(bars[1].startMs, closeTo(3000, 0.01));
    });
  });

  group('1.8 bar grid', () {
    test('empty bar becomes a bar-long rest, one measure end per bar', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('q', [FxNote(0, 1)]), FxBeat('q'), FxBeat('h')]),
        const FxBar([]), // empty bar
        const FxBar([FxBeat('w', [FxNote(0, 3)])]),
      ]);
      final score = GpxParserService.parseGpifXml(xml);
      final t = score.tracks.first;
      expect(t.measureEndIndices.length, 3);
      final emptyBar = t.beats[t.barStartIndex(1)];
      expect(emptyBar.isRest, isTrue);
      expect(emptyBar.duration, 4.0);
    });

    test('whole rest in 3/4 is 3 quarters', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('w')], time: '3/4'),
      ]);
      final beats = GpxParserService.parseGpifXml(xml).tracks.first.beats;
      expect(beats.fold<double>(0, (a, b) => a + b.duration), 3.0);
    });

    test('short bars are padded to the bar length', () {
      final xml = buildGpif(bars: [
        const FxBar([FxBeat('q', [FxNote(0, 1)])]),
      ]);
      final beats = GpxParserService.parseGpifXml(xml).tracks.first.beats;
      expect(beats.fold<double>(0, (a, b) => a + b.duration), 4.0);
    });
  });

  group('1.9 encoding / format', () {
    test('accented title survives UTF-8 decoding', () {
      final xml = buildGpif(title: 'Café Über', artist: 'Björk', bars: oneBar(const FxNote(0, 0)));
      final score = GpxParserService.parseBytes(zipGpif(xml));
      expect(score.title, 'Café Über');
      expect(score.artist, 'Björk');
    });

    test('.gpx (GP6) gives a readable error', () {
      final bytes = [...'BCFZ'.codeUnits, 0, 0, 0, 0];
      expect(
        () => GpxParserService.parseBytes(bytes),
        throwsA(isA<GpParseException>().having((e) => e.message, 'message', contains('Guitar Pro 6'))),
      );
    });

    test('garbage gives a readable error', () {
      expect(() => GpxParserService.parseBytes(List<int>.filled(64, 7)), throwsA(isA<GpParseException>()));
    });
  });
}