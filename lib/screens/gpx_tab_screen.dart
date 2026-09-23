import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_track.dart';
import '../models/master_bar_event.dart';
import '../services/gpx_parser_service.dart';
import '../services/recent_files_service.dart';
import '../widgets/gpx_viewer/gpx_track_menu.dart';
import '../widgets/gpx_viewer/gpx_recent_files_view.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';

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

  String? _fileName;
  String _songTitle = '';
  String _artist = '';
  bool _isLoading = false;

  List<GpTrack> _tracks = [];
  List<MasterBarEvent> _masterBars = [];
  int _selectedTrackIndex = 0;
  Set<int> _soloedTracks = {};
  Set<int> _mutedTracks = {};

  List<Map<String, String>> _recentFiles = [];

  int _endRests = 0;
  double _speedMultiplier = 1.0;

  List<GpBeat> get _parsedBeats {
    if (_tracks.isEmpty) return [];
    final List<GpBeat> baseBeats = List<GpBeat>.from(_tracks[_selectedTrackIndex].beats);

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
    if (_tracks.isEmpty) return const [];
    return _tracks[_selectedTrackIndex].measureEndIndices;
  }

  final MidiPro _midiPro = MidiPro();
  static const MethodChannel _nativeMidiChannel = MethodChannel('flutter_midi_pro');
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _playbackToken = 0;
  
  // Independent channel tokens to prevent multiple bending notes from cancelling each other
  final Map<int, int> _bendTokens = {for (int i = 0; i <= 15; i++) i: 0};
  
  int _currentPlayingIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  final Map<int, Set<int>> _activeSoundingPitches = {for (int i = 0; i <= 15; i++) i: {}};

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _notesPerMeasure = 16;
  int _measuresPerLine = 3; 
  int _tempo = 120;

  final Map<int, int> _standardTuning = {
    1: 64, // e4
    2: 59, // B3
    3: 55, // G3
    4: 50, // D3
    5: 45, // A2
    6: 40, // E2
    7: 35, // B1
    8: 30, // F#1
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
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: 27);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint('GP Viewer MIDI setup error: $e');
    }
  }

  Future<void> _sendRawNoteOn(int pitch, int velocity, int channel) async {
    try {
      await _nativeMidiChannel.invokeMethod('sendMidiEvent', {
        'status': 0x90 | (channel & 0x0F),
        'data1': pitch,
        'data2': velocity,
      });
    } catch (_) {
      _midiPro.playMidiNote(midi: pitch, velocity: velocity);
    }
  }

  Future<void> _sendRawNoteOff(int pitch, int channel) async {
    try {
      await _nativeMidiChannel.invokeMethod('sendMidiEvent', {
        'status': 0x80 | (channel & 0x0F),
        'data1': pitch,
        'data2': 0,
      });
    } catch (_) {
      _midiPro.stopMidiNote(midi: pitch);
    }
  }

  Future<void> _sendPitchBend(int value, {int channel = 0}) async {
    final int clamped = value.clamp(0, 16383);
    final int lsb = clamped & 0x7F;
    final int msb = (clamped >> 7) & 0x7F;
    try {
      await _nativeMidiChannel.invokeMethod('sendMidiEvent', {
        'status': 0xE0 | (channel & 0x0F),
        'data1': lsb,
        'data2': msb,
      });
    } catch (_) {
      try {
        await _nativeMidiChannel.invokeMethod('pitchBend', {
          'value': clamped,
          'channel': channel,
        });
      } catch (_) {}
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

  void _spawnBendLoop(GpBend bend, double durationMs, int token, int bendToken, int channel) {
    final Stopwatch bendTimer = Stopwatch()..start();
    const int stepIntervalMs = 16;

    Future.doWhile(() async {
      if (!mounted || _playbackToken != token || _bendTokens[channel] != bendToken || !_isPlaying) {
        await _resetPitchBend(channel: channel);
        return false;
      }

      final double elapsed = bendTimer.elapsedMilliseconds.toDouble();
      if (elapsed >= durationMs) {
        await _resetPitchBend(channel: channel);
        return false;
      }

      final double progress = (elapsed / durationMs).clamp(0.0, 1.0);
      final double offsetSemitones = _interpolateBend(bend.envelope, progress);
      final int bendValue = (8192 + (offsetSemitones / 2.0) * 8191).clamp(0, 16383).round();
      
      await _sendPitchBend(bendValue, channel: channel);
      await Future.delayed(const Duration(milliseconds: stepIntervalMs));
      return true;
    });
  }

  void _spawnVibratoLoop(GpVibrato vibrato, double durationMs, int token, int bendToken, int channel) {
    final Stopwatch vibTimer = Stopwatch()..start();
    const int stepIntervalMs = 16;
    final double sustainStartMs = durationMs * 0.2;

    Future.doWhile(() async {
      if (!mounted || _playbackToken != token || _bendTokens[channel] != bendToken || !_isPlaying) {
        await _resetPitchBend(channel: channel);
        return false;
      }

      final double elapsed = vibTimer.elapsedMilliseconds.toDouble();
      if (elapsed >= durationMs) {
        await _resetPitchBend(channel: channel);
        return false;
      }

      if (elapsed >= sustainStartMs) {
        final double tSec = (elapsed - sustainStartMs) / 1000.0;
        final double lfo = sin(2 * pi * vibrato.frequency * tSec);
        final double offsetSemitones = lfo * (vibrato.amplitude * 0.4);
        final int bendValue = (8192 + (offsetSemitones / 2.0) * 8191).clamp(0, 16383).round();
        await _sendPitchBend(bendValue, channel: channel);
      }

      await Future.delayed(const Duration(milliseconds: stepIntervalMs));
      return true;
    });
  }

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
          content: Text('Invalid file type. Please select a Guitar Pro 7/8 (.gp) file.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    await _processFile(file.name, file.path, file.bytes);
  }

  Future<void> _processFile(String name, String? path, List<int>? bytesData) async {
    setState(() {
      _isLoading = true;
      _fileName = name;
      _songTitle = '';
      _artist = '';
      _tracks = [];
      _masterBars = [];
      _selectedTrackIndex = 0;
      _soloedTracks = {0}; 
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
        _masterBars = score.masterBars;
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
      _masterBars = [];
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
      _currentPlayingIndex = -1;
    });
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

  List<_ScheduledBeatEvent> _buildTrackSchedule({
    required int trackIndex,
    required List<GpBeat> trackBeats,
    required List<int> measureEnds,
    required bool isMainTrack,
    required double speedMultiplier,
  }) {
    final List<_ScheduledBeatEvent> events = [];
    if (trackBeats.isEmpty) return events;

    int currentMeasureIndex = 0;
    double currentMeasureStartMs = 0.0;
    int measureTempo = (_masterBars.isNotEmpty && currentMeasureIndex < _masterBars.length)
        ? _masterBars[currentMeasureIndex].tempo
        : _tempo;

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
        if (_masterBars.isNotEmpty && currentMeasureIndex < _masterBars.length) {
          measureTempo = _masterBars[currentMeasureIndex].tempo;
        }
      }
    }
    return events;
  }

  Future<void> _startPlayback() async {
    final List<GpBeat> mainBeats = _parsedBeats;
    if (!_isMidiReady || mainBeats.isEmpty) return;

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
        _currentPlayingIndex < mainBeats.length) {
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

    _midiPro.playMidiNote(midi: 12, velocity: 1);
    await Future.delayed(const Duration(milliseconds: 100));
    _midiPro.stopMidiNote(midi: 12);

    if (!mounted || _playbackToken != token || !_isPlaying) return;

    final mainEvents = _buildTrackSchedule(
      trackIndex: _selectedTrackIndex,
      trackBeats: mainBeats,
      measureEnds: _parsedMeasureEnds,
      isMainTrack: true,
      speedMultiplier: _speedMultiplier,
    );

    if (mainEvents.isEmpty) return;

    final double originStartMs = (startIdx < mainEvents.length)
        ? mainEvents[startIdx].startMs
        : 0.0;
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

    for (int tIdx = 0; tIdx < _tracks.length; tIdx++) {
      if (tIdx == _selectedTrackIndex) continue;
      final bTrack = _tracks[tIdx];
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

  void _dispatchBeatEvent(_ScheduledBeatEvent ev, int token) {
    final beat = ev.beat;
    final int tIdx = ev.trackIndex;

    if (ev.isMainTrack && mounted) {
      setState(() => _currentPlayingIndex = ev.beatIndexInTrack);
    }

    final bool shouldPlay = _soloedTracks.isNotEmpty
        ? _soloedTracks.contains(tIdx)
        : !_mutedTracks.contains(tIdx);

    if (!shouldPlay || beat.isRest) return;

    for (final note in beat.notes) {
      if (note.isRest) continue;

      final int pitch = note.pitch != -1
          ? note.pitch
          : ((_standardTuning[note.stringNum] ?? 40) + note.fretNum);

      // Route string output to specific channels to prevent pitch bends from collapsing chords
      int targetChannel = note.stringNum.clamp(0, 15);

      if (note.isTie && _activeSoundingPitches[targetChannel]?.contains(pitch) == true) {
        continue;
      }

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

      _sendRawNoteOn(pitch, velocity, targetChannel);
      _activeSoundingPitches[targetChannel]?.add(pitch);

      // Replaced ++map! to prevent Dart compilation errors on null-asserted r-values
      if (note.bend != null) {
        _bendTokens[targetChannel] = (_bendTokens[targetChannel] ?? 0) + 1;
        final int bendToken = _bendTokens[targetChannel]!;
        _spawnBendLoop(note.bend!, playDurationMs, token, bendToken, targetChannel);
      } else if (note.vibrato != null) {
        _bendTokens[targetChannel] = (_bendTokens[targetChannel] ?? 0) + 1;
        final int bendToken = _bendTokens[targetChannel]!;
        _spawnVibratoLoop(note.vibrato!, playDurationMs, token, bendToken, targetChannel);
      }

      final int delayMs = max(15, playDurationMs.round());
      Future.delayed(Duration(milliseconds: delayMs)).then((_) {
        if (_playbackToken == token && _activeSoundingPitches[targetChannel]?.contains(pitch) == true) {
          _sendRawNoteOff(pitch, targetChannel);
          _activeSoundingPitches[targetChannel]?.remove(pitch);
        }
      });
    }
  }

  void _cleanUpMidiState() {
    for (int channel = 0; channel <= 15; channel++) {
      if (_activeSoundingPitches[channel] != null) {
        for (final p in _activeSoundingPitches[channel]!) {
          _sendRawNoteOff(p, channel);
        }
        _activeSoundingPitches[channel]!.clear();
      }
      _resetPitchBend(channel: channel);
      _bendTokens[channel] = (_bendTokens[channel] ?? 0) + 1; // Instantly aborts any hanging doWhile pitch bend loops
    }
  }

  void _pausePlayback() {
    _playbackToken++;
    _cleanUpMidiState();
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _stopPlayback({bool resetPosition = true}) {
    _playbackToken++;
    _cleanUpMidiState();
    _isPaused = false;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        if (resetPosition) {
          _currentPlayingIndex = -1;
        }
      });
      if (resetPosition && _selectionStart != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentPlayingIndex = _selectionStart);
        });
      }
    }
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
        if (mounted && _parsedBeats.isNotEmpty) {
          setState(() => _currentPlayingIndex = 0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<GpBeat> beats = _parsedBeats;
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
                        icon: const Icon(Icons.close, color: Colors.redAccent),
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
            const Expanded(child: Center(child: CircularProgressIndicator()))
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
              child: beats.isEmpty
                  ? Center(
                      child: Text(
                        _tracks.isNotEmpty
                            ? 'No notes found for "${_tracks[_selectedTrackIndex].name}".'
                            : 'No tracks found in this file.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800, width: 2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.library_music, size: 14, color: Colors.cyanAccent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _tracks.isNotEmpty ? _tracks[_selectedTrackIndex].name : "No Track Selected",
                                        style: const TextStyle(fontSize: 13, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Time Sig: ${_masterBars.isNotEmpty ? '${_masterBars.first.numerator}/${_masterBars.first.denominator}' : 'Auto'}  |  Tempo: $_tempo",
                                      style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text("Bars/Row: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                        GestureDetector(
                                          onTap: () {
                                            if (_measuresPerLine > 1) {
                                              setState(() => _measuresPerLine--);
                                            }
                                          },
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
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InteractiveTabDisplay(
                                sequence: beats,
                                notesPerMeasure: _notesPerMeasure,
                                measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
                                currentPlayingIndex: _currentPlayingIndex,
                                selectionStart: _selectionStart,
                                selectionEnd: _selectionEnd,
                                tuningStr: 'Standard E',
                                onBeatTapped: _onBeatTapped,
                                measureEndIndices: _parsedMeasureEnds,
                                masterBars: _masterBars,
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
                isPlaying: _isPlaying,
                isMidiReady: _isMidiReady,
                isLooping: _loopMode != LoopMode.off,
                hasSequence: beats.isNotEmpty,
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