import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../services/gpx_parser_service.dart';
import '../services/midi_service.dart';
import '../services/recent_files_service.dart';
import '../utils/tab_sequence_builder.dart';
import '../widgets/gpx_viewer/gpx_recent_files_view.dart';
import '../widgets/gpx_viewer/gpx_track_menu.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';

class GpxTabScreen extends StatefulWidget {
  const GpxTabScreen({super.key});

  @override
  State<GpxTabScreen> createState() => _GpxTabScreenState();
}

class _GpxTabScreenState extends State<GpxTabScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  GpScore? _score;
  bool _isLoading = false;
  List<Map<String, String>> _recentFiles = [];
  int _selectedTrackIndex = 0;
  Set<int> _soloedTracks = {0};
  Set<int> _mutedTracks = {};
  int _endRests = 0;
  double _speedMultiplier = 1.0;

  List<GpBeat> get _parsedBeats {
    if (_score == null || _score!.tracks.isEmpty) return [];
    final List<GpBeat> baseBeats = List<GpBeat>.from(_score!.tracks[_selectedTrackIndex].beats);
    if (_endRests > 0) {
      if (_selectionStart != -1 && _selectionEnd != -1) {
        int insertIdx = max(_selectionStart, _selectionEnd) + 1;
        insertIdx = insertIdx.clamp(0, baseBeats.length);
        baseBeats.insertAll(insertIdx, List.generate(_endRests, (_) => GpBeat.rest(duration: 0.25)));
      } else {
        baseBeats.addAll(List.generate(_endRests, (_) => GpBeat.rest(duration: 0.25)));
      }
    }
    return baseBeats;
  }

  List<int> get _parsedMeasureEnds {
    if (_score == null || _score!.tracks.isEmpty) return const [];
    return _score!.tracks[_selectedTrackIndex].measureEndIndices;
  }

  final MidiService _midiService = MidiService();
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _playbackToken = 0;
  int _currentBendToken = 0;
  LoopMode _loopMode = LoopMode.off;
  final Set<int> _activeSoundingPitches = {};

  final ValueNotifier<int> _playingIndexNotifier = ValueNotifier<int>(-1);

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;
  int _measuresPerLine = 3;

  int _diagnosticMidiCalls = 0;
  double _diagnosticMaxDrift = 0.0;
  double _diagnosticMaxExecutionJitter = 0.0;
  int _diagnosticActiveLoops = 0;
  DateTime _lastDiagnosticPrint = DateTime.now();

  int _getTargetChannel(int trackIndex) {
    if (trackIndex == 0) return 12;
    if (trackIndex == 1) return 1;
    if (trackIndex == 2) return 3;
    if (trackIndex == 3) return 7;
    if (trackIndex == 4) return 10;
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _initMidi();
    _loadRecentFiles();
  }

  @override
  void dispose() {
    _stopPlayback(resetPosition: true);
    _playingIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _initMidi() async {
    await _midiService.init();
    if (mounted) {
      setState(() => _isMidiReady = _midiService.isReady);
    }
  }

  void _trackMidiSyncCall(String type, Function action) {
    _diagnosticMidiCalls++;
    final sw = Stopwatch()..start();
    action();
    sw.stop();
  }

  void _sendPitchBend(int value, {int channel = 0}) {
    _diagnosticMidiCalls++;
    _midiService.sendPitchBend(value, channel: channel);
  }

  void _resetPitchBend({int channel = 0}) {
    _sendPitchBend(8192, channel: channel);
  }

  double _interpolateBend(List<BendPoint> envelope, double progress) {
    if (envelope.isEmpty) return 0.0;
    if (progress <= envelope.first.position) return envelope.first.offset;
    if (progress >= envelope.last.position) return envelope.last.offset;

    for (int i = 0; i < envelope.length - 1; i++) {
      final p0 = envelope[i];
      final p1 = envelope[i + 1];
      if (progress >= p0.position && progress <= p1.position) {
        final double range = p1.position - p0.position;
        if (range <= 0.0001) return p0.offset;
        final double t = (progress - p0.position) / range;
        return p0.offset + t * (p1.offset - p0.offset);
      }
    }
    return envelope.last.offset;
  }

  void _spawnBendLoop(GpBend bend, double durationMs, int token, int bendToken, int channel) async {
    final Stopwatch bendTimer = Stopwatch()..start();
    const int stepIntervalMs = 30; 
    int lastSentValue = -1;
    
    _diagnosticActiveLoops++;
    try {
      await Future.doWhile(() async {
        if (!mounted || _playbackToken != token || _currentBendToken != bendToken || !_isPlaying) {
          _resetPitchBend(channel: channel);
          return false;
        }
        final double elapsed = bendTimer.elapsedMilliseconds.toDouble();
        if (elapsed >= durationMs) {
          _resetPitchBend(channel: channel);
          return false;
        }

        final double progress = (elapsed / durationMs).clamp(0.0, 1.0);
        final double offsetSemitones = _interpolateBend(bend.envelope, progress);
        
        final double safeOffset = offsetSemitones.clamp(-12.0, 12.0);
        final int bendValue = (8192 + (safeOffset / 12.0) * 8191).clamp(0, 16383).round();

        if (bendValue != lastSentValue) {
          _sendPitchBend(bendValue, channel: channel);
          lastSentValue = bendValue;
        }

        await Future.delayed(const Duration(milliseconds: stepIntervalMs));
        return true;
      });
    } finally {
      _diagnosticActiveLoops--;
    }
  }

  void _spawnSlideLoop(SlideType slide, double durationMs, int token, int bendToken, int channel) async {
    if (slide == SlideType.none || slide == SlideType.legato || slide == SlideType.shift) return;
    final Stopwatch slideTimer = Stopwatch()..start();
    const int stepIntervalMs = 30;
    int lastSentValue = -1;

    _diagnosticActiveLoops++;
    try {
      await Future.doWhile(() async {
        if (!mounted || _playbackToken != token || _currentBendToken != bendToken || !_isPlaying) {
          _resetPitchBend(channel: channel);
          return false;
        }
        final double elapsed = slideTimer.elapsedMilliseconds.toDouble();
        if (elapsed >= durationMs) {
          _resetPitchBend(channel: channel);
          return false;
        }

        final double progress = (elapsed / durationMs).clamp(0.0, 1.0);
        
        double offsetSemitones = 0.0;
        if (slide == SlideType.intoFromBelow) {
          offsetSemitones = -2.0 * (1.0 - progress);
        } else if (slide == SlideType.intoFromAbove) {
          offsetSemitones = 2.0 * (1.0 - progress);
        } else if (slide == SlideType.outDownwards) {
          offsetSemitones = -2.0 * progress;
        } else if (slide == SlideType.outUpwards) {
          offsetSemitones = 2.0 * progress;
        }

        final double safeOffset = offsetSemitones.clamp(-12.0, 12.0);
        final int bendValue = (8192 + (safeOffset / 12.0) * 8191).clamp(0, 16383).round();

        if (bendValue != lastSentValue) {
          _sendPitchBend(bendValue, channel: channel);
          lastSentValue = bendValue;
        }

        await Future.delayed(const Duration(milliseconds: stepIntervalMs));
        return true;
      });
    } finally {
      _diagnosticActiveLoops--;
    }
  }

  void _spawnVibratoLoop(GpVibrato vibrato, double durationMs, int token, int bendToken, int channel) async {
    final Stopwatch vibTimer = Stopwatch()..start();
    const int stepIntervalMs = 30;
    final double sustainStartMs = durationMs * 0.2;
    int lastSentValue = -1;

    _diagnosticActiveLoops++;
    try {
      await Future.doWhile(() async {
        if (!mounted || _playbackToken != token || _currentBendToken != bendToken || !_isPlaying) {
          _resetPitchBend(channel: channel);
          return false;
        }
        final double elapsed = vibTimer.elapsedMilliseconds.toDouble();
        if (elapsed >= durationMs) {
          _resetPitchBend(channel: channel);
          return false;
        }

        if (elapsed >= sustainStartMs) {
          final double tSec = (elapsed - sustainStartMs) / 1000.0;
          final double lfo = sin(2 * pi * vibrato.frequency * tSec);
          final double offsetSemitones = lfo * (vibrato.amplitude * 0.4);
          
          final double safeOffset = offsetSemitones.clamp(-12.0, 12.0);
          final int bendValue = (8192 + (safeOffset / 12.0) * 8191).clamp(0, 16383).round();

          if (bendValue != lastSentValue) {
            _sendPitchBend(bendValue, channel: channel);
            lastSentValue = bendValue;
          }
        }

        await Future.delayed(const Duration(milliseconds: stepIntervalMs));
        return true;
      });
    } finally {
      _diagnosticActiveLoops--;
    }
  }

  Future<void> _loadRecentFiles() async {
    final files = await RecentFilesService.load();
    if (mounted) setState(() => _recentFiles = files);
  }

  Future<void> _openRecentFile(String name, String path) async {
    _stopPlayback(resetPosition: true);
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('File not found. It may have been moved or deleted.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      final files = await RecentFilesService.remove(_recentFiles, path);
      setState(() => _recentFiles = files);
      return;
    }
    await _processFile(() => GpxParserService.parseGpFile(name, path, null), saveRecent: true);
  }

  Future<void> _pickAndParseGp() async {
    _stopPlayback(resetPosition: true);
    await _processFile(() => GpxParserService.pickAndParse(), saveRecent: true);
  }

  Future<void> _processFile(Future<GpScore?> Function() parseAction, {bool saveRecent = false}) async {
    setState(() {
      _isLoading = true;
      _score = null;
      _selectedTrackIndex = 0;
      _soloedTracks = {0};
      _mutedTracks = {};
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
    _playingIndexNotifier.value = -1;

    try {
      final result = await parseAction();
      if (result != null) {
        if (saveRecent) {
          _recentFiles = await RecentFilesService.add(_recentFiles, result.fileName, result.filePath);
        }
        setState(() => _score = result);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _closeFile() {
    _stopPlayback(resetPosition: true);
    setState(() {
      _score = null;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  Future<void> _startPlayback() async {
    final List<GpBeat> mainBeats = _parsedBeats;
    if (!_isMidiReady || mainBeats.isEmpty || _score == null) return;

    final bool isSingleNoteSelected = _selectionStart != -1 && _selectionEnd != -1 && _selectionStart == _selectionEnd;
    final bool isRangeSelected = _selectionStart != -1 && _selectionEnd != -1 && _selectionStart != _selectionEnd;

    final int selMin = isRangeSelected ? min(_selectionStart, _selectionEnd) : _selectionStart;
    final int selMax = isRangeSelected ? (max(_selectionStart, _selectionEnd) + _endRests) : _selectionEnd;

    final int startIdx;
    if (_isPaused && _playingIndexNotifier.value >= 0 && _playingIndexNotifier.value < mainBeats.length) {
      startIdx = _playingIndexNotifier.value;
    } else if (isSingleNoteSelected) {
      startIdx = _selectionStart.clamp(0, mainBeats.length - 1);
    } else if (isRangeSelected) {
      startIdx = selMin.clamp(0, mainBeats.length - 1);
    } else if (_loopMode == LoopMode.selection && _selectionStart != -1) {
      startIdx = _selectionStart.clamp(0, mainBeats.length - 1);
    } else {
      startIdx = 0;
    }

    final int endIdx = isRangeSelected
        ? selMax.clamp(0, mainBeats.length - 1)
        : ((_loopMode == LoopMode.selection && _selectionEnd != -1)
            ? _selectionEnd.clamp(0, mainBeats.length - 1)
            : mainBeats.length - 1);

    _isPaused = false;
    _playbackToken++;
    final int token = _playbackToken;

    _diagnosticMidiCalls = 0;
    _diagnosticMaxDrift = 0.0;
    _diagnosticMaxExecutionJitter = 0.0;
    _diagnosticActiveLoops = 0;
    _lastDiagnosticPrint = DateTime.now();

    setState(() {
      _isPlaying = true;
    });
    _playingIndexNotifier.value = startIdx;

    _trackMidiSyncCall('initNote', () => _midiService.playNote(key: 12, velocity: 1));
    await Future.delayed(const Duration(milliseconds: 100));
    _trackMidiSyncCall('initNoteOff', () => _midiService.stopNote(key: 12));

    if (!mounted || _playbackToken != token || !_isPlaying) return;

    double calculateMsForBeatIndex(int targetIndex) {
      double ms = 0.0;
      int measureIdx = 0;
      int tpo = _score!.tempo;
      if (_score!.masterBars.isNotEmpty) tpo = _score!.masterBars[0].tempo;
      
      for (int i = 0; i < targetIndex && i < mainBeats.length; i++) {
        final double effTempo = tpo * _speedMultiplier;
        ms += mainBeats[i].duration * (60000.0 / effTempo);
        if (_parsedMeasureEnds.contains(i)) {
          measureIdx++;
          if (_score!.masterBars.isNotEmpty && measureIdx < _score!.masterBars.length) {
            tpo = _score!.masterBars[measureIdx].tempo;
          }
        }
      }
      return TabSequenceBuilder.roundMs(ms);
    }

    final double originStartMs = calculateMsForBeatIndex(startIdx);
    final double originEndMs = calculateMsForBeatIndex(endIdx + 1);

    final mainTimeline = TabSequenceBuilder.buildAbsoluteTimeline(
      beats: mainBeats,
      measureEnds: _parsedMeasureEnds,
      initialTempo: _score!.tempo,
      masterBars: _score!.masterBars,
      trackIndex: _selectedTrackIndex,
      channel: _getTargetChannel(_selectedTrackIndex),
      isMainTrack: true,
      speedMultiplier: _speedMultiplier,
    );

    if (mainTimeline.isEmpty) return;

    List<ScheduledMidiEvent> unifiedTimeline = [];

    void _addEventsToUnifiedTimeline(List<ScheduledMidiEvent> sourceTimeline, bool isMainTrack) {
      for (final ev in sourceTimeline) {
        if (ev.timeMs >= originStartMs && ev.timeMs <= originEndMs) {
          unifiedTimeline.add(ScheduledMidiEvent(
            timeMs: TabSequenceBuilder.roundMs(ev.timeMs - originStartMs),
            type: ev.type,
            channel: ev.channel,
            data1: ev.data1,
            data2: ev.data2,
            trackIndex: ev.trackIndex,
            beatIndex: ev.beatIndex,
            isMainTrack: isMainTrack,
            bend: ev.bend,
            vibrato: ev.vibrato,
            slideType: ev.slideType,
            durationMs: ev.durationMs,
            isMuted: ev.isMuted,
            isGhost: ev.isGhost,
          ));
        } 
      }
    }

    _addEventsToUnifiedTimeline(mainTimeline, true);

    for (int tIdx = 0; tIdx < _score!.tracks.length; tIdx++) {
      if (tIdx == _selectedTrackIndex) continue;
      final bTrack = _score!.tracks[tIdx];
      final bTimeline = TabSequenceBuilder.buildAbsoluteTimeline(
        beats: bTrack.beats,
        measureEnds: bTrack.measureEndIndices,
        initialTempo: _score!.tempo,
        masterBars: _score!.masterBars,
        trackIndex: tIdx,
        channel: _getTargetChannel(tIdx),
        isMainTrack: false,
        speedMultiplier: _speedMultiplier,
      );
      _addEventsToUnifiedTimeline(bTimeline, false);
    }

    unifiedTimeline.sort();

    while (true) {
      if (!mounted || _playbackToken != token || !_isPlaying) return;

      final Stopwatch masterClock = Stopwatch()..start();
      int eventIndex = 0;

      while (eventIndex < unifiedTimeline.length) {
        if (!mounted || _playbackToken != token || !_isPlaying) {
          _cleanUpMidiState();
          return;
        }

        final ev = unifiedTimeline[eventIndex];
        final double targetMs = ev.timeMs;
        final double elapsedMs = masterClock.elapsedMicroseconds / 1000.0;
        final int waitMs = (targetMs - elapsedMs).round();

        if (waitMs > 0) {
          await Future.delayed(Duration(milliseconds: waitMs));
          if (!mounted || _playbackToken != token || !_isPlaying) {
            _cleanUpMidiState();
            return;
          }
        }

        final double wokeUpAtMs = masterClock.elapsedMicroseconds / 1000.0;
        final double timerDrift = wokeUpAtMs - targetMs;
        if (timerDrift > _diagnosticMaxDrift) _diagnosticMaxDrift = timerDrift;

        final Stopwatch execSw = Stopwatch()..start();
        while (eventIndex < unifiedTimeline.length &&
            unifiedTimeline[eventIndex].timeMs <= (masterClock.elapsedMicroseconds / 1000.0) + 2.0) {
          _dispatchMidiEvent(unifiedTimeline[eventIndex], token);
          eventIndex++;
        }
        execSw.stop();
        if (execSw.elapsedMicroseconds / 1000.0 > _diagnosticMaxExecutionJitter) {
          _diagnosticMaxExecutionJitter = execSw.elapsedMicroseconds / 1000.0;
        }

        if (DateTime.now().difference(_lastDiagnosticPrint).inMilliseconds >= 1000) {
          debugPrint('[PERF TELEMETRY] Timer Drift: ${_diagnosticMaxDrift.toStringAsFixed(1)}ms | '
                     'Exec Time: ${_diagnosticMaxExecutionJitter.toStringAsFixed(1)}ms | '
                     'Native Calls/sec: $_diagnosticMidiCalls | '
                     'Active Loops: $_diagnosticActiveLoops');
          _diagnosticMidiCalls = 0;
          _diagnosticMaxDrift = 0.0;
          _diagnosticMaxExecutionJitter = 0.0;
          _lastDiagnosticPrint = DateTime.now();
        }
      }

      final double totalSongMs = originEndMs - originStartMs;
      final double currentElapsed = masterClock.elapsedMicroseconds / 1000.0;
      final int trailingWaitMs = (totalSongMs - currentElapsed).round();

      if (trailingWaitMs > 0) {
        await Future.delayed(Duration(milliseconds: trailingWaitMs));
      }

      _cleanUpMidiState();

      if (!mounted || _playbackToken != token || !_isPlaying) return;

      switch (_loopMode) {
        case LoopMode.off:
          setState(() {
            _isPlaying = false;
          });
          _playingIndexNotifier.value = -1;
          return;
        case LoopMode.all:
        case LoopMode.selection:
          break;
      }
    }
  }

  void _dispatchMidiEvent(ScheduledMidiEvent ev, int token) {
    final int tIdx = ev.trackIndex;
    final bool shouldPlay = _soloedTracks.isNotEmpty ? _soloedTracks.contains(tIdx) : !_mutedTracks.contains(tIdx);

    if (ev.isMainTrack && mounted && ev.type == 'note_on') {
      _playingIndexNotifier.value = ev.beatIndex;
    }

    if (!shouldPlay) return;

    if (ev.type == 'note_on') {
      if (ev.isMuted || ev.isGhost) {
        debugPrint('[EXPRESSIVITY DIAGNOSTIC] Firing ${ev.isMuted ? "Muted (x)" : "Ghost ()"} | Pitch: ${ev.data1} | Vel: ${ev.data2} | Dur: ${ev.durationMs}ms');
      }
      
      _trackMidiSyncCall('playNote', () => _midiService.playNote(key: ev.data1, velocity: ev.data2, channel: ev.channel));
      _activeSoundingPitches.add(ev.data1);
      
      if (ev.bend != null && ev.durationMs != null) {
        _currentBendToken++;
        _spawnBendLoop(ev.bend!, ev.durationMs!, token, _currentBendToken, ev.channel);
      } else if (ev.vibrato != null && ev.durationMs != null) {
        _currentBendToken++;
        _spawnVibratoLoop(ev.vibrato!, ev.durationMs!, token, _currentBendToken, ev.channel);
      } else if (ev.slideType != SlideType.none && ev.durationMs != null) {
        _currentBendToken++;
        _spawnSlideLoop(ev.slideType, ev.durationMs!, token, _currentBendToken, ev.channel);
      }
    } else if (ev.type == 'note_off') {
      _trackMidiSyncCall('stopNote', () => _midiService.stopNote(key: ev.data1, channel: ev.channel));
      _activeSoundingPitches.remove(ev.data1);
    }
  }

  void _cleanUpMidiState() {
    final channel = _getTargetChannel(_selectedTrackIndex);
    for (final p in _activeSoundingPitches) {
      _midiService.stopNote(key: p, channel: channel);
    }
    _activeSoundingPitches.clear();
    _resetPitchBend(channel: channel);
  }

  void _pausePlayback() {
    _playbackToken++;
    _cleanUpMidiState();
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _stopPlayback({bool resetPosition = false}) {
    _playbackToken++;
    _cleanUpMidiState();
    _isPaused = false;
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
      if (resetPosition) {
        _playingIndexNotifier.value = -1;
        if (_selectionStart != -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _playingIndexNotifier.value = _selectionStart;
          });
        }
      }
    }
  }

  void _rewind() {
    bool wasPlaying = _isPlaying;
    _stopPlayback(resetPosition: false);
    setState(() { _isPaused = false; });
    _playingIndexNotifier.value = 0;
    if (wasPlaying) _startPlayback();
  }

  void _onBeatTapped(int index) {
    setState(() {
      _isPaused = false;
      if (_tapAnchorIndex == null) {
        _tapAnchorIndex = index; _selectionStart = index; _selectionEnd = index;
      } else if (_tapAnchorIndex == index) {
        _tapAnchorIndex = null; _selectionStart = -1; _selectionEnd = -1;
      } else {
        _selectionStart = min(_tapAnchorIndex!, index);
        _selectionEnd = max(_tapAnchorIndex!, index);
        _tapAnchorIndex = null;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null;
    });
    if (!_isPlaying && _parsedBeats.isNotEmpty) _playingIndexNotifier.value = 0;
  }

  void _cycleLoopMode() {
    setState(() {
      _loopMode = _loopMode == LoopMode.off ? LoopMode.all : (_loopMode == LoopMode.all ? LoopMode.selection : LoopMode.off);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final beats = _parsedBeats;
    final bool hasFile = _score != null && !_isLoading;

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
                            Text(_score!.songTitleFormatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent), overflow: TextOverflow.ellipsis),
                            Text(_score!.fileName, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (_score!.tracks.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.tune, color: Colors.amberAccent),
                          onPressed: () => showGpxTrackMenu(
                            context,
                            tracks: _score!.tracks,
                            selectedTrackIndex: _selectedTrackIndex,
                            soloedTracks: _soloedTracks,
                            mutedTracks: _mutedTracks,
                            onSelectTrack: (i) {
                              _stopPlayback(resetPosition: true);
                              setState(() {
                                _selectedTrackIndex = i;
                                _selectionStart = -1;
                                _selectionEnd = -1;
                              });
                            },
                            onToggleSolo: (i) => setState(() { if (_soloedTracks.contains(i)) _soloedTracks.remove(i); else { _soloedTracks.add(i); _mutedTracks.remove(i); } }),
                            onToggleMute: (i) => setState(() { if (_mutedTracks.contains(i)) _mutedTracks.remove(i); else { _mutedTracks.add(i); _soloedTracks.remove(i); } }),
                          ),
                        ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: _closeFile),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_isLoading) const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (!hasFile) Expanded(child: GpxRecentFilesView(recentFiles: _recentFiles, onOpen: _openRecentFile, onRemove: (path) async { final files = await RecentFilesService.remove(_recentFiles, path); setState(() => _recentFiles = files); }))
          else ...[
            Expanded(
              child: beats.isEmpty
                  ? const Center(child: Text('No notes found.', style: TextStyle(color: Colors.grey, fontSize: 13)))
                  : Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Time Signature: ${_score!.masterBars.isNotEmpty ? '${_score!.masterBars.first.numerator}/${_score!.masterBars.first.denominator}' : 'Auto'} | Tempo: ${_score!.tempo}", style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text("Bars/Row: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    GestureDetector(onTap: () { if (_measuresPerLine > 1) setState(() => _measuresPerLine--); }, child: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.white70)),
                                    Padding(padding: const EdgeInsets.symmetric(horizontal: 6.0), child: Text("$_measuresPerLine", style: const TextStyle(fontSize: 12, color: Colors.white))),
                                    GestureDetector(onTap: () => setState(() => _measuresPerLine++), child: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white70)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InteractiveTabDisplay(
                                sequence: beats, 
                                notesPerMeasure: _score!.notesPerMeasure, 
                                measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
                                currentPlayingIndex: -1, 
                                playingIndexNotifier: _playingIndexNotifier,
                                selectionStart: _selectionStart, 
                                selectionEnd: _selectionEnd,
                                tuningStr: 'Standard E', 
                                onBeatTapped: _onBeatTapped, 
                                measureEndIndices: _parsedMeasureEnds, 
                                masterBars: _score!.masterBars,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.only(bottom: 24.0),
              child: PlaybackControlBar(
                isPlaying: _isPlaying, isMidiReady: _isMidiReady, isLooping: _loopMode != LoopMode.off,
                hasSequence: beats.isNotEmpty, hasSelection: _selectionStart != -1 && _selectionEnd != -1,
                selectionStart: _selectionStart, selectionEnd: _selectionEnd,
                onPlay: () => _isPlaying ? _pausePlayback() : _startPlayback(),
                onStop: () => _stopPlayback(resetPosition: true),
                onToggleLoop: _cycleLoopMode, onSave: () {}, onCopy: () {}, onClearSelection: _clearSelection,
                isPaused: _isPaused, gpLoopMode: _loopMode, onCycleLoopMode: _cycleLoopMode,
                onRewind: _rewind, speedMultiplier: _speedMultiplier, onSpeedChanged: (s) => setState(() => _speedMultiplier = s.clamp(0.1, 2.0)),
                endRests: _endRests, onEndRestsChanged: (v) => setState(() => _endRests = v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}