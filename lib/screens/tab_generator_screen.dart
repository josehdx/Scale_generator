import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lick_preset.dart';
import '../scale_engine.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/interactive_tab_display.dart';
import '../widgets/playback_control_bar.dart';
import 'saved_presets_screen.dart';

// Token wrapper for robust ReorderableListView support
class MotifToken {
  final String id;
  final String value;
  MotifToken(this.id, this.value);
}

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
  int _playbackToken = 0;

  bool _isMidiReady = false;
  bool _isLooping = false;
  bool _isFretboardVisible = true;

  bool _isTheoryExpanded = false;
  bool _isPathwaysExpanded = false;
  bool _isFormattingExpanded = false;
  bool _isTabExpanded = false;

  final Set<int> _activeMidiNotes = {};
  final ScrollController _fretboardScrollController = ScrollController();
  
  // Drives both Fretboard and Tab display safely across previews and main playback
  final ValueNotifier<Map<String, dynamic>?> _activeNoteNotifier = ValueNotifier(null);

  int _selectionStart = -1;
  int _selectionEnd = -1;
  int? _tapAnchorIndex;

  int _selectedInstrumentIndex = 27;

  // THEORY STATE
  String _selectedKey = "C";
  String _selectedScale = "Minor Pentatonic";
  String _selectedTuning = "Standard E";
  int _startFret = 8;
  String _selectedSystem = "Box Position / CAGED";
  int _startString = 6;
  int _endString = 1;
  int _singleStringTarget = 1;
  String _customNpsProfile = "3,4,3,4,3,3";

  // MOTIF & PATHWAY STATE
  String _selectedPathway = "Custom Motif Builder";
  String _selectedDirection = "Ascend -> Descend";
  List<MotifToken> _motifTokens = [];
  final TextEditingController _customSequenceController = TextEditingController(text: "1, 2, 3, 4, 5, 6, 7, 8");

  // RHYTHM STATE
  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1;
  int _tempo = 120;
  String _selectedRhythmPattern = "Straight 16ths";
  final TextEditingController _customRhythmController = TextEditingController(text: "16,16,8");
  List<String> _parsedRhythmPattern = ["16th"];

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];
  List<LickPreset> _savedPresets = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Custom Notes-Per-String", "Single String Horizontal"];
  final List<String> _pathways = ["Straight Linear", "3-Step Triplet", "4-Step 16th", "Note Skipping", "Custom Motif Builder", "Custom Sequence (Indices)"];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way (Ascend)", "One-Way (Descend)"];
  final List<String> _rhythmPatterns = ["Straight 16ths", "Straight 8ths", "Gallop (8-16-16)", "Reverse Gallop (16-16-8)", "Syncopated (16-8-16)", "Custom Pattern"];
  final Map<String, int> _guitarSounds = {"Clean Electric": 27, "Steel Acoustic": 25, "Jazz Electric": 26, "Nylon Acoustic": 24};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSoundFont();
    _loadPresetsFromDisk();
    
    // Init Motif Builder
    "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1".split(',').forEach((t) {
      _motifTokens.add(MotifToken(UniqueKey().toString(), t));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _generateTab());
  }

  @override
  void dispose() {
    _stopPlayback();
    _pageController.dispose();
    _fretboardScrollController.dispose();
    _activeNoteNotifier.dispose();
    _customRhythmController.dispose();
    _customSequenceController.dispose();
    super.dispose();
  }

  String _getMotifString() => _motifTokens.map((t) => t.value).join(',');

  int get _dynamicBeatsPerMeasure {
    if (_selectedPathway == "3-Step Triplet") return 3;
    if (_selectedPathway == "Custom Motif Builder") {
      return _motifTokens.isNotEmpty ? _motifTokens.length : 4;
    }
    if (_selectedPathway == "Custom Sequence (Indices)") {
      int count = _customSequenceController.text.split(',').where((e) => e.trim().isNotEmpty).length;
      return count > 0 ? count : 4;
    }
    return 4; 
  }

  String get _autoTimeSignature => "$_dynamicBeatsPerMeasure/4";

  List<String> _parsePatternString(String val) {
    switch (val) {
      case "Straight 8ths": return ["8th"];
      case "Gallop (8-16-16)": return ["8th", "16th", "16th"];
      case "Reverse Gallop (16-16-8)": return ["16th", "16th", "8th"];
      case "Syncopated (16-8-16)": return ["16th", "8th", "16th"];
      case "Custom Pattern":
        return _customRhythmController.text.split(',').map((e) {
          String c = e.trim();
          if (c == "4" || c == "Quarter") return "Quarter";
          if (c == "8" || c == "8th") return "8th";
          return "16th";
        }).toList();
      case "Straight 16ths":
      default:
        return ["16th"];
    }
  }

  int _calculateNotesPerMeasure() {
    int target16ths = _dynamicBeatsPerMeasure * 4;
    int current16ths = 0;
    int noteCount = 0;
    int patternIdx = 0;
    
    if (_parsedRhythmPattern.isEmpty) return _dynamicBeatsPerMeasure * 4;

    while (current16ths < target16ths) {
      String note = _parsedRhythmPattern[patternIdx % _parsedRhythmPattern.length];
      int length16ths = {"Quarter": 4, "8th": 2, "16th": 1}[note] ?? 1;
      current16ths += length16ths;
      noteCount++;
      patternIdx++;
    }
    return noteCount;
  }

  void _onDirectionChanged(String newDir) {
    bool needsSwap = false;
    if (newDir.contains("Ascend") && !newDir.startsWith("Descend -> Ascend")) {
      if (_startString < _endString) needsSwap = true;
    } else if (newDir.contains("Descend") && !newDir.startsWith("Ascend -> Descend")) {
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
      _generateTab();
    });
  }

  void _swapStrings() {
    setState(() {
      int temp = _startString;
      _startString = _endString;
      _endString = temp;
      
      if (_startString > _endString) {
        if (_selectedDirection.contains("Descend") && !_selectedDirection.startsWith("Descend -> Ascend")) {
          _selectedDirection = "One-Way (Ascend)";
        } else if (_selectedDirection == "Descend -> Ascend") {
          _selectedDirection = "Ascend -> Descend";
        }
      } else if (_startString < _endString) {
        if (_selectedDirection.contains("Ascend") && !_selectedDirection.startsWith("Ascend -> Descend")) {
          _selectedDirection = "One-Way (Descend)";
        } else if (_selectedDirection == "Ascend -> Descend") {
          _selectedDirection = "Descend -> Ascend";
        }
      }
      _motifTokens = _motifTokens.reversed.toList();
      _generateTab();
    });
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

  Future<void> _exportPresets(List<LickPreset> presetsToExport) async {
    if (presetsToExport.isEmpty) return;
    try {
      final jsonList = presetsToExport.map((e) => e.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      final directory = await getTemporaryDirectory();
      String safeName = presetsToExport.length == 1 
          ? presetsToExport.first.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          : 'TabStudio_Batch_${DateTime.now().millisecondsSinceEpoch}';
      final file = File('${directory.path}/$safeName.json');
      await file.writeAsString(jsonString);
      await Share.shareXFiles([XFile(file.path)], text: 'Tab Generator Studio Presets');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  Future<void> _importPresets() async {
    try {
      final List<PlatformFile>? result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json', 'txt'],
      );
      if (result != null && result.isNotEmpty && result.first.path != null) {
        File file = File(result.first.path!);
        String jsonString = await file.readAsString();
        final List<dynamic> decodedList = jsonDecode(jsonString);
        final List<LickPreset> importedPresets = decodedList.map((e) => LickPreset.fromJson(e)).toList();
        setState(() {
          for (var preset in importedPresets) {
            if (!_savedPresets.any((existing) => existing.id == preset.id)) _savedPresets.add(preset);
          }
          _savedPresets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
        _savePresetsToDisk();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imported successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import failed. Check format."), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: _selectedInstrumentIndex);
      if (mounted) setState(() => _isMidiReady = true);
    } catch (e) { debugPrint("MIDI Setup Error."); }
  }

  Future<void> _changeGuitarSound(int newIndex) async {
    setState(() => _selectedInstrumentIndex = newIndex);
    try { await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: newIndex); } 
    catch (e) { debugPrint("Error switching instrument: $e"); }
  }

  void _clearSelection() {
    setState(() { _selectionStart = -1; _selectionEnd = -1; _tapAnchorIndex = null; });
  }

  void _saveCurrentLick() {
    if (_currentSequence.isEmpty || _generatedTab.startsWith("❌")) return;
    String patternLabel = _selectedPathway.contains("Custom") ? "Custom Pattern" : _selectedPathway;
    String presetName = "$_selectedKey $_selectedScale - $patternLabel (Fret $_startFret)";
    
    final preset = LickPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(), name: presetName, key: _selectedKey, scale: _selectedScale,
      tuning: _selectedTuning, system: _selectedSystem, 
      fragment: _selectedSystem == "Single String Horizontal" ? _singleStringTarget.toString() : "$_startString-$_endString", 
      customNps: _customNpsProfile, startFret: _startFret, pathway: _selectedPathway, direction: _selectedDirection, 
      motifPairDirection: "Descend (High -> Low)", motifString: _selectedPathway == "Custom Motif Builder" ? _getMotifString() : _customSequenceController.text, 
      rhythm: _selectedRhythmPattern, tempo: _tempo, measuresPerLine: _measuresPerLine, breakInterval: _breakInterval, 
      breakLength: _breakLength, endRests: _endRests, tabOutput: _generatedTab, createdAt: DateTime.now(),
    );
    
    setState(() => _savedPresets.insert(0, preset));
    _savePresetsToDisk();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved Preset: '$presetName'")));
  }

  void _applyPresetState(LickPreset preset) {
    setState(() {
      _selectedKey = preset.key;
      _selectedScale = preset.scale;
      _selectedTuning = preset.tuning;
      _selectedSystem = preset.system;
      _startFret = preset.startFret;
      _selectedPathway = preset.pathway;
      _customNpsProfile = preset.customNps;

      if (preset.system == "Single String Horizontal") {
        _singleStringTarget = int.tryParse(preset.fragment) ?? 1;
      } else {
        if (preset.fragment.contains('-') && !preset.fragment.contains('Strings')) {
          var parts = preset.fragment.split('-');
          _startString = int.tryParse(parts[0]) ?? 6;
          _endString = int.tryParse(parts[1]) ?? 1;
        } else {
          _startString = 6; _endString = 1;
        }
      }

      String loadedDir = preset.direction;
      if (loadedDir == "One-Way") loadedDir = "One-Way (Ascend)";
      _selectedDirection = loadedDir;

      if (_selectedPathway == "Custom Motif Builder") {
        _motifTokens.clear();
        if (preset.motifString.isNotEmpty) {
          preset.motifString.split(',').forEach((t) {
            _motifTokens.add(MotifToken(UniqueKey().toString(), t));
          });
        }
      } else {
        _customSequenceController.text = preset.motifString;
      }

      _selectedRhythmPattern = preset.rhythm;
      _tempo = preset.tempo;
      _measuresPerLine = preset.measuresPerLine;
      _breakInterval = preset.breakInterval;
      _breakLength = preset.breakLength;
      _endRests = preset.endRests;
      _generatedTab = preset.tabOutput;
    });

    setState(() {}); // Force UI refresh for the dynamic time signature calculation
    _generateTab();
  }

  void _loadPreset(LickPreset preset) {
    _applyPresetState(preset);
    _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  List<int> _parseNpsProfile(String npsStr) {
    List<int> parsed = npsStr.split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
    while (parsed.length < 6) parsed.add(3);
    return parsed.take(6).toList();
  }

  List<List<int>> _buildSequenceForPreset(LickPreset preset) {
    _engine.setTuning(preset.tuning);
    int stStr = 6, enStr = 1;
    if (preset.system != "Single String Horizontal") {
      if (preset.fragment.contains('-') && !preset.fragment.contains('Strings')) {
        var parts = preset.fragment.split('-');
        stStr = int.tryParse(parts[0]) ?? 6;
        enStr = int.tryParse(parts[1]) ?? 1;
      }
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
      boxDict = _engine.getScaleNotesCustomNPS(preset.key, preset.scale, preset.startFret, targetStrings, _parseNpsProfile(preset.customNps));
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
        
        if (preset.direction.startsWith("One-Way")) sequence = patternNotes;
        else sequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
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
    _activeNoteNotifier.value = null;
    _parsedRhythmPattern = _parsePatternString(_selectedRhythmPattern);

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

    if (_selectedPathway == "Custom Motif Builder") {
      if (_selectedSystem == "Single String Horizontal" || targetStrings.length < 2) {
        setState(() => _generatedTab = "⚠️ Custom Motif Builder requires at least 2 strings.");
        return;
      }
      _currentSequence = _engine.buildCustomMotif(boxDict, _getMotifString(), _startString, _endString);
    } else {
      List<List<int>> baseNotes = _engine.flattenBoxDict(boxDict, _startString, _endString);
      if (_selectedPathway == "Custom Sequence (Indices)") {
        _currentSequence = _engine.buildCustomSequence(baseNotes, _customSequenceController.text);
      } else {
        List<List<int>> patternNotes;
        if (_selectedPathway == "3-Step Triplet") patternNotes = _engine.apply3StepSequence(baseNotes);
        else if (_selectedPathway == "4-Step 16th") patternNotes = _engine.apply4StepSequence(baseNotes);
        else if (_selectedPathway == "Note Skipping") patternNotes = _engine.applyNoteSkipping(baseNotes);
        else patternNotes = baseNotes;
        
        if (_selectedDirection.startsWith("One-Way")) _currentSequence = patternNotes;
        else _currentSequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
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
        _currentSequence,
        notesPerMeasure: _calculateNotesPerMeasure(),
        rhythmLabel: _selectedRhythmPattern,
        measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
        beatsPerMeasure: _dynamicBeatsPerMeasure,
        tempo: _tempo,
      );
    });
  }

  void _playLick({List<List<int>>? overrideSequence, int? overrideTempo, String? overrideRhythm, String? overrideTuning, String? presetId}) async {
    if (!_isMidiReady) return;
    List<List<int>> seqToPlay = overrideSequence ?? _currentSequence;
    if (seqToPlay.isEmpty) return;
    
    _stopPlayback(); 
    _playbackToken++;
    final int currentToken = _playbackToken;
    bool isPreview = presetId != null;
    
    setState(() {
      if (isPreview) {
        _isPreviewPlaying = true;
        _previewPresetId = presetId;
      } else {
        _isPlaying = true;
      }
    });
    
    String rhythm = overrideRhythm ?? _selectedRhythmPattern;
    int tempo = overrideTempo ?? _tempo;
    String tuning = overrideTuning ?? _selectedTuning;
    
    Map<int, int> activeOpenStrings = _engine.tunings[tuning] ?? _engine.openStrings;
    List<String> activePattern = _parsePatternString(rhythm);
    
    int startIdx = 0;
    int endIdx = seqToPlay.length - 1;
    if (!isPreview && _selectionStart != -1 && _selectionEnd != -1) {
      startIdx = _selectionStart.clamp(0, seqToPlay.length - 1);
      endIdx = _selectionEnd.clamp(startIdx, seqToPlay.length - 1);
    }
    
    do {
      for (int i = startIdx; i <= endIdx; i++) {
        if (!mounted || _playbackToken != currentToken || (isPreview && !_isPreviewPlaying) || (!isPreview && !_isPlaying)) {
           _stopPlayback(); 
           return;
        }
        
        var note = seqToPlay[i];
        int pitch = -1;
        
        if (note[0] != -1) {
          pitch = activeOpenStrings[note[0]]! + note[1];
          _midiPro.playMidiNote(midi: pitch, velocity: 127);
          _activeMidiNotes.add(pitch);
        }

        _activeNoteNotifier.value = {
          'string': note[0],
          'fret': note[1],
          'isPreview': isPreview,
          'index': i,
        };
        
        String currentRhythm = activePattern[i % activePattern.length];
        double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[currentRhythm] ?? 0.25;
        int msDelay = ((60000 / tempo) * beatMultiplier).round();
        if (msDelay < 20) msDelay = 20;

        await Future.delayed(Duration(milliseconds: msDelay));
        
        if (_playbackToken != currentToken) return;

        if (pitch != -1) {
          _midiPro.stopMidiNote(midi: pitch);
          _activeMidiNotes.remove(pitch);
        }
      }
    } while ((isPreview ? _isPreviewLooping : _isLooping) && mounted && _playbackToken == currentToken && ((isPreview && _isPreviewPlaying) || (!isPreview && _isPlaying)));
    
    if (_playbackToken == currentToken) {
      _stopPlayback();
    }
  }

  void _stopPlayback() {
    _playbackToken++;
    for (int pitch in _activeMidiNotes) _midiPro.stopMidiNote(midi: pitch);
    _activeMidiNotes.clear();
    _activeNoteNotifier.value = null;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _isPreviewPlaying = false;
      });
    }
  }

  // ===========================================================================
  // UI WIDGET BUILDERS
  // ===========================================================================

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true, 
      decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)), 
      value: value, 
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), 
      onChanged: onChanged
    );
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(), 
      keyboardType: TextInputType.number, 
      textAlign: TextAlign.center, 
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11, height: 1.1), floatingLabelAlignment: FloatingLabelAlignment.center, floatingLabelBehavior: FloatingLabelBehavior.always, alignLabelWithHint: true, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: const OutlineInputBorder()), 
      onChanged: (val) { 
        int? parsed = int.tryParse(val); 
        if (parsed != null && parsed >= 0) onChanged(parsed); 
      }
    );
  }

  Widget _buildMotifChipBuilder() {
    int maxNotes = 4; // default
    if (_selectedSystem == "3-Note-Per-String (3NPS)") maxNotes = 6;
    else if (_selectedSystem == "Box Position / CAGED") maxNotes = 4;
    else if (_selectedSystem == "Custom Notes-Per-String") maxNotes = 8; 
    
    List<String> availableNotes = [];
    for(int i=1; i<=maxNotes; i++) availableNotes.add("L$i");
    for(int i=1; i<=maxNotes; i++) availableNotes.add("H$i");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 12.0, bottom: 4.0),
          child: Text("Motif Timeline (Drag to reorder):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: _motifTokens.isEmpty
              ? const Center(child: Text("Sequence empty. Add notes from below.", style: TextStyle(color: Colors.grey, fontSize: 12)))
              : ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  itemCount: _motifTokens.length,
                  itemBuilder: (context, index) {
                    final token = _motifTokens[index];
                    bool isLower = token.value.startsWith('L');
                    return Padding(
                      key: ValueKey(token.id),
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InputChip(
                        label: Text(token.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: isLower ? Colors.blue.shade900 : Colors.teal.shade900,
                        deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.white70),
                        onDeleted: () {
                          setState(() {
                            _motifTokens.removeAt(index);
                            _generateTab();
                          });
                        },
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final item = _motifTokens.removeAt(oldIndex);
                      _motifTokens.insert(newIndex, item);
                      _generateTab();
                    });
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12.0, bottom: 4.0),
          child: Text("Available Notes Bank (Tap to add):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: availableNotes.map((note) {
            bool isLower = note.startsWith('L');
            return ActionChip(
              label: Text(note),
              backgroundColor: Colors.grey.shade900,
              side: BorderSide(color: isLower ? Colors.blue.shade700 : Colors.teal.shade700),
              onPressed: () {
                setState(() {
                  _motifTokens.add(MotifToken(UniqueKey().toString(), note));
                  _generateTab();
                });
              },
            );
          }).toList(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() { _motifTokens.clear(); _generateTab(); }),
            icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.redAccent),
            label: const Text("Clear Sequence", style: TextStyle(color: Colors.redAccent)),
          ),
        )
      ],
    );
  }

  Widget _buildCollapsibleSection(String title, bool isExpanded, VoidCallback onToggle, Widget child) {
    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
          onTap: onToggle, dense: true,
        ),
        AnimatedCrossFade(
          firstChild: Padding(padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12.0), child: child),
          secondChild: const SizedBox.shrink(),
          crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
        const Divider(height: 1, thickness: 1, color: Colors.black26),
      ],
    );
  }

  Widget _buildTheoryContent() {
    return Column(
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
            if (_selectedSystem == "Single String Horizontal")
              Expanded(
                flex: 2,
                child: _buildDropdown('String Target', _singleStringTarget.toString(), ["1", "2", "3", "4", "5", "6"], (v) => setState(() { _singleStringTarget = int.parse(v!); _generateTab(); }))
              )
            else ...[
              Expanded(child: _buildDropdown('Start Str', _startString.toString(), ["1", "2", "3", "4", "5", "6"], (v) {
                  setState(() { _startString = int.parse(v!); _generateTab(); });
              })),
              IconButton(icon: const Icon(Icons.swap_horiz, color: Colors.grey), onPressed: _swapStrings),
              Expanded(child: _buildDropdown('End Str', _endString.toString(), ["1", "2", "3", "4", "5", "6"], (v) {
                  setState(() { _endString = int.parse(v!); _generateTab(); });
              })),
            ],
          ],
        ),
        if (_selectedSystem == "Custom Notes-Per-String")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextFormField(
              initialValue: _customNpsProfile,
              decoration: const InputDecoration(labelText: "NPS Profile (e, B, G, D, A, E)", hintText: "e.g., 3, 4, 3, 4, 3, 3", border: OutlineInputBorder(), isDense: true),
              onChanged: (val) { _customNpsProfile = val; _generateTab(); },
            ),
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
    );
  }

  Widget _buildPathwaysContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: _buildDropdown('Pathway', _selectedPathway, _pathways, (v) => setState(() { _selectedPathway = v!; _generateTab(); }))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2, 
              child: _selectedPathway == "Custom Motif Builder"
                  ? const SizedBox.shrink()
                  : _buildDropdown('Loop Direction', _selectedDirection, _directions, (v) => _onDirectionChanged(v!))
            ),
          ],
        ),
        if (_selectedPathway == "Custom Motif Builder")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _buildMotifChipBuilder(),
          )
        else if (_selectedPathway == "Custom Sequence (Indices)")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextField(
              controller: _customSequenceController,
              decoration: const InputDecoration(labelText: "Note Sequence (1-based index)", hintText: "e.g., 1, 2, 3, 2, 3, 4", border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _generateTab(),
            ),
          ),
      ],
    );
  }

  Widget _buildFormattingContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildDropdown(
                'Rhythm Pattern', _selectedRhythmPattern, _rhythmPatterns,
                (v) {
                  bool wasPlaying = _isPlaying;
                  setState(() => _selectedRhythmPattern = v!);
                  _generateTab();
                  if (wasPlaying) _playLick();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _buildNumberField(
                'Tempo\nBPM', _tempo,
                (v) {
                  bool wasPlaying = _isPlaying;
                  setState(() => _tempo = v.clamp(40, 300));
                  _generateTab();
                  if (wasPlaying) _playLick();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildNumberField('Wrap\nLines', _measuresPerLine, (v) { setState(() => _measuresPerLine = v); _generateTab(); }),
            ),
          ],
        ),
        if (_selectedRhythmPattern == "Custom Pattern")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextField(
              controller: _customRhythmController,
              decoration: const InputDecoration(labelText: "Custom Rhythm Pattern (e.g. 16,16,8,4)", border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _generateTab(),
            ),
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
            Expanded(child: _buildNumberField('Break\nInterval', _breakInterval, (v) { setState(() => _breakInterval = v); _generateTab(); })),
            const SizedBox(width: 8),
            Expanded(child: _buildNumberField('Break\nLength', _breakLength, (v) { setState(() => _breakLength = v); _generateTab(); })),
            const SizedBox(width: 8),
            Expanded(child: _buildNumberField('End\nRests', _endRests, (v) { setState(() => _endRests = v); _generateTab(); })),
          ],
        ),
      ],
    );
  }

  Widget _buildInteractiveTabOutput() {
    if (_currentSequence.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        width: double.infinity, 
        child: Text(_generatedTab, style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent))
      );
    }
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 350), 
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Time Signature: $_autoTimeSignature (Driven Automatically)", style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                const Icon(Icons.lock_outline, size: 12, color: Colors.grey),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: _activeNoteNotifier,
                builder: (context, noteData, child) {
                  int playingIdx = -1;
                  if (noteData != null && !noteData['isPreview']) playingIdx = noteData['index'];
                  
                  return InteractiveTabDisplay(
                    sequence: _currentSequence, 
                    rhythmStr: _parsedRhythmPattern.first, 
                    measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine, 
                    currentPlayingIndex: playingIdx, 
                    selectionStart: _selectionStart, 
                    selectionEnd: _selectionEnd, 
                    tuningStr: _selectedTuning, 
                    onBeatTapped: (index) => setState(() {
                      if (_selectionStart == -1 || (_selectionStart != -1 && _selectionEnd != _selectionStart)) {
                        _selectionStart = index; _selectionEnd = index; _tapAnchorIndex = index;
                      } else {
                        _selectionStart = min(_tapAnchorIndex!, index); _selectionEnd = max(_tapAnchorIndex!, index);
                      }
                    })
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(child: _buildDropdown('Scale', _selectedScale, _engine.scaleFormulas.keys.toList(), (v) => setState(() { _selectedScale = v!; _generateTab(); }))),
              const SizedBox(width: 8),
              Chip(avatar: const Icon(Icons.music_note, color: Colors.redAccent, size: 16), label: Text('Root: $_selectedKey | Fret: $_startFret')),
              IconButton(icon: Icon(_isFretboardVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey), tooltip: _isFretboardVisible ? 'Hide Fretboard' : 'Show Fretboard', onPressed: () => setState(() => _isFretboardVisible = !_isFretboardVisible))
            ],
          ),
        ),
        if (_isFretboardVisible)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: _activeNoteNotifier,
              builder: (context, noteData, child) {
                int? actStr, actFret, prevStr, prevFret;
                if (noteData != null && noteData['string'] != -1) {
                  if (noteData['isPreview']) {
                    prevStr = noteData['string'];
                    prevFret = noteData['fret'];
                  } else {
                    actStr = noteData['string'];
                    actFret = noteData['fret'];
                  }
                }
                return InteractiveFretboard(
                  engine: _engine, selectedKey: _selectedKey, selectedScale: _selectedScale, startFret: _startFret, 
                  selectedTuning: _selectedTuning, activeString: actStr, activeFret: actFret, 
                  previewString: prevStr, previewFret: prevFret, scrollController: _fretboardScrollController, 
                  onNoteTapped: (k, f) => setState(() { _selectedKey = k; _startFret = f; _generateTab(); })
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        PlaybackControlBar(isPlaying: _isPlaying, isMidiReady: _isMidiReady, isLooping: _isLooping, hasSequence: _currentSequence.isNotEmpty, hasSelection: _selectionStart != -1 && _selectionEnd != -1, selectionStart: _selectionStart, selectionEnd: _selectionEnd, onPlay: _playLick, onStop: _stopPlayback, onToggleLoop: () => setState(() => _isLooping = !_isLooping), onSave: _saveCurrentLick, onCopy: () => Clipboard.setData(ClipboardData(text: _generatedTab)), onClearSelection: _clearSelection),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildCollapsibleSection("  1. Theory & Fretboard", _isTheoryExpanded, () => setState(() => _isTheoryExpanded = !_isTheoryExpanded), _buildTheoryContent()),
                _buildCollapsibleSection("  2. Pathways & Motifs", _isPathwaysExpanded, () => setState(() => _isPathwaysExpanded = !_isPathwaysExpanded), _buildPathwaysContent()),
                _buildCollapsibleSection("  3. Formatting & Rhythm", _isFormattingExpanded, () => setState(() => _isFormattingExpanded = !_isFormattingExpanded), _buildFormattingContent()),
                _buildCollapsibleSection("  4. Generated Tab", _isTabExpanded, () => setState(() => _isTabExpanded = !_isTabExpanded), _buildInteractiveTabOutput()),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
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
          if (index != 0 && _isPlaying) _stopPlayback(); 
        },
        children: [
          _buildStudioScreen(),
          SavedPresetsScreen(
            savedPresets: _savedPresets,
            activePreviewId: _previewPresetId,
            isPreviewPlaying: _isPreviewPlaying,
            isPreviewLooping: _isPreviewLooping,
            onPlayPreview: (preset) {
              _applyPresetState(preset);
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
              if (ids.contains(_previewPresetId)) { _stopPlayback(); _previewPresetId = null; }
              _savePresetsToDisk();
             }),
            onRenamePreset: (id, name) => setState(() { 
              var idx = _savedPresets.indexWhere((p) => p.id == id); 
              if (idx != -1) { 
                var o = _savedPresets[idx]; 
                _savedPresets[idx] = LickPreset(id: o.id, name: name, key: o.key, scale: o.scale, tuning: o.tuning, system: o.system, fragment: o.fragment, customNps: o.customNps, startFret: o.startFret, pathway: o.pathway, direction: o.direction, motifPairDirection: o.motifPairDirection, motifString: o.motifString, rhythm: o.rhythm, tempo: o.tempo, measuresPerLine: o.measuresPerLine, breakInterval: o.breakInterval, breakLength: o.breakLength, endRests: o.endRests, tabOutput: o.tabOutput, createdAt: o.createdAt); 
                _savePresetsToDisk(); 
              } 
            }),
            onExportPresets: _exportPresets,
            onReorderPresets: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _savedPresets.removeAt(oldIndex);
                _savedPresets.insert(newIndex, item);
                _savePresetsToDisk();
              });
            },
            onImport: _importPresets,
          ),
        ],
      ),
    );
  }
}