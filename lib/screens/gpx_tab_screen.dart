import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../services/gpx_parser_service.dart';
import '../services/recent_files_service.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';
import '../widgets/gpx_viewer/gpx_track_menu.dart';
import '../widgets/gpx_viewer/gpx_recent_files_view.dart';

class _ScheduledBeatEvent implements Comparable<_ScheduledBeatEvent> {
  final int trackIndex;
  final int beatIndexInTrack;
  final GpBeat beat;
  final double startMs;
  final double durationMs;
  final bool isMainTrack;

  const _ScheduledBeatEvent({
    required this.trackIndex,
    required this.beatIndexInTrack,
    required this.beat,
    required this.startMs,
    required this.durationMs,
    required this.isMainTrack,
  });

  @override
  int compareTo(_ScheduledBeatEvent other) {
    final cmp = startMs.compareTo(other.startMs);
    if (cmp != 0) return cmp;
    if (isMainTrack && !other.isMainTrack) return -1;
    if (!isMainTrack && other.isMainTrack) return 1;
    return trackIndex.compareTo(other.trackIndex);
  }
}

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
  Set<int> _soloedTracks = {};
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

  final MidiPro _midiPro = MidiPro();
  int? _sfId;
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _playbackToken = 0;
  int _currentPlayingIndex = -1;
  int _currentBendToken = 0;
  LoopMode _loopMode = LoopMode.off;

  final Map<int, int> _pitchGenerations = {};

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _measuresPerLine = 3;

  final Map<int, int> _standardTuning = {
    1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40, 7: 35, 8: 30,
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
      if (!_midiPro.isInitialized) {
        await _midiPro.init(sampleRate: 44100, bufferSize: 64, polyphony: 64);
      }
      _sfId = await _midiPro.loadSoundfontAsset(assetPath: 'assets/guitar.sf2', program: 27);
      
      // Setup Pitch Bend Range via MIDI Registered Parameter Numbers (RPN CC 101/100/6)
      if (_sfId != null) {
        await _configurePitchBendSensitivity();
      }

      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint("MIDI Setup Error in GP Viewer: $e");
    }
  }

  Future<void> _configurePitchBendSensitivity() async {
    if (_sfId == null) return;
    for (int ch = 0; ch < 16; ch++) {
      await _midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 101, data2: 0, sfId: _sfId!); // RPN MSB = 0
      await _midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 100, data2: 0, sfId: _sfId!); // RPN LSB = 0
      await _midiPro.sendMidiEvent(status: 0xB0 | ch, data1: 6, data2: 12, sfId: _sfId!);  // Data Entry = 12 semitones
    }
  }

  Future<void> _sendPitchBend(int value, {int channel = 0}) async {
    final int clamped = value.clamp(0, 16383);
    final int lsb = clamped & 0x7F;
    final int msb = (clamped >> 7) & 0x7F;
    if (_sfId != null) {
      await _midiPro.sendMidiEvent(
        status: 0xE0 | (channel & 0x0F),
        data1: lsb,
        data2: msb,
        sfId: _sfId!,
      );
    }
  }

  Future<void> _resetPitchBend({int channel = 0}) async {
    await _sendPitchBend(8192, channel: channel);
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

  void _spawnBendLoop(GpBend bend, double durationMs, int token, int bendToken) {
    final Stopwatch bendTimer = Stopwatch()..start();
    const int stepIntervalMs = 12;

    Future.doWhile(() async {
      if (!mounted || _playbackToken != token || _currentBendToken != bendToken || !_isPlaying) {
        return false;
      }

      final double elapsed = bendTimer.elapsedMilliseconds.toDouble();
      if (elapsed >= durationMs) {
        return false;
      }

      final double progress = (elapsed / durationMs).clamp(0.0, 1.0);
      final double offsetSemitones = _interpolateBend(bend.envelope, progress);
      
      // Calculate 14-bit MIDI pitch bend value based on 12 semitones full scale
      final int bendValue = (8192 + (offsetSemitones / 12.0) * 8191).clamp(0, 16383).round();
      
      await _sendPitchBend(bendValue);
      await Future.delayed(const Duration(milliseconds: stepIntervalMs));
      return true;
    });
  }

  void _spawnVibratoLoop(GpVibrato vibrato, double durationMs, int token, int bendToken) {
    final Stopwatch vibTimer = Stopwatch()..start();
    const int stepIntervalMs = 12;
    final double sustainStartMs = durationMs * 0.15;

    Future.doWhile(() async {
      if (!mounted || _playbackToken != token || _currentBendToken != bendToken || !_isPlaying) {
        return false;
      }

      final double elapsed = vibTimer.elapsedMilliseconds.toDouble();
      if (elapsed >= durationMs) {
        return false;
      }

      if (elapsed >= sustainStartMs) {
        final double tSec = (elapsed - sustainStartMs) / 1000.0;
        final double lfo = sin(2 * pi * vibrato.frequency * tSec);
        final double offsetSemitones = lfo * (vibrato.amplitude * 0.5);
        final int bendValue = (8192 + (offsetSemitones / 12.0) * 8191).clamp(0, 16383).round();
        await _sendPitchBend(bendValue);
      }

      await Future.delayed(const Duration(milliseconds: stepIntervalMs));
      return true;
    });
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
      _currentPlayingIndex = -1;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });

    try {
      final result = await parseAction();
      if (result != null) {
        if (saveRecent && result.filePath.isNotEmpty) {
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
      _currentPlayingIndex = -1;
    });
  }

  List<_ScheduledBeatEvent> _buildTrackSchedule({
    required int trackIndex,
    required List<GpBeat> trackBeats,
    required List<int> measureEnds,
    required bool isMainTrack,
    required double speedMultiplier,
  }) {
    final List<_ScheduledBeatEvent> events = [];
    if (trackBeats.isEmpty || _score == null) return events;

    int currentMeasureIndex = 0;
    double currentMeasureStartMs = 0.0;
    int measureTempo = (_score!.masterBars.isNotEmpty && currentMeasureIndex < _score!.masterBars.length)
        ? _score!.masterBars[currentMeasureIndex].tempo
        : _score!.tempo;

    double beatAccumulatorInMeasureMs = 0.0;

    for (int i = 0; i < trackBeats.length; i++) {
      final beat = trackBeats[i];
      final double effectiveTempo = measureTempo * speedMultiplier;
      final double beatDurationMs = beat.duration * (60000.0 / effectiveTempo);
      final double beatStartMs = currentMeasureStartMs + beatAccumulatorInMeasureMs;

      events.add(_ScheduledBeatEvent(
        trackIndex: trackIndex,
        beatIndexInTrack: i,
        beat: beat,
        startMs: beatStartMs,
        durationMs: beatDurationMs,
        isMainTrack: isMainTrack,
      ));

      beatAccumulatorInMeasureMs += beatDurationMs;

      if (measureEnds.contains(i)) {
        currentMeasureStartMs += beatAccumulatorInMeasureMs;
        beatAccumulatorInMeasureMs = 0.0;
        currentMeasureIndex++;
        if (_score!.masterBars.isNotEmpty && currentMeasureIndex < _score!.masterBars.length) {
          measureTempo = _score!.masterBars[currentMeasureIndex].tempo;
        }
      }
    }
    return events;
  }

  Future<void> _startPlayback() async {
    final List<GpBeat> mainBeats = _parsedBeats;
    if (!_isMidiReady || _sfId == null || mainBeats.isEmpty) return;

    final bool isSingleNoteSelected = _selectionStart != -1 && _selectionStart == _selectionEnd;
    final bool isRangeSelected = _selectionStart != -1 && _selectionEnd != -1 && _selectionStart != _selectionEnd;

    final int selMin = isRangeSelected ? min(_selectionStart, _selectionEnd) : _selectionStart;
    final int selMax = isRangeSelected ? (max(_selectionStart, _selectionEnd) + _endRests) : _selectionEnd;

    final int startIdx;
    if (_isPaused && _currentPlayingIndex >= 0 && _currentPlayingIndex < mainBeats.length) {
      startIdx = _currentPlayingIndex;
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

    setState(() {
      _isPlaying = true;
      _currentPlayingIndex = startIdx;
    });

    _midiPro.playNote(key: 12, velocity: 1, sfId: _sfId!);
    await Future.delayed(const Duration(milliseconds: 100));
    _midiPro.stopNote(key: 12, sfId: _sfId!);

    if (!mounted || _playbackToken != token || !_isPlaying) return;

    final mainEvents = _buildTrackSchedule(
      trackIndex: _selectedTrackIndex,
      trackBeats: mainBeats,
      measureEnds: _parsedMeasureEnds,
      isMainTrack: true,
      speedMultiplier: _speedMultiplier,
    );

    if (mainEvents.isEmpty) return;

    final double originStartMs = (startIdx < mainEvents.length) ? mainEvents[startIdx].startMs : 0.0;
    final double originEndMs = (endIdx < mainEvents.length)
        ? (mainEvents[endIdx].startMs + mainEvents[endIdx].durationMs)
        : mainEvents.last.startMs;

    List<_ScheduledBeatEvent> unifiedTimeline = [];

    for (final ev in mainEvents) {
      if (ev.beatIndexInTrack >= startIdx && ev.beatIndexInTrack <= endIdx) {
        unifiedTimeline.add(_ScheduledBeatEvent(
          trackIndex: ev.trackIndex,
          beatIndexInTrack: ev.beatIndexInTrack,
          beat: ev.beat,
          startMs: ev.startMs - originStartMs,
          durationMs: ev.durationMs,
          isMainTrack: true,
        ));
      }
    }

    for (int tIdx = 0; tIdx < _score!.tracks.length; tIdx++) {
      if (tIdx == _selectedTrackIndex) continue;
      final bTrack = _score!.tracks[tIdx];
      final bEvents = _buildTrackSchedule(
        trackIndex: tIdx,
        trackBeats: bTrack.beats,
        measureEnds: bTrack.measureEndIndices,
        isMainTrack: false,
        speedMultiplier: _speedMultiplier,
      );

      for (final ev in bEvents) {
        if (ev.startMs >= originStartMs && ev.startMs <= originEndMs) {
          unifiedTimeline.add(_ScheduledBeatEvent(
            trackIndex: ev.trackIndex,
            beatIndexInTrack: ev.beatIndexInTrack,
            beat: ev.beat,
            startMs: ev.startMs - originStartMs,
            durationMs: ev.durationMs,
            isMainTrack: false,
          ));
        }
      }
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
        final double targetMs = ev.startMs;
        final double elapsedMs = masterClock.elapsedMicroseconds / 1000.0;
        final int waitMs = (targetMs - elapsedMs).round();

        if (waitMs > 0) {
          await Future.delayed(Duration(milliseconds: waitMs));
          if (!mounted || _playbackToken != token || !_isPlaying) {
            _cleanUpMidiState();
            return;
          }
        }

        while (eventIndex < unifiedTimeline.length &&
            unifiedTimeline[eventIndex].startMs <= (masterClock.elapsedMicroseconds / 1000.0) + 2.0) {
          _dispatchBeatEvent(unifiedTimeline[eventIndex], token);
          eventIndex++;
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
            _currentPlayingIndex = -1;
          });
          return;
        case LoopMode.all:
        case LoopMode.selection:
          break;
      }
    }
  }

  void _dispatchBeatEvent(_ScheduledBeatEvent ev, int token) async {
    final beat = ev.beat;
    final int tIdx = ev.trackIndex;

    if (ev.isMainTrack && mounted) {
      setState(() => _currentPlayingIndex = ev.beatIndexInTrack);
    }

    final bool shouldPlay = _soloedTracks.isNotEmpty ? _soloedTracks.contains(tIdx) : !_mutedTracks.contains(tIdx);
    if (!shouldPlay || beat.isRest) return;

    List<GpNote> sortedNotes = List.from(beat.notes.where((n) => !n.isRest));

    if (beat.strumDirection == StrumDirection.down) {
      sortedNotes.sort((a, b) => b.stringNum.compareTo(a.stringNum));
    } else if (beat.strumDirection == StrumDirection.up) {
      sortedNotes.sort((a, b) => a.stringNum.compareTo(b.stringNum));
    }

    const int strumMicroDelayMs = 6;

    for (int idx = 0; idx < sortedNotes.length; idx++) {
      final note = sortedNotes[idx];
      if (beat.strumDirection != StrumDirection.none && idx > 0) {
        await Future.delayed(const Duration(milliseconds: strumMicroDelayMs));
      }

      final int pitch = note.pitch != -1 ? note.pitch : ((_standardTuning[note.stringNum] ?? 40) + note.fretNum);
      int velocity = ev.isMainTrack ? 110 : 80;
      double playDurationMs = ev.durationMs;

      if (note.isMuted) {
        velocity = 20;
        playDurationMs = min(ev.durationMs, 30.0);
      } else if (note.isPalmMute) {
        velocity = (velocity * 0.6).round();
        playDurationMs = ev.durationMs * 0.5;
      } else if (note.isLetRing) {
        playDurationMs = max(ev.durationMs, 800.0);
      }

      final int currentGen = (_pitchGenerations[pitch] ?? 0) + 1;
      _pitchGenerations[pitch] = currentGen;

      if (_sfId != null) _midiPro.playNote(key: pitch, velocity: velocity, sfId: _sfId!);

      if (note.bend != null) {
        final int bendToken = ++_currentBendToken;
        _spawnBendLoop(note.bend!, playDurationMs, token, bendToken);
      } else if (note.vibrato != null) {
        final int bendToken = ++_currentBendToken;
        _spawnVibratoLoop(note.vibrato!, playDurationMs, token, bendToken);
      }

      final int delayMs = max(15, playDurationMs.round());
      Future.delayed(Duration(milliseconds: delayMs)).then((_) {
        if (_playbackToken == token && _pitchGenerations[pitch] == currentGen) {
          if (_sfId != null) _midiPro.stopNote(key: pitch, sfId: _sfId!);
          _pitchGenerations.remove(pitch);
        }
      });
    }
  }

  void _cleanUpMidiState() {
    if (_sfId != null) {
      for (final p in _pitchGenerations.keys) {
        _midiPro.stopNote(key: p, sfId: _sfId!);
      }
    }
    _pitchGenerations.clear();
    _resetPitchBend();
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
        if (resetPosition) _currentPlayingIndex = -1;
      });
      if (resetPosition && _selectionStart != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentPlayingIndex = _selectionStart);
        });
      }
    }
  }

  void _rewind() {
    bool wasPlaying = _isPlaying;
    _stopPlayback(resetPosition: false);
    setState(() { _currentPlayingIndex = 0; _isPaused = false; });
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
      if (!_isPlaying && _parsedBeats.isNotEmpty) _currentPlayingIndex = 0;
    });
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
                            onSelectTrack: (i) { _stopPlayback(resetPosition: true); setState(() { _selectedTrackIndex = i; _selectionStart = -1; _selectionEnd = -1; }); },
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _score!.tracks[_selectedTrackIndex].name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "Time Signature: ${_score!.masterBars.isNotEmpty ? '${_score!.masterBars.first.numerator}/${_score!.masterBars.first.denominator}' : 'Auto'} | Tempo: ${_score!.tempo}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text("Bars/Row: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    GestureDetector(
                                      onTap: () { if (_measuresPerLine > 1) setState(() => _measuresPerLine--); },
                                      child: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.white70),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                      child: Text("$_measuresPerLine", style: const TextStyle(fontSize: 12, color: Colors.white)),
                                    ),
                                    GestureDetector(
                                      onTap: () => setState(() => _measuresPerLine++),
                                      child: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InteractiveTabDisplay(
                                sequence: beats, notesPerMeasure: _score!.notesPerMeasure, measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
                                currentPlayingIndex: _currentPlayingIndex, selectionStart: _selectionStart, selectionEnd: _selectionEnd,
                                tuningStr: 'Standard E', onBeatTapped: _onBeatTapped, measureEndIndices: _parsedMeasureEnds, masterBars: _score!.masterBars,
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