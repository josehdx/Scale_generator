import 'dart:convert';

import 'package:archive/archive.dart';

/// Tiny GPIF writer for tests. One track, notes described by [FxNote].
class FxNote {
  final int string; // GPIF string index, 0 = lowest
  final int fret;
  final String extraProps; // raw <Property> XML
  final String extraChildren; // raw child XML of <Note>
  const FxNote(this.string, this.fret, {this.extraProps = '', this.extraChildren = ''});
}

/// A beat: rhythm id + notes (empty = rest).
class FxBeat {
  final String rhythm;
  final List<FxNote> notes;
  const FxBeat(this.rhythm, [this.notes = const []]);
}

/// A master bar with the beats of the single voice.
class FxBar {
  final String time;
  final String masterExtra; // e.g. <Repeat .../>
  final List<FxBeat> beats;
  const FxBar(this.beats, {this.time = '4/4', this.masterExtra = ''});
}

String buildGpif({
  required List<FxBar> bars,
  List<int> tuning = const [40, 45, 50, 55, 59, 64],
  String automations = '<Automation><Type>Tempo</Type><Linear>false</Linear><Bar>0</Bar><Position>0</Position><Visible>true</Visible><Value>120 2</Value></Automation>',
  String title = 'Test',
  String artist = 'Artist',
  bool drums = false,
}) {
  final noteXml = StringBuffer();
  final beatXml = StringBuffer();
  final voiceXml = StringBuffer();
  final barXml = StringBuffer();
  final masterXml = StringBuffer();
  int noteId = 0, beatId = 0;

  for (int b = 0; b < bars.length; b++) {
    final ids = <int>[];
    for (final beat in bars[b].beats) {
      final nIds = <int>[];
      for (final n in beat.notes) {
        noteXml.write('<Note id="$noteId"><Properties>'
            '<Property name="String"><String>${n.string}</String></Property>'
            '<Property name="Fret"><Fret>${n.fret}</Fret></Property>'
            '${n.extraProps}</Properties>${n.extraChildren}</Note>');
        nIds.add(noteId++);
      }
      beatXml.write('<Beat id="$beatId"><Rhythm ref="${beat.rhythm}"/>'
          '${nIds.isEmpty ? '' : '<Notes>${nIds.join(' ')}</Notes>'}</Beat>');
      ids.add(beatId++);
    }
    voiceXml.write('<Voice id="$b"><Beats>${ids.join(' ')}</Beats></Voice>');
    barXml.write('<Bar id="$b"><Voices>${ids.isEmpty ? '-1' : '$b'} -1 -1 -1</Voices></Bar>');
    masterXml.write('<MasterBar><Time>${bars[b].time}</Time>${bars[b].masterExtra}<Bars>$b</Bars></MasterBar>');
  }

  return '<?xml version="1.0" encoding="utf-8"?><GPIF>'
      '<Score><Title><![CDATA[$title]]></Title><Artist><![CDATA[$artist]]></Artist></Score>'
      '<MasterTrack><Tracks>0</Tracks><Automations>$automations</Automations></MasterTrack>'
      '<Tracks><Track id="0"><Name>Gtr</Name>'
      '${drums ? '<InstrumentSet><Type>drumKit</Type></InstrumentSet>' : ''}'
      '<Staves><Staff id="0"><Properties>'
      '<Property name="Tuning"><Pitches>${tuning.join(' ')}</Pitches></Property>'
      '<Property name="CapoFret"><Fret>0</Fret></Property>'
      '</Properties></Staff></Staves></Track></Tracks>'
      '<MasterBars>$masterXml</MasterBars>'
      '<Bars>$barXml</Bars><Voices>$voiceXml</Voices>'
      '<Beats>$beatXml</Beats><Notes>$noteXml</Notes>'
      '<Rhythms>'
      '<Rhythm id="q"><NoteValue>Quarter</NoteValue></Rhythm>'
      '<Rhythm id="e"><NoteValue>Eighth</NoteValue></Rhythm>'
      '<Rhythm id="h"><NoteValue>Half</NoteValue></Rhythm>'
      '<Rhythm id="w"><NoteValue>Whole</NoteValue></Rhythm>'
      '</Rhythms></GPIF>';
}

/// Zips a GPIF string like a real .gp file.
List<int> zipGpif(String gpif) {
  final bytes = utf8.encode(gpif);
  final archive = Archive()..addFile(ArchiveFile('Content/score.gpif', bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}
