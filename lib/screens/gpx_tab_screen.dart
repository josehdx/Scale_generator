import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/gp_track.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';

class GpxTabScreen extends StatefulWidget {
  const GpxTabScreen({super.key});

  @override
  State<GpxTabScreen> createState() => _GpxTabScreenState();
}

class _GpxTabScreenState extends State<GpxTabScreen> {
  // File / Song metadata
  String? _fileName;
  String _songTitle = '';
  String _artist = '';
  bool _isLoading = false;

  // Track data
  List<GpTrack> _tracks = [];
  int _selectedTrackIndex = 0;

  // Dynamic Rests & Speed
  int _endRests = 0;
  double _speedMultiplier = 1.0;

  List<List<int>> get _parsedSequence {
    if (_tracks.isEmpty) return [];
    final List<List<int>> baseNotes = List<List<int>>.from(_tracks[_selectedTrackIndex].notes);

    if (_endRests > 0) {
      if (_selectionStart != -1 && _selectionEnd != -1) {
        int insertIdx = max(_selectionStart, _selectionEnd) + 1;
        insertIdx = insertIdx.clamp(0, baseNotes.length);
        baseNotes.insertAll(insertIdx, List.generate(_endRests, (_) => [-1, -1]));
      } else {
        baseNotes.addAll(List.generate(_endRests, (_) => [-1, -1]));
      }
    }
    return baseNotes;
  }

  List<double> get _parsedRhythms {
    if (_tracks.isEmpty) return [];
    final List<double> baseRhythms = List<double>.from(_tracks[_selectedTrackIndex].rhythms);

    if (_endRests > 0) {
      if (_selectionStart != -1 && _selectionEnd != -1) {
        int insertIdx = max(_selectionStart, _selectionEnd) + 1;
        insertIdx = insertIdx.clamp(0, baseRhythms.length);
        baseRhythms.insertAll(insertIdx, List.generate(_endRests, (_) => 0.25));
      } else {
        baseRhythms.addAll(List.generate(_endRests, (_) => 0.25));
      }
    }
    return baseRhythms;
  }

  // Playback state
  final MidiPro _midiPro = MidiPro();
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _playbackToken = 0;
  int _currentPlayingIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  // Note selection
  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  // Visualizer layout
  int _notesPerMeasure = 16;
  static const int _measuresPerLine = 2;
  int _tempo = 120;

  final Map<int, int> _standardTuning = {
    1: 64, // e4
    2: 59, // B3
    3: 55, // G3
    4: 50, // D3
    5: 45, // A2
    6: 40, // E2
  };

  @override
  void initState() {
    super.initState();
    _loadSoundFont();
  }

  @override
  void dispose() {
    _stopPlayback(resetPosition: true);
    super.dispose();
  }

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(
          sf2Path: 'assets/guitar.sf2', instrumentIndex: 27);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint('GP Viewer MIDI setup error: $e');
    }
  }

  Future<void> _pickAndParseGp() async {
    try {
      _stopPlayback(resetPosition: true);

      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      if (!result.files.single.name.toLowerCase().endsWith('.gp')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Invalid file type. Please select a Guitar Pro 7/8 (.gp) file.'),
            backgroundColor: Colors.redAccent,
          ));
        }
        return;
      }

      setState(() {
        _isLoading = true;
        _fileName = result.files.single.name;
        _songTitle = '';
        _artist = '';
        _tracks = [];
        _selectedTrackIndex = 0;
        _currentPlayingIndex = -1;
        _selectionStart = -1;
        _selectionEnd = -1;
        _tapAnchorIndex = null;
      });

      final List<int> bytes;
      try {
        if (result.files.single.path != null) {
          bytes = await File(result.files.single.path!).readAsBytes();
        } else if (result.files.single.bytes != null) {
          bytes = result.files.single.bytes!;
        } else {
          throw Exception('Could not read file data.');
        }
      } catch (e) {
        throw Exception('Failed to read file from storage: $e');
      }

      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } on FormatException {
        throw Exception(
            'Invalid GP format. Ensure you are using a Guitar Pro 7/8 (.gp) '
            'file, not an older .gpx or .gp5 file.');
      } catch (e) {
        throw Exception('Could not unzip file: $e');
      }

      ArchiveFile? gpifFile;
      for (final file in archive) {
        final String baseName = file.name.split('/').last.toLowerCase();
        if (baseName == 'score.gpif' || baseName == 'main.xml') {
          gpifFile = file;
          break;
        }
      }

      if (gpifFile == null) {
        throw Exception(
            'Invalid .gp file: Could not find score.gpif or main.xml inside the archive.');
      }

      final String gpifContent =
          String.fromCharCodes(gpifFile.content as List<int>);
      final XmlDocument document = XmlDocument.parse(gpifContent);

      final String title =
          document.findAllElements('Title').firstOrNull?.innerText ??
              'Unknown Title';
      final String artist =
          document.findAllElements('Artist').firstOrNull?.innerText ??
              'Unknown Artist';

      int notesPerMeasure = 16;
      final String? firstTime = document
          .findAllElements('MasterBar')
          .firstOrNull
          ?.findElements('Time')
          .firstOrNull
          ?.innerText;

      if (firstTime != null) {
        final List<String> parts = firstTime.split('/');
        if (parts.length == 2) {
          final int? num = int.tryParse(parts[0]);
          if (num != null && num > 0) notesPerMeasure = num * 4;
        }
      }

      int parsedTempo = 120;
      final tempoElem = document.findAllElements('Automation').where(
        (e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo'
      ).firstOrNull?.findElements('Value').firstOrNull?.innerText;
      
      if (tempoElem != null) {
        final parts = tempoElem.split(' ');
        if (parts.isNotEmpty) {
          parsedTempo = int.tryParse(parts[0]) ?? 120;
        }
      }

      final List<GpTrack> parsedTracks = _parseTracksFromDocument(document);

      setState(() {
        _songTitle = title;
        _artist = artist;
        _tracks = parsedTracks;
        _selectedTrackIndex = 0;
        _notesPerMeasure = notesPerMeasure;
        _tempo = parsedTempo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error parsing GP file: $e')),
        );
      }
    }
  }

  List<GpTrack> _parseTracksFromDocument(XmlDocument document) {
    final List<XmlElement> trackElements =
        document.findAllElements('Track').toList();
    final List<String> trackNames = trackElements
        .map((t) =>
            t.findElements('Name').firstOrNull?.innerText.trim() ?? 'Track')
        .toList();

    if (trackNames.isEmpty) trackNames.add('All Tracks');

    final Map<String, double> rhythmMap = {};
    final Map<String, bool> rhythmIs8th = {};
    final rhythmsElement = document.findAllElements('Rhythms').firstOrNull;

    if (rhythmsElement != null) {
      for (final rhythm in rhythmsElement.findAllElements('Rhythm')) {
        final id = rhythm.getAttribute('id') ?? '';
        final noteVal = rhythm.findElements('NoteValue').firstOrNull?.innerText ?? 'Quarter';
        
        double val = 1.0;
        switch (noteVal) {
          case 'Whole': val = 4.0; break;
          case 'Half': val = 2.0; break;
          case 'Quarter': val = 1.0; break;
          case '8th':
          case 'Eighth': val = 0.5; break;
          case '16th': val = 0.25; break;
          case '32nd': val = 0.125; break;
          case '64th': val = 0.0625; break;
          default: val = 1.0;
        }

        final dot = rhythm.findElements('AugmentationDot').firstOrNull?.getAttribute('count');
        final bool hasDot = dot != null && dot.isNotEmpty;
        if (dot == '1') val *= 1.5;
        if (dot == '2') val *= 1.75;

        final tuplet = rhythm.findElements('PrimaryTuplet').firstOrNull;
        final bool hasTuplet = tuplet != null;
        if (tuplet != null) {
          final numStr = tuplet.getAttribute('num') ?? '3';
          final denStr = tuplet.getAttribute('den') ?? '2';
          val *= (int.parse(denStr) / int.parse(numStr));
        }

        rhythmMap[id] = val;
        rhythmIs8th[id] = (noteVal == '8th' || noteVal == 'Eighth') && !hasDot && !hasTuplet;
      }
    }

    final Map<String, List<int>> noteIdToNote = {};
    for (final XmlElement note in document.findAllElements('Note')) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final XmlElement? strNode = note.findAllElements('String').firstOrNull ?? note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode = note.findAllElements('Fret').firstOrNull ?? note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;

      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;

      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        noteIdToNote[id] = [displayString, fretNum];
      }
    }

    final Map<String, dynamic> beatIdToBeat = {};
    for (final XmlElement beat in document.findAllElements('Beat')) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      
      final String rhythmRef = beat.findElements('Rhythm').firstOrNull?.getAttribute('ref') ?? '';
      final double beatDuration = rhythmMap[rhythmRef] ?? 1.0;
      final bool is8th = rhythmIs8th[rhythmRef] ?? false;
      
      final String notesText = beat.findElements('Notes').firstOrNull?.innerText ?? '';
      final List<List<int>> notes = notesText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty && noteIdToNote.containsKey(s))
          .map((nid) => noteIdToNote[nid]!)
          .toList();
          
      if (notes.isEmpty) {
        notes.add([-1, -1]); // Rest
      }
      
      beatIdToBeat[id] = {'notes': notes, 'rhythm': beatDuration, 'is8th': is8th};
    }

    final Map<String, List<dynamic>> voiceIdToBeats = {};
    for (final XmlElement voice in document.findAllElements('Voice')) {
      final String id = voice.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final String beatsText = voice.findElements('Beats').firstOrNull?.innerText ?? '';
      final List<dynamic> beats = [];
      for (final String bid in beatsText.trim().split(' ').where((s) => s.isNotEmpty)) {
        if (beatIdToBeat.containsKey(bid)) {
          beats.add(beatIdToBeat[bid]);
        }
      }
      voiceIdToBeats[id] = beats;
    }

    final Map<String, List<dynamic>> barIdToBeats = {};
    final Map<String, bool> barShuffleMap = {};
    for (final XmlElement bar in document.findAllElements('Bar')) {
      final String id = bar.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final String tf = bar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ?? '';
      final String sh = bar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      if (tf.contains('8th') || tf.contains('triplet') || tf.contains('shuffle') || sh.isNotEmpty) {
        barShuffleMap[id] = true;
      }

      final String voicesText = bar.findElements('Voices').firstOrNull?.innerText ?? '';
      final List<String> voiceIds = voicesText.trim().split(' ').where((s) => s.isNotEmpty).toList();
      barIdToBeats[id] = voiceIds.isNotEmpty ? (voiceIdToBeats[voiceIds[0]] ?? []) : [];
    }

    final List<List<List<int>>> trackNotes = List.generate(trackNames.length, (_) => []);
    final List<List<double>> trackRhythms = List.generate(trackNames.length, (_) => []);
    
    for (final XmlElement masterBar in document.findAllElements('MasterBar')) {
      final String tf = masterBar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ?? '';
      final String sh = masterBar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      final bool masterBarShuffle = tf.contains('8th') || tf.contains('triplet') || tf.contains('shuffle') || sh.isNotEmpty;

      final String barsText = masterBar.findElements('Bars').firstOrNull?.innerText ?? '';
      final List<String> barIds = barsText.trim().split(' ').where((s) => s.isNotEmpty).toList();

      for (int i = 0; i < barIds.length && i < trackNotes.length; i++) {
        final String barId = barIds[i];
        final bool isShuffle = masterBarShuffle || (barShuffleMap[barId] == true);
        final List<dynamic> barBeats = barIdToBeats[barId] ?? [];

        int eighthIndexInBar = 0;
        for (final beat in barBeats) {
          final List<List<int>> beatNotes = beat['notes'];
          double rhythm = beat['rhythm'];
          final bool is8th = beat['is8th'] == true;

          if (isShuffle && is8th) {
            if (eighthIndexInBar % 2 == 0) {
              rhythm = 0.5 * (4.0 / 3.0);
            } else {
              rhythm = 0.5 * (2.0 / 3.0);
            }
            eighthIndexInBar++;
          } else if (!is8th) {
            eighthIndexInBar += (rhythm / 0.5).round();
          }

          for (int n = 0; n < beatNotes.length; n++) {
            trackNotes[i].add(beatNotes[n]);
            trackRhythms[i].add(n == beatNotes.length - 1 ? rhythm : 0.0);
          }
        }
      }
    }

    if (trackNotes.any((t) => t.isNotEmpty)) {
      return [
        for (int i = 0; i < trackNames.length; i++)
          GpTrack(id: '$i', name: trackNames[i], notes: trackNotes[i], rhythms: trackRhythms[i]),
      ];
    }

    final List<List<int>> flatNotes = [];
    final List<double> flatRhythms = [];
    for (final XmlElement note in document.findAllElements('Note')) {
      final XmlElement? strNode = note.findAllElements('String').firstOrNull ?? note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode = note.findAllElements('Fret').firstOrNull ?? note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;

      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;

      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        flatNotes.add([displayString, fretNum]);
        flatRhythms.add(0.25);
      }
    }

    return [GpTrack(id: '0', name: 'All Tracks', notes: flatNotes, rhythms: flatRhythms)];
  }

  void _selectTrack(int index) {
    if (index == _selectedTrackIndex) return;
    _stopPlayback(resetPosition: true);
    setState(() {
      _selectedTrackIndex = index;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  void _onPlayPause() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  void _rewind() {
    final bool wasPlaying = _isPlaying;
    _stopPlayback(resetPosition: false);
    setState(() {
      _currentPlayingIndex = 0;
      _isPaused = false;
    });
    if (wasPlaying) {
      _startPlayback();
    }
  }

  // FIX: Background track independent playback loop
  Future<void> _playBackgroundTrack(int tIdx, int token, int startIdx, int endIdx) async {
    final track = _tracks[tIdx];
    final seq = track.notes;
    final rhythms = track.rhythms;
    
    if (seq.isEmpty) return;

    int i = startIdx.clamp(0, seq.length - 1);
    final int actualEnd = endIdx.clamp(0, seq.length - 1);
    final List<int> activePitches = [];

    while (i <= actualEnd) {
      if (!mounted || _playbackToken != token || !_isPlaying) return;
      
      if (i < seq.length) {
        final note = seq[i];
        final double rhythmMultiplier = (i < rhythms.length) ? rhythms[i] : 0.25;
        final double effectiveTempo = _tempo * _speedMultiplier;
        final int msDelay = (rhythmMultiplier * (60000 / effectiveTempo)).round();

        if (note[0] != -1) {
          final int pitch = (_standardTuning[note[0]] ?? 40) + note[1];
          _midiPro.playMidiNote(midi: pitch, velocity: 80); // Lower velocity for backing tracks
          activePitches.add(pitch);
        }

        if (msDelay > 0) {
          await Future.delayed(Duration(milliseconds: msDelay));
          if (_playbackToken != token) return;
          for (var p in activePitches) _midiPro.stopMidiNote(midi: p);
          activePitches.clear();
        }
      }
      i++;
    }
  }

  Future<void> _startPlayback() async {
    final List<List<int>> seq = _parsedSequence;
    final List<double> rhythms = _parsedRhythms;

    if (!_isMidiReady || seq.isEmpty) return;

    final bool isSingleNoteSelected =
        _selectionStart != -1 && _selectionStart == _selectionEnd;
    final bool isRangeSelected =
        _selectionStart != -1 && _selectionEnd != -1 && _selectionStart != _selectionEnd;

    final int selMin = isRangeSelected ? min(_selectionStart, _selectionEnd) : _selectionStart;
    final int selMax = isRangeSelected ? max(_selectionStart, _selectionEnd) : _selectionEnd;

    final int startIdx;
    if (_isPaused &&
        _currentPlayingIndex >= 0 &&
        _currentPlayingIndex < seq.length) {
      startIdx = _currentPlayingIndex; 
    } else if (isSingleNoteSelected) {
      startIdx = _selectionStart.clamp(0, seq.length - 1);
    } else if (isRangeSelected) {
      startIdx = selMin.clamp(0, seq.length - 1);
    } else if (_loopMode == LoopMode.selection && _selectionStart != -1) {
      startIdx = _selectionStart.clamp(0, seq.length - 1);
    } else {
      startIdx = 0;
    }

    _isPaused = false;
    _playbackToken++;
    final int token = _playbackToken;

    setState(() {
      _isPlaying = true;
      _currentPlayingIndex = startIdx;
    });

    _midiPro.playMidiNote(midi: 12, velocity: 1);
    await Future.delayed(const Duration(milliseconds: 150));
    _midiPro.stopMidiNote(midi: 12);

    final int endIdx = isRangeSelected
        ? selMax.clamp(0, seq.length - 1)
        : ((_loopMode == LoopMode.selection && _selectionEnd != -1)
            ? _selectionEnd.clamp(0, seq.length - 1)
            : seq.length - 1);

    // FIX: Spawn independent timing loops for all unselected backing tracks
    for (int tIdx = 0; tIdx < _tracks.length; tIdx++) {
      if (tIdx != _selectedTrackIndex) {
        _playBackgroundTrack(tIdx, token, startIdx, endIdx);
      }
    }

    int i = startIdx;
    final List<int> activePitches = [];

    while (true) {
      if (!mounted || _playbackToken != token || !_isPlaying) return;

      final List<int> note = seq[i];
      final double rhythmMultiplier = (i < rhythms.length) ? rhythms[i] : 0.25;
      final double effectiveTempo = _tempo * _speedMultiplier;
      final int msDelay = (rhythmMultiplier * (60000 / effectiveTempo)).round();

      if (mounted) setState(() => _currentPlayingIndex = i);

      if (note[0] != -1) {
        final int pitch = (_standardTuning[note[0]] ?? 40) + note[1];
        _midiPro.playMidiNote(midi: pitch, velocity: 110);
        activePitches.add(pitch);
      }

      if (msDelay > 0) {
        await Future.delayed(Duration(milliseconds: msDelay));
        if (_playbackToken != token) return;
        for (var p in activePitches) {
          _midiPro.stopMidiNote(midi: p);
        }
        activePitches.clear();
      }

      i++;

      if (i > endIdx) {
        switch (_loopMode) {
          case LoopMode.off:
            if (mounted && _playbackToken == token) {
              setState(() {
                _isPlaying = false;
                _currentPlayingIndex = -1;
              });
            }
            return;
          case LoopMode.all:
            i = isRangeSelected ? selMin : 0;
            break;
          case LoopMode.selection:
            i = isRangeSelected
                ? selMin
                : ((_selectionStart != -1) ? _selectionStart : 0);
            break;
        }

        // IF LOOPING: Restart background tracks at the same time
        if (_loopMode != LoopMode.off) {
           for (int tIdx = 0; tIdx < _tracks.length; tIdx++) {
             if (tIdx != _selectedTrackIndex) {
               _playBackgroundTrack(tIdx, token, i, endIdx);
             }
           }
        }
      }
    }
  }

  void _pausePlayback() {
    _playbackToken++;
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _stopPlayback({bool resetPosition = false}) {
    _playbackToken++;
    _isPaused = false;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        if (resetPosition) _currentPlayingIndex = -1;
      });
    }
    _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: 27);
  }

  void _cycleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.all;
          break;
        case LoopMode.all:
          _loopMode = LoopMode.selection;
          break;
        case LoopMode.selection:
          _loopMode = LoopMode.off;
          break;
      }
    });
  }

  void _onBeatTapped(int index) {
    setState(() {
      _isPaused = false;
      if (_tapAnchorIndex == null) {
        _tapAnchorIndex = index;
        _selectionStart = index;
        _selectionEnd = index;
      } else if (_tapAnchorIndex == index) {
        _tapAnchorIndex = null;
        _selectionStart = -1;
        _selectionEnd = -1;
      } else {
        final int anchor = _tapAnchorIndex!;
        _selectionStart = index < anchor ? index : anchor;
        _selectionEnd = index < anchor ? anchor : index;
        _tapAnchorIndex = null;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<List<int>> seq = _parsedSequence;
    final bool hasFile = _fileName != null && !_isLoading;
    final bool hasSelection = _selectionStart != -1 && _selectionEnd != -1;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickAndParseGp,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open .gp File'),
                ),
                if (hasFile) ...[
                  const SizedBox(height: 6),
                  Text(
                    _songTitle.isNotEmpty ? '$_songTitle - $_artist' : _artist,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _fileName!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_isLoading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (!hasFile)
            const Expanded(
              child: Center(
                child: Text(
                  'No GP file loaded yet.\nTap "Open .gp File" to start.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          else ...[
            if (_tracks.length > 1) ...[
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _tracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final bool selected = _selectedTrackIndex == i;
                    return ChoiceChip(
                      label: Text(
                        _tracks[i].name,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? Colors.white
                              : Colors.grey.shade300,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => _selectTrack(i),
                      selectedColor: Colors.blueAccent,
                      backgroundColor: Colors.grey.shade800,
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: seq.isEmpty
                  ? Center(
                      child: Text(
                        _tracks.isNotEmpty
                            ? 'No notes found for "${_tracks[_selectedTrackIndex].name}".'
                            : 'No tracks found in this file.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : InteractiveTabDisplay(
                      sequence: seq,
                      notesPerMeasure: _notesPerMeasure,
                      measuresPerLine: _measuresPerLine,
                      currentPlayingIndex: _currentPlayingIndex,
                      selectionStart: _selectionStart,
                      selectionEnd: _selectionEnd,
                      tuningStr: 'Standard E',
                      onBeatTapped: _onBeatTapped,
                    ),
            ),
            Container(
              color: const Color(0xFF1A1A1A),
              child: PlaybackControlBar(
                isPlaying: _isPlaying,
                isMidiReady: _isMidiReady,
                isLooping: _loopMode != LoopMode.off,
                hasSequence: seq.isNotEmpty,
                hasSelection: hasSelection,
                selectionStart: _selectionStart,
                selectionEnd: _selectionEnd,
                onPlay: _onPlayPause,
                onStop: () => _stopPlayback(resetPosition: true),
                onToggleLoop: _cycleLoopMode,
                onSave: () {}, 
                onCopy: () {}, 
                onClearSelection: _clearSelection,
                isPaused: _isPaused,
                gpLoopMode: _loopMode,
                onCycleLoopMode: _cycleLoopMode,
                onRewind: _rewind,
                speedMultiplier: _speedMultiplier,
                onSpeedChanged: (s) =>
                    setState(() => _speedMultiplier = s.clamp(0.1, 2.0)),
                endRests: _endRests,
                onEndRestsChanged: (v) => setState(() => _endRests = v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}