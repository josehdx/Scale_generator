import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lick_preset.dart';
import '../models/motif_token.dart';
import '../models/preset_sanitizer.dart';
import '../scale_engine.dart';
import '../services/midi_service.dart';
import '../services/preset_storage_service.dart';
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

class _TabGeneratorScreenState extends State<TabGeneratorScreen> {
  final ScaleEngine _engine = ScaleEngine();
  final MidiService _midiService = MidiService();
  final PresetStorageService _storage = PresetStorageService();
  late final TabSequenceBuilder _builder;
  late PageController _pageController;

  int _selectedPageIndex = 0;
  bool _isPlaying = false;
  bool _isPreviewPlaying = false;
  bool _isPreviewLooping = false;
  String? _previewPresetId;
  int _playbackToken = 0;
  bool _isMidiReady = false;
  bool _isLooping = false;

  bool _isFretboardVisible = true;
  bool _isTheoryExpanded = false;
  bool _isPathwaysExpanded = false;
  bool _isFormattingExpanded = false;
  bool _isTabExpanded = true;

  final Set<int> _activeMidiNotes = {};
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
  int _tempo = 120;
  String _selectedRhythmPattern = "Straight 16ths";
  String _selectedTimeSignature = "Auto";
  final TextEditingController _customRhythmController = TextEditingController(text: "16,16,8");
  final TextEditingController _customAccentController = TextEditingController(text: "1,0,0,0");

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];
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

  String get _autoTimeSignature => "$_dynamicBeatsPerMeasure/4";

  String get _currentNps {
    List<String> parsedRhythm = _builder.parsePatternString(_selectedRhythmPattern, customRhythmOverride: _customRhythmController.text);
    double maxMultiplier = 1.0;
    for (String rhythm in parsedRhythm) {
      double mult = {"Quarter": 1.0, "8th": 2.0, "16th": 4.0, "32nd": 8.0}[rhythm] ?? 4.0;
      if (mult > maxMultiplier) maxMultiplier = mult;
    }
    double nps = (_tempo / 60) * maxMultiplier;
    return nps.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _builder = TabSequenceBuilder(engine: _engine);
    _pageController = PageController(initialPage: _selectedPageIndex);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initMidi();
    });
    
    _loadPresetsFromDisk();
    
    "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1".split(',').forEach((t) {
      _motifTokens.add(MotifToken(UniqueKey().toString(), t));
    });
    
    _loadSessionFromDisk();
  }

  @override
  void dispose() {
    _stopPlayback();
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
    final success = await _midiService.init();
    if (mounted) {
      setState(() => _isMidiReady = success);
    }
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
    if (mounted) setState(() => _savedPresets = list);
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
      createdAt: DateTime.now(),
    );
  }

  Future<void> _saveCurrentLick() async {
    String? name = await StudioDialogs.showSavePresetDialog(context, "${_selectedKey} ${_selectedScale} Lick");
    if (name != null) {
      setState(() => _savedPresets.insert(0, _createPresetObject(name)));
      await _storage.savePresets(_savedPresets);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name" to Presets'), backgroundColor: Colors.green));
    }
  }

  void _loadPreset(LickPreset p) {
    setState(() {
      _selectedKey = p.key; _selectedScale = p.scale; _selectedTuning = p.tuning;
      _selectedSystem = p.system; _customNpsProfile = p.customNps ?? "3,4,3,4,3,3";
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
        _customSequenceController.text = (p.motifString != null && p.motifString.isNotEmpty) ? p.motifString : p.fragment;
        _motifTokens = [];
      } else {
        _motifTokens = (p.motifString ?? "").split(',').where((s) => s.isNotEmpty).map((s) => MotifToken(UniqueKey().toString(), s)).toList();
      }
      
      _selectedRhythmPattern = _rhythmPatterns.contains(p.rhythm) ? p.rhythm : "Straight 16ths";
      _customRhythmController.text = p.customRhythmString ?? "";
      _customAccentController.text = p.customAccentString ?? "";
      _selectedTimeSignature = p.timeSignature; _tempo = p.tempo;
      _measuresPerLine = p.measuresPerLine; _breakInterval = p.breakInterval;
      _breakLength = p.breakLength; _endRests = p.endRests;
      _manualTabController.text = p.manualTabString;
      
      if (p.instrumentIndex != null) _changeGuitarSound(p.instrumentIndex!);
      _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null;
    });
    _generateTab();
    if (_selectedPageIndex != 0) _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _importPresets() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json', 'txt'],
      );
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        File file = File(result.files.first.path!);
        String jsonString = await file.readAsString();
        final List<dynamic> decodedList = jsonDecode(jsonString);
        final List<LickPreset> importedPresets = decodedList.map((e) => LickPreset.fromJson(e)).toList();
        setState(() {
          for (var preset in importedPresets) {
            if (!_savedPresets.any((existing) => existing.id == preset.id)) _savedPresets.add(preset);
          }
          _savedPresets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
        _storage.savePresets(_savedPresets);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imported successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import failed. Check format."), backgroundColor: Colors.redAccent));
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

  void _generateTab() {
    _stopPlayback();
    
    _syncAccentPatternToMotif();
    LickPreset currentState = _createPresetObject("temp");
    List<List<int>> sequence = _builder.buildSequenceForPreset(
      currentState,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
    );
    setState(() {
      _currentSequence = sequence;
      if (sequence.isEmpty) {
        _generatedTab = "  (No sequence generated. Add notes to begin.)";
        return;
      }
      int notesPerMeasure = _builder.calculateNotesPerMeasure(_selectedTimeSignature, _selectedRhythmPattern, customRhythm: _customRhythmController.text);
      int beatsPerMeasure = _dynamicBeatsPerMeasure;
      
      _generatedTab = _engine.renderAsciiTab(
        _currentSequence,
        notesPerMeasure: notesPerMeasure,
        rhythmLabel: _selectedRhythmPattern,
        nps: _builder.parsePatternString(_selectedRhythmPattern, customRhythmOverride: _customRhythmController.text).map((e) => e=="8th"?"2":"4").first,
        measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
        beatsPerMeasure: beatsPerMeasure,
        tempo: _tempo,
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

  void _playLick({
    List<List<int>>? overrideSequence, int? overrideTempo, String? overrideRhythm, 
    String? overrideCustomRhythm, String? overrideAccentPattern, String? overrideTuning, 
    String? overrideKey, String? overrideScale, int? overrideInstrument, String? presetId
  }) async {
    if (!_midiService.isReady) return;
    List<List<int>> seqToPlay = overrideSequence ?? _currentSequence;
    if (seqToPlay.isEmpty) return;
    
    _stopPlayback();
    _playbackToken++;
    final int currentToken = _playbackToken;
    bool isPreview = presetId != null;
    
    if (overrideInstrument != null && overrideInstrument != _selectedInstrumentIndex) {
      await _midiService.selectInstrument(overrideInstrument);
    }
    
    setState(() {
      if (isPreview) { _isPreviewPlaying = true; _previewPresetId = presetId; } 
      else { _isPlaying = true; }
    });
    
    _midiService.playNote(key: 12, velocity: 1);
    await Future.delayed(const Duration(milliseconds: 150));
    _midiService.stopNote(key: 12);
    
    int tempo = overrideTempo ?? _tempo;
    Map<int, int> activeOpenStrings = _engine.tunings[overrideTuning ?? _selectedTuning] ?? _engine.openStrings;
    List<String> activePattern = _builder.parsePatternString(overrideRhythm ?? _selectedRhythmPattern, customRhythmOverride: overrideCustomRhythm);
    List<int> activeAccents = _builder.parseAccentPattern(overrideAccentPattern ?? _customAccentController.text);
    
    int startIdx = 0, endIdx = seqToPlay.length - 1;
    if (!isPreview && _selectionStart != -1 && _selectionEnd != -1) {
      startIdx = _selectionStart.clamp(0, seqToPlay.length - 1);
      endIdx = (max(_selectionStart, _selectionEnd) + _endRests).clamp(startIdx, seqToPlay.length - 1);
    }
    
    do {
      for (int i = startIdx; i <= endIdx; i++) {
        if (!mounted || _playbackToken != currentToken || (isPreview && !_isPreviewPlaying) || (!isPreview && !_isPlaying)) {
            _stopPlayback();
            return;
        }
        
        var note = seqToPlay[i];
        int pitch = -1;
        int currentVelocity = activeAccents[i % activeAccents.length];
        
        if (note[0] != -1) {
          pitch = activeOpenStrings[note[0]]! + note[1];
          _midiService.playNote(key: pitch, velocity: currentVelocity);
          _activeMidiNotes.add(pitch);
        }
        
        _activeNoteNotifier.value = {
          'string': note[0], 'fret': note[1], 'isPreview': isPreview, 'index': i,
          'previewKey': overrideKey, 'previewScale': overrideScale, 'previewTuning': overrideTuning,
          'isAccent': currentVelocity == 127,
        };
        
        String currentRhythm = activePattern[i % activePattern.length];
        double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[currentRhythm] ?? 0.25;
        
        int msDelay = max(20, ((60000 / tempo) * beatMultiplier).round());
        await Future.delayed(Duration(milliseconds: msDelay));
        
        if (_playbackToken != currentToken) return;
        if (pitch != -1) {
          _midiService.stopNote(key: pitch);
          _activeMidiNotes.remove(pitch);
        }
      }
    } while ((isPreview ? _isPreviewLooping : _isLooping) && mounted && _playbackToken == currentToken && ((isPreview && _isPreviewPlaying) || (!isPreview && _isPlaying)));
    
    if (_playbackToken == currentToken) _stopPlayback();
  }

  void _stopPlayback() {
    _playbackToken++;
    for (int pitch in _activeMidiNotes) {
      _midiService.stopNote(key: pitch);
    }
    _activeMidiNotes.clear();
    _activeNoteNotifier.value = null;
    if (mounted) setState(() { _isPlaying = false; _isPreviewPlaying = false; });
    _midiService.selectInstrument(_selectedInstrumentIndex);
  }

  // --- Manual Handlers ---

  void _handleFretboardTap(String? newKey, int str, int fret) {
    if (_selectedSystem == "Manual Entry") {
      String newNote = "$str:$fret";
      if (_manualSelectedDuration == "8th" || _manualSelectedDuration == "Quarter") {
         newNote = "$newNote(${_manualSelectedDuration.substring(0, 1)})";
      }
      String text = _manualTabController.text.trim();
      _manualTabController.text = text.isEmpty ? newNote : "$text, $newNote";
      _generateTab();
    }
  }

  void _showManualDeleteMenu() async {
    final result = await StudioDialogs.showManualDeleteMenu(context, hasSelection: _selectionStart != -1 && _selectionEnd != -1);
    if (result == null) return;
    
    List<String> notes = _manualTabController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (notes.isEmpty) return;

    if (result['action'] == 'clear') {
      _manualTabController.clear();
    } else if (result['action'] == 'delete_selection') {
       int s = min(_selectionStart, _selectionEnd);
       int e = max(_selectionStart, _selectionEnd);
       notes.removeRange(s, e + 1);
       _manualTabController.text = notes.join(', ');
       _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null;
    } else if (result['action'] == 'backspace') {
       int count = min(result['count'] as int, notes.length);
       notes.removeRange(notes.length - count, notes.length);
       _manualTabController.text = notes.join(', ');
    }
    _generateTab();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Tab Generator Studio'),
        actions: [ IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save Lick Preset', onPressed: _saveCurrentLick) ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedPageIndex = index);
          if (index != 0 && _isPlaying) _stopPlayback();
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
                      GestureDetector(onTap: () => setState(() => _isFretboardVisible = !_isFretboardVisible), child: Icon(_isFretboardVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey, size: 24)),
                    ],
                  ),
                ),
                if (_isFretboardVisible)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ValueListenableBuilder<Map<String, dynamic>?>(
                      valueListenable: _activeNoteNotifier,
                      builder: (context, noteData, child) {
                        return InteractiveFretboard(
                          engine: _engine, selectedKey: _selectedKey, selectedScale: _selectedScale, startFret: _startFret, 
                          selectedTuning: _selectedTuning,
                          activeString: (noteData != null && !(noteData['isPreview'] as bool)) ? noteData['string'] : null,
                          activeFret: (noteData != null && !(noteData['isPreview'] as bool)) ? noteData['fret'] : null,
                          previewString: (noteData != null && noteData['isPreview'] as bool) ? noteData['string'] : null,
                          previewFret: (noteData != null && noteData['isPreview'] as bool) ? noteData['fret'] : null,
                          isAccent: noteData?['isAccent'],
                          isManualMode: _selectedSystem == "Manual Entry",
                          scrollController: _fretboardScrollController, 
                          onNoteTapped: _handleFretboardTap,
                        );
                      },
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
                    setState(() => _endRests = v);
                    _generateTab();
                  },
                  onPlay: _playLick,
                  onStop: _stopPlayback,
                  onToggleLoop: () => setState(() => _isLooping = !_isLooping),
                  onSave: _saveCurrentLick,
                  onCopy: () => Clipboard.setData(ClipboardData(text: _generatedTab)),
                  onClearSelection: () => setState(() {
                    _selectionStart = -1;
                    _selectionEnd = -1;
                    _tapAnchorIndex = null;
                  }),
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
                            onCursorLeft: () => setState(() { _selectionStart = max(0, (_selectionStart == -1 ? _currentSequence.length : _selectionStart) - 1); _selectionEnd = _selectionStart; }),
                            onCursorRight: () => setState(() { if (_selectionStart != -1) { _selectionStart = min(_currentSequence.length - 1, _selectionStart + 1); _selectionEnd = _selectionStart; } }),
                            onInsertRest: () { _manualTabController.text += ", r"; _generateTab(); },
                            onDeleteMenu: _showManualDeleteMenu,
                            onManualDurationChanged: (v) => setState(() => _manualSelectedDuration = v!),
                            onKeyChanged: (v) { setState(() => _selectedKey = v!); _generateTab(); },
                            onScaleChanged: (v) { setState(() => _selectedScale = v!); _generateTab(); },
                            onTuningChanged: (v) { setState(() => _selectedTuning = v!); _generateTab(); },
                            onSystemChanged: (v) { setState(() { _selectedSystem = v!; if (v == "Manual Entry") { _isFretboardVisible = true; _isTabExpanded = true; } _selectionStart = -1; _selectionEnd = -1; }); _generateTab(); },
                            onSingleStringTargetChanged: (v) { setState(() => _singleStringTarget = int.parse(v!)); _generateTab(); },
                            onStartStringChanged: (v) { setState(() => _startString = int.parse(v!)); _generateTab(); },
                            onEndStringChanged: (v) { setState(() => _endString = int.parse(v!)); _generateTab(); },
                            onSwapStrings: _swapStrings,
                            onCustomNpsChanged: (v) { _customNpsProfile = v; _generateTab(); },
                            onStartFretChanged: (v) { setState(() => _startFret = v); _generateTab(); },
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
                              onClearMotifs: () { setState(() => _motifTokens.clear()); _generateTab(); },
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
                            tempo: _tempo, measuresPerLine: _measuresPerLine, currentNps: _currentNps,
                            customRhythmController: _customRhythmController, customAccentController: _customAccentController,
                            selectedInstrumentKey: _guitarSounds.keys.firstWhere((k) => _guitarSounds[k] == _selectedInstrumentIndex), availableInstruments: _guitarSounds.keys.toList(),
                            breakInterval: _breakInterval, breakLength: _breakLength, endRests: _endRests,
                            onRhythmChanged: (v) { bool w = _isPlaying; setState(() => _selectedRhythmPattern = v!); _generateTab(); if(w)_playLick(); },
                            onTimeSignatureChanged: (v) { bool w = _isPlaying; setState(() => _selectedTimeSignature = v!); _generateTab(); if(w)_playLick(); },
                            onTempoChanged: (v) { bool w = _isPlaying; setState(() => _tempo = v.clamp(40, 300)); _generateTab(); if(w)_playLick(); },
                            onMeasuresChanged: (v) { setState(() => _measuresPerLine = v); _generateTab(); },
                            onCustomRhythmChanged: (_) => _generateTab(), onCustomAccentChanged: (_) => _generateTab(),
                            onInstrumentChanged: (v) { if (v != null) _changeGuitarSound(_guitarSounds[v]!); },
                            onBreakIntervalChanged: (v) { setState(() => _breakInterval = v); _generateTab(); },
                            onBreakLengthChanged: (v) { setState(() => _breakLength = v); _generateTab(); },
                            onEndRestsChanged: (v) { setState(() => _endRests = v); _generateTab(); },
                          ),
                        ),
                        CollapsibleSection(
                          title: _selectedSystem == "Manual Entry" ? "  3. Generated Tab" : "  4. Generated Tab",
                          isExpanded: _isTabExpanded,
                          onToggle: () => setState(() => _isTabExpanded = !_isTabExpanded),
                          child: TabOutputSection(
                            currentSequence: _builder.sequenceToBeats(_currentSequence), 
                            generatedTab: _generatedTab, autoTimeSignature: _autoTimeSignature,
                            activeNoteNotifier: _activeNoteNotifier, notesPerMeasure: _builder.calculateNotesPerMeasure(_selectedTimeSignature, _selectedRhythmPattern, customRhythm: _customRhythmController.text),
                            rhythmStr: _builder.parsePatternString(_selectedRhythmPattern, customRhythmOverride: _customRhythmController.text).first, measuresPerLine: _measuresPerLine,
                            selectionStart: _selectionStart, selectionEnd: _selectionEnd, selectedTuning: _selectedTuning,
                            onBeatTapped: (index) {
                              setState(() {
                                if (_selectionStart == -1 || (_selectionStart != -1 && _selectionEnd != _selectionStart)) {
                                  _selectionStart = index; _selectionEnd = index; _tapAnchorIndex = index;
                                } else {
                                  _selectionStart = min(_tapAnchorIndex!, index); _selectionEnd = max(_tapAnchorIndex!, index);
                                }
                              });
                              if (_endRests > 0) _generateTab();
                            },
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
              final (healed, _) = PresetSanitizer.validateAndSanitize(p);
              _playLick(
                overrideSequence: _builder.buildSequenceForPreset(healed), overrideTempo: healed.tempo, overrideRhythm: healed.rhythm,
                overrideCustomRhythm: healed.customRhythmString, overrideAccentPattern: healed.customAccentString, overrideTuning: healed.tuning,
                overrideKey: healed.key, overrideScale: healed.scale, overrideInstrument: healed.instrumentIndex, presetId: healed.id,
              );
            },
            onStopPreview: _stopPlayback, onTogglePreviewLoop: () => setState(() => _isPreviewLooping = !_isPreviewLooping),
            onLoadPreset: _loadPreset,
            onDeletePresets: (ids) async {
              setState(() { _savedPresets.removeWhere((p) => ids.contains(p.id)); if (ids.contains(_previewPresetId)) { _stopPlayback(); _previewPresetId = null; } });
              await _storage.savePresets(_savedPresets);
            },
            onRenamePreset: (id, name) async {
              var i = _savedPresets.indexWhere((p) => p.id == id);
              if (i != -1) {
                var o = _savedPresets[i];
                setState(() => _savedPresets[i] = LickPreset(
                  id: o.id, name: name, key: o.key, scale: o.scale, tuning: o.tuning, system: o.system, fragment: o.fragment,
                  customNps: o.customNps, startFret: o.startFret, pathway: o.pathway, direction: o.direction, motifString: o.motifString,
                  rhythm: o.rhythm, customRhythmString: o.customRhythmString, customAccentString: o.customAccentString, manualTabString: o.manualTabString,
                  timeSignature: o.timeSignature, tempo: o.tempo, measuresPerLine: o.measuresPerLine, breakInterval: o.breakInterval,
                  breakLength: o.breakLength, endRests: o.endRests, tabOutput: o.tabOutput, instrumentIndex: o.instrumentIndex, createdAt: o.createdAt
                ));
                await _storage.savePresets(_savedPresets);
              }
            },
            onExportPresets: _storage.exportPresets,
            onReorderPresets: (o, n) async { setState(() { if(n>o)n--; _savedPresets.insert(n, _savedPresets.removeAt(o)); }); await _storage.savePresets(_savedPresets); },
            onImport: _importPresets
          ),
          const GpxTabScreen(),
        ],
      ),
    );
  }
}