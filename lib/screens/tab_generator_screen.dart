import 'dart:async';
import 'dart:math';

import 'dart:ui' show Rect;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gp_beat.dart';
import '../models/lick_preset.dart';
import '../models/motif_token.dart';
import '../models/preset_sanitizer.dart';
import '../scale_engine.dart';
import '../services/midi_service.dart';
import '../services/playback_scheduler.dart';
import '../services/preset_storage_service.dart';
import '../utils/gp_timeline.dart';
import '../utils/tab_sequence_builder.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/playback_control_bar.dart';
import '../widgets/studio/studio_components.dart';
import '../widgets/studio/theory_section.dart';
import '../widgets/studio/pathways_section.dart';
import '../widgets/studio/formatting_section.dart';
import '../widgets/studio/tab_output_section.dart';
import '../widgets/studio/studio_dialogs.dart';
import 'saved_presets_screen.dart';
import 'gpx_tab_screen.dart';

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});
  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class TabGeneratorScreen extends StatefulWidget {
  const TabGeneratorScreen({super.key});

  @override
  State<TabGeneratorScreen> createState() => _TabGeneratorScreenState();
}

/// What the scheduler is currently playing (snapshot, so editing the tab while
/// it plays cannot change what is heard).
class _PlayContext {
  final List<List<int>> seq;
  final List<int> accents;
  final bool isPreview;
  final String? key, scale, tuning;
  const _PlayContext(this.seq, this.accents, this.isPreview, this.key, this.scale, this.tuning);
}

class _TabGeneratorScreenState extends State<TabGeneratorScreen> with WidgetsBindingObserver {
  final ScaleEngine _engine = ScaleEngine();
  final MidiService _midiService = MidiService();
  final PresetStorageService _storage = PresetStorageService();
  late final TabSequenceBuilder _builder;
  late final PlaybackScheduler _scheduler = PlaybackScheduler(MidiServiceSink(_midiService));

  late PageController _pageController;
  int _selectedPageIndex = 0;
  bool _isPlaying = false;
  bool _isPreviewPlaying = false;
  bool _isPreviewLooping = false;
  String? _previewPresetId;
  bool _isMidiReady = false;
  bool _isLooping = false;
  bool _instrumentOverridden = false;
  _PlayContext? _playCtx;
  int _playTempo = 120;

  bool _isFretboardVisible = true;
  bool _useFlats = false;
  bool _isTheoryExpanded = false;
  bool _isPathwaysExpanded = false;
  bool _isFormattingExpanded = false;
  bool _isTabExpanded = true;

  final ScrollController _fretboardScrollController = ScrollController();
  final ValueNotifier<Map<String, dynamic>?> _activeNoteNotifier = ValueNotifier(null);

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _selectedInstrumentIndex = 27;

  // State Values
  String _selectedKey = "C";
  String _selectedScale = "Minor Pentatonic";
  String _selectedTuning = "Standard E";
  int _startFret = 8;

  String _selectedSystem = "Box Position / CAGED";
  int _startString = 6;
  int _endString = 1;
  int _singleStringTarget = 1;
  String _customNpsProfile = "3,4,3,4,3,3";
  final TextEditingController _customNpsController = TextEditingController(text: "3,4,3,4,3,3");
  final TextEditingController _manualTabController = TextEditingController(text: "6:5, 6:8, 5:5, 5:7");
  String _manualSelectedDuration = "16th";

  String _selectedPathway = "Custom Motif Builder";
  String _selectedDirection = "Ascend -> Descend";
  List<MotifToken> _motifTokens = [];
  final TextEditingController _customSequenceController = TextEditingController(text: "1, 2, 3, 4, 5, 6, 7, 8");

  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1;
  int _patternMultiplier = 1;
  int _tempo = 120;
  String _selectedRhythmPattern = "Straight 16ths";
  String _selectedTimeSignature = "Auto";

  final TextEditingController _customRhythmController = TextEditingController(text: "16,16,8");
  final TextEditingController _customAccentController = TextEditingController(text: "1,0,0,0");

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];

  /// Beats of [_currentSequence]. Built once per generation: a new list on every
  /// build made the tab view rebuild and reset its scroll position.
  List<GpBeat> _currentBeats = const [];
  List<LickPreset> _savedPresets = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Custom Notes-Per-String", "Single String Horizontal", "Manual Entry"];
  final List<String> _pathways = ["Straight Linear", "3-Step Triplet", "4-Step 16th", "Note Skipping", "Custom Motif Builder", "Custom Sequence (Indices)"];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way (Ascend)", "One-Way (Descend)"];
  final List<String> _rhythmPatterns = ["Straight 16ths", "Straight 8ths", "Gallop (8-16-16)", "Reverse Gallop (16-16-8)", "Syncopated (16-8-16)", "Custom Pattern"];
  final List<String> _timeSignatures = ["Auto", "2/4", "3/4", "4/4", "5/4", "6/4", "7/4", "9/4", "12/4"];
  final Map<String, int> _guitarSounds = {"Clean Electric": 27, "Steel Acoustic": 25, "Jazz Electric": 26, "Nylon Acoustic": 24};

  int get _dynamicBeatsPerMeasure {
    if (_selectedTimeSignature != "Auto") {
      int? parsed = int.tryParse(_selectedTimeSignature.split('/')[0]);
      if (parsed != null && parsed > 0) return parsed;
    }
    if (_selectedSystem == "Manual Entry") return 4;
    if (_selectedPathway == "3-Step Triplet") return 3;
    if (_selectedPathway == "Custom Motif Builder" && _selectedSystem != "Manual Entry") {
      return _motifTokens.isNotEmpty ? _motifTokens.length : 4;
    }
    if (_selectedPathway == "Custom Sequence (Indices)" && _selectedSystem != "Manual Entry") {
      int count = _customSequenceController.text.split(',').where((e) => e.trim().isNotEmpty).length;
      return count > 0 ? count : 4;
    }
    return 4;
  }

  /// Notes in one bar when the time signature is "Auto" and the pathway defines
  /// a cycle (motif / triplet / index sequence); null otherwise.
  int? get _autoNotes {
    if (_selectedTimeSignature != "Auto" || _selectedSystem == "Manual Entry") return null;
    if (_selectedPathway == "3-Step Triplet") return 3;
    if (_selectedPathway == "Custom Motif Builder") return _motifTokens.isNotEmpty ? _motifTokens.length : null;
    if (_selectedPathway == "Custom Sequence (Indices)") {
      final int n = _customSequenceController.text.split(',').where((e) => e.trim().isNotEmpty).length;
      return n > 0 ? n : null;
    }
    return null;
  }

  /// "4/4", or "10 notes per bar" for a 10-note motif (it used to say "10/4").
  String get _autoTimeSignature {
    final int? n = _autoNotes;
    return n != null ? "$n notes per bar" : "$_dynamicBeatsPerMeasure/4";
  }

  int get _notesPerMeasure => _builder.calculateNotesPerMeasure(
        _selectedTimeSignature, _selectedRhythmPattern,
        customRhythm: _customRhythmController.text, autoNotes: _autoNotes,
      );

  List<String> get _activePattern =>
      _builder.parsePatternString(_selectedRhythmPattern, customRhythmOverride: _customRhythmController.text);

  String get _currentNps => _builder.notesPerSecond(_tempo, _activePattern).toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _builder = TabSequenceBuilder(engine: _engine);
    _pageController = PageController(initialPage: _selectedPageIndex);
    _scheduler.onBeat = _onStudioBeat;
    _scheduler.onFinished = _onStudioFinished;
    _initMidi();
    _loadPresetsFromDisk();

    "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1".split(',').forEach((t) {
      _motifTokens.add(MotifToken(UniqueKey().toString(), t));
    });

    _loadSessionFromDisk();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _storage.flushSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPlayback(notify: false); // setState during dispose throws
    _scheduler.dispose();
    _storage.flushSession();
    _pageController.dispose();
    _fretboardScrollController.dispose();
    _activeNoteNotifier.dispose();
    _customRhythmController.dispose();
    _customAccentController.dispose();
    _customSequenceController.dispose();
    _customNpsController.dispose();
    _manualTabController.dispose();
    super.dispose();
  }

  Future<void> _initMidi() async {
    await _midiService.init();
    if (mounted) {
      setState(() => _isMidiReady = _midiService.isReady);
    }
  }

  void _showMessage(String text, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : null,
      action: action,
    ));
  }

  // --- Interaction Logics ---
  void _onDirectionChanged(String newDir) {
    bool needsSwap = false;
    if (newDir.contains("Ascend") && !newDir.startsWith("Descend")) {
      if (_startString < _endString) needsSwap = true;
    } else if (newDir.contains("Descend") && !newDir.startsWith("Ascend")) {
      if (_startString > _endString) needsSwap = true;
    }

    setState(() {
      _selectedDirection = newDir;
      if (needsSwap) {
        int temp = _startString;
        _startString = _endString;
        _endString = temp;
      }
      _motifTokens = _motifTokens.reversed.toList();
    });
    _generateTab();
  }

  void _swapStrings() {
    setState(() {
      int temp = _startString;
      _startString = _endString;
      _endString = temp;

      if (_startString > _endString) {
        if (_selectedDirection == "One-Way (Descend)") {
          _selectedDirection = "One-Way (Ascend)";
        } else if (_selectedDirection == "Descend -> Ascend") {
          _selectedDirection = "Ascend -> Descend";
        }
      } else if (_startString < _endString) {
        if (_selectedDirection == "One-Way (Ascend)") {
          _selectedDirection = "One-Way (Descend)";
        } else if (_selectedDirection == "Ascend -> Descend") {
          _selectedDirection = "Descend -> Ascend";
        }
      }
      _motifTokens = _motifTokens.reversed.toList();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateTab());
  }

  // --- Storage Operations ---
  Future<void> _loadPresetsFromDisk() async {
    final list = await _storage.loadPresets();
    if (!mounted) return;
    setState(() => _savedPresets = list);
    if (_storage.lastSkippedCount > 0) {
      _showMessage('${_storage.lastSkippedCount} saved preset(s) could not be read and were skipped.', error: true);
    }
  }

  Future<void> _loadSessionFromDisk() async {
    final preset = await _storage.loadSession();
    if (preset != null && mounted) {
      _loadPreset(preset);
    } else {
      _generateTab();
    }
  }

  Future<void> _saveSessionToDisk() async {
    await _storage.saveSession(_createPresetObject("Auto-Save"));
  }

  LickPreset _createPresetObject(String name) {
    _syncAccentPatternToMotif();
    return LickPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      key: _selectedKey, scale: _selectedScale, tuning: _selectedTuning,
      system: _selectedSystem,
      fragment: _selectedSystem == "Single String Horizontal" ? _singleStringTarget.toString() : "$_startString-$_endString",
      customNps: _customNpsProfile,
      startFret: _startFret,
      pathway: _selectedPathway, direction: _selectedDirection,
      motifString: _selectedPathway == "Custom Sequence (Indices)" ? _customSequenceController.text : _motifTokens.map((e) => e.value).join(','),
      rhythm: _selectedRhythmPattern, customRhythmString: _customRhythmController.text,
      customAccentString: _customAccentController.text,
      timeSignature: _selectedTimeSignature, tempo: _tempo,
      measuresPerLine: _measuresPerLine, breakInterval: _breakInterval,
      breakLength: _breakLength, endRests: _endRests,
      manualTabString: _manualTabController.text,
      tabOutput: _generatedTab,
      instrumentIndex: _selectedInstrumentIndex,
      patternMultiplier: _patternMultiplier,
      createdAt: DateTime.now(),
    );
  }

  /// Every dropdown value must exist in its list and every number must be in
  /// range, otherwise one bad preset red-screens the whole studio.
  LickPreset _sanitize(LickPreset p) {
    final LickPreset fields = PresetSanitizer.sanitizeFields(
      p,
      keys: _engine.noteMap.keys.toSet(),
      scales: _engine.scaleFormulas.keys.toSet(),
      tunings: _engine.tunings.keys.toSet(),
      systems: _systems.toSet(),
      pathways: _pathways.toSet(),
      directions: _directions.toSet(),
      timeSignatures: _timeSignatures.toSet(),
      rhythms: _rhythmPatterns.toSet(),
      instrumentIndexes: _guitarSounds.values.toSet(),
    );
    return PresetSanitizer.validateAndSanitize(fields).$1;
  }

  Future<void> _saveCurrentLick() async {
    String? name = await StudioDialogs.showSavePresetDialog(context, "$_selectedKey $_selectedScale Lick");
    if (name != null) {
      setState(() => _savedPresets.insert(0, _createPresetObject(name)));
      await _storage.savePresets(_savedPresets);
      _showMessage('Saved "$name" to Presets');
    }
  }

  void _loadPreset(LickPreset raw) {
    final LickPreset p = _sanitize(raw);
    setState(() {
      _selectedKey = p.key; _selectedScale = p.scale; _selectedTuning = p.tuning;
      _selectedSystem = p.system; _customNpsProfile = p.customNps;
      _customNpsController.text = _customNpsProfile; _startFret = p.startFret;
      _selectedPathway = p.pathway; _selectedDirection = p.direction;

      if (p.system == "Single String Horizontal") {
        _singleStringTarget = int.tryParse(p.fragment) ?? 1;
      } else if (p.fragment.contains('-')) {
        var parts = p.fragment.split('-');
        _startString = int.tryParse(parts[0]) ?? 6;
        _endString = int.tryParse(parts[1]) ?? 1;
      }

      if (p.pathway == "Custom Sequence (Indices)") {
        _customSequenceController.text = p.motifString.isNotEmpty ? p.motifString : p.fragment;
        _motifTokens = [];
      } else {
        _motifTokens = p.motifString.split(',').where((s) => s.isNotEmpty).map((s) => MotifToken(UniqueKey().toString(), s)).toList();
      }

      _selectedRhythmPattern = p.rhythm;
      _customRhythmController.text = p.customRhythmString;
      _customAccentController.text = p.customAccentString;
      _selectedTimeSignature = p.timeSignature; _tempo = p.tempo;
      _measuresPerLine = p.measuresPerLine; _breakInterval = p.breakInterval;
      _patternMultiplier = p.patternMultiplier;
      _breakLength = p.breakLength; _endRests = p.endRests;
      _manualTabController.text = p.manualTabString;

      _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null;
    });
    _changeGuitarSound(p.instrumentIndex); // calls setState itself: keep it outside
    _generateTab();
    if (_selectedPageIndex != 0) _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _importPresets() async {
    try {
      final List<LickPreset>? imported = await _storage.importPresets();
      if (imported == null) return; // cancelled
      setState(() {
        for (var preset in imported) {
          if (!_savedPresets.any((existing) => existing.id == preset.id)) _savedPresets.add(preset);
        }
        _savedPresets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
      await _storage.savePresets(_savedPresets);
      final int skipped = _storage.lastSkippedCount;
      _showMessage(skipped > 0 ? 'Imported ${imported.length} presets ($skipped unreadable skipped).' : 'Imported ${imported.length} presets.');
    } catch (e) {
      _showMessage("Import failed. The file is not a valid preset list.", error: true);
    }
  }

  void _syncAccentPatternToMotif() {
    int expectedBeats = _dynamicBeatsPerMeasure;
    List<String> accents = _customAccentController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    bool isAuto = accents.isEmpty || (accents.first == "1" && accents.skip(1).every((e) => e == "0"));
    if (isAuto || accents.length != expectedBeats) {
      String newAccentStr = List.generate(expectedBeats, (i) => i == 0 ? "1" : "0").join(",");
      if (_customAccentController.text != newAccentStr && isAuto) {
        _customAccentController.text = newAccentStr;
      }
    }
  }

  // --- Tab Generation ---
  void _generateTab({bool stopPlayback = true}) {
    if (stopPlayback) _stopPlayback();

    _syncAccentPatternToMotif();
    LickPreset currentState = _createPresetObject("temp");

    // The builder switches the engine to the preset's tuning itself, so the
    // generated frets always match the tuning that is selected right now.
    List<List<int>> sequence = _builder.buildSequenceForPreset(
      currentState,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
    );

    setState(() {
      _currentSequence = sequence;
      _currentBeats = _builder.sequenceToBeats(sequence);
      if (_selectionEnd >= sequence.length || _selectionStart >= sequence.length) {
        _selectionStart = -1;
        _selectionEnd = -1;
        _tapAnchorIndex = null;
      }
      if (sequence.isEmpty) {
        _generatedTab = "  (No sequence generated. Add notes to begin.)";
        return;
      }

      final int? autoNotes = _autoNotes;
      _generatedTab = _engine.renderAsciiTab(
        _currentSequence,
        notesPerMeasure: _notesPerMeasure,
        rhythmLabel: _selectedRhythmPattern,
        nps: _currentNps,
        measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
        beatsPerMeasure: _dynamicBeatsPerMeasure,
        tempo: _tempo,
        timeSignatureLabel: autoNotes != null ? "$autoNotes notes per bar" : null,
      );
    });
    _saveSessionToDisk();
  }

  // --- Playback ---
  void _changeGuitarSound(int instrumentIndex) async {
    setState(() => _selectedInstrumentIndex = instrumentIndex);
    await _midiService.selectInstrument(instrumentIndex);
    _saveSessionToDisk();
  }

  /// Builds the schedule for [seq] between [startIdx] and [endIdx]. Note
  /// lengths come from the rhythm pattern (or a per-note `(8)` / `(Q)` marker in
  /// manual mode); `beatIndex` is the absolute index in [seq].
  GpPlaybackPlan _studioPlan(
    List<List<int>> seq, int startIdx, int endIdx, int tempo,
    List<String> pattern, List<int> accents, Map<int, int> openStrings,
  ) {
    final List<ScheduledMidiEvent> events = [];
    double t = 0.0;
    for (int i = startIdx; i <= endIdx; i++) {
      final List<int> note = seq[i];
      final double? perNote = note.length > 2 ? TabSequenceBuilder.durationCodeToBeats(note[2]) : null;
      final double beats = perNote ??
          (const {"Quarter": 1.0, "8th": 0.5, "16th": 0.25, "32nd": 0.125}[pattern[i % pattern.length]] ?? 0.25);
      final double dur = max(20.0, (60000.0 / tempo) * beats);

      events.add(ScheduledMidiEvent(
        timeMs: t, type: MidiEventType.marker, channel: 0, data1: 0,
        trackIndex: 0, beatIndex: i, isMainTrack: true, noteId: i,
      ));
      final int? open = note[0] == -1 ? null : openStrings[note[0]];
      if (open != null) {
        final int pitch = (open + note[1]).clamp(0, 127);
        events.add(ScheduledMidiEvent(
          timeMs: t, type: MidiEventType.noteOn, channel: 0, data1: pitch,
          data2: accents[i % accents.length].clamp(1, 127),
          trackIndex: 0, beatIndex: i, isMainTrack: true, noteId: i,
        ));
        events.add(ScheduledMidiEvent(
          timeMs: t + dur, type: MidiEventType.noteOff, channel: 0, data1: pitch,
          trackIndex: 0, beatIndex: i, isMainTrack: true, noteId: i,
        ));
      }
      t += dur;
    }
    events.sort();
    return GpPlaybackPlan(events, t, startIdx);
  }

  Future<void> _playLick({
    List<List<int>>? overrideSequence, int? overrideTempo, String? overrideRhythm,
    String? overrideCustomRhythm, String? overrideAccentPattern, String? overrideTuning,
    String? overrideKey, String? overrideScale, int? overrideInstrument, String? presetId
  }) async {
    if (!_midiService.isReady) return;
    final List<List<int>> seqToPlay = overrideSequence ?? _currentSequence;
    if (seqToPlay.isEmpty) return;

    final bool isPreview = presetId != null;
    _scheduler.stop();

    if (overrideInstrument != null && overrideInstrument != _selectedInstrumentIndex) {
      await _midiService.selectInstrument(overrideInstrument);
      _instrumentOverridden = true;
    }

    final int tempo = (overrideTempo ?? _tempo).clamp(40, 300); // tempo 0 used to end in Infinity.round()
    final Map<int, int> openStrings = _engine.tunings[overrideTuning ?? _selectedTuning] ?? _engine.openStrings;
    final List<String> pattern = _builder.parsePatternString(overrideRhythm ?? _selectedRhythmPattern, customRhythmOverride: overrideCustomRhythm);
    final List<int> accents = _builder.parseAccentPattern(overrideAccentPattern ?? _customAccentController.text);

    int startIdx = 0, endIdx = seqToPlay.length - 1;
    if (!isPreview && _selectionStart != -1 && _selectionEnd != -1) {
      startIdx = _selectionStart.clamp(0, seqToPlay.length - 1);
      endIdx = (max(_selectionStart, _selectionEnd) + _endRests).clamp(startIdx, seqToPlay.length - 1);
    }

    final GpPlaybackPlan plan = _studioPlan(seqToPlay, startIdx, endIdx, tempo, pattern.isEmpty ? const ["16th"] : pattern, accents, openStrings);

    _playCtx = _PlayContext(seqToPlay, accents, isPreview, overrideKey, overrideScale, overrideTuning);
    _playTempo = tempo;
    if (!mounted) return;
    setState(() {
      if (isPreview) {
        _isPreviewPlaying = true;
        _isPlaying = false;
        _previewPresetId = presetId;
      } else {
        _isPlaying = true;
        _isPreviewPlaying = false;
      }
    });
    _scheduler.speed = 1.0;
    await _scheduler.start(
      events: plan.events,
      durationMs: plan.durationMs,
      loop: isPreview ? _isPreviewLooping : _isLooping,
    );
  }

  void _onStudioBeat(int i) {
    final _PlayContext? ctx = _playCtx;
    if (ctx == null || i < 0 || i >= ctx.seq.length) return;
    final List<int> note = ctx.seq[i];
    _activeNoteNotifier.value = {
      'string': note[0], 'fret': note[1], 'isPreview': ctx.isPreview, 'index': i,
      'previewKey': ctx.key, 'previewScale': ctx.scale, 'previewTuning': ctx.tuning,
      'isAccent': ctx.accents[i % ctx.accents.length] == 127,
    };
  }

  void _onStudioFinished() {
    if (!mounted) return;
    _activeNoteNotifier.value = null;
    setState(() {
      _isPlaying = false;
      _isPreviewPlaying = false;
    });
    _restoreInstrument();
  }

  void _restoreInstrument() {
    if (_instrumentOverridden) {
      _instrumentOverridden = false;
      _midiService.selectInstrument(_selectedInstrumentIndex);
    }
  }

  /// [notify] must be false when called from dispose().
  void _stopPlayback({bool notify = true}) {
    _scheduler.stop();
    _activeNoteNotifier.value = null;
    _isPlaying = false;
    _isPreviewPlaying = false;
    if (notify && mounted) setState(() {});
    _restoreInstrument();
  }

  /// Plays a fretboard cell for a moment (not while a lick is playing).
  void _auditionNote(int pitch) {
    if (!_midiService.isReady || _isPlaying || _isPreviewPlaying) return;
    final int key = pitch.clamp(0, 127).toInt();
    _midiService.playNote(key: key, velocity: 100);
    Timer(const Duration(milliseconds: 450), () => _midiService.stopNote(key: key));
  }

  /// iPad share sheets are popovers and need an anchor rectangle.
  Rect _shareOrigin() {
    final Size size = MediaQuery.of(context).size;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  // --- Selection ---
  void _onBeatTapped(int index) {
    setState(() {
      if (_selectionStart == -1 || _selectionStart != _selectionEnd) {
        // nothing selected, or a range: start a new selection
        _selectionStart = index;
        _selectionEnd = index;
        _tapAnchorIndex = index;
      } else {
        // A single note is selected. The anchor is null when that selection
        // came from the cursor arrows, which used to crash on `_tapAnchorIndex!`.
        final int anchor = _tapAnchorIndex ?? _selectionStart;
        _selectionStart = min(anchor, index);
        _selectionEnd = max(anchor, index);
      }
    });
    if (_endRests > 0) _generateTab();
  }

  void _clearSelection() {
    setState(() {
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  /// Second-tap on the red cross: resets resting sections back to zero and
  /// regenerates the tab so the rests disappear from the display.
  void _clearRests() {
    if (_endRests == 0) return;
    setState(() => _endRests = 0);
    _generateTab();
  }

  // --- Manual Handlers ---
  int _tokenAt(int seqIndex) {
    if (seqIndex < 0 || seqIndex >= _currentSequence.length) return -1;
    final List<int> n = _currentSequence[seqIndex];
    return n.length > 3 ? n[3] : -1;
  }

  int _firstIndexOfToken(int token) {
    for (int i = 0; i < _currentSequence.length; i++) {
      if (_tokenAt(i) == token) return i;
    }
    return -1;
  }

  /// Inserts [token] right after the cursor (single selected note), or at the
  /// end when there is no cursor. It used to always append.
  void _insertManualToken(String token) {
    final List<String> tokens = TabSequenceBuilder.manualTokens(_manualTabController.text);
    final bool hasCursor = _selectionStart != -1 && _selectionStart == _selectionEnd;
    int insertAt = tokens.length;
    if (hasCursor) {
      final int t = _tokenAt(_selectionEnd);
      if (t != -1) insertAt = min(t + 1, tokens.length);
    }
    tokens.insert(insertAt, token);
    _manualTabController.text = tokens.join(', ');
    _generateTab();
    if (hasCursor) {
      final int idx = _firstIndexOfToken(insertAt);
      if (idx != -1) {
        setState(() {
          _selectionStart = idx;
          _selectionEnd = idx;
          _tapAnchorIndex = null;
        });
      }
    }
  }

  void _handleFretboardTap(String? newKey, int str, int fret) {
    if (_selectedSystem != "Manual Entry") return;
    String newNote = "$str:$fret";
    // "6:5(8)" is understood by parseManualTab (it used to be dropped silently).
    if (_manualSelectedDuration == "8th" || _manualSelectedDuration == "Quarter") {
      newNote = "$newNote(${_manualSelectedDuration.substring(0, 1)})";
    }
    _insertManualToken(newNote);
  }

  void _moveCursor(int delta) {
    if (_currentSequence.isEmpty) return;
    setState(() {
      if (_selectionStart == -1) {
        _selectionStart = delta < 0 ? _currentSequence.length - 1 : 0;
      } else {
        _selectionStart = (_selectionStart + delta).clamp(0, _currentSequence.length - 1);
      }
      _selectionEnd = _selectionStart;
      _tapAnchorIndex = null;
    });
  }

  void _showManualDeleteMenu() async {
    final result = await StudioDialogs.showManualDeleteMenu(context, hasSelection: _selectionStart != -1 && _selectionEnd != -1);
    if (result == null) return;

    final String before = _manualTabController.text;
    final List<String> tokens = TabSequenceBuilder.manualTokens(before);
    if (tokens.isEmpty) return;

    String message = '';
    if (result['action'] == 'clear') {
      _manualTabController.clear();
      message = 'Tab cleared';
    } else if (result['action'] == 'delete_selection') {
      // Selection indexes belong to the EXPANDED sequence (chords, repeats,
      // breaks); map them back to the tokens they came from.
      final int s = min(_selectionStart, _selectionEnd);
      final int e = max(_selectionStart, _selectionEnd);
      final Set<int> remove = {for (int i = s; i <= e; i++) if (_tokenAt(i) != -1) _tokenAt(i)};
      if (remove.isEmpty) {
        _showMessage('The selection contains no editable notes.');
        return;
      }
      final List<int> desc = remove.toList()..sort((a, b) => b.compareTo(a));
      for (final int t in desc) {
        if (t < tokens.length) tokens.removeAt(t);
      }
      _manualTabController.text = tokens.join(', ');
      _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null;
      message = 'Deleted ${remove.length} note(s)';
    } else if (result['action'] == 'backspace') {
      final int count = min((result['count'] as int?) ?? 1, tokens.length);
      tokens.removeRange(tokens.length - count, tokens.length);
      _manualTabController.text = tokens.join(', ');
      message = 'Deleted $count note(s)';
    }
    _generateTab();
    _showMessage(message, action: SnackBarAction(
      label: 'UNDO',
      onPressed: () {
        _manualTabController.text = before;
        _generateTab();
      },
    ));
  }

  // --- Build ---
  @override
  Widget build(BuildContext context) {
    final String instrumentKey = _guitarSounds.entries
        .firstWhere((e) => e.value == _selectedInstrumentIndex, orElse: () => _guitarSounds.entries.first)
        .key;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Tab Generator Studio'),
        actions: [ IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save Lick Preset', onPressed: _saveCurrentLick) ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          // scrolls horizontally instead of overflowing with large system text
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(label: const Text("Main Studio"), selected: _selectedPageIndex == 0, onSelected: (s) { if (s) { _stopPlayback(); _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); } }),
              const SizedBox(width: 16),
              ChoiceChip(label: const Text("Saved Presets"), selected: _selectedPageIndex == 1, onSelected: (s) { if (s) { _stopPlayback(); _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); } }),
              const SizedBox(width: 16),
              ChoiceChip(label: const Text("GP Viewer"), selected: _selectedPageIndex == 2, onSelected: (s) { if (s) { _stopPlayback(); _pageController.animateToPage(2, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); } }),
            ],
          ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        // Pages are switched with the chips above. Swiping fought with the
        // horizontally scrolling tab views.
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _selectedPageIndex = index);
          if (index != 0 && _isPlaying) _stopPlayback();
          if (index == 2 && _isPreviewPlaying) _stopPlayback();
        },
        children: [
          KeepAliveWrapper(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Interactive Fretboard", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const Spacer(),
                      Tooltip(
                        message: 'Show notes as sharps or flats',
                        child: ChoiceChip(
                          label: Text(_useFlats ? '\u266D flats' : '\u266F sharps', style: const TextStyle(fontSize: 12)),
                          selected: _useFlats,
                          onSelected: (v) => setState(() => _useFlats = v),
                        ),
                      ),
                      IconButton(
                        tooltip: _isFretboardVisible ? 'Hide fretboard' : 'Show fretboard',
                        onPressed: () => setState(() => _isFretboardVisible = !_isFretboardVisible),
                        icon: Icon(_isFretboardVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey, size: 24),
                      ),
                    ],
                  ),
                ),
                if (_isFretboardVisible)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: InteractiveFretboard(
                      engine: _engine,
                      selectedKey: _selectedKey,
                      selectedScale: _selectedScale,
                      startFret: _startFret,
                      selectedTuning: _selectedTuning,
                      activeNoteNotifier: _activeNoteNotifier,
                      isManualMode: _selectedSystem == "Manual Entry",
                      scrollController: _fretboardScrollController,
                      onNoteTapped: _handleFretboardTap,
                      onPlayNote: _auditionNote,
                      useFlats: _useFlats,
                    ),
                  ),
                const SizedBox(height: 8),
                PlaybackControlBar(
                  isPlaying: _isPlaying,
                  isMidiReady: _isMidiReady,
                  isLooping: _isLooping,
                  hasSequence: _currentSequence.isNotEmpty,
                  hasSelection: _selectionStart != -1 && _selectionEnd != -1,
                  selectionStart: _selectionStart,
                  selectionEnd: _selectionEnd,
                  endRests: _endRests,
                  onEndRestsChanged: (v) {
                    setState(() => _endRests = v.clamp(0, 64).toInt());
                    _generateTab();
                  },
                  onPlay: _playLick,
                  onStop: _stopPlayback,
                  onToggleLoop: () {
                    setState(() => _isLooping = !_isLooping);
                    if (_isPlaying) _scheduler.loop = _isLooping;
                  },
                  onSave: _saveCurrentLick,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: _generatedTab));
                    _showMessage('Tab copied to clipboard');
                  },
                  onClearSelection: _clearSelection,
                  onClearRests: _clearRests,
                  hasRests: _endRests > 0,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        CollapsibleSection(
                          title: "  1. Theory & System",
                          isExpanded: _isTheoryExpanded,
                          onToggle: () => setState(() => _isTheoryExpanded = !_isTheoryExpanded),
                          child: TheorySection(
                            isManualMode: _selectedSystem == "Manual Entry",
                            manualSelectedDuration: _manualSelectedDuration, selectedKey: _selectedKey, availableKeys: _engine.noteMap.keys.toList(),
                            selectedScale: _selectedScale, availableScales: _engine.scaleFormulas.keys.toList(), selectedTuning: _selectedTuning, availableTunings: _engine.tunings.keys.toList(),
                            selectedSystem: _selectedSystem, availableSystems: _systems, singleStringTarget: _singleStringTarget, startString: _startString,
                            endString: _endString, startFret: _startFret, customNpsController: _customNpsController,
                            onCursorLeft: () => _moveCursor(-1),
                            onCursorRight: () => _moveCursor(1),
                            onInsertRest: () => _insertManualToken("r"),
                            onDeleteMenu: _showManualDeleteMenu,
                            onManualDurationChanged: (v) => setState(() => _manualSelectedDuration = v ?? "16th"),
                            onKeyChanged: (v) { setState(() => _selectedKey = v!); _generateTab(); },
                            onScaleChanged: (v) { setState(() => _selectedScale = v!); _generateTab(); },
                            onTuningChanged: (v) { setState(() => _selectedTuning = v!); _generateTab(); },
                            onSystemChanged: (v) { setState(() { _selectedSystem = v!; if (v == "Manual Entry") { _isFretboardVisible = true; _isTabExpanded = true; } _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null; }); _generateTab(); },
                            onSingleStringTargetChanged: (v) { setState(() => _singleStringTarget = int.parse(v!)); _generateTab(); },
                            onStartStringChanged: (v) { setState(() => _startString = int.parse(v!)); _generateTab(); },
                            onEndStringChanged: (v) { setState(() => _endString = int.parse(v!)); _generateTab(); },
                            onSwapStrings: _swapStrings,
                            onCustomNpsChanged: (v) { _customNpsProfile = v; _generateTab(); },
                            onStartFretChanged: (v) { setState(() => _startFret = v.clamp(0, 24).toInt()); _generateTab(); },
                          ),
                        ),
                        if (_selectedSystem != "Manual Entry")
                          CollapsibleSection(
                            title: "  2. Pathways & Motifs",
                            isExpanded: _isPathwaysExpanded,
                            onToggle: () => setState(() => _isPathwaysExpanded = !_isPathwaysExpanded),
                            child: PathwaysSection(
                              selectedPathway: _selectedPathway, availablePathways: _pathways, selectedDirection: _selectedDirection, availableDirections: _directions,
                              selectedSystem: _selectedSystem, motifTokens: _motifTokens, customSequenceController: _customSequenceController,
                              onPathwayChanged: (v) { setState(() => _selectedPathway = v!); _generateTab(); },
                              onDirectionChanged: (v) => _onDirectionChanged(v!),
                              onMotifAdded: (n) { setState(() => _motifTokens.add(MotifToken(UniqueKey().toString(), n))); _generateTab(); },
                              onMotifRemoved: (i) { setState(() => _motifTokens.removeAt(i)); _generateTab(); },
                              onMotifReordered: (o, n) { setState(() { if(o<n)n--; _motifTokens.insert(n, _motifTokens.removeAt(o)); }); _generateTab(); },
                              onClearMotifs: () {
                                final saved = List<MotifToken>.of(_motifTokens);
                                setState(() => _motifTokens.clear());
                                _generateTab();
                                _showMessage('Motif cleared', action: SnackBarAction(label: 'UNDO', onPressed: () {
                                  setState(() => _motifTokens = saved);
                                  _generateTab();
                                }));
                              },
                              onCustomSequenceChanged: (_) => _generateTab(),
                            ),
                          ),
                        CollapsibleSection(
                          title: _selectedSystem == "Manual Entry" ? "  2. Formatting & Rhythm" : "  3. Formatting & Rhythm",
                          isExpanded: _isFormattingExpanded,
                          onToggle: () => setState(() => _isFormattingExpanded = !_isFormattingExpanded),
                          child: FormattingSection(
                            selectedRhythmPattern: _selectedRhythmPattern, availableRhythmPatterns: _rhythmPatterns,
                            selectedTimeSignature: _selectedTimeSignature, availableTimeSignatures: _timeSignatures,
                            tempo: _tempo, measuresPerLine: _measuresPerLine, patternMultiplier: _patternMultiplier, currentNps: _currentNps,
                            customRhythmController: _customRhythmController, customAccentController: _customAccentController,
                            selectedInstrumentKey: instrumentKey, availableInstruments: _guitarSounds.keys.toList(),
                            breakInterval: _breakInterval, breakLength: _breakLength, endRests: _endRests,
                            onRhythmChanged: (v) { bool w = _isPlaying; setState(() => _selectedRhythmPattern = v!); _generateTab(); if (w) _playLick(); },
                            onTimeSignatureChanged: (v) { bool w = _isPlaying; setState(() => _selectedTimeSignature = v!); _generateTab(); if (w) _playLick(); },
                            onTempoChanged: (v) {
                              setState(() => _tempo = v.clamp(40, 300).toInt());
                              // Tempo does not change the notes: keep playing and just scale
                              // the clock. (Re-starting playback on every stepper tick raced.)
                              _generateTab(stopPlayback: false);
                              if (_isPlaying) _scheduler.speed = _tempo / _playTempo;
                            },
                            onMeasuresChanged: (v) { setState(() => _measuresPerLine = v.clamp(0, 16).toInt()); _generateTab(); },
                            onPatternMultiplierChanged: (v) { setState(() => _patternMultiplier = v.clamp(1, 32).toInt()); _generateTab(); },
                            onCustomRhythmChanged: (_) => _generateTab(), onCustomAccentChanged: (_) => _generateTab(),
                            onInstrumentChanged: (v) { if (v != null && _guitarSounds.containsKey(v)) _changeGuitarSound(_guitarSounds[v]!); },
                            onBreakIntervalChanged: (v) { setState(() => _breakInterval = v.clamp(0, 64).toInt()); _generateTab(); },
                            onBreakLengthChanged: (v) { setState(() => _breakLength = v.clamp(0, 32).toInt()); _generateTab(); },
                            onEndRestsChanged: (v) { setState(() => _endRests = v.clamp(0, 64).toInt()); _generateTab(); },
                          ),
                        ),
                        CollapsibleSection(
                          title: _selectedSystem == "Manual Entry" ? "  3. Generated Tab" : "  4. Generated Tab",
                          isExpanded: _isTabExpanded,
                          onToggle: () => setState(() => _isTabExpanded = !_isTabExpanded),
                          child: TabOutputSection(
                            currentSequence: _currentBeats,
                            generatedTab: _generatedTab, autoTimeSignature: _autoTimeSignature,
                            activeNoteNotifier: _activeNoteNotifier, notesPerMeasure: _notesPerMeasure,
                            rhythmStr: _activePattern.isNotEmpty ? _activePattern.first : "16th", measuresPerLine: _measuresPerLine,
                            selectionStart: _selectionStart, selectionEnd: _selectionEnd, selectedTuning: _selectedTuning,
                            onBeatTapped: _onBeatTapped,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SavedPresetsScreen(
            savedPresets: _savedPresets, activePreviewId: _previewPresetId,
            isPreviewPlaying: _isPreviewPlaying, isPreviewLooping: _isPreviewLooping,
            onPlayPreview: (p) {
              final LickPreset healed = _sanitize(p);
              _playLick(
                overrideSequence: _builder.buildSequenceForPreset(healed), overrideTempo: healed.tempo, overrideRhythm: healed.rhythm,
                overrideCustomRhythm: healed.customRhythmString, overrideAccentPattern: healed.customAccentString, overrideTuning: healed.tuning,
                overrideKey: healed.key, overrideScale: healed.scale, overrideInstrument: healed.instrumentIndex, presetId: healed.id,
              );
              // The preview generated its notes in the preset's tuning; put the
              // engine back to the studio's tuning for the fretboard.
              _engine.setTuning(_selectedTuning);
            },
            onStopPreview: _stopPlayback,
            onTogglePreviewLoop: () {
              setState(() => _isPreviewLooping = !_isPreviewLooping);
              if (_isPreviewPlaying) _scheduler.loop = _isPreviewLooping;
            },
            onLoadPreset: _loadPreset,
            onDeletePresets: (ids) async {
              setState(() { _savedPresets.removeWhere((p) => ids.contains(p.id)); if (ids.contains(_previewPresetId)) { _stopPlayback(); _previewPresetId = null; } });
              await _storage.savePresets(_savedPresets);
            },
            onRenamePreset: (id, name) async {
              var i = _savedPresets.indexWhere((p) => p.id == id);
              if (i != -1) {
                setState(() => _savedPresets[i] = _savedPresets[i].copyWith(name: name));
                await _storage.savePresets(_savedPresets);
              }
            },
            onExportPresets: (list) => _storage.exportPresets(list, sharePositionOrigin: _shareOrigin()),
            onReorderPresets: (o, n) async { setState(() { if(n>o)n--; _savedPresets.insert(n, _savedPresets.removeAt(o)); }); await _storage.savePresets(_savedPresets); },
            onImport: _importPresets
          ),
          GpxTabScreen(),
        ],
      ),
    );
  }
}
