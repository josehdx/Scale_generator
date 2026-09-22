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
import '../models/motif_token.dart';
import '../models/preset_sanitizer.dart';
import '../scale_engine.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/playback_control_bar.dart';
import '../widgets/studio/studio_components.dart';
import '../widgets/studio/theory_section.dart';
import '../widgets/studio/pathways_section.dart';
import '../widgets/studio/formatting_section.dart';
import '../widgets/studio/tab_output_section.dart';
import 'saved_presets_screen.dart';

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});
  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
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
  static const String _storageKey = 'auto_saved_lick_presets';
  static const String _sessionKey = 'last_session_state';
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
  bool _isLoadingPreset = false;
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
  final TextEditingController _customNpsController = TextEditingController(text: "3,4,3,4,3,3");

  // MANUAL ENTRY STATE
  final TextEditingController _manualTabController = TextEditingController(text: "6:5, 6:8, 5:5, 5:7");
  String _manualSelectedDuration = "16th";

  // MOTIF & PATHWAY STATE
  String _selectedPathway = "Custom Motif Builder";
  String _selectedDirection = "Ascend -> Descend";
  List<MotifToken> _motifTokens = [];
  final TextEditingController _customSequenceController = TextEditingController(text: "1, 2, 3, 4, 5, 6, 7, 8");

  // RHYTHM & FORMATTING STATE
  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1;
  int _tempo = 120;
  String _selectedRhythmPattern = "Straight 16ths";
  String _selectedTimeSignature = "Auto";
  final TextEditingController _customRhythmController = TextEditingController(text: "16,16,8");
  final TextEditingController _customAccentController = TextEditingController(text: "1,0,0,0");
  String _lastAutoAccentString = "1,0,0,0";
  List<String> _parsedRhythmPattern = ["16th"];
  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];
  List<LickPreset> _savedPresets = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Custom Notes-Per-String", "Single String Horizontal", "Manual Entry"];
  final List<String> _pathways = ["Straight Linear", "3-Step Triplet", "4-Step 16th", "Note Skipping", "Custom Motif Builder", "Custom Sequence (Indices)"];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way (Ascend)", "One-Way (Descend)"];
  final List<String> _rhythmPatterns = ["Straight 16ths", "Straight 8ths", "Gallop (8-16-16)", "Reverse Gallop (16-16-8)", "Syncopated (16-8-16)", "Custom Pattern"];
  final List<String> _timeSignatures = ["Auto", "2/4", "3/4", "4/4", "5/4", "6/4", "7/4", "9/4", "12/4"];
  final Map<String, int> _guitarSounds = {"Clean Electric": 27, "Steel Acoustic": 25, "Jazz Electric": 26, "Nylon Acoustic": 24};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedPageIndex);
    _loadSoundFont();
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

  String _getMotifString() => _motifTokens.map((t) => t.value).join(',');

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
    double maxMultiplier = 1.0;
    for (String rhythm in _parsedRhythmPattern) {
      double mult = {"Quarter": 1.0, "8th": 2.0, "16th": 4.0}[rhythm] ?? 4.0;
      if (mult > maxMultiplier) maxMultiplier = mult;
    }
    double nps = (_tempo / 60) * maxMultiplier;
    return nps.toStringAsFixed(1);
  }

  bool _isAutoAccent(String val) {
    final parts = val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty || parts.first != "1") return false;
    if (parts.length == 1) return true;
    return parts.skip(1).every((e) => e == "0");
  }

  List<int> _parseAccentPattern(String val) {
    if (val.trim().isEmpty) return [100];
    return val.split(',').map((e) {
      String c = e.trim();
      return (c == "1") ? 127 : 80;
    }).toList();
  }

  List<String> _parsePatternString(String val, {String? customRhythmOverride}) {
    switch (val) {
      case "Straight 8ths": return ["8th"];
      case "Gallop (8-16-16)": return ["8th", "16th", "16th"];
      case "Reverse Gallop (16-16-8)": return ["16th", "16th", "8th"];
      case "Syncopated (16-8-16)": return ["16th", "8th", "16th"];
      case "Custom Pattern":
        String rhythmStr = customRhythmOverride ?? _customRhythmController.text;
        return rhythmStr.split(',').map((e) {
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

  List<List<int>> _parseManualTab(String val) {
    List<List<int>> result = [];
    var parts = val.split(',');
    for (var p in parts) {
      var pair = p.split(':');
      if (pair.length == 2) {
        int? stringNum = int.tryParse(pair[0].trim());
        int? fretNum = int.tryParse(pair[1].trim());
        if (stringNum != null && fretNum != null && stringNum >= 1 && stringNum <= 6 && fretNum >= 0) {
          result.add([stringNum, fretNum]);
        }
      } else if (p.trim().toUpperCase() == 'R') {
        result.add([-1, -1]);
      }
    }
    return result;
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
        if (_selectedDirection.contains("Ascend") && !_selectedDirection.startsWith("Ascend -> Ascend")) {
          _selectedDirection = "One-Way (Descend)";
        } else if (_selectedDirection == "Ascend -> Descend") {
          _selectedDirection = "Descend -> Ascend";
        }
      }
      _motifTokens = _motifTokens.reversed.toList();
      _generateTab();
    });
  }

  void _handleFretboardTap(String noteName, int stringNum, int fretNum) {
    if (_selectedSystem == "Manual Entry") {
      int pitch = _engine.openStrings[stringNum]! + fretNum;
      _midiPro.playMidiNote(midi: pitch, velocity: 127);
      Future.delayed(const Duration(milliseconds: 300), () => _midiPro.stopMidiNote(midi: pitch));
      
      if (_selectedRhythmPattern != "Custom Pattern") {
        setState(() { _selectedRhythmPattern = "Custom Pattern"; });
      }
      List<List<int>> currentSeq = _parseManualTab(_manualTabController.text);
      List<String> currentRhythms = _customRhythmController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      
      while(currentRhythms.length < currentSeq.length) currentRhythms.add("16th");
      int cursor = _selectionStart != -1 ? max(_selectionStart, _selectionEnd) : currentSeq.length;
      
      if (cursor >= currentSeq.length) {
        currentSeq.add([stringNum, fretNum]);
        currentRhythms.add(_manualSelectedDuration);
        cursor = currentSeq.length; 
      } else {
        currentSeq[cursor] = [stringNum, fretNum];
        currentRhythms[cursor] = _manualSelectedDuration;
        cursor++; 
      }
      _manualTabController.text = currentSeq.map((n) => n[0] == -1 ? "R" : "${n[0]}:${n[1]}").join(", ");
      _customRhythmController.text = currentRhythms.join(",");
      
      setState(() {
        _selectionStart = cursor < currentSeq.length ? cursor : -1;
        _selectionEnd = _selectionStart;
        _tapAnchorIndex = _selectionStart;
      });
      
      _generateTab();
    } else {
      setState(() { _selectedKey = noteName; _startFret = fretNum; _generateTab(); });
    }
  }

  void _handleInsertRest() {
    if (_selectedRhythmPattern != "Custom Pattern") {
      setState(() { _selectedRhythmPattern = "Custom Pattern"; });
    }
    List<List<int>> currentSeq = _parseManualTab(_manualTabController.text);
    List<String> currentRhythms = _customRhythmController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    while(currentRhythms.length < currentSeq.length) currentRhythms.add("16th");
    int cursor = _selectionStart != -1 ? max(_selectionStart, _selectionEnd) : currentSeq.length;
    if (cursor >= currentSeq.length) {
      currentSeq.add([-1, -1]);
      currentRhythms.add(_manualSelectedDuration);
      cursor = currentSeq.length;
    } else {
      currentSeq[cursor] = [-1, -1];
      currentRhythms[cursor] = _manualSelectedDuration;
      cursor++;
    }
    _manualTabController.text = currentSeq.map((n) => n[0] == -1 ? "R" : "${n[0]}:${n[1]}").join(", ");
    _customRhythmController.text = currentRhythms.join(",");
    setState(() {
      _selectionStart = cursor < currentSeq.length ? cursor : -1;
      _selectionEnd = _selectionStart;
      _tapAnchorIndex = _selectionStart;
    });
    _generateTab();
  }

  void _showManualDeleteMenu() {
    int startIdx, endIdx;
    
    if (_selectionStart != -1 && _selectionEnd != -1) {
      startIdx = min(_selectionStart, _selectionEnd);
      endIdx = max(_selectionStart, _selectionEnd);
    } else {
      int cursor = _currentSequence.length - 1;
      if (cursor < 0) return;
      startIdx = cursor;
      endIdx = cursor;
    }
    
    int count = endIdx - startIdx + 1;
    showModalBottomSheet(context: context, builder: (c) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.clear),
              title: Text("Clear $count Note${count > 1 ? 's' : ''} (Keep Empty Space)"),
              onTap: () {
                Navigator.pop(c);
                List<List<int>> currentSeq = _parseManualTab(_manualTabController.text);
                
                for (int i = startIdx; i <= endIdx; i++) {
                  if (i < currentSeq.length) {
                    currentSeq[i] = [-1, -1];
                  }
                }
                
                _manualTabController.text = currentSeq.map((n) => n[0] == -1 ? "R" : "${n[0]}:${n[1]}").join(", ");
                _generateTab();
              }
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text("Delete $count Beat${count > 1 ? 's' : ''} (Shorten Tab)", style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(c);
                List<List<int>> currentSeq = _parseManualTab(_manualTabController.text);
                List<String> currentRhythms = _customRhythmController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                
                int actualStart = startIdx.clamp(0, currentSeq.length - 1);
                int actualEnd = endIdx.clamp(0, currentSeq.length - 1);
                
                currentSeq.removeRange(actualStart, actualEnd + 1);
                
                int rStart = startIdx.clamp(0, currentRhythms.length);
                int rEnd = (endIdx + 1).clamp(0, currentRhythms.length);
                if (rStart < rEnd) {
                  currentRhythms.removeRange(rStart, rEnd);
                }
                
                _manualTabController.text = currentSeq.map((n) => n[0] == -1 ? "R" : "${n[0]}:${n[1]}").join(", ");
                _customRhythmController.text = currentRhythms.join(",");
                
                setState(() {
                  if (currentSeq.isEmpty) {
                    _selectionStart = -1;
                  } else {
                    _selectionStart = actualStart > 0 ? actualStart - 1 : 0;
                    if (_selectionStart >= currentSeq.length) {
                      _selectionStart = currentSeq.length - 1;
                    }
                  }
                  _selectionEnd = _selectionStart;
                  _tapAnchorIndex = _selectionStart;
                });
                _generateTab();
              }
            ),
          ],
        ),
      );
    });
  }

  Future<void> _loadSessionFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_sessionKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final preset = LickPreset.fromJson(jsonDecode(jsonString));
        _applyPresetState(preset);
        return;
      }
    } catch (e) {
      debugPrint("Session Read Error: $e");
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateTab());
  }

  Future<void> _saveSessionToDisk() async {
    if (_currentSequence.isEmpty) return;
    try {
      final preset = _buildCurrentStateAsPreset('session', 'session');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(preset.toJson()));
    } catch (e) {
      debugPrint("Session Write Error: $e");
    }
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

  LickPreset _buildCurrentStateAsPreset(String id, String name) {
    return LickPreset(
      id: id, name: name, key: _selectedKey, scale: _selectedScale,
      tuning: _selectedTuning, system: _selectedSystem, 
      fragment: _selectedSystem == "Single String Horizontal" ? _singleStringTarget.toString() : "$_startString-$_endString", 
      customNps: _customNpsProfile, startFret: _startFret, pathway: _selectedPathway, direction: _selectedDirection, 
      motifString: _selectedPathway == "Custom Motif Builder" ? _getMotifString() : _customSequenceController.text, 
      rhythm: _selectedRhythmPattern, customRhythmString: _customRhythmController.text, customAccentString: _customAccentController.text,
      manualTabString: _manualTabController.text, timeSignature: _selectedTimeSignature,
      tempo: _tempo, measuresPerLine: _measuresPerLine, breakInterval: _breakInterval, 
      breakLength: _breakLength, endRests: _endRests, tabOutput: _generatedTab, instrumentIndex: _selectedInstrumentIndex, createdAt: DateTime.now(),
    );
  }

  void _saveCurrentLick() {
    if (_currentSequence.isEmpty || _generatedTab.startsWith(" ")) return;
    
    if (_selectedSystem == "Manual Entry") {
      TextEditingController nameController = TextEditingController();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Save Manual Tab"),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: "Preset Name", border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context);
                  _executeSave(nameController.text.trim());
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      );
    } else {
      String patternLabel = _selectedPathway.contains("Custom") ? "Custom Pattern" : _selectedPathway;
      String presetName = "$_selectedKey $_selectedScale - $patternLabel (Fret $_startFret)";
      _executeSave(presetName);
    }
  }

  void _executeSave(String presetName) {
    final preset = _buildCurrentStateAsPreset(DateTime.now().millisecondsSinceEpoch.toString(), presetName);
    setState(() => _savedPresets.insert(0, preset));
    _savePresetsToDisk();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved Preset: '$presetName'")));
  }

  void _applyPresetState(LickPreset preset) {
    _isLoadingPreset = true;
    setState(() {
      _selectedKey = preset.key;
      _selectedScale = preset.scale;
      _selectedTuning = preset.tuning;
      _selectedSystem = preset.system;
      _startFret = preset.startFret.clamp(0, 24);
      _selectedPathway = preset.pathway;
      _customNpsProfile = preset.customNps;
      _customNpsController.text = preset.customNps;
      _manualTabController.text = preset.manualTabString;
      _selectedTimeSignature = preset.timeSignature;
      
      if (preset.system == "Single String Horizontal") {
        _singleStringTarget = (int.tryParse(preset.fragment) ?? 1).clamp(1, 6);
      } else {
        if (preset.fragment.contains('-') && !preset.fragment.contains('Strings')) {
          var parts = preset.fragment.split('-');
          _startString = (int.tryParse(parts[0]) ?? 6).clamp(1, 6);
          _endString = (int.tryParse(parts[1]) ?? 1).clamp(1, 6);
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
      _customRhythmController.text = preset.customRhythmString;
      _customAccentController.text = preset.customAccentString;
      _lastAutoAccentString = preset.customAccentString;
      _tempo = preset.tempo;
      _measuresPerLine = preset.measuresPerLine;
      _breakInterval = preset.breakInterval;
      _breakLength = preset.breakLength;
      _endRests = preset.endRests;
      _generatedTab = preset.tabOutput;
      _selectedInstrumentIndex = preset.instrumentIndex;
      
      _selectionStart = -1;
      _selectionEnd = -1;
      _tapAnchorIndex = null;
    });
    _changeGuitarSound(preset.instrumentIndex);
    _generateTab();
    _isLoadingPreset = false;
  }

  void _loadPreset(LickPreset preset) {
    _applyPresetState(preset);
    _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  List<List<int>> _buildSequenceForPreset(LickPreset preset) {
    _engine.setTuning(preset.tuning);
    if (preset.system == "Manual Entry") {
      return _parseManualTab(preset.manualTabString);
    }
    int safeStartFret = preset.startFret.clamp(0, 24);
    int safeSingleTarget = (int.tryParse(preset.fragment) ?? 1).clamp(1, 6);
    int stStr = 6, enStr = 1;
    if (preset.system != "Single String Horizontal") {
      if (preset.fragment.contains('-') && !preset.fragment.contains('Strings')) {
        var parts = preset.fragment.split('-');
        stStr = (int.tryParse(parts[0]) ?? 6).clamp(1, 6);
        enStr = (int.tryParse(parts[1]) ?? 1).clamp(1, 6);
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
      boxDict = _engine.getScaleNotesBox(preset.key, preset.scale, safeStartFret, targetStrings);
    } else if (preset.system == "3-Note-Per-String (3NPS)") {
      boxDict = _engine.getScaleNotes3NPS(preset.key, preset.scale, safeStartFret, targetStrings);
    } else if (preset.system == "Custom Notes-Per-String") {
      List<int> customNpsList = preset.customNps.split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
      while (customNpsList.length < 6) customNpsList.add(3);
      boxDict = _engine.getScaleNotesCustomNPS(preset.key, preset.scale, safeStartFret, targetStrings, customNpsList.take(6).toList());
    } else {
      boxDict = _engine.getScaleNotesSingleString(preset.key, preset.scale, safeStartFret, safeSingleTarget);
    }
    
    List<List<int>> sequence = [];
    if (preset.pathway == "Custom Motif Builder") {
      if (preset.system == "Single String Horizontal") {
        sequence = _engine.buildSingleStringMotif(boxDict, preset.motifString, safeSingleTarget, preset.direction);
      } else if (targetStrings.length >= 2) {
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
    _activeNoteNotifier.value = null;
    _parsedRhythmPattern = _parsePatternString(_selectedRhythmPattern);
    
    if (_selectedSystem == "Manual Entry") {
      _currentSequence = _parseManualTab(_manualTabController.text);
    } else {
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
        List<int> customNpsList = _customNpsController.text.split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
        while (customNpsList.length < 6) customNpsList.add(3);
        boxDict = _engine.getScaleNotesCustomNPS(_selectedKey, _selectedScale, _startFret, targetStrings, customNpsList.take(6).toList());
      } else {
        boxDict = _engine.getScaleNotesSingleString(_selectedKey, _selectedScale, _startFret, _singleStringTarget);
      }
      
      _currentSequence = [];
      if (_selectedPathway == "Custom Motif Builder") {
        if (_selectedSystem == "Single String Horizontal") {
          _currentSequence = _engine.buildSingleStringMotif(boxDict, _getMotifString(), _singleStringTarget, _selectedDirection);
        } else {
          if (targetStrings.length < 2) {
            setState(() => _generatedTab = "  Custom Motif Builder requires at least 2 strings.");
            return;
          }
          _currentSequence = _engine.buildCustomMotif(boxDict, _getMotifString(), _startString, _endString);
        }
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
    }
    
    if (_currentSequence.isEmpty) {
      setState(() => _generatedTab = "  Error: No valid notes found.");
      return;
    }
    
    _currentSequence = _engine.applyIntervalBreaks(_currentSequence, _breakInterval, _breakLength);
    for (int i = 0; i < _endRests; i++) _currentSequence.add([-1, -1]);
    
    int calculatedNotesPerMeasure = _calculateNotesPerMeasure();
    if (_isAutoAccent(_customAccentController.text)) {
      List<String> newAccentList = List.generate(_dynamicBeatsPerMeasure, (i) => i == 0 ? "1" : "0");
      String newAccentStr = newAccentList.join(",");
      if (_customAccentController.text != newAccentStr) {
        _customAccentController.text = newAccentStr;
      }
    }
    setState(() {
      _generatedTab = _engine.renderAsciiTab(
        _currentSequence,
        notesPerMeasure: calculatedNotesPerMeasure,
        rhythmLabel: _selectedRhythmPattern,
        nps: _currentNps,
        measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
        beatsPerMeasure: _dynamicBeatsPerMeasure,
        tempo: _tempo,
      );
    });
    
    _saveSessionToDisk();
  }

  void _playLick({
    List<List<int>>? overrideSequence, 
    int? overrideTempo, 
    String? overrideRhythm, 
    String? overrideCustomRhythm,
    String? overrideAccentPattern, 
    String? overrideTuning, 
    String? overrideKey, 
    String? overrideScale,
    int? overrideInstrument,
    String? presetId
  }) async {
    if (!_isMidiReady) return;
    List<List<int>> seqToPlay = overrideSequence ?? _currentSequence;
    if (seqToPlay.isEmpty) return;
    
    _stopPlayback();
    _playbackToken++;
    final int currentToken = _playbackToken;
    bool isPreview = presetId != null;
    if (overrideInstrument != null && overrideInstrument != _selectedInstrumentIndex) {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: overrideInstrument);
    }
    
    setState(() {
      if (isPreview) {
        _isPreviewPlaying = true;
        _previewPresetId = presetId;
      } else {
        _isPlaying = true;
      }
    });
    _midiPro.playMidiNote(midi: 12, velocity: 1);
    await Future.delayed(const Duration(milliseconds: 150));
    _midiPro.stopMidiNote(midi: 12);
    
    String rhythm = overrideRhythm ?? _selectedRhythmPattern;
    int tempo = overrideTempo ?? _tempo;
    String tuning = overrideTuning ?? _selectedTuning;
    
    Map<int, int> activeOpenStrings = _engine.tunings[tuning] ?? _engine.openStrings;
    List<String> activePattern = _parsePatternString(rhythm, customRhythmOverride: overrideCustomRhythm);
    List<int> activeAccents = _parseAccentPattern(overrideAccentPattern ?? _customAccentController.text);
    
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
        
        int currentVelocity = activeAccents[i % activeAccents.length];
        
        if (note[0] != -1) {
          pitch = activeOpenStrings[note[0]]! + note[1];
          _midiPro.playMidiNote(midi: pitch, velocity: currentVelocity);
          _activeMidiNotes.add(pitch);
        }
        
        _activeNoteNotifier.value = {
          'string': note[0],
          'fret': note[1],
          'isPreview': isPreview,
          'index': i,
          'previewKey': overrideKey,
          'previewScale': overrideScale,
          'previewTuning': overrideTuning,
          'isAccent': currentVelocity == 127,
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
    _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2', instrumentIndex: _selectedInstrumentIndex);
  }

  Widget _buildStudioScreen() {
    bool isManualMode = _selectedSystem == "Manual Entry";
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Interactive Fretboard", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              GestureDetector(
                onTap: () => setState(() => _isFretboardVisible = !_isFretboardVisible),
                child: Icon(_isFretboardVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey, size: 24),
              ),
            ],
          ),
        ),
        if (_isFretboardVisible)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, right: 8.0),
            child: ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: _activeNoteNotifier,
              builder: (context, noteData, child) {
                int? actStr, actFret, prevStr, prevFret;
                String? pKey, pScale, pTuning;
                bool? isAccent;
                if (noteData != null && noteData['string'] != -1) {
                  isAccent = noteData['isAccent'];
                  if (noteData['isPreview']) {
                    prevStr = noteData['string'];
                    prevFret = noteData['fret'];
                    pKey = noteData['previewKey'];
                    pScale = noteData['previewScale'];
                    pTuning = noteData['previewTuning'];
                  } else {
                    actStr = noteData['string'];
                    actFret = noteData['fret'];
                  }
                }
                return InteractiveFretboard(
                  engine: _engine, selectedKey: _selectedKey, selectedScale: _selectedScale, startFret: _startFret, 
                  selectedTuning: _selectedTuning, activeString: actStr, activeFret: actFret, 
                  previewString: prevStr, previewFret: prevFret, previewKey: pKey, previewScale: pScale, previewTuning: pTuning, 
                  isAccent: isAccent,
                  isManualMode: isManualMode,
                  scrollController: _fretboardScrollController, 
                  onNoteTapped: _handleFretboardTap,
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        PlaybackControlBar(isPlaying: _isPlaying, isMidiReady: _isMidiReady, isLooping: _isLooping, hasSequence: _currentSequence.isNotEmpty, hasSelection: _selectionStart != -1 && _selectionEnd != -1, selectionStart: _selectionStart, selectionEnd: _selectionEnd, onPlay: _playLick, onStop: _stopPlayback, onToggleLoop: () => setState(() => _isLooping = !_isLooping), onSave: _saveCurrentLick, onCopy: () => Clipboard.setData(ClipboardData(text: _generatedTab)), onClearSelection: _clearSelection),
        const SizedBox(height: 4),
        Expanded(
          child: ClipRect(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (ScrollUpdateNotification notification) {
                if (notification.dragDetails != null) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    CollapsibleSection(
                      title: "  1. Theory & System",
                      isExpanded: _isTheoryExpanded,
                      onToggle: () => setState(() => _isTheoryExpanded = !_isTheoryExpanded),
                      child: TheorySection(
                        isManualMode: isManualMode,
                        manualSelectedDuration: _manualSelectedDuration,
                        selectedKey: _selectedKey, availableKeys: _engine.noteMap.keys.toList(),
                        selectedScale: _selectedScale, availableScales: _engine.scaleFormulas.keys.toList(),
                        selectedTuning: _selectedTuning, availableTunings: _engine.tunings.keys.toList(),
                        selectedSystem: _selectedSystem, availableSystems: _systems,
                        singleStringTarget: _singleStringTarget, startString: _startString,
                        endString: _endString, startFret: _startFret, customNpsController: _customNpsController,
                        onCursorLeft: () => setState(() { _selectionStart = max(0, (_selectionStart == -1 ? _currentSequence.length : _selectionStart) - 1); _selectionEnd = _selectionStart; }),
                        onCursorRight: () => setState(() { if (_selectionStart != -1) { _selectionStart = min(_currentSequence.length - 1, _selectionStart + 1); _selectionEnd = _selectionStart; } }),
                        onInsertRest: _handleInsertRest,
                        onDeleteMenu: _showManualDeleteMenu,
                        onManualDurationChanged: (v) => setState(() => _manualSelectedDuration = v!),
                        onKeyChanged: (v) => setState(() { _selectedKey = v!; _generateTab(); }),
                        onScaleChanged: (v) => setState(() { _selectedScale = v!; _generateTab(); }),
                        onTuningChanged: (v) => setState(() { _selectedTuning = v!; _generateTab(); }),
                        onSystemChanged: (v) => setState(() { 
                           _selectedSystem = v!; 
                           if (_selectedSystem == "Manual Entry") {
                            _isFretboardVisible = true;
                            _isTabExpanded = true;
                          }
                          _clearSelection(); 
                           _generateTab(); 
                         }),
                        onSingleStringTargetChanged: (v) => setState(() { _singleStringTarget = int.parse(v!); _generateTab(); }),
                        onStartStringChanged: (v) => setState(() { _startString = int.parse(v!); _generateTab(); }),
                        onEndStringChanged: (v) => setState(() { _endString = int.parse(v!); _generateTab(); }),
                        onSwapStrings: _swapStrings,
                        onCustomNpsChanged: (val) { _customNpsProfile = val; _generateTab(); },
                        onStartFretChanged: (val) => setState(() { _startFret = val; _generateTab(); }),
                      ),
                    ),
                    if (!isManualMode)
                      CollapsibleSection(
                        title: "  2. Pathways & Motifs",
                        isExpanded: _isPathwaysExpanded,
                        onToggle: () => setState(() => _isPathwaysExpanded = !_isPathwaysExpanded),
                        child: PathwaysSection(
                          selectedPathway: _selectedPathway, availablePathways: _pathways,
                          selectedDirection: _selectedDirection, availableDirections: _directions,
                          selectedSystem: _selectedSystem, motifTokens: _motifTokens, customSequenceController: _customSequenceController,
                          onPathwayChanged: (v) => setState(() { _selectedPathway = v!; _generateTab(); }),
                          onDirectionChanged: (v) => _onDirectionChanged(v!),
                          onMotifAdded: (note) => setState(() { _motifTokens.add(MotifToken(UniqueKey().toString(), note)); _generateTab(); }),
                          onMotifRemoved: (index) => setState(() { _motifTokens.removeAt(index); _generateTab(); }),
                          onMotifReordered: (oldIndex, newIndex) => setState(() {
                            if (oldIndex < newIndex) newIndex -= 1;
                            final item = _motifTokens.removeAt(oldIndex);
                            _motifTokens.insert(newIndex, item);
                            _generateTab();
                          }),
                          onClearMotifs: () => setState(() { _motifTokens.clear(); _generateTab(); }),
                          onCustomSequenceChanged: (_) => _generateTab(),
                        ),
                      ),
                    CollapsibleSection(
                      title: isManualMode ? "  2. Formatting & Rhythm" : "  3. Formatting & Rhythm",
                      isExpanded: _isFormattingExpanded,
                      onToggle: () => setState(() => _isFormattingExpanded = !_isFormattingExpanded),
                      child: FormattingSection(
                        selectedRhythmPattern: _selectedRhythmPattern, availableRhythmPatterns: _rhythmPatterns,
                        selectedTimeSignature: _selectedTimeSignature, availableTimeSignatures: _timeSignatures,
                        tempo: _tempo, measuresPerLine: _measuresPerLine, currentNps: _currentNps,
                        customRhythmController: _customRhythmController, customAccentController: _customAccentController,
                        selectedInstrumentKey: _guitarSounds.keys.firstWhere((k) => _guitarSounds[k] == _selectedInstrumentIndex), availableInstruments: _guitarSounds.keys.toList(),
                        breakInterval: _breakInterval, breakLength: _breakLength, endRests: _endRests,
                        onRhythmChanged: (v) {
                          bool wasPlaying = _isPlaying;
                          setState(() => _selectedRhythmPattern = v!);
                          _generateTab();
                          if (wasPlaying) _playLick();
                        },
                        onTimeSignatureChanged: (v) {
                          bool wasPlaying = _isPlaying;
                          setState(() => _selectedTimeSignature = v!);
                          _generateTab();
                          if (wasPlaying) _playLick();
                        },
                        onTempoChanged: (v) {
                          bool wasPlaying = _isPlaying;
                          setState(() => _tempo = v.clamp(40, 300));
                          _generateTab();
                          if (wasPlaying) _playLick();
                        },
                        onMeasuresChanged: (v) { setState(() => _measuresPerLine = v); _generateTab(); },
                        onCustomRhythmChanged: (_) => _generateTab(),
                        onCustomAccentChanged: (_) => _generateTab(),
                        onInstrumentChanged: (v) { if (v != null) _changeGuitarSound(_guitarSounds[v]!); },
                        onBreakIntervalChanged: (v) { setState(() => _breakInterval = v); _generateTab(); },
                        onBreakLengthChanged: (v) { setState(() => _breakLength = v); _generateTab(); },
                        onEndRestsChanged: (v) { setState(() => _endRests = v); _generateTab(); },
                      ),
                    ),
                    CollapsibleSection(
                      title: isManualMode ? "  3. Generated Tab" : "  4. Generated Tab",
                      isExpanded: _isTabExpanded,
                      onToggle: () => setState(() => _isTabExpanded = !_isTabExpanded),
                      child: TabOutputSection(
                        currentSequence: _currentSequence, generatedTab: _generatedTab, autoTimeSignature: _autoTimeSignature,
                        activeNoteNotifier: _activeNoteNotifier, notesPerMeasure: _calculateNotesPerMeasure(),
                        rhythmStr: _parsedRhythmPattern.first, measuresPerLine: _measuresPerLine,
                        selectionStart: _selectionStart, selectionEnd: _selectionEnd, selectedTuning: _selectedTuning,
                        onBeatTapped: (index) => setState(() {
                          if (_selectionStart == -1 || (_selectionStart != -1 && _selectionEnd != _selectionStart)) {
                            _selectionStart = index; _selectionEnd = index; _tapAnchorIndex = index;
                          } else {
                            _selectionStart = min(_tapAnchorIndex!, index); _selectionEnd = max(_tapAnchorIndex!, index);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

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
          KeepAliveWrapper(child: _buildStudioScreen()),
          SavedPresetsScreen(
            savedPresets: _savedPresets,
            activePreviewId: _previewPresetId,
            isPreviewPlaying: _isPreviewPlaying,
            isPreviewLooping: _isPreviewLooping,
            onPlayPreview: (preset) {
              final (healedPreset, issues) = PresetSanitizer.validateAndSanitize(preset);

              if (issues.isNotEmpty && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Auto-aligned preset parameters: ${issues.map((i) => i.message).join(' ')}"),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.amber.shade900,
                  ),
                );
              }

              _playLick(
                overrideSequence: _buildSequenceForPreset(healedPreset),
                overrideTempo: healedPreset.tempo,
                overrideRhythm: healedPreset.rhythm,
                overrideCustomRhythm: healedPreset.customRhythmString,
                overrideAccentPattern: healedPreset.customAccentString,
                overrideTuning: healedPreset.tuning,
                overrideKey: healedPreset.key,
                overrideScale: healedPreset.scale,
                overrideInstrument: healedPreset.instrumentIndex,
                presetId: healedPreset.id,
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
                _savedPresets[idx] = LickPreset(
                  id: o.id, name: name, key: o.key, scale: o.scale, tuning: o.tuning, 
                  system: o.system, fragment: o.fragment, customNps: o.customNps, 
                  startFret: o.startFret, pathway: o.pathway, direction: o.direction, 
                  motifString: o.motifString, rhythm: o.rhythm, customRhythmString: o.customRhythmString, 
                  customAccentString: o.customAccentString, manualTabString: o.manualTabString, 
                  timeSignature: o.timeSignature, tempo: o.tempo, measuresPerLine: o.measuresPerLine, 
                  breakInterval: o.breakInterval, breakLength: o.breakLength, endRests: o.endRests, 
                  tabOutput: o.tabOutput, instrumentIndex: o.instrumentIndex, createdAt: o.createdAt
                );
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