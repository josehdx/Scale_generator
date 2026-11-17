import 'dart:math';

import 'package:flutter/material.dart';

import '../models/gp_beat.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../services/gpx_parser_service.dart';
import '../services/midi_service.dart';
import '../services/playback_scheduler.dart';
import '../services/recent_files_service.dart';
import '../utils/gp_timeline.dart';
import '../widgets/gpx_viewer/gpx_recent_files_view.dart';
import '../widgets/gpx_viewer/gpx_seek_bar.dart';
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

  /// Empty solo set = everything audible (minus muted tracks).
  Set<int> _soloedTracks = {};
  Set<int> _mutedTracks = {};

  /// Silence appended after the played range / song (in 16th notes). It used to
  /// insert fake rest beats into the track, which shifted every beat index and
  /// bar line after the insertion point; it is now pure scheduling.
  int _endRests = 0;
  double _speedMultiplier = 1.0;

  // The beat list is the track's own list: its identity is stable, so taps no
  // longer rebuild the tab view and reset its scroll position.
  List<GpBeat> get _parsedBeats {
    final GpScore? s = _score;
    if (s == null || s.tracks.isEmpty) return const [];
    return s.tracks[_selectedTrackIndex].beats;
  }

  final MidiService _midiService = MidiService();
  late final PlaybackScheduler _scheduler = PlaybackScheduler(MidiServiceSink(_midiService));
  bool _isMidiReady = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  LoopMode _loopMode = LoopMode.off;
  final ValueNotifier<int> _playingIndexNotifier = ValueNotifier<int>(-1);

  /// Schedules are independent of speed, so they are cached per request.
  final Map<String, GpPlaybackPlan> _planCache = {};

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _measuresPerLine = 3;
  double _fullTotalMs = 0.0;

  @override
  void initState() {
    super.initState();
    _scheduler.isAudible = _isTrackAudible;
    _scheduler.onBeat = (int beat) {
      if (mounted) _playingIndexNotifier.value = beat;
    };
    _scheduler.onFinished = _onPlaybackFinished;
    _initMidi();
    _loadRecentFiles();
  }

  @override
  void dispose() {
    _scheduler.dispose();
    _playingIndexNotifier.dispose();
    super.dispose();
  }

  bool _isTrackAudible(int trackIndex) =>
      _soloedTracks.isNotEmpty ? _soloedTracks.contains(trackIndex) : !_mutedTracks.contains(trackIndex);

  Future<void> _initMidi() async {
    await _midiService.init();
    if (mounted) setState(() => _isMidiReady = _midiService.isReady);
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : null,
    ));
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  Future<void> _loadRecentFiles() async {
    final files = await RecentFilesService.load();
    if (mounted) setState(() => _recentFiles = files);
  }

  Future<void> _openRecentFile(String name, String storedPath) async {
    // Resolve against the current documents folder: stored absolute paths go
    // stale when iOS changes the app container.
    final String? path = await RecentFilesService.resolve(name, storedPath);
    if (path == null) {
      _showMessage('"$name" was not found. It may have been deleted.', error: true);
      final files = await RecentFilesService.remove(_recentFiles, storedPath);
      if (mounted) setState(() => _recentFiles = files);
      return;
    }
    await _processFile(() => GpxParserService.parseGpFile(name, path, null), saveRecent: true);
  }

  Future<void> _pickAndParseGp() async {
    await _processFile(() => GpxParserService.pickAndParse(), saveRecent: true);
  }

  /// The currently open song is only replaced once the new file parsed
  /// successfully; a failed or cancelled load leaves everything as it was.
  Future<void> _processFile(Future<GpScore?> Function() parseAction, {bool saveRecent = false}) async {
    setState(() => _isLoading = true);
    try {
      final GpScore? result = await parseAction();
      if (result == null) return; // picker cancelled
      if (saveRecent) {
        _recentFiles = await RecentFilesService.add(_recentFiles, result.fileName, result.filePath);
      }
      _scheduler.stop();
      _planCache.clear();
      if (!mounted) return;
      setState(() {
        _score = result;
        _fullTotalMs = BarGrid(result.masterBars, result.playOrder).totalMs;
        _selectedTrackIndex = _firstPitchedTrack(result);
        _soloedTracks = {};
        _mutedTracks = {};
        _selectionStart = -1;
        _selectionEnd = -1;
        _tapAnchorIndex = null;
        _isPlaying = false;
        _isPaused = false;
      });
      _playingIndexNotifier.value = -1;
    } catch (e) {
      _showMessage(e is GpParseException ? e.message : 'Could not open the file.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _firstPitchedTrack(GpScore score) {
    for (int i = 0; i < score.tracks.length; i++) {
      if (!score.tracks[i].isPercussion) return i;
    }
    return 0;
  }

  void _closeFile() {
    _stopPlayback(resetPosition: true);
    _planCache.clear();
    setState(() {
      _score = null;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  GpPlaybackPlan _planFor(GpScore score, {required int from, required int to}) {
    final String key = '$_selectedTrackIndex|$from|$to|$_endRests';
    return _planCache.putIfAbsent(
      key,
      () => GpPlaybackPlanner.plan(
        score: score,
        mainTrack: _selectedTrackIndex,
        fromBeat: from,
        toBeat: to,
        tailRestSixteenths: _endRests,
      ),
    );
  }

  Future<void> _startPlayback() async {
    final GpScore? score = _score;
    if (score == null || !_isMidiReady || _parsedBeats.isEmpty) return;

    // Resume exactly where pause stopped (the scheduler remembers the position).
    if (_isPaused) {
      setState(() {
        _isPlaying = true;
        _isPaused = false;
      });
      await _scheduler.resume();
      return;
    }

    final bool hasSelection = _selectionStart != -1 && _selectionEnd != -1;
    final int selMin = hasSelection ? min(_selectionStart, _selectionEnd) : -1;
    final int selMax = hasSelection ? max(_selectionStart, _selectionEnd) : -1;

    int from = -1;
    int to = -1;
    if (hasSelection && (selMin != selMax || _loopMode == LoopMode.selection)) {
      from = selMin; // range (or a single beat looped on its own)
      to = selMax;
    } else if (hasSelection) {
      from = selMin; // single beat: play from there to the end
    }

    final GpPlaybackPlan plan = _planFor(score, from: from, to: to);
    if (plan.events.isEmpty && plan.durationMs <= 0) return;

    setState(() {
      _isPlaying = true;
      _isPaused = false;
    });
    _playingIndexNotifier.value = plan.startBeat;
    _scheduler.speed = _speedMultiplier;
    await _scheduler.start(
      events: plan.events,
      durationMs: plan.durationMs,
      loop: _loopMode != LoopMode.off,
    );
  }

  void _onPlaybackFinished() {
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _isPaused = false;
    });
    _playingIndexNotifier.value = -1;
  }

  void _pausePlayback() {
    _scheduler.pause();
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _stopPlayback({bool resetPosition = false}) {
    _scheduler.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _isPaused = false;
    });
    if (resetPosition) {
      _playingIndexNotifier.value = _selectionStart != -1 ? _selectionStart : -1;
    }
  }

  void _rewind() {
    final bool wasPlaying = _isPlaying;
    _stopPlayback(resetPosition: false);
    _playingIndexNotifier.value = 0;
    if (wasPlaying) _startPlayback();
  }

  void _onBeatTapped(int index) {
    if (!_isPlaying) _scheduler.stop(); // a paused position belongs to the old selection
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
        _selectionStart = min(_tapAnchorIndex!, index);
        _selectionEnd = max(_tapAnchorIndex!, index);
        _tapAnchorIndex = null;
      }
    });
  }

  void _clearSelection() {
    if (!_isPlaying) _scheduler.stop();
    setState(() {
      _isPaused = false;
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
    if (!_isPlaying && _parsedBeats.isNotEmpty) _playingIndexNotifier.value = 0;
  }

  void _cycleLoopMode() {
    setState(() {
      _loopMode = _loopMode == LoopMode.off
          ? LoopMode.all
          : (_loopMode == LoopMode.all ? LoopMode.selection : LoopMode.off);
    });
    _scheduler.loop = _loopMode != LoopMode.off;
  }

  void _onSpeedChanged(double s) {
    final double v = s.clamp(0.1, 2.0).toDouble();
    setState(() => _speedMultiplier = v);
    _scheduler.speed = v; // takes effect immediately, no restart needed
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final beats = _parsedBeats;
    final bool hasFile = _score != null;

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
                if (_isLoading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
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
                          tooltip: 'Tracks',
                          icon: const Icon(Icons.tune, color: Colors.amberAccent),
                          onPressed: _openTrackMenu,
                        ),
                      IconButton(tooltip: 'Close file', icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: _closeFile),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (!hasFile && _isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (!hasFile)
            Expanded(
              child: GpxRecentFilesView(
                recentFiles: _recentFiles,
                onOpen: _openRecentFile,
                onRemove: (path) async {
                  final files = await RecentFilesService.remove(_recentFiles, path);
                  if (mounted) setState(() => _recentFiles = files);
                },
              ),
            )
          else ...[
            Expanded(
              child: beats.isEmpty
                  ? const Center(child: Text('No notes found.', style: TextStyle(color: Colors.grey, fontSize: 13)))
                  : _buildTabPanel(beats),
            ),
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GpxSeekBar(
                    scheduler: _scheduler,
                    idleDurationMs: _fullTotalMs,
                    isPlaying: _isPlaying,
                    // Seeking while stopped behaves like a pause at that position.
                    onSeeked: () {
                      if (!_isPlaying && !_isPaused) setState(() => _isPaused = true);
                    },
                  ),
                  PlaybackControlBar(
                isPlaying: _isPlaying,
                isMidiReady: _isMidiReady,
                isLooping: _loopMode != LoopMode.off,
                hasSequence: beats.isNotEmpty,
                hasSelection: _selectionStart != -1 && _selectionEnd != -1,
                selectionStart: _selectionStart,
                selectionEnd: _selectionEnd,
                onPlay: () => _isPlaying ? _pausePlayback() : _startPlayback(),
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
                onSpeedChanged: _onSpeedChanged,
                endRests: _endRests,
                onEndRestsChanged: (v) {
                  setState(() => _endRests = v.clamp(0, 64).toInt());
                },
              ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openTrackMenu() {
    final GpScore score = _score!;
    showGpxTrackMenu(
      context,
      tracks: score.tracks,
      selectedTrackIndex: _selectedTrackIndex,
      soloedTracks: _soloedTracks,
      mutedTracks: _mutedTracks,
      onSelectTrack: (i) {
        _stopPlayback(resetPosition: true);
        setState(() {
          _selectedTrackIndex = i;
          _selectionStart = -1;
          _selectionEnd = -1;
          _tapAnchorIndex = null;
        });
      },
      onToggleSolo: (i) {
        setState(() {
          if (_soloedTracks.contains(i)) {
            _soloedTracks.remove(i);
          } else {
            _soloedTracks.add(i);
            _mutedTracks.remove(i);
          }
        });
        _scheduler.refreshAudibility();
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
        _scheduler.refreshAudibility();
      },
    );
  }

  Widget _buildTabPanel(List<GpBeat> beats) {
    final GpScore score = _score!;
    final GpTrack track = score.tracks[_selectedTrackIndex];
    final String timeSig = score.masterBars.isNotEmpty
        ? '${score.masterBars.first.numerator}/${score.masterBars.first.denominator}'
        : 'Auto';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Time Signature: $timeSig | Tempo: ${score.tempo}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Bars/Row: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    IconButton(
                      tooltip: 'Fewer bars per row',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.white70),
                      onPressed: _measuresPerLine > 1 ? () => setState(() => _measuresPerLine--) : null,
                    ),
                    Text('$_measuresPerLine', style: const TextStyle(fontSize: 12, color: Colors.white)),
                    IconButton(
                      tooltip: 'More bars per row',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.white70),
                      onPressed: _measuresPerLine < 12 ? () => setState(() => _measuresPerLine++) : null,
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
                notesPerMeasure: score.notesPerMeasure,
                measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
                currentPlayingIndex: -1,
                playingIndexNotifier: _playingIndexNotifier,
                selectionStart: _selectionStart,
                selectionEnd: _selectionEnd,
                tuningStr: 'Standard E',
                onBeatTapped: _onBeatTapped,
                measureEndIndices: track.measureEndIndices,
                masterBars: score.masterBars,
                stringCount: track.stringCount,
                stringLabels: track.isPercussion
                    ? const ['CY', 'HH', 'T', 'SN', 'FT', 'BD']
                    : tuningLabels(track.tuning),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
