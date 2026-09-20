import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lick_preset.dart';
import '../models/motif_token.dart';
import '../scale_engine.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/motif_chip_builder.dart';
import '../widgets/playback_control_bar.dart';
import 'saved_presets_screen.dart';

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
  bool _isMidiReady = false;
  bool _isLooping = false;
  bool _isChangingSound = false;
  bool _isFretboardVisible = true; // NEW: Toggle for Fretboard Visibility
  
  Timer? _playbackTimer;
  final Set<int> _activeMidiNotes = {}; 
  
  final ScrollController _fretboardScrollController = ScrollController();
  final ValueNotifier<int> _currentPlayingNoteIndex = ValueNotifier<int>(-1);
  
  int? _previewString;
  int? _previewFret;

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _selectedInstrumentIndex = 27;

  String _selectedKey = "C";
  String _selectedScale = "Minor Pentatonic";
  String _selectedTuning = "Standard E";
  int _startFret = 8;

  String _selectedSystem = "Box Position / CAGED";
  String _selectedFragment = "Full 6 Strings";
  int _singleStringTarget = 1;

  String _selectedPathway = "Custom Motif Builder";
  String _selectedDirection = "Ascend -> Descend";
  String _motifPairDirection = "Descend (High -> Low)";

  List<MotifToken> _motifTokens = [];
  String? _activeTemplateName;

  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1; 
  String _selectedRhythm = "16th";
  int _tempo = 120;

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];
  List<LickPreset> _savedPresets = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Single String Horizontal"];
  final List<String> _fragments = ["Full 6 Strings", "High Strings (1-3)", "Middle Strings (2-4)", "Low Strings (4-6)"];
  final List<String> _pathways = ["Straight Linear", "3-Step Triplet", "4-Step 16th", "Note Skipping", "Custom Motif Builder"];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way (Ascend)", "One-Way (Descend)"];
  final List<String> _rhythms = ["Quarter", "8th", "16th"];
  final Map<String, int> _guitarSounds = {"Clean Electric": 27, "Steel Acoustic": 25, "Jazz Electric": 26, "Nylon Acoustic": 24};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSoundFont();
    _loadPresetsFromDisk();
    
    _injectTemplate(["L2", "L1", "L2", "H1", "H2", "H1", "L2", "L1", "L2", "L1"], "Default Intro");
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

  String _getMotifString() => _motifTokens.map((t) => t.value).join(',');

  void _injectTemplate(List<String> tokens, [String? templateName]) {
    setState(() {
      _activeTemplateName = templateName;
      _motifTokens = tokens.map((t) => MotifToken(UniqueKey().toString(), t)).toList();
      _generateTab();
    });
  }

  void _generateRandomMotif() {
    final rand = Random();
    final available = ["L1", "L2", "L3", "L4", "H1", "H2", "H3", "H4"];
    int length = rand.nextInt(5) + 4; 
    List<String> randomSequence = List.generate(length, (_) => available[rand.nextInt(available.length)]);
    _injectTemplate(randomSequence, "Random Motif");
  }

  (int stringNum, int fretNum, int pitch)? _getNoteDataForToken(String token) {
    List<int> targetStrings = [1, 2, 3, 4, 5, 6];
    if (_selectedSystem != "Single String Horizontal") {
      if (_selectedFragment == "High Strings (1-3)") targetStrings = [1, 2, 3];
      else if (_selectedFragment == "Middle Strings (2-4)") targetStrings = [2, 3, 4];
      else if (_selectedFragment == "Low Strings (4-6)") targetStrings = [4, 5, 6];
    }

    Map<int, List<int>> boxDict;
    if (_selectedSystem == "Box Position / CAGED") {
      boxDict = _engine.getScaleNotesBox(_selectedKey, _selectedScale, _startFret, targetStrings);
    } else if (_selectedSystem == "3-Note-Per-String (3NPS)") {
      boxDict = _engine.getScaleNotes3NPS(_selectedKey, _selectedScale, _startFret, targetStrings);
    } else {
      boxDict = _engine.getScaleNotesSingleString(_selectedKey, _selectedScale, _startFret, _singleStringTarget);
    }

    if (boxDict.isEmpty) return null;

    List<int> sortedStrings = boxDict.keys.toList()..sort();
    int higherPitchStr = sortedStrings.first;
    int lowerPitchStr = sortedStrings.length > 1 ? sortedStrings[1] : sortedStrings.first;

    if (_motifPairDirection == "Ascend (Low -> High)" && sortedStrings.length > 1) {
      lowerPitchStr = sortedStrings.last;
      higherPitchStr = sortedStrings[sortedStrings.length - 2];
    }

    bool isHigh = token.startsWith('H');
    int targetString = isHigh ? higherPitchStr : lowerPitchStr;
    int noteIndex = int.parse(token.substring(1)) - 1;
    List<int> frets = boxDict[targetString] ?? [];
    frets.sort();

    if (noteIndex >= 0 && noteIndex < frets.length) {
      int fret = frets[noteIndex];
      int pitch = (_engine.openStrings[targetString] ?? 0) + fret;
      return (targetString, fret, pitch);
    }
    return null;
  }

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
      _midiPro.playMidiNote(midi: 60, velocity: 0);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint("MIDI Setup Error.");
    }
  }

  Future<void> _changeGuitarSound(int newIndex) async {
    if (_isChangingSound) return; 
    setState(() => _isChangingSound = true);
    try {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: newIndex);
      _midiPro.playMidiNote(midi: 60, velocity: 0);
    } catch (e) {
      debugPrint("Error switching instrument: $e");
    } finally {
      if (mounted) setState(() => _isChangingSound = false);
    }
  }

  void _clearSelection() {
    setState(() {
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
  }

  void _saveCurrentLick() {
    if (_currentSequence.isEmpty || _generatedTab.startsWith("❌")) return;
    String patternLabel = _selectedPathway;
    if (_selectedPathway == "Custom Motif Builder") {
      if (_activeTemplateName != null) {
        patternLabel = _activeTemplateName!;
      } else {
        List<String> tokens = _getMotifString().split(',');
        String shortMotif = tokens.length > 4 ? "${tokens.take(4).join(',')},..." : tokens.join(',');
        patternLabel = "Custom [$shortMotif]";
      }
    }
    String presetName = "$_selectedKey $_selectedScale - $patternLabel (Fret $_startFret, $_selectedRhythm)";
    final preset = LickPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(), name: presetName, key: _selectedKey, scale: _selectedScale,
      tuning: _selectedTuning, system: _selectedSystem, fragment: _selectedFragment, startFret: _startFret, pathway: _selectedPathway,
      direction: _selectedDirection, motifPairDirection: _motifPairDirection, motifString: _getMotifString(), rhythm: _selectedRhythm,
      tempo: _tempo, measuresPerLine: _measuresPerLine, breakInterval: _breakInterval, breakLength: _breakLength, endRests: _endRests,
      tabOutput: _generatedTab, createdAt: DateTime.now(),
    );
    setState(() => _savedPresets.insert(0, preset));
    _savePresetsToDisk();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved Preset: '$presetName'")));
  }

  void _deletePresets(List<String> idsToDelete) {
    setState(() => _savedPresets.removeWhere((p) => idsToDelete.contains(p.id)));
    _savePresetsToDisk();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted ${idsToDelete.length} preset(s)")));
  }

  void _renamePreset(String presetId, String newName) {
    setState(() {
      int index = _savedPresets.indexWhere((p) => p.id == presetId);
      if (index != -1) {
        var old = _savedPresets[index];
        _savedPresets[index] = LickPreset(
          id: old.id, name: newName, key: old.key, scale: old.scale, tuning: old.tuning, system: old.system, fragment: old.fragment,
          startFret: old.startFret, pathway: old.pathway, direction: old.direction, motifPairDirection: old.motifPairDirection, motifString: old.motifString,
          rhythm: old.rhythm, tempo: old.tempo, measuresPerLine: old.measuresPerLine, breakInterval: old.breakInterval, breakLength: old.breakLength,
          endRests: old.endRests, tabOutput: old.tabOutput, createdAt: old.createdAt,
        );
      }
    });
    _savePresetsToDisk();
  }

  void _loadPreset(LickPreset preset) {
    setState(() {
      _selectedKey = preset.key; _selectedScale = preset.scale; _selectedTuning = preset.tuning; _selectedSystem = preset.system; _selectedFragment = preset.fragment;
      _startFret = preset.startFret; _selectedPathway = preset.pathway;
      String loadedDir = preset.direction;
      if (loadedDir == "One-Way") loadedDir = "One-Way (Ascend)";
      _selectedDirection = loadedDir; _motifPairDirection = preset.motifPairDirection;
      _motifTokens.clear();
      if (preset.motifString.isNotEmpty) {
        preset.motifString.split(',').forEach((t) => _motifTokens.add(MotifToken(UniqueKey().toString(), t)));
      }
      _activeTemplateName = null;
      _selectedRhythm = preset.rhythm; _tempo = preset.tempo; _measuresPerLine = preset.measuresPerLine; _breakInterval = preset.breakInterval;
      _breakLength = preset.breakLength; _endRests = preset.endRests; _generatedTab = preset.tabOutput;
    });
    _generateTab();
    _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _exportPresetsToFile(List<LickPreset> presetsToExport) async {
    if (presetsToExport.isEmpty) return;
    try {
      final jsonString = const JsonEncoder.withIndent('  ').convert(presetsToExport.map((e) => e.toJson()).toList());
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Presets Backup', fileName: 'tab_generator_backup.json', type: FileType.custom, allowedExtensions: ['json'], bytes: Uint8List.fromList(utf8.encode(jsonString)),
      );
      if (outputFile != null) {
        final file = File(outputFile);
        if (!await file.exists()) await file.writeAsString(jsonString);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Exported ${presetsToExport.length} preset(s) successfully!")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _importPresetsFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return;
      final jsonString = await File(result.files.single.path!).readAsString();
      final List<LickPreset> importedPresets = jsonDecode(jsonString).map<LickPreset>((e) => LickPreset.fromJson(e)).toList();
      setState(() {
        for (var preset in importedPresets) {
          if (!_savedPresets.any((existing) => existing.id == preset.id)) _savedPresets.add(preset);
        }
        _savedPresets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
      _savePresetsToDisk();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imported presets successfully!")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import failed."), backgroundColor: Colors.redAccent));
    }
  }

  void _generateTab() {
    _engine.setTuning(_selectedTuning);
    _clearSelection();
    _currentPlayingNoteIndex.value = -1;

    List<int> targetStrings = [1, 2, 3, 4, 5, 6];
    if (_selectedSystem != "Single String Horizontal") {
      if (_selectedFragment == "High Strings (1-3)") targetStrings = [1, 2, 3];
      else if (_selectedFragment == "Middle Strings (2-4)") targetStrings = [2, 3, 4];
      else if (_selectedFragment == "Low Strings (4-6)") targetStrings = [4, 5, 6];
    }

    Map<int, List<int>> boxDict;
    if (_selectedSystem == "Box Position / CAGED") boxDict = _engine.getScaleNotesBox(_selectedKey, _selectedScale, _startFret, targetStrings);
    else if (_selectedSystem == "3-Note-Per-String (3NPS)") boxDict = _engine.getScaleNotes3NPS(_selectedKey, _selectedScale, _startFret, targetStrings);
    else boxDict = _engine.getScaleNotesSingleString(_selectedKey, _selectedScale, _startFret, _singleStringTarget);

    int beatsPerMeasure = 4;
    _currentSequence = [];

    if (_selectedPathway == "Custom Motif Builder") {
      if (_selectedSystem == "Single String Horizontal") {
        setState(() => _generatedTab = "⚠️ Custom Motif Builder requires at least 2 strings.");
        return;
      }
      _currentSequence = _engine.buildCustomMotif(boxDict, _getMotifString(), _motifPairDirection);
    } else {
      List<List<int>> baseNotes = _engine.flattenBoxDict(boxDict);
      if (_selectedDirection == "Descend -> Ascend" || _selectedDirection == "One-Way (Descend)") baseNotes = baseNotes.reversed.toList();
      
      List<List<int>> patternNotes;
      if (_selectedPathway == "3-Step Triplet") { patternNotes = _engine.apply3StepSequence(baseNotes); beatsPerMeasure = 3; }
      else if (_selectedPathway == "4-Step 16th") patternNotes = _engine.apply4StepSequence(baseNotes);
      else if (_selectedPathway == "Note Skipping") patternNotes = _engine.applyNoteSkipping(baseNotes);
      else patternNotes = baseNotes;

      if (_selectedDirection.startsWith("One-Way")) _currentSequence = patternNotes;
      else _currentSequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
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

  void _playLick() {
    if (!_isMidiReady || _currentSequence.isEmpty || _isPlaying) return;
    setState(() => _isPlaying = true);
    
    double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[_selectedRhythm] ?? 0.25;
    int msPerNote = ((60000 / _tempo) * beatMultiplier).round();
    int startIdx = _selectionStart != -1 ? _selectionStart.clamp(0, _currentSequence.length - 1) : 0;
    int endIdx = _selectionEnd != -1 ? _selectionEnd.clamp(startIdx, _currentSequence.length - 1) : _currentSequence.length - 1;
    
    int currentIndex = startIdx;
    List<int> notesToStop = [];

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(Duration(milliseconds: msPerNote), (timer) {
      if (!mounted || !_isPlaying) { timer.cancel(); _stopPlayback(); return; }

      if (currentIndex > endIdx) {
        if (_isLooping) currentIndex = startIdx; 
        else { timer.cancel(); _stopPlayback(); return; }
      }

      for (var pitch in notesToStop) {
        _midiPro.stopMidiNote(midi: pitch);
        _activeMidiNotes.remove(pitch);
      }
      notesToStop.clear();

      var note = _currentSequence[currentIndex];
      if (note[0] != -1) {
        int pitch = _engine.openStrings[note[0]]! + note[1];
        _midiPro.playMidiNote(midi: pitch, velocity: 127);
        _activeMidiNotes.add(pitch);
        notesToStop.add(pitch); 
      }
      _currentPlayingNoteIndex.value = currentIndex;
      currentIndex++;
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    for (int pitch in _activeMidiNotes) _midiPro.stopMidiNote(midi: pitch);
    _activeMidiNotes.clear();
    _currentPlayingNoteIndex.value = -1;
    if (mounted) setState(() => _isPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tab Generator Studio'),
        actions: [
          IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save Lick Preset', onPressed: _saveCurrentLick),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(label: const Text("Form Controls"), selected: _selectedPageIndex == 0, onSelected: (selected) { if (selected) _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text("Interactive Fretboard"), selected: _selectedPageIndex == 1, onSelected: (selected) { if (selected) _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text("Saved Presets"), selected: _selectedPageIndex == 2, onSelected: (selected) { if (selected) _pageController.animateToPage(2, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }),
              ],
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _selectedPageIndex = index),
        children: [
          _buildFormScreen(),
          _buildFretboardScreen(),
          SavedPresetsScreen(
            savedPresets: _savedPresets,
            onLoadPreset: _loadPreset,
            onDeletePresets: _deletePresets,
            onRenamePreset: _renamePreset,
            onExportPresets: _exportPresetsToFile,
            onImport: _importPresetsFromFile,
          ),
        ],
      ),
    );
  }

  Widget _buildFormScreen() {
    return Column(
      children: [
        // FIX: Replaced Expanded with Flexible so it shrinks when collapsed
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                ExpansionTile(
                  title: const Text("🎸 1. Theory & Fretboard", style: TextStyle(fontWeight: FontWeight.bold)),
                  initiallyExpanded: true,
                  childrenPadding: const EdgeInsets.all(12.0),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildDropdown('Key', _selectedKey, _engine.noteMap.keys.toList(), (v) => setState(() { _selectedKey = v!; _generateTab(); }))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildDropdown('Scale', _selectedScale, _engine.scaleFormulas.keys.toList(), (v) => setState(() { _selectedScale = v!; _generateTab(); }))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildDropdown('Tuning', _selectedTuning, _engine.tunings.keys.toList(), (v) => setState(() { _selectedTuning = v!; _generateTab(); }))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 2, child: _buildDropdown('System', _selectedSystem, _systems, (v) => setState(() { _selectedSystem = v!; _generateTab(); }))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _selectedSystem == "Single String Horizontal"
                              ? _buildDropdown('String', _singleStringTarget.toString(), ["1", "2", "3", "4", "5", "6"], (v) => setState(() { _singleStringTarget = int.parse(v!); _generateTab(); }))
                              : _buildDropdown('Fragment', _selectedFragment, _fragments, (v) => setState(() { _selectedFragment = v!; _generateTab(); })),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text("Start Fret: $_startFret"),
                        Expanded(
                          child: Slider(
                            value: _startFret.toDouble(), min: 0, max: 20, divisions: 20, label: _startFret.toString(),
                            onChanged: (val) => setState(() { _startFret = val.toInt(); _generateTab(); }),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
                ExpansionTile(
                  title: const Text("🎼 2. Pathways & Motifs", style: TextStyle(fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.all(12.0),
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 2, child: _buildDropdown('Pathway', _selectedPathway, _pathways, (v) => setState(() { _selectedPathway = v!; _generateTab(); }))),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _selectedPathway == "Custom Motif Builder"
                              ? _buildDropdown('Pair Direction', _motifPairDirection, const ["Descend (High -> Low)", "Ascend (Low -> High)"], (v) => setState(() { _motifPairDirection = v!; _generateTab(); }))
                              : _buildDropdown('Loop Direction', _selectedDirection, _directions, (v) => setState(() { _selectedDirection = v!; _generateTab(); })),
                        ),
                      ],
                    ),
                    if (_selectedPathway == "Custom Motif Builder")
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: MotifChipBuilder(
                          tokens: _motifTokens,
                          onDeleteToken: (index) => setState(() { _activeTemplateName = null; _motifTokens.removeAt(index); _generateTab(); }),
                          onAddToken: (note) => setState(() { _activeTemplateName = null; _previewString = null; _previewFret = null; _motifTokens.add(MotifToken(UniqueKey().toString(), note)); _generateTab(); }),
                          onReorder: (oldIndex, newIndex) => setState(() { _activeTemplateName = null; if (oldIndex < newIndex) newIndex -= 1; final item = _motifTokens.removeAt(oldIndex); _motifTokens.insert(newIndex, item); _generateTab(); }),
                          onAuditionNote: (note) {
                            var data = _getNoteDataForToken(note);
                            if (data != null && _isMidiReady) {
                              _midiPro.playMidiNote(midi: data.$3, velocity: 127);
                              setState(() { _previewString = data.$1; _previewFret = data.$2; });
                            }
                          },
                          onAuditionCancel: () => setState(() { _previewString = null; _previewFret = null; }),
                          onClear: () => setState(() { _activeTemplateName = null; _motifTokens.clear(); _generateTab(); }),
                          onRandomize: _generateRandomMotif,
                          onInjectTemplate: _injectTemplate,
                        ),
                      ),
                  ],
                ),
                ExpansionTile(
                  title: const Text("⏱️ 3. Formatting & Rhythm", style: TextStyle(fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.all(12.0),
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 2, child: _buildDropdown('Rhythm', _selectedRhythm, _rhythms, (v) => setState(() { _selectedRhythm = v!; _generateTab(); }))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildNumberField('Tempo\nBPM', _tempo, (v) => setState(() => _tempo = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('Wrap\nLines', _measuresPerLine, (v) => setState(() => _measuresPerLine = v))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            'Guitar Sound', _guitarSounds.keys.firstWhere((k) => _guitarSounds[k] == _selectedInstrumentIndex), _guitarSounds.keys.toList(),
                            (v) { if (v != null) _changeGuitarSound(_guitarSounds[v]!); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('Break\nInterval', _breakInterval, (v) => setState(() => _breakInterval = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('Break\nLength', _breakLength, (v) => setState(() => _breakLength = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('End\nRests', _endRests, (v) => setState(() => _endRests = v))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        PlaybackControlBar(
          isPlaying: _isPlaying, isMidiReady: _isMidiReady, isLooping: _isLooping,
          hasSequence: _currentSequence.isNotEmpty, hasSelection: _selectionStart != -1 && _selectionEnd != -1,
          selectionStart: _selectionStart, selectionEnd: _selectionEnd,
          onPlay: _playLick, onStop: _stopPlayback, onToggleLoop: () => setState(() => _isLooping = !_isLooping),
          onSave: _saveCurrentLick, onCopy: () => Clipboard.setData(ClipboardData(text: _generatedTab)), onClearSelection: _clearSelection,
        ),
        _buildInteractiveTabOutput(),
      ],
    );
  }

  Widget _buildFretboardScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(child: _buildDropdown('Scale', _selectedScale, _engine.scaleFormulas.keys.toList(), (v) => setState(() { _selectedScale = v!; _generateTab(); }))),
              const SizedBox(width: 8),
              Chip(avatar: const Icon(Icons.music_note, color: Colors.redAccent, size: 16), label: Text('Root: $_selectedKey | Fret: $_startFret')),
              IconButton(
                icon: Icon(_isFretboardVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                tooltip: _isFretboardVisible ? 'Hide Fretboard' : 'Show Fretboard',
                onPressed: () => setState(() => _isFretboardVisible = !_isFretboardVisible),
              )
            ],
          ),
        ),
        if (_isFretboardVisible)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ValueListenableBuilder<int>(
              valueListenable: _currentPlayingNoteIndex,
              builder: (context, playingIndex, child) {
                int? actStr, actFret;
                if (playingIndex != -1 && playingIndex < _currentSequence.length) {
                  var activeNote = _currentSequence[playingIndex];
                  if (activeNote[0] != -1) { actStr = activeNote[0]; actFret = activeNote[1]; }
                }
                return InteractiveFretboard(
                  engine: _engine, selectedKey: _selectedKey, selectedScale: _selectedScale, startFret: _startFret, selectedTuning: _selectedTuning,
                  activeString: actStr, activeFret: actFret, previewString: _previewString, previewFret: _previewFret, scrollController: _fretboardScrollController, 
                  onNoteTapped: (k, f) => setState(() { _selectedKey = k; _startFret = f; _generateTab(); }),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        // FIX: Replaced Expanded with Flexible so it shrinks when motif builder is hidden/empty
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 2, child: _buildDropdown('Pathway', _selectedPathway, _pathways, (v) => setState(() { _selectedPathway = v!; _generateTab(); }))),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _selectedPathway == "Custom Motif Builder"
                            ? _buildDropdown('Pair Direction', _motifPairDirection, const ["Descend (High -> Low)", "Ascend (Low -> High)"], (v) => setState(() { _motifPairDirection = v!; _generateTab(); }))
                            : _buildDropdown('Loop Direction', _selectedDirection, _directions, (v) => setState(() { _selectedDirection = v!; _generateTab(); })),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDropdown('Rhythm', _selectedRhythm, _rhythms, (v) => setState(() { _selectedRhythm = v!; _generateTab(); }))),
                    ],
                  ),
                  if (_selectedPathway == "Custom Motif Builder")
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: MotifChipBuilder(
                        tokens: _motifTokens,
                        onDeleteToken: (index) => setState(() { _activeTemplateName = null; _motifTokens.removeAt(index); _generateTab(); }),
                        onAddToken: (note) => setState(() { _activeTemplateName = null; _previewString = null; _previewFret = null; _motifTokens.add(MotifToken(UniqueKey().toString(), note)); _generateTab(); }),
                        onReorder: (oldIndex, newIndex) => setState(() { _activeTemplateName = null; if (oldIndex < newIndex) newIndex -= 1; final item = _motifTokens.removeAt(oldIndex); _motifTokens.insert(newIndex, item); _generateTab(); }),
                        onAuditionNote: (note) {
                          var data = _getNoteDataForToken(note);
                          if (data != null && _isMidiReady) {
                            _midiPro.playMidiNote(midi: data.$3, velocity: 127);
                            setState(() { _previewString = data.$1; _previewFret = data.$2; });
                          }
                        },
                        onAuditionCancel: () => setState(() { _previewString = null; _previewFret = null; }),
                        onClear: () => setState(() { _activeTemplateName = null; _motifTokens.clear(); _generateTab(); }),
                        onRandomize: _generateRandomMotif,
                        onInjectTemplate: _injectTemplate,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        PlaybackControlBar(
          isPlaying: _isPlaying, isMidiReady: _isMidiReady, isLooping: _isLooping,
          hasSequence: _currentSequence.isNotEmpty, hasSelection: _selectionStart != -1 && _selectionEnd != -1,
          selectionStart: _selectionStart, selectionEnd: _selectionEnd,
          onPlay: _playLick, onStop: _stopPlayback, onToggleLoop: () => setState(() => _isLooping = !_isLooping),
          onSave: _saveCurrentLick, onCopy: () => Clipboard.setData(ClipboardData(text: _generatedTab)), onClearSelection: _clearSelection,
        ),
        _buildInteractiveTabOutput(),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
      value: value, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged,
    );
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(), keyboardType: TextInputType.number, textAlign: TextAlign.center,
      decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(fontSize: 11, height: 1.1), floatingLabelAlignment: FloatingLabelAlignment.center,
          floatingLabelBehavior: FloatingLabelBehavior.always, alignLabelWithHint: true, isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: const OutlineInputBorder()),
      onChanged: (val) {
        int? parsed = int.tryParse(val);
        if (parsed != null && parsed >= 0) { onChanged(parsed); _generateTab(); }
      },
    );
  }

  Widget _buildInteractiveTabOutput() {
    if (_currentSequence.isEmpty) {
      return Expanded(child: Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)), width: double.infinity, child: Text(_generatedTab, style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent))));
    }
    return Expanded(
      child: ValueListenableBuilder<int>(
        valueListenable: _currentPlayingNoteIndex,
        builder: (context, playingIndex, child) {
          return InteractiveTabDisplay(
            sequence: _currentSequence, rhythmStr: _selectedRhythm, measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
            currentPlayingIndex: playingIndex, selectionStart: _selectionStart, selectionEnd: _selectionEnd, tuningStr: _selectedTuning,
            onBeatTapped: (index) => setState(() {
                if (_selectionStart == -1 || (_selectionStart != -1 && _selectionEnd != _selectionStart)) { _selectionStart = index; _selectionEnd = index; _tapAnchorIndex = index; } 
                else { _selectionStart = min(_tapAnchorIndex!, index); _selectionEnd = max(_tapAnchorIndex!, index); }
              }),
          );
        },
      ),
    );
  }
}