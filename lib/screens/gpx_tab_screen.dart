import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/gp_track.dart';
import '../services/gpx_parser_service.dart';
import '../services/recent_files_service.dart';
import '../widgets/gpx_viewer/gpx_track_menu.dart';
import '../widgets/gpx_viewer/gpx_recent_files_view.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';

class GpxTabScreen extends StatefulWidget {
  const GpxTabScreen({super.key});

  @override
  State<GpxTabScreen> createState() => _GpxTabScreenState();
}

class _GpxTabScreenState extends State<GpxTabScreen>
    with AutomaticKeepAliveClientMixin {
  // Preserve state when switching tabs
  @override
  bool get wantKeepAlive => true;

  // File / Song metadata
  String? _fileName;
  String _songTitle = '';
  String _artist = '';
  bool _isLoading = false;

  // Track data & Solo/Mute States
  List<GpTrack> _tracks = [];
  int _selectedTrackIndex = 0;
  Set<int> _soloedTracks = {};
  Set<int> _mutedTracks = {};

  // Recent Files
  List<Map<String, String>> _recentFiles = [];

  // Dynamic Rests & Speed
  int _endRests = 0;
  double _speedMultiplier = 1.0;

  List<List<int>> get _parsedSequence {
    if (_tracks.isEmpty) return [];
    final List<List<int>> baseNotes =
        List<List<int>>.from(_tracks[_selectedTrackIndex].notes);

    if (_endRests > 0) {
      if (_selectionStart != -1 && _selectionEnd != -1) {
        int insertIdx = max(_selectionStart, _selectionEnd) + 1;
        insertIdx = insertIdx.clamp(0, baseNotes.length);
        baseNotes.insertAll(
            insertIdx, List.generate(_endRests, (_) => [-1, -1]));
      } else {
        baseNotes.addAll(List.generate(_endRests, (_) => [-1, -1]));
      }
    }
    return baseNotes;
  }

  List<double> get _parsedRhythms {
    if (_tracks.isEmpty) return [];
    final List<double> baseRhythms =
        List<double>.from(_tracks[_selectedTrackIndex].rhythms);

    if (_endRests > 0) {
      if (_selectionStart != -1 && _selectionEnd != -1) {
        int insertIdx = max(_selectionStart, _selectionEnd) + 1;
        insertIdx = insertIdx.clamp(0, baseRhythms.length);
        baseRhythms.insertAll(
            insertIdx, List.generate(_endRests, (_) => 0.25));
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
    _loadRecentFiles();
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

  // ---------------------------------------------------------------------------
  // Recent Files
  // ---------------------------------------------------------------------------

  Future<void> _loadRecentFiles() async {
    final files = await RecentFilesService.load();
    if (mounted) setState(() => _recentFiles = files);
  }

  Future<void> _addRecentFile(String name, String path) async {
    final updated = await RecentFilesService.add(_recentFiles, name, path);
    if (mounted) setState(() => _recentFiles = updated);
  }

  Future<void> _removeRecentFile(String path) async {
    final updated = await RecentFilesService.remove(_recentFiles, path);
    if (mounted) setState(() => _recentFiles = updated);
  }

  Future<void> _openRecentFile(String name, String path) async {
    _stopPlayback(resetPosition: true);
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('File not found. It may have been moved or deleted.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      _removeRecentFile(path);
      return;
    }
    await _processFile(name, path, null);
  }

  // ---------------------------------------------------------------------------
  // GP Parsing
  // ---------------------------------------------------------------------------

  Future<void> _pickAndParseGp() async {
    _stopPlayback(resetPosition: true);

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.gp')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Invalid file type. Please select a Guitar Pro 7/8 (.gp) file.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    await _processFile(file.name, file.path, file.bytes);
  }

  Future<void> _processFile(
      String name, String? path, List<int>? bytesData) async {
    setState(() {
      _isLoading = true;
      _fileName = name;
      _songTitle = '';
      _artist = '';
      _tracks = [];
      _selectedTrackIndex = 0;
      _soloedTracks = {0}; // Default: solo the first instrument
      _mutedTracks = {};
      _currentPlayingIndex = -1;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });

    try {
      final score = await GpxParserService.parseGpFile(path, bytesData);

      if (path != null) {
        await _addRecentFile(name, path);
      }

      setState(() {
        _songTitle = score.title;
        _artist = score.artist;
        _tracks = score.tracks;
        _selectedTrackIndex = 0;
        _notesPerMeasure = score.notesPerMeasure;
        _tempo = score.tempo;
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

  void _closeFile() {
    _stopPlayback(resetPosition: true);
    setState(() {
      _fileName = null;
      _songTitle = '';
      _artist = '';
      _tracks = [];
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
      _currentPlayingIndex = -1;
    });
  }

  // ---------------------------------------------------------------------------
  // Track selection & menu
  // ---------------------------------------------------------------------------

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

  void _showTracksMenu() {
    showGpxTrackMenu(
      context,
      tracks: _tracks,
      selectedTrackIndex: _selectedTrackIndex,
      soloedTracks: _soloedTracks,
      mutedTracks: _mutedTracks,
      onSelectTrack: _selectTrack,
      onToggleSolo: (i) {
        setState(() {
          if (_soloedTracks.contains(i)) {
            _soloedTracks.remove(i);
          } else {
            _soloedTracks.add(i);
            _mutedTracks.remove(i);
          }
        });
      },
      onToggleMute: (i) {
        setState(() {
          if (_mutedTracks.contains(i)) {
            _mutedTracks.remove(i);
          } else {
            _mutedTracks.add(i);
            _soloedTracks.remove(i);
          }
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

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

    // Force index to -1 first to guarantee a state change to InteractiveTabDisplay
    setState(() {
      _currentPlayingIndex = -1;
      _isPaused = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _currentPlayingIndex = 0);
        if (wasPlaying) {
          _startPlayback();
        }
      }
    });
  }

  /// Background track independent playback loop.
  Future<void> _playBackgroundTrack(
      int tIdx, int token, int startIdx, int endIdx) async {
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
        final double rhythmMultiplier =
            (i < rhythms.length) ? rhythms[i] : 0.25;
        final double effectiveTempo = _tempo * _speedMultiplier;
        final int msDelay =
            (rhythmMultiplier * (60000 / effectiveTempo)).round();

        bool shouldPlay = _soloedTracks.isNotEmpty
            ? _soloedTracks.contains(tIdx)
            : !_mutedTracks.contains(tIdx);

        if (note[0] != -1 && shouldPlay) {
          final int pitch = (_standardTuning[note[0]] ?? 40) + note[1];
          _midiPro.playMidiNote(midi: pitch, velocity: 80);
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
    final bool isRangeSelected = _selectionStart != -1 &&
        _selectionEnd != -1 &&
        _selectionStart != _selectionEnd;

    final int selMin =
        isRangeSelected ? min(_selectionStart, _selectionEnd) : _selectionStart;
    final int selMax = isRangeSelected
        ? (max(_selectionStart, _selectionEnd) + _endRests)
        : _selectionEnd;

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

    // Spawn independent timing loops for all unselected backing tracks.
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
      final double rhythmMultiplier =
          (i < rhythms.length) ? rhythms[i] : 0.25;
      final double effectiveTempo = _tempo * _speedMultiplier;
      final int msDelay =
          (rhythmMultiplier * (60000 / effectiveTempo)).round();

      if (mounted) setState(() => _currentPlayingIndex = i);

      bool shouldPlayMain = _soloedTracks.isNotEmpty
          ? _soloedTracks.contains(_selectedTrackIndex)
          : !_mutedTracks.contains(_selectedTrackIndex);

      if (note[0] != -1 && shouldPlayMain) {
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

        // Restart background tracks when looping.
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

  void _stopPlayback({bool resetPosition = true}) {
    _playbackToken++;
    _isPaused = false;

    if (mounted) {
      setState(() {
        _isPlaying = false;
        if (resetPosition) {
          _currentPlayingIndex = -1;
        }
      });

      // If we have a selection, snap the playhead back to it after the frame.
      if (resetPosition && _selectionStart != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentPlayingIndex = _selectionStart);
        });
      }
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
      if (!_isPlaying) {
        _currentPlayingIndex = -1;
      }
    });

    if (!_isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _parsedSequence.isNotEmpty) {
          setState(() => _currentPlayingIndex = 0);
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _songTitle.isNotEmpty
                                  ? '$_songTitle - $_artist'
                                  : _artist,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _fileName!,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_tracks.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.tune,
                              color: Colors.amberAccent),
                          tooltip: 'Tracks & Instruments',
                          onPressed: _showTracksMenu,
                        ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.redAccent),
                        tooltip: 'Close File',
                        onPressed: _closeFile,
                      ),
                    ],
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
            Expanded(
              child: GpxRecentFilesView(
                recentFiles: _recentFiles,
                onOpen: _openRecentFile,
                onRemove: _removeRecentFile,
              ),
            )
          else ...[
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
              padding: const EdgeInsets.only(
                  bottom: 24.0), // Padding to clear virtual element
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