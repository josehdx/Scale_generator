import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart'; 
import 'scale_engine.dart';

void main() {
  runApp(const TabGeneratorApp());
}

class TabGeneratorApp extends StatelessWidget {
  const TabGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tab Generator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark, 
      ),
      home: const TabGeneratorScreen(),
    );
  }
}

class TabGeneratorScreen extends StatefulWidget {
  const TabGeneratorScreen({super.key});

  @override
  State<TabGeneratorScreen> createState() => _TabGeneratorScreenState();
}

class _TabGeneratorScreenState extends State<TabGeneratorScreen> {
  final ScaleEngine _engine = ScaleEngine();
  final MidiPro _midiPro = MidiPro();
  bool _isPlaying = false;
  bool _isMidiReady = false;
  
  // Core State
  String _selectedKey = "C";
  String _selectedScale = "Minor Pentatonic";
  String _selectedTuning = "Standard E";
  int _startFret = 5;
  
  // System State
  String _selectedSystem = "Box Position / CAGED";
  String _selectedFragment = "Full 6 Strings";
  int _singleStringTarget = 1;

  // Pathway State
  String _selectedPathway = "Straight Linear";
  String _selectedDirection = "Ascend -> Descend";
  String _motifPairDirection = "Descend (High -> Low)";
  final TextEditingController _motifController = TextEditingController(text: "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1");

  // Format & Timing State
  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  String _selectedRhythm = "16th";
  int _measuresPerLine = 1; // Default to 1 measure per line for mobile portrait mode
  int _tempo = 120;

  String _generatedTab = "Select parameters and press Generate.";
  List<List<int>> _currentSequence = [];

  final List<String> _systems = ["Box Position / CAGED", "3-Note-Per-String (3NPS)", "Single String Horizontal"];
  final List<String> _fragments = ["Full 6 Strings", "High Strings (1-3)", "Middle Strings (2-4)", "Low Strings (4-6)"];
  final List<String> _pathways = ["Straight Linear", "3-Step Triplet", "4-Step 16th", "Note Skipping", "Custom Motif Builder"];
  final List<String> _directions = ["Ascend -> Descend", "Descend -> Ascend", "One-Way"];
  final List<String> _rhythms = ["Quarter", "8th", "16th"];

  @override
  void initState() {
    super.initState();
    _loadSoundFont();
  }

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(sf2Path: 'assets/guitar.sf2');
      setState(() => _isMidiReady = true);
    } catch (e) {
      debugPrint("MIDI Setup Error: Please ensure 'assets/guitar.sf2' is added to your project.");
    }
  }

  void _generateTab() {
    _engine.setTuning(_selectedTuning);

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

    int beatsPerMeasure = 4;
    _currentSequence = [];
    
    if (_selectedPathway == "Custom Motif Builder") {
      if (_selectedSystem == "Single String Horizontal") {
        setState(() => _generatedTab = "⚠️ Custom Motif Builder requires at least 2 strings.");
        return;
      }
      _currentSequence = _engine.buildCustomMotif(boxDict, _motifController.text, _motifPairDirection);
    } else {
      List<List<int>> baseNotes = _engine.flattenBoxDict(boxDict);
      if (_selectedDirection == "Descend -> Ascend") baseNotes = baseNotes.reversed.toList();

      List<List<int>> patternNotes;
      if (_selectedPathway == "3-Step Triplet") {
        patternNotes = _engine.apply3StepSequence(baseNotes);
        beatsPerMeasure = 3; 
      }
      else if (_selectedPathway == "4-Step 16th") patternNotes = _engine.apply4StepSequence(baseNotes);
      else if (_selectedPathway == "Note Skipping") patternNotes = _engine.applyNoteSkipping(baseNotes);
      else patternNotes = baseNotes;

      if (_selectedDirection == "One-Way") {
        _currentSequence = patternNotes;
      } else {
        var returnLoop = patternNotes.reversed.skip(1).toList();
        _currentSequence = [...patternNotes, ...returnLoop];
      }
    }

    if (_currentSequence.isEmpty) {
      setState(() => _generatedTab = "❌ Error: No valid notes found for this configuration.");
      return;
    }

    _currentSequence = _engine.applyIntervalBreaks(_currentSequence, _breakInterval, _breakLength);
    for (int i = 0; i < _endRests; i++) {
      _currentSequence.add([-1, -1]);
    }

    int activeMeasuresPerLine = _measuresPerLine <= 0 ? 999 : _measuresPerLine; 

    setState(() {
      _generatedTab = _engine.renderAsciiTab(
        _currentSequence,
        rhythmStr: _selectedRhythm,
        measuresPerSystem: activeMeasuresPerLine,
        beatsPerMeasure: beatsPerMeasure,
        tempo: _tempo,
      );
    });
  }

  Future<void> _playLick() async {
    if (!_isMidiReady || _currentSequence.isEmpty || _isPlaying) return;
    
    setState(() => _isPlaying = true);
    
    double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[_selectedRhythm] ?? 0.25;
    int msPerBeat = (60000 / _tempo).round();
    int msPerNote = (msPerBeat * beatMultiplier).round();

    for (var note in _currentSequence) {
      if (!_isPlaying) break;
      
      int str = note[0];
      int fret = note[1];

      if (str != -1) {
        int midiPitch = _engine.openStrings[str]! + fret;
        _midiPro.playMidiNote(midi: midiPitch, velocity: 127);
      }
      
      await Future.delayed(Duration(milliseconds: msPerNote));
    }
    
    setState(() => _isPlaying = false);
  }

  void _stopPlayback() {
    setState(() => _isPlaying = false);
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _generatedTab)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tab copied to clipboard!")));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tab Generator Studio')),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: ListView(
              children: [
                ExpansionTile(
                  title: const Text("🎸 1. Theory & Fretboard", style: TextStyle(fontWeight: FontWeight.bold)),
                  initiallyExpanded: true,
                  childrenPadding: const EdgeInsets.all(12.0),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildDropdown('Key', _selectedKey, _engine.noteMap.keys.toList(), (v) => setState(() => _selectedKey = v!))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildDropdown('Scale', _selectedScale, _engine.scaleFormulas.keys.toList(), (v) => setState(() => _selectedScale = v!))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildDropdown('Tuning', _selectedTuning, _engine.tunings.keys.toList(), (v) => setState(() => _selectedTuning = v!))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 2, child: _buildDropdown('System', _selectedSystem, _systems, (v) => setState(() => _selectedSystem = v!))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _selectedSystem == "Single String Horizontal"
                            ? _buildDropdown('String', _singleStringTarget.toString(), ["1", "2", "3", "4", "5", "6"], (v) => setState(() => _singleStringTarget = int.parse(v!)))
                            : _buildDropdown('Fragment', _selectedFragment, _fragments, (v) => setState(() => _selectedFragment = v!)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text("Start Fret: "),
                        Expanded(
                          child: Slider(
                            value: _startFret.toDouble(),
                            min: 0, max: 15, divisions: 15,
                            label: _startFret.toString(),
                            onChanged: (val) => setState(() => _startFret = val.toInt()),
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
                        Expanded(flex: 2, child: _buildDropdown('Pathway', _selectedPathway, _pathways, (v) => setState(() => _selectedPathway = v!))),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2, 
                          child: _selectedPathway == "Custom Motif Builder"
                            ? _buildDropdown('Pair Direction', _motifPairDirection, const ["Descend (High -> Low)", "Ascend (Low -> High)"], (v) => setState(() => _motifPairDirection = v!))
                            : _buildDropdown('Loop Direction', _selectedDirection, _directions, (v) => setState(() => _selectedDirection = v!))
                        ),
                      ],
                    ),
                    if (_selectedPathway == "Custom Motif Builder")
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          controller: _motifController,
                          decoration: const InputDecoration(labelText: "Motif Sequence (e.g., L2,L1,L2,H1,H2)", border: OutlineInputBorder(), isDense: true),
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
                        Expanded(flex: 2, child: _buildDropdown('Rhythm', _selectedRhythm, _rhythms, (v) => setState(() => _selectedRhythm = v!))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildNumberField('Tempo BPM', _tempo, (v) => setState(() => _tempo = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('Wrap Len', _measuresPerLine, (v) => setState(() => _measuresPerLine = v))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildNumberField('Break Interval', _breakInterval, (v) => setState(() => _breakInterval = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('Break Len', _breakLength, (v) => setState(() => _breakLength = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberField('End Rests', _endRests, (v) => setState(() => _endRests = v))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _generateTab,
                  icon: const Icon(Icons.bolt),
                  label: const Text("Generate"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                ),
                if (_isPlaying)
                  ElevatedButton.icon(
                    onPressed: _stopPlayback,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (_isMidiReady && _currentSequence.isNotEmpty) ? _playLick : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Play Lick"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy Output',
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),

          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Text(
                    _generatedTab,
                    style: const TextStyle(
                      fontFamily: 'monospace', 
                      color: Colors.greenAccent, 
                      fontSize: 10.5,
                      letterSpacing: -0.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), border: const OutlineInputBorder()),
      onChanged: (val) {
        int? parsed = int.tryParse(val);
        if (parsed != null && parsed >= 0) onChanged(parsed);
      },
    );
  }
}