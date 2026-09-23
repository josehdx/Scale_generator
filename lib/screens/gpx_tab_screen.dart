import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import '../models/gp_track.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';

// ─── Screen widget ────────────────────────────────────────────────────────────

class GpxTabScreen extends StatefulWidget {
  const GpxTabScreen({super.key});

  @override
  State<GpxTabScreen> createState() => _GpxTabScreenState();
}

class _GpxTabScreenState extends State<GpxTabScreen> {
  // ── File / Song metadata ──────────────────────────────────────────────────
  String? _fileName;
  String _songTitle = '';
  String _artist = '';
  bool _isLoading = false;

  // ── Track data ────────────────────────────────────────────────────────────
  List<GpTrack> _tracks = [];
  int _selectedTrackIndex = 0;

  /// Active note sequence derived from the selected track.
  List<List<int>> get _parsedSequence =>
      _tracks.isNotEmpty ? _tracks[_selectedTrackIndex].notes : [];

  // ── Playback state ────────────────────────────────────────────────────────
  final MidiPro _midiPro = MidiPro();
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _playbackToken = 0;
  int _currentPlayingIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  // ── Note selection ────────────────────────────────────────────────────────
  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  // ── Visualizer layout ─────────────────────────────────────────────────────
  /// Notes per measure calculated from the time signature (default: 4/4 × 4 = 16 sixteenth-notes).
  int _notesPerMeasure = 16;
  static const int _measuresPerLine = 2;

  /// Standard guitar tuning: string number (1=high-e) → open-string MIDI pitch.
  final Map<int, int> _standardTuning = {
    1: 64, // e4
    2: 59, // B3
    3: 55, // G3
    4: 50, // D3
    5: 45, // A2
    6: 40, // E2
  };

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

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

  // ─── MIDI ──────────────────────────────────────────────────────────────────

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(
          sf2Path: 'assets/guitar.sf2', instrumentIndex: 27);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint('GP Viewer — MIDI setup error: $e');
    }
  }

  // ─── FILE PICKING & PARSING ────────────────────────────────────────────────

  Future<void> _pickAndParseGp() async {
    try {
      _stopPlayback(resetPosition: true);

      // ── Pick file ──
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      // ── Validate extension ──
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

      // ── Read bytes (prefer path to avoid Android memory truncation) ──
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

      // ── Unzip ──
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

      // ── Locate GPIF entry (handles subfolder layouts) ──
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

      // ── Parse XML ──
      final String gpifContent =
          String.fromCharCodes(gpifFile.content as List<int>);
      final XmlDocument document = XmlDocument.parse(gpifContent);

      final String title =
          document.findAllElements('Title').firstOrNull?.innerText ??
              'Unknown Title';
      final String artist =
          document.findAllElements('Artist').firstOrNull?.innerText ??
              'Unknown Artist';

      // Parse time signature → notesPerMeasure (assuming 16th-note granularity)
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

      final List<GpTrack> parsedTracks = _parseTracksFromDocument(document);

      setState(() {
        _songTitle = title;
        _artist = artist;
        _tracks = parsedTracks;
        _selectedTrackIndex = 0;
        _notesPerMeasure = notesPerMeasure;
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

  // ─── GPIF MULTI-TRACK PARSER ───────────────────────────────────────────────

  /// Parses [GpTrack] list from a GPIF [XmlDocument].
  ///
  /// **Strategy (structured walk):**
  /// 1. Collect `<Track>` elements → names.
  /// 2. Build `noteId → [string, fret]` map from `<Note>` elements.
  /// 3. Build `beatId → notes` map via `<Beat>/<Notes>`.
  /// 4. Build `voiceId → notes` map via `<Voice>/<Beats>` (primary voice only).
  /// 5. Build `barId → notes` map via `<Bar>/<Voices>`.
  /// 6. Assemble per-track note lists from `<MasterBar>/<Bars>` index (one bar ID per track).
  ///
  /// **Fallback:** if the structured walk produces no notes for any track
  /// (schema variant), performs a flat `<Note>` scan under a single "All Tracks" pseudo-track.
  List<GpTrack> _parseTracksFromDocument(XmlDocument document) {
    // ── 1. Track names ──
    final List<XmlElement> trackElements =
        document.findAllElements('Track').toList();
    final List<String> trackNames = trackElements
        .map((t) =>
            t.findElements('Name').firstOrNull?.innerText.trim() ?? 'Track')
        .toList();
    if (trackNames.isEmpty) trackNames.add('All Tracks');

    // ── 2. noteId → [displayString (1-indexed), fretNum] ──
    final Map<String, List<int>> noteIdToNote = {};
    for (final XmlElement note in document.findAllElements('Note')) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final XmlElement? strNode =
          note.findAllElements('String').firstOrNull ??
              note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode =
          note.findAllElements('Fret').firstOrNull ??
              note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;

      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;

      // GPIF string is 0-indexed; display is 1-indexed (1 = high-e)
      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        noteIdToNote[id] = [displayString, fretNum];
      }
    }

    // ── 3. beatId → notes ──
    final Map<String, List<List<int>>> beatIdToNotes = {};
    for (final XmlElement beat in document.findAllElements('Beat')) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String notesText =
          beat.findElements('Notes').firstOrNull?.innerText ?? '';
      beatIdToNotes[id] = notesText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty && noteIdToNote.containsKey(s))
          .map((nid) => noteIdToNote[nid]!)
          .toList();
    }

    // ── 4. voiceId → notes (primary voice) ──
    final Map<String, List<List<int>>> voiceIdToNotes = {};
    for (final XmlElement voice in document.findAllElements('Voice')) {
      final String id = voice.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String beatsText =
          voice.findElements('Beats').firstOrNull?.innerText ?? '';
      final List<List<int>> notes = [];
      for (final String bid
          in beatsText.trim().split(' ').where((s) => s.isNotEmpty)) {
        notes.addAll(beatIdToNotes[bid] ?? []);
      }
      voiceIdToNotes[id] = notes;
    }

    // ── 5. barId → notes (voice 0 only) ──
    final Map<String, List<List<int>>> barIdToNotes = {};
    for (final XmlElement bar in document.findAllElements('Bar')) {
      final String id = bar.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String voicesText =
          bar.findElements('Voices').firstOrNull?.innerText ?? '';
      final List<String> voiceIds = voicesText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();
      barIdToNotes[id] =
          voiceIds.isNotEmpty ? (voiceIdToNotes[voiceIds[0]] ?? []) : [];
    }

    // ── 6. Assemble per-track note lists from MasterBar.Bars index ──
    final List<List<List<int>>> trackNotes =
        List.generate(trackNames.length, (_) => []);
    for (final XmlElement masterBar
        in document.findAllElements('MasterBar')) {
      final String barsText =
          masterBar.findElements('Bars').firstOrNull?.innerText ?? '';
      final List<String> barIds = barsText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();
      for (int i = 0; i < barIds.length && i < trackNotes.length; i++) {
        trackNotes[i].addAll(barIdToNotes[barIds[i]] ?? []);
      }
    }

    // Use structured result if at least one track has notes
    if (trackNotes.any((t) => t.isNotEmpty)) {
      return [
        for (int i = 0; i < trackNames.length; i++)
          GpTrack(id: '$i', name: trackNames[i], notes: trackNotes[i]),
      ];
    }

    // ── Fallback: flat Note scan → single pseudo-track ──
    final List<List<int>> flatNotes = [];
    for (final XmlElement note in document.findAllElements('Note')) {
      final XmlElement? strNode =
          note.findAllElements('String').firstOrNull ??
              note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode =
          note.findAllElements('Fret').firstOrNull ??
              note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;
      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;
      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        flatNotes.add([displayString, fretNum]);
      }
    }
    return [GpTrack(id: '0', name: 'All Tracks', notes: flatNotes)];
  }

  // ─── TRACK SWITCHING ───────────────────────────────────────────────────────

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

  // ─── PLAYBACK ENGINE ───────────────────────────────────────────────────────

  /// Toggles between Play and Pause. Wires up the PlaybackControlBar [onPlay] callback.
  void _onPlayPause() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  /// Starts or resumes playback from the appropriate position.
  Future<void> _startPlayback() async {
    final List<List<int>> seq = _parsedSequence;
    if (!_isMidiReady || seq.isEmpty) return;

    // Determine start index
    final int startIdx;
    if (_isPaused &&
        _currentPlayingIndex >= 0 &&
        _currentPlayingIndex < seq.length) {
      startIdx = _currentPlayingIndex; // resume from paused position
    } else if (_loopMode == LoopMode.selection && _selectionStart != -1) {
      startIdx = _selectionStart;
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

    // Wake up MIDI engine (silent warm-up note)
    _midiPro.playMidiNote(midi: 12, velocity: 1);
    await Future.delayed(const Duration(milliseconds: 150));
    _midiPro.stopMidiNote(midi: 12);

    int i = startIdx;

    while (true) {
      if (!mounted || _playbackToken != token || !_isPlaying) return;

      final List<int> note = seq[i];
      final int stringNum = note[0];
      final int fretNum = note[1];
      final int pitch = (_standardTuning[stringNum] ?? 40) + fretNum;

      // Highlight active note in visualizer
      if (mounted) setState(() => _currentPlayingIndex = i);

      _midiPro.playMidiNote(midi: pitch, velocity: 100);
      await Future.delayed(const Duration(milliseconds: 250));
      if (_playbackToken != token) return;
      _midiPro.stopMidiNote(midi: pitch);

      i++;

      // Determine end bound for this loop pass
      final int endIdx =
          (_loopMode == LoopMode.selection && _selectionEnd != -1)
              ? _selectionEnd
              : seq.length - 1;

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
            i = 0;
          case LoopMode.selection:
            i = (_selectionStart != -1) ? _selectionStart : 0;
        }
      }
    }
  }

  /// Pauses playback — preserves [_currentPlayingIndex] for resume.
  void _pausePlayback() {
    _playbackToken++;
    setState(() {
      _isPlaying = false;
      _isPaused = true;
      // _currentPlayingIndex intentionally not reset
    });
  }

  /// Stops playback. When [resetPosition] is true, clears the active note highlight.
  void _stopPlayback({bool resetPosition = false}) {
    _playbackToken++;
    _isPaused = false;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        if (resetPosition) _currentPlayingIndex = -1;
      });
    }
    // Hard-reset MIDI to silence any hanging notes
    _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: 27);
  }

  /// Cycles the loop mode: off → all → selection → off.
  void _cycleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.all;
        case LoopMode.all:
          _loopMode = LoopMode.selection;
        case LoopMode.selection:
          _loopMode = LoopMode.off;
      }
    });
  }

  // ─── NOTE SELECTION ────────────────────────────────────────────────────────

  /// Handles a tap on [index] in the tab visualizer.
  ///
  /// * First tap → sets anchor + single-note selection.
  /// * Second tap on same note → clears selection.
  /// * Second tap on different note → completes range selection.
  void _onBeatTapped(int index) {
    setState(() {
      if (_tapAnchorIndex == null) {
        _tapAnchorIndex = index;
        _selectionStart = index;
        _selectionEnd = index;
      } else if (_tapAnchorIndex == index) {
        // Re-tapping the anchor clears selection
        _tapAnchorIndex = null;
        _selectionStart = -1;
        _selectionEnd = -1;
      } else {
        // Complete range between anchor and this note
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

  // ─── BUILD ─────────────────────────────────────────────────────────────────

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
          // ── Header bar ────────────────────────────────────────────────────
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
                    _songTitle.isNotEmpty ? '$_songTitle  •  $_artist' : _artist,
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

          // ── Body ──────────────────────────────────────────────────────────
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
            // ── Track switcher ────────────────────────────────────────────
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

            // ── Tab visualizer ────────────────────────────────────────────
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

            // ── Playback controls ─────────────────────────────────────────
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
                onSave: () {}, // not applicable in GP viewer
                onCopy: () {}, // not applicable in GP viewer
                onClearSelection: _clearSelection,
                // GP-viewer extensions
                isPaused: _isPaused,
                gpLoopMode: _loopMode,
                onCycleLoopMode: _cycleLoopMode,
              ),
            ),
          ],
        ],
      ),
    );
  }
}