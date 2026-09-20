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
    if (_startString > _endString) { // 6 to 1 is Ascending Pitch
      // Sync Motif Direction unconditionally
      if (_motifPairDirection != "Ascend (Low -> High)") {
        _motifPairDirection = "Ascend (Low -> High)";
        _customMotif = _invertMotifTokens(_customMotif);
        _selectedMotifTemplate = "Custom (Build Below)";
      }
      // Sync Standard Direction unconditionally
      if (_selectedDirection.contains("Descend") && !_selectedDirection.startsWith("Descend -> Ascend")) {
        _selectedDirection = "One-Way (Ascend)";
      } else if (_selectedDirection == "Descend -> Ascend") {
        _selectedDirection = "Ascend -> Descend";
      }
    } else if (_startString < _endString) { // 1 to 6 is Descending Pitch
      // Sync Motif Direction unconditionally
      if (_motifPairDirection != "Descend (High -> Low)") {
        _motifPairDirection = "Descend (High -> Low)";
        _customMotif = _invertMotifTokens(_customMotif);
        _selectedMotifTemplate = "Custom (Build Below)";
      }
      // Sync Standard Direction unconditionally
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

  void _generateTab() {
    _stopPlayback(); // Critical constraint fix: Kill active read-loop before mutating base data
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

  void _playLick() {
    if (!_isMidiReady || _currentSequence.isEmpty || _isPlaying) return;
    setState(() => _isPlaying = true);
    
    double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[_selectedRhythm] ?? 0.25;
    int msPerNote = ((60000 / _tempo) * beatMultiplier).round();
    if (msPerNote < 20) msPerNote = 20; // Hard fallback limit to mathematically prevent event loop flooding
    
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
              Expanded(child: _buildDropdown('Start Str', _startString.toString(), ["1", "2", "3", "4", "5", "6"], (v) => setState(() { 
                _startString = int.parse(v!); 
                _syncDirectionWithStrings();
                _generateTab(); 
              }))),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown('End Str', _endString.toString(), ["1", "2", "3", "4", "5", "6"], (v) => setState(() { 
                _endString = int.parse(v!); 
                _syncDirectionWithStrings();
                _generateTab(); 
              }))),
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

  Widget _buildTemplateDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return PopupMenuButton<String>(
      initialValue: value,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (BuildContext context) {
        return items.map((String item) {
          return PopupMenuItem<String>(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 14)),
          );
        }).toList();
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveMotifBuilder() {
    List<String> tokens = _customMotif.split(',').where((e) => e.trim().isNotEmpty).toList();

    int maxNPS = 3; 
    if (_selectedSystem == "Box Position / CAGED") {
      maxNPS = 2; 
    } else if (_selectedSystem == "3-Note-Per-String (3NPS)") {
      maxNPS = 3; 
    } else if (_selectedSystem == "Custom Notes-Per-String") {
      List<int> profile = _parseNpsProfile(_customNpsProfile);
      maxNPS = profile.isNotEmpty ? profile.reduce(max) : 3;
      maxNPS = maxNPS.clamp(2, 6); 
    }

    List<Widget> lowButtons = List.generate(maxNPS, (i) => _buildMotifAddButton("L${i+1}", Colors.teal));
    List<Widget> highButtons = List.generate(maxNPS, (i) => _buildMotifAddButton("H${i+1}", Colors.deepPurpleAccent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _buildTemplateDropdown(
          'Motif Template',
          _selectedMotifTemplate,
          _motifTemplates.keys.toList(),
          (v) {
            if (v != null) {
              setState(() {
                _selectedMotifTemplate = v;
                if (_motifTemplates[v]!.isNotEmpty) {
                  _customMotif = _motifTemplates[v]!;
                }
                _generateTab();
              });
            }
          },
        ),
        const SizedBox(height: 12),
        const Text("Tap Notes to Build Motif Pattern:", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ...lowButtons,
            const SizedBox(width: 8),
            ...highButtons,
          ],
        ),
        
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Motif Timeline (${tokens.length} notes):", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.backspace, size: 16, color: Colors.amberAccent),
                        tooltip: "Remove Last Note",
                        onPressed: tokens.isEmpty ? null : _removeLastMotifChip,
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(), 
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 18, color: Colors.redAccent),
                        tooltip: "Clear All",
                        onPressed: tokens.isEmpty ? null : _clearMotifChips,
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(), 
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 6),
              if (tokens.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text("Tap buttons above or select a Template.", style: TextStyle(fontSize: 12, color: Colors.white38, fontStyle: FontStyle.italic)),
                )
              else
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tokens.map((token) {
                    bool isLow = token.startsWith('L');
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLow ? Colors.teal.shade800 : Colors.deepPurple.shade700,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isLow ? Colors.tealAccent : Colors.purpleAccent, width: 0.8),
                      ),
                      child: Text(
                        token,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMotifAddButton(String token, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.0),
        child: InkWell(
          onTap: () => _addMotifChip(token),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              border: Border.all(color: color, width: 1.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              token,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white.withAlpha(230)),
            ),
          ),
        ),
      ),
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
                  ? _buildDropdown('Pair Direction', _motifPairDirection, ["Descend (High -> Low)", "Ascend (Low -> High)"], (v) => setState(() { 
                      if (_motifPairDirection != v) {
                        _customMotif = _invertMotifTokens(_customMotif);
                        _selectedMotifTemplate = "Custom (Build Below)";
                      }
                      _motifPairDirection = v!; 
                      _syncStringsWithDirection(v);
                      _generateTab(); 
                    }))
                  : _buildDropdown('Loop Direction', _selectedDirection, _directions, (v) => setState(() { 
                      _selectedDirection = v!; 
                      _syncStringsWithDirection(v);
                      _generateTab(); 
                    }))
            ),
          ],
        ),
        
        if (_selectedPathway == "Custom Motif Builder")
          _buildInteractiveMotifBuilder()
        else if (_selectedPathway == "Custom Sequence (Indices)")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextFormField(
              initialValue: _customSequence,
              decoration: const InputDecoration(labelText: "Note Sequence (1-based index)", hintText: "e.g., 1, 2, 3, 2, 3, 4", border: OutlineInputBorder(), isDense: true),
              onChanged: (val) { _customSequence = val; _generateTab(); },
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
            Expanded(flex: 2, child: _buildDropdown('Rhythm', _selectedRhythm, _rhythms, (v) { 
              bool wasPlaying = _isPlaying;
              setState(() => _selectedRhythm = v!); 
              _generateTab();
              if (wasPlaying) _playLick();
            })),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _buildNumberField('Tempo\nBPM', _tempo, (v) { 
              bool wasPlaying = _isPlaying;
              setState(() => _tempo = v.clamp(40, 300)); 
              _generateTab();
              if (wasPlaying) _playLick();
            })),
            const SizedBox(width: 8),
            Expanded(child: _buildNumberField('Wrap\nLines', _measuresPerLine, (v) { setState(() => _measuresPerLine = v); _generateTab(); })),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)),
      child: ValueListenableBuilder<int>(
        valueListenable: _currentPlayingNoteIndex,
        builder: (context, playingIndex, child) => InteractiveTabDisplay(
          sequence: _currentSequence, rhythmStr: _selectedRhythm, measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine, 
          currentPlayingIndex: playingIndex, selectionStart: _selectionStart, selectionEnd: _selectionEnd, tuningStr: _selectedTuning, 
          onBeatTapped: (index) => setState(() { 
            if (_selectionStart == -1 || (_selectionStart != -1 && _selectionEnd != _selectionStart)) { 
              _selectionStart = index; _selectionEnd = index; _tapAnchorIndex = index; 
            } else { 
              _selectionStart = min(_tapAnchorIndex!, index); _selectionEnd = max(_tapAnchorIndex!, index); 
            } 
          })
        ),
      ),
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
        onPageChanged: (index) => setState(() => _selectedPageIndex = index),
        children: [
          _buildStudioScreen(),
          SavedPresetsScreen(
            savedPresets: _savedPresets, onLoadPreset: _loadPreset, onDeletePresets: (ids) => setState(() { _savedPresets.removeWhere((p) => ids.contains(p.id)); _savePresetsToDisk(); }),
            onRenamePreset: (id, name) => setState(() { var idx = _savedPresets.indexWhere((p) => p.id == id); if (idx != -1) { var o = _savedPresets[idx]; _savedPresets[idx] = LickPreset(id: o.id, name: name, key: o.key, scale: o.scale, tuning: o.tuning, system: o.system, fragment: o.fragment, startFret: o.startFret, pathway: o.pathway, direction: o.direction, motifPairDirection: o.motifPairDirection, motifString: o.motifString, rhythm: o.rhythm, tempo: o.tempo, measuresPerLine: o.measuresPerLine, breakInterval: o.breakInterval, breakLength: o.breakLength, endRests: o.endRests, tabOutput: o.tabOutput, createdAt: o.createdAt); _savePresetsToDisk(); } }),
            onExportPresets: (p) {}, onImport: () {},
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
            child: ValueListenableBuilder<int>(
              valueListenable: _currentPlayingNoteIndex,
              builder: (context, playingIndex, child) {
                int? actStr, actFret;
                if (playingIndex != -1 && playingIndex < _currentSequence.length && _currentSequence[playingIndex][0] != -1) { actStr = _currentSequence[playingIndex][0]; actFret = _currentSequence[playingIndex][1]; }
                return InteractiveFretboard(engine: _engine, selectedKey: _selectedKey, selectedScale: _selectedScale, startFret: _startFret, selectedTuning: _selectedTuning, activeString: actStr, activeFret: actFret, scrollController: _fretboardScrollController, onNoteTapped: (k, f) => setState(() { _selectedKey = k; _startFret = f; _generateTab(); }));
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
                _buildCollapsibleSection("🎸 1. Theory & Fretboard", _isTheoryExpanded, () => setState(() => _isTheoryExpanded = !_isTheoryExpanded), _buildTheoryContent()),
                _buildCollapsibleSection("🎼 2. Pathways & Motifs", _isPathwaysExpanded, () => setState(() => _isPathwaysExpanded = !_isPathwaysExpanded), _buildPathwaysContent()),
                _buildCollapsibleSection("⏱️ 3. Formatting & Rhythm", _isFormattingExpanded, () => setState(() => _isFormattingExpanded = !_isFormattingExpanded), _buildFormattingContent()),
                _buildCollapsibleSection("📄 4. Generated Tab", _isTabExpanded, () => setState(() => _isTabExpanded = !_isTabExpanded), _buildInteractiveTabOutput()),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)), value: value, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged);
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(initialValue: value.toString(), keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11, height: 1.1), floatingLabelAlignment: FloatingLabelAlignment.center, floatingLabelBehavior: FloatingLabelBehavior.always, alignLabelWithHint: true, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: const OutlineInputBorder()), onChanged: (val) { int? parsed = int.tryParse(val); if (parsed != null && parsed >= 0) { onChanged(parsed); } });
  }
}