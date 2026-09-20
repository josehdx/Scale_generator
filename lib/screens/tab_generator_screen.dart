import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lick_preset.dart';
import '../scale_engine.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';
import 'saved_presets_screen.dart';

// UI Extracted to a separate file to prevent density
part 'tab_generator_studio_ui.dart';

class TabGeneratorScreen extends StatefulWidget {
  const TabGeneratorScreen({super.key});

  @override
  State<TabGeneratorScreen> createState() => _TabGeneratorScreenState();
}

class _TabGeneratorScreenState extends State<TabGeneratorScreen> {
  static const String _storageKey = 'auto_saved_lick_presets';

  final ScaleEngine _engine = ScaleEngine();
  final MidiPro _midiPro = MidiPro();
  late PageController _pageController;

  int _selectedPageIndex = 0;
  bool _isPlaying = false;
  bool _isPreviewPlaying = false; 
  bool _isPreviewLooping = false; 
  String? _previewPresetId;
  
  bool _isMidiReady = false;
  bool _isLooping = false;
  bool _isFretboardVisible = true; 
  
  bool _isTheoryExpanded = false;
  bool _isPathwaysExpanded = false;
  bool _isFormattingExpanded = false;
  bool _isTabExpanded = false; 
  
  Timer? _playbackTimer;
  final Set<int> _activeMidiNotes = {}; 
  final ScrollController _fretboardScrollController = ScrollController();
  final ValueNotifier<int> _currentPlayingNoteIndex = ValueNotifier<int>(-1);
  
  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;
  int _selectedInstrumentIndex = 27;

  // THEORY STATE
  String _selectedKey = "C";
  String _selectedScale = "Minor Pentatonic";
  String _selectedTuning = "Standard E";
  int _startFret = 10;
  String _selectedSystem = "Box Position / CAGED";
  int _startString = 6; 
  int _endString = 1;   
  int _singleStringTarget = 1;
  String _customNpsProfile = "3,4,3,4,3,3"; 

  // MOTIF & PATHWAY STATE
  String _selectedPathway = "Custom Motif Builder";
  String _selectedDirection = "One-Way (Ascend)";
  String _motifPairDirection = "Descend (High -> Low)";
  String _customMotif = "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1";
  String _customSequence = "1, 2, 3, 4, 5, 6, 7, 8";

  String _selectedMotifTemplate = "Default Pentatonic Roll";
  final Map<String, String> _motifTemplates = {
    "Default Pentatonic Roll": "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1",
    "Low Pedal Point": "L1,H1,L1,H2,L1,H3",
    "High Pedal Point": "H1,L1,H1,L2,H1,L3",
    "Zig-Zag / Cross-Pick": "L1,H2,L2,H1,L3,H2",
    "Blues Pentatonic Roll": "H2,H1,L2,H1,L2,L1",
    "Ascending 3-Note Run": "L1,L2,H1,L2,H1,H2",
    "Descending 4-Note Run": "H3,H2,H1,L3",
    "Pivot Arpeggio": "L1,H1,H3,L3",
    "Custom (Build Below)": "",
  };

  // RHYTHM STATE
  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1; 
  String _selectedRhythm = "16th";
  int _tempo = 120;

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];
  List<LickPreset> _savedPresets = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Custom Notes-Per-String", "Single String Horizontal"];
  final List<String> _pathways = [
    "Straight Linear", 
    "3-Step Triplet", 
    "4-Step 16th", 
    "Note Skipping", 
    "Custom Motif Builder",      
    "Custom Sequence (Indices)"  
  ];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way (Ascend)", "One-Way (Descend)"];
  final List<String> _rhythms = ["Quarter", "8th", "16th"];
  final Map<String, int> _guitarSounds = {"Clean Electric": 27, "Steel Acoustic": 25, "Jazz Electric": 26, "Nylon Acoustic": 24};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSoundFont();
    _loadPresetsFromDisk();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateTab());
  }

  @override
  void dispose() {
    _stopPlayback(); 
    _pageController.dispose();
    _fretboardScrollController.dispose();
    _currentPlayingNoteIndex.dispose();
    super.dispose();
  }

  // --- TWO-WAY BINDING LOGIC --- //

  String _invertMotifTokens(String motif) {
    if (motif.isEmpty) return "";
    return motif.split(',').map((t) {
      t = t.trim();
      if (t.startsWith('L')) return 'H${t.substring(1)}';
      if (t.startsWith('H')) return 'L${t.substring(1)}';
      return t;
    }).join(',');
  }

  void _syncStringsWithDirection(String dir) {
    if (dir.contains("Ascend (Low -> High)") || dir == "One-Way (Ascend)" || dir == "Ascend -> Descend") {
      if (_startString < _endString) {
        int temp = _startString;
        _startString = _endString;
        _endString = temp;
      }
    } else if (dir.contains("Descend (High -> Low)") || dir == "One-Way (Descend)" || dir == "Descend -> Ascend") {
      if (_startString > _endString) {
        int temp = _startString;
        _startString = _endString;
        _endString = temp;
      }
    }
  }

  void _syncDirectionWithStrings() {
    if (_startString > _endString) { 
      if (_motifPairDirection != "Ascend (Low -> High)") {
        _motifPairDirection = "Ascend (Low -> High)";
        _customMotif = _invertMotifTokens(_customMotif);
        _selectedMotifTemplate = "Custom (Build Below)";
      }
      if (_selectedDirection.contains("Descend") && !_selectedDirection.startsWith("Descend -> Ascend")) {
        _selectedDirection = "One-Way (Ascend)";
      } else if (_selectedDirection == "Descend -> Ascend") {
        _selectedDirection = "Ascend -> Descend";
      }
    } else if (_startString < _endString) { 
      if (_motifPairDirection != "Descend (High -> Low)") {
        _motifPairDirection = "Descend (High -> Low)";
        _customMotif = _invertMotifTokens(_customMotif);
        _selectedMotifTemplate = "Custom (Build Below)";
      }
      if (_selectedDirection.contains("Ascend") && !_selectedDirection.startsWith("Ascend -> Descend")) {
        _selectedDirection = "One-Way (Descend)";
      } else if (_selectedDirection == "Ascend -> Descend") {
        _selectedDirection = "Descend -> Ascend";
      }
    }
  }

  // --- DATA METHODS --- //

  Future<void> _loadPresetsFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        setState(() => _savedPresets = decodedList.map((e) => LickPreset.fromJson(e)).toList());
      }
    } catch (e) {
      debugPrint("Storage Read Error: $e");
    }
  }

  Future<void> _savePresetsToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_savedPresets.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint("Storage Write Error: $e");
    }
  }

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: _selectedInstrumentIndex);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint("MIDI Setup Error.");
    }
  }

  Future<void> _changeGuitarSound(int newIndex) async {
    setState(() => _selectedInstrumentIndex = newIndex);
    try {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: newIndex);
    } catch (e) {
      debugPrint("Error switching instrument: $e");
    }
  }

  void _clearSelection() {
    setState(() { _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null; });
  }

  void _saveCurrentLick() {
    if (_currentSequence.isEmpty || _generatedTab.startsWith("❌")) return;
    String patternLabel = _selectedPathway.contains("Custom") ? "Custom Pattern" : _selectedPathway;
    String presetName = "$_selectedKey $_selectedScale - $patternLabel (Fret $_startFret)";
    String stringToSave = _selectedPathway == "Custom Motif Builder" ? _customMotif : _customSequence;

    final preset = LickPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(), name: presetName, key: _selectedKey, scale: _selectedScale,
      tuning: _selectedTuning, system: _selectedSystem, fragment: "$_startString-$_endString", startFret: _startFret, pathway: _selectedPathway,
      direction: _selectedDirection, motifPairDirection: _motifPairDirection, motifString: stringToSave, rhythm: _selectedRhythm,
      tempo: _tempo, measuresPerLine: _measuresPerLine, breakInterval: _breakInterval, breakLength: _breakLength, endRests: _endRests,
      tabOutput: _generatedTab, createdAt: DateTime.now(),
    );
    setState(() => _savedPresets.insert(0, preset));
    _savePresetsToDisk();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved Preset: '$presetName'")));
  }

  void _loadPreset(LickPreset preset) {
    setState(() {
      _selectedKey = preset.key; _selectedScale = preset.scale; _selectedTuning = preset.tuning; _selectedSystem = preset.system; 
      _startFret = preset.startFret; _selectedPathway = preset.pathway;
      
      String frag = preset.fragment;
      if (frag.contains('-') && !frag.contains('Strings')) {
        var parts = frag.split('-');
        _startString = int.tryParse(parts[0]) ?? 6;
        _endString = int.tryParse(parts[1]) ?? 1;
      } else {
        if (frag.contains("High")) { _startString = 3; _endString = 1; }
        else if (frag.contains("Middle")) { _startString = 4; _endString = 2; }
        else if (frag.contains("Low")) { _startString = 6; _endString = 4; }
        else if (frag.startsWith("Strings ")) {
          var s = frag.replaceAll("Strings ", "").split("-");
          _startString = int.tryParse(s[0]) ?? 6;
          _endString = int.tryParse(s[1]) ?? 1;
        } else { _startString = 6; _endString = 1; }
      }

      String loadedDir = preset.direction;
      if (loadedDir == "One-Way") loadedDir = "One-Way (Ascend)";
      _selectedDirection = loadedDir; 
      _motifPairDirection = preset.motifPairDirection; 
      
      if (_selectedPathway == "Custom Motif Builder") {
        _customMotif = preset.motifString;
        _selectedMotifTemplate = "Custom (Build Below)";
      } else {
        _customSequence = preset.motifString;
      }

      _selectedRhythm = preset.rhythm; _tempo = preset.tempo; _measuresPerLine = preset.measuresPerLine; _breakInterval = preset.breakInterval;
      _breakLength = preset.breakLength; _endRests = preset.endRests; _generatedTab = preset.tabOutput;
    });
    _generateTab();
    _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  List<int> _parseNpsProfile(String npsStr) {
    List<int> parsed = npsStr.split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
    while (parsed.length < 6) parsed.add(3); 
    return parsed.take(6).toList();
  }

  void _addMotifChip(String token) {
    setState(() {
      _selectedMotifTemplate = "Custom (Build Below)";
      List<String> currentTokens = _customMotif.split(',').where((e) => e.trim().isNotEmpty).toList();
      currentTokens.add(token);
      _customMotif = currentTokens.join(',');
      _generateTab();
    });
  }

  void _removeLastMotifChip() {
    setState(() {
      List<String> currentTokens = _customMotif.split(',').where((e) => e.trim().isNotEmpty).toList();
      if (currentTokens.isNotEmpty) {
        currentTokens.removeLast();
        _customMotif = currentTokens.join(',');
        _selectedMotifTemplate = "Custom (Build Below)";
        _generateTab();
      }
    });
  }

  void _clearMotifChips() {
    setState(() {
      _customMotif = "";
      _selectedMotifTemplate = "Custom (Build Below)";
      _generateTab();
    });
  }

  List<List<int>> _buildSequenceForPreset(LickPreset preset) {
    _engine.setTuning(preset.tuning);
    
    int stStr = 6, enStr = 1;
    String frag = preset.fragment;
    if (frag.contains('-') && !frag.contains('Strings')) {
      var parts = frag.split('-');
      stStr = int.tryParse(parts[0]) ?? 6;
      enStr = int.tryParse(parts[1]) ?? 1;
    } else {
      if (frag.contains("High")) { stStr = 3; enStr = 1; }
      else if (frag.contains("Middle")) { stStr = 4; enStr = 2; }
      else if (frag.contains("Low")) { stStr = 6; enStr = 4; }
      else if (frag.startsWith("Strings ")) {
        var s = frag.replaceAll("Strings ", "").split("-");
        stStr = int.tryParse(s[0]) ?? 6;
        enStr = int.tryParse(s[1]) ?? 1;
      } else { stStr = 6; enStr = 1; }
    }

    List<int> targetStrings = [];
    if (preset.system != "Single String Horizontal") {
      int minStr = min(stStr, enStr);
      int maxStr = max(stStr, enStr);
      targetStrings = [for (int i = minStr; i <= maxStr; i++) i];
    }

    Map<int, List<int>> boxDict;
    if (preset.system == "Box Position / CAGED") {
      boxDict = _engine.getScaleNotesBox(preset.key, preset.scale, preset.startFret, targetStrings);
    } else if (preset.system == "3-Note-Per-String (3NPS)") {
      boxDict = _engine.getScaleNotes3NPS(preset.key, preset.scale, preset.startFret, targetStrings);
    } else if (preset.system == "Custom Notes-Per-String") {
      boxDict = _engine.getScaleNotesCustomNPS(preset.key, preset.scale, preset.startFret, targetStrings, [3,3,3,3,3,3]); 
    } else {
      boxDict = _engine.getScaleNotesSingleString(preset.key, preset.scale, preset.startFret, 1);
    }

    List<List<int>> sequence = [];
    if (preset.pathway == "Custom Motif Builder") {
      if (preset.system != "Single String Horizontal" && targetStrings.length >= 2) {
        sequence = _engine.buildCustomMotif(boxDict, preset.motifString, stStr, enStr);
      }
    } else {
      List<List<int>> baseNotes = _engine.flattenBoxDict(boxDict, stStr, enStr);
      
      if (preset.pathway == "Custom Sequence (Indices)") {
        sequence = _engine.buildCustomSequence(baseNotes, preset.motifString);
      } else {
        List<List<int>> patternNotes;
        if (preset.pathway == "3-Step Triplet") { patternNotes = _engine.apply3StepSequence(baseNotes); }
        else if (preset.pathway == "4-Step 16th") { patternNotes = _engine.apply4StepSequence(baseNotes); }
        else if (preset.pathway == "Note Skipping") { patternNotes = _engine.applyNoteSkipping(baseNotes); }
        else { patternNotes = baseNotes; }

        if (preset.direction.startsWith("One-Way")) {
          sequence = patternNotes;
        } else {
          sequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
        }
      }
    }

    sequence = _engine.applyIntervalBreaks(sequence, preset.breakInterval, preset.breakLength);
    for (int i = 0; i < preset.endRests; i++) sequence.add([-1, -1]);

    _engine.setTuning(_selectedTuning);
    return sequence;
  }

  void _generateTab() {
    _stopPlayback(); 
    _engine.setTuning(_selectedTuning);
    _clearSelection();
    _currentPlayingNoteIndex.value = -1;

    List<int> targetStrings = [];
    if (_selectedSystem != "Single String Horizontal") {
      int minStr = min(_startString, _endString);
      int maxStr = max(_startString, _endString);
      targetStrings = [for (int i = minStr; i <= maxStr; i++) i];
    }

    Map<int, List<int>> boxDict;
    if (_selectedSystem == "Box Position / CAGED") {
      boxDict = _engine.getScaleNotesBox(_selectedKey, _selectedScale, _startFret, targetStrings);
    } else if (_selectedSystem == "3-Note-Per-String (3NPS)") {
      boxDict = _engine.getScaleNotes3NPS(_selectedKey, _selectedScale, _startFret, targetStrings);
    } else if (_selectedSystem == "Custom Notes-Per-String") {
      boxDict = _engine.getScaleNotesCustomNPS(_selectedKey, _selectedScale, _startFret, targetStrings, _parseNpsProfile(_customNpsProfile));
    } else {
      boxDict = _engine.getScaleNotesSingleString(_selectedKey, _selectedScale, _startFret, _singleStringTarget);
    }

    _currentSequence = [];
    int beatsPerMeasure = 4;

    if (_selectedPathway == "Custom Motif Builder") {
      if (_selectedSystem == "Single String Horizontal" || targetStrings.length < 2) {
        setState(() => _generatedTab = "⚠️ Custom Motif Builder requires at least 2 strings for pairs.");
        return;
      }
      _currentSequence = _engine.buildCustomMotif(boxDict, _customMotif, _startString, _endString);
    } else {
      List<List<int>> baseNotes = _engine.flattenBoxDict(boxDict, _startString, _endString);
      
      if (_selectedPathway == "Custom Sequence (Indices)") {
        _currentSequence = _engine.buildCustomSequence(baseNotes, _customSequence);
      } else {
        List<List<int>> patternNotes;
        if (_selectedPathway == "3-Step Triplet") { patternNotes = _engine.apply3StepSequence(baseNotes); beatsPerMeasure = 3; }
        else if (_selectedPathway == "4-Step 16th") patternNotes = _engine.apply4StepSequence(baseNotes);
        else if (_selectedPathway == "Note Skipping") patternNotes = _engine.applyNoteSkipping(baseNotes);
        else patternNotes = baseNotes;

        if (_selectedDirection.startsWith("One-Way")) {
          _currentSequence = patternNotes;
        } else {
          _currentSequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
        }
      }
    }

    if (_currentSequence.isEmpty) {
      setState(() => _generatedTab = "❌ Error: No valid notes found.");
      return;
    }

    _currentSequence = _engine.applyIntervalBreaks(_currentSequence, _breakInterval, _breakLength);
    for (int i = 0; i < _endRests; i++) _currentSequence.add([-1, -1]);

    setState(() {
      _generatedTab = _engine.renderAsciiTab(
        _currentSequence, rhythmStr: _selectedRhythm, measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine, beatsPerMeasure: beatsPerMeasure, tempo: _tempo,
      );
    });
  }

  void _playLick({List<List<int>>? overrideSequence, int? overrideTempo, String? overrideRhythm, String? overrideTuning, String? presetId}) {
    if (!_isMidiReady) return;
    
    List<List<int>> seqToPlay = overrideSequence ?? _currentSequence;
    if (seqToPlay.isEmpty) return;

    _stopPlayback(); 
    bool isPreview = presetId != null;
    
    setState(() {
      if (isPreview) {
        _isPreviewPlaying = true;
        _previewPresetId = presetId;
      } else {
        _isPlaying = true;
      }
    });
    
    String rhythm = overrideRhythm ?? _selectedRhythm;
    int tempo = overrideTempo ?? _tempo;
    
    String tuning = overrideTuning ?? _selectedTuning;
    Map<int, int> activeOpenStrings = _engine.tunings[tuning] ?? _engine.openStrings;

    double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[rhythm] ?? 0.25;
    int msPerNote = ((60000 / tempo) * beatMultiplier).round();
    if (msPerNote < 20) msPerNote = 20; 
    
    int startIdx = 0;
    int endIdx = seqToPlay.length - 1;
    
    if (!isPreview && _selectionStart != -1 && _selectionEnd != -1) {
      startIdx = _selectionStart.clamp(0, seqToPlay.length - 1);
      endIdx = _selectionEnd.clamp(startIdx, seqToPlay.length - 1);
    }
    
    int currentIndex = startIdx;
    List<int> notesToStop = [];

    _playbackTimer = Timer.periodic(Duration(milliseconds: msPerNote), (timer) {
      if (!mounted || (isPreview && !_isPreviewPlaying) || (!isPreview && !_isPlaying)) { 
        timer.cancel(); _stopPlayback(); return; 
      }

      if (currentIndex > endIdx) {
        if (isPreview ? _isPreviewLooping : _isLooping) {
          currentIndex = startIdx; 
        } else { 
          timer.cancel(); _stopPlayback(); return; 
        }
      }

      for (var pitch in notesToStop) {
        _midiPro.stopMidiNote(midi: pitch);
        _activeMidiNotes.remove(pitch);
      }
      notesToStop.clear();

      var note = seqToPlay[currentIndex];
      if (note[0] != -1) {
        int pitch = activeOpenStrings[note[0]]! + note[1];
        _midiPro.playMidiNote(midi: pitch, velocity: 127);
        _activeMidiNotes.add(pitch);
        notesToStop.add(pitch); 
      }
      if (!isPreview) _currentPlayingNoteIndex.value = currentIndex;
      currentIndex++;
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    for (int pitch in _activeMidiNotes) _midiPro.stopMidiNote(midi: pitch);
    _activeMidiNotes.clear();
    _currentPlayingNoteIndex.value = -1;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _isPreviewPlaying = false;
        _previewPresetId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tab Generator Studio'),
        actions: [ IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save Lick Preset', onPressed: _saveCurrentLick) ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(label: const Text("Main Studio"), selected: _selectedPageIndex == 0, onSelected: (s) { if (s) _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }),
              const SizedBox(width: 16),
              ChoiceChip(label: const Text("Saved Presets"), selected: _selectedPageIndex == 1, onSelected: (s) { if (s) _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }),
            ],
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedPageIndex = index);
          if (index != 1 && _isPreviewPlaying) {
             _stopPlayback(); 
          }
        },
        children: [
          _buildStudioScreen(),
          SavedPresetsScreen(
            savedPresets: _savedPresets, 
            activePreviewId: _previewPresetId,
            isPreviewPlaying: _isPreviewPlaying,
            isPreviewLooping: _isPreviewLooping,
            onPlayPreview: (preset) {
              _playLick(
                overrideSequence: _buildSequenceForPreset(preset),
                overrideTempo: preset.tempo,
                overrideRhythm: preset.rhythm,
                overrideTuning: preset.tuning,
                presetId: preset.id,
              );
            },
            onStopPreview: _stopPlayback,
            onTogglePreviewLoop: () => setState(() => _isPreviewLooping = !_isPreviewLooping),
            onLoadPreset: _loadPreset, 
            onDeletePresets: (ids) => setState(() { 
              _savedPresets.removeWhere((p) => ids.contains(p.id)); 
              if (ids.contains(_previewPresetId)) _stopPlayback();
              _savePresetsToDisk(); 
            }),
            onRenamePreset: (id, name) => setState(() { var idx = _savedPresets.indexWhere((p) => p.id == id); if (idx != -1) { var o = _savedPresets[idx]; _savedPresets[idx] = LickPreset(id: o.id, name: name, key: o.key, scale: o.scale, tuning: o.tuning, system: o.system, fragment: o.fragment, startFret: o.startFret, pathway: o.pathway, direction: o.direction, motifPairDirection: o.motifPairDirection, motifString: o.motifString, rhythm: o.rhythm, tempo: o.tempo, measuresPerLine: o.measuresPerLine, breakInterval: o.breakInterval, breakLength: o.breakLength, endRests: o.endRests, tabOutput: o.tabOutput, createdAt: o.createdAt); _savePresetsToDisk(); } }),
            onExportPresets: (p) {}, 
            onReorderPresets: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _savedPresets.removeAt(oldIndex);
                _savedPresets.insert(newIndex, item);
                _savePresetsToDisk();
              });
            },
            onImport: () {},
          ),
        ],
      ),
    );
  }
}