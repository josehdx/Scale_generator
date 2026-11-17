import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/gp_note.dart';
import 'package:tab_generator/services/gpx_parser_service.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.
//
// Expected values were computed by an INDEPENDENT Python implementation that
// reads the raw GPIF of the six audit files (tuning + fret pitch, harmonic
// intervals, grace-note and drum-placeholder filtering, volta brackets,
// tempo map with in-bar positions). The Dart parser must agree.

class _T {
  final String name;
  final bool perc;
  final int strings, notes, minPitch, maxPitch, tieDest, hopoDest, slides, harmonics, bends;
  const _T(this.name, this.perc, this.strings, this.notes, this.minPitch, this.maxPitch, this.tieDest, this.hopoDest, this.slides, this.harmonics, this.bends);
}

class _F {
  final int bars, playOrderLength, totalMs;
  final List<_T> tracks;
  const _F(this.bars, this.playOrderLength, this.totalMs, this.tracks);
}

const Map<String, _F> expected = {
  'Fleetwood_Mac_-_Black_Magic_Woman.gp': _F(67, 67, 134000, [
    _T('Lead Guitar', false, 6, 195, 50, 81, 4, 4, 4, 0, 17),
    _T('Rhythm Guitar', false, 6, 1504, 43, 74, 10, 0, 3, 0, 3),
  ]),
  'Megadeth_-_Tornado_Of_Souls.gp': _F(223, 260, 337297, [
    _T('Dave', false, 6, 2206, 40, 74, 214, 94, 0, 44, 0),
    _T('Marty', false, 6, 1953, 40, 88, 165, 169, 9, 44, 24),
    _T('Voices', false, 6, 271, 61, 69, 52, 0, 0, 0, 0),
    _T('David', false, 4, 1332, 28, 57, 117, 12, 0, 0, 0),
    _T('Nick', true, 6, 1946, 35, 53, 0, 0, 0, 0, 0),
  ]),
  'Rata_Blanca_-_La_Leyenda_Del_Hada_Y_El_Mago__ver_3_.gp': _F(203, 203, 324800, [
    _T('Gtr 1', false, 6, 1918, 40, 86, 35, 125, 4, 0, 37),
    _T('Gtr 2', false, 6, 1904, 40, 60, 22, 0, 0, 0, 0),
    _T('Bajo', false, 4, 2024, 28, 48, 215, 0, 0, 0, 0),
    _T('Teclado', false, 6, 592, 52, 84, 127, 0, 0, 0, 0),
    _T('Voz', false, 6, 408, 59, 76, 19, 0, 0, 0, 0),
    _T('Bateria', true, 6, 2349, 36, 57, 0, 0, 0, 0, 0),
  ]),
  'Steve_Vai_-_Tender_Surrender.gp': _F(81, 81, 289091, [
    _T('Clean tone', false, 6, 729, 40, 81, 74, 18, 154, 11, 22),
    _T('Distorsion', false, 6, 724, 40, 86, 56, 277, 45, 1, 78),
    _T('Bass', false, 4, 149, 28, 40, 7, 0, 0, 0, 0),
    _T('Distorsion 2', false, 7, 145, 35, 88, 58, 0, 0, 1, 54),
    _T('Batterie', true, 6, 947, 35, 57, 0, 0, 0, 0, 0),
  ]),
  'The_Doors_-_Roadhouse_Blues.gp': _F(121, 121, 244034, [
    _T('Electric Guitar', false, 6, 1257, 40, 79, 100, 30, 19, 0, 32),
  ]),
  'The_Guess_Who_-_American_Woman.gp': _F(92, 123, 327025, [
    _T('Intro Guitar', false, 6, 220, 43, 74, 0, 6, 0, 4, 0),
    _T('Rhythm Guitar 1', false, 6, 868, 47, 68, 0, 0, 16, 0, 37),
    _T('Rhythm Guitar 2', false, 6, 3082, 40, 68, 4, 0, 58, 0, 0),
    _T('Solo/Fills', false, 6, 257, 64, 83, 85, 12, 7, 0, 77),
    _T('Bass', false, 4, 699, 33, 43, 1, 0, 89, 0, 0),
  ]),
};

void main() {
  for (final entry in expected.entries) {
    final file = File('test/fixtures/${entry.key}');
    group(entry.key, () {
      if (!file.existsSync()) {
        test('fixture present', () {}, skip: 'missing ${file.path}');
        return;
      }
      final score = GpxParserService.parseBytes(file.readAsBytesSync(), fileName: entry.key);
      final exp = entry.value;

      test('structure', () {
        expect(score.masterBars.length, exp.bars);
        expect(score.playOrder.length, exp.playOrderLength);
        final total = score.playOrder.fold<double>(0, (a, b) => a + score.masterBars[b].durationMs);
        expect(total, closeTo(exp.totalMs, 5));
        expect(score.tracks.length, exp.tracks.length);
      });

      for (int i = 0; i < exp.tracks.length; i++) {
        final e = exp.tracks[i];
        test('track ${e.name}', () {
          final t = score.tracks[i];
          final notes = t.allNotes.where((n) => !n.isRest).toList();
          expect(t.name, e.name);
          expect(t.isPercussion, e.perc);
          expect(t.stringCount, e.strings);
          expect(notes.length, e.notes);
          expect(notes.map((n) => n.pitch).reduce((a, b) => a < b ? a : b), e.minPitch);
          expect(notes.map((n) => n.pitch).reduce((a, b) => a > b ? a : b), e.maxPitch);
          expect(notes.where((n) => n.isTie).length, e.tieDest);
          expect(notes.where((n) => n.isLegato).length, e.hopoDest);
          expect(notes.where((n) => n.slideType != SlideType.none).length, e.slides);
          expect(notes.where((n) => n.harmonicType != HarmonicType.none).length, e.harmonics);
          expect(notes.where((n) => n.bend != null).length, e.bends);
          // display lines are always inside the track's string count
          for (final n in notes) {
            expect(n.stringNum, inInclusiveRange(1, t.stringCount));
          }
        });
      }
    });
  }
}
