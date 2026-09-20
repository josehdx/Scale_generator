import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/lick_preset.dart';
import '../scale_engine.dart';
import '../widgets/interactive_fretboard.dart';
import '../widgets/interactive_tab_display.dart';
import 'saved_presets_screen.dart';

class TabGeneratorScreen extends StatefulWidget {
  const TabGeneratorScreen({super.key});

  @override
  State<TabGeneratorScreen> createState() => _TabGeneratorScreenState();
}

class _TabGeneratorScreenState extends State<TabGeneratorScreen> {
  final ScaleEngine _engine = ScaleEngine();
  final MidiPro _midiPro = MidiPro();

  late PageController _pageController;
  int _selectedPageIndex = 0;

  bool _isPlaying = false;
  bool _isMidiReady = false;
  bool _isLooping = false;
  bool _isChangingSound = false;
  
  Timer? _playbackTimer;
  final Set<int> _activeMidiNotes = {}; 
  
  final ScrollController _fretboardScrollController = ScrollController();
  
  final ValueNotifier<int> _currentPlayingNoteIndex = ValueNotifier<int>(-1);

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
  final TextEditingController _motifController =
      TextEditingController(text: "L2,L1,L2,H1,H2,H1,L2,L1,L2,L1");

  int _breakInterval = 0;
  int _breakLength = 4;
  int _endRests = 0;
  int _measuresPerLine = 1; 
  String _selectedRhythm = "16th";
  int _tempo = 120;

  String _generatedTab = "Generating tab...";
  List<List<int>> _currentSequence = [];

  final List<LickPreset> _savedPresets = [];

  final List<String> _systems = [
    "Box Position / CAGED",
    "3-Note-Per-String (3NPS)",
    "Single String Horizontal"
  ];
  final List<String> _fragments = [
    "Full 6 Strings",
    "High Strings (1-3)",
    "Middle Strings (2-4)",
    "Low Strings (4-6)"
  ];
  final List<String> _pathways = [
    "Straight Linear",
    "3-Step Triplet",
    "4-Step 16th",
    "Note Skipping",
    "Custom Motif Builder"
  ];
  final List<String> _directions = [
    "Ascend -> Descend",
    "Descend -> Ascend",
    "One-Way (Ascend)",
    "One-Way (Descend)"
  ];
  final List<String> _rhythms = ["Quarter", "8th", "16th"];

  final Map<String, int> _guitarSounds = {
    "Clean Electric": 27,
    "Steel Acoustic": 25,
    "Jazz Electric": 26,
    "Nylon Acoustic": 24,
  };

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSoundFont();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateTab();
    });
  }

  @override
  void dispose() {
    _stopPlayback(); 
    _pageController.dispose();
    _motifController.dispose();
    _fretboardScrollController.dispose();
    _currentPlayingNoteIndex.dispose();
    super.dispose();
  }

  Future<void> _loadSoundFont() async {
    try {
      await _midiPro.loadSoundfont(
        sf2Path: 'assets/guitar.sf2',
        instrumentIndex: _selectedInstrumentIndex,
      );
      _midiPro.playMidiNote(midi: 60, velocity: 0);
      
      if (mounted) {
        setState(() => _isMidiReady = true);
      }
    } catch (e) {
      debugPrint("MIDI Setup Error.");
    }
  }

  Future<void> _changeGuitarSound(int newIndex) async {
    if (_isChangingSound) return; 
    setState(() {
      _selectedInstrumentIndex = newIndex;
      _isChangingSound = true;
    });
    
    try {
      await _midiPro.loadSoundfont(
        sf2Path: 'assets/guitar.sf2',
        instrumentIndex: newIndex,
      );
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

  String _generateMeaningfulName() {
    String patternLabel = _selectedPathway == "Custom Motif Builder"
        ? "Custom Motif"
        : _selectedPathway;
    return "$_selectedKey $_selectedScale - $patternLabel (Fret $_startFret)";
  }

  void _saveCurrentLick() {
    if (_currentSequence.isEmpty || _generatedTab.startsWith("❌")) return;

    final presetName = _generateMeaningfulName();

    final preset = LickPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: presetName,
      key: _selectedKey,
      scale: _selectedScale,
      tuning: _selectedTuning,
      system: _selectedSystem,
      fragment: _selectedFragment,
      startFret: _startFret,
      pathway: _selectedPathway,
      direction: _selectedDirection,
      motifPairDirection: _motifPairDirection,
      motifString: _motifController.text,
      rhythm: _selectedRhythm,
      tempo: _tempo,
      measuresPerLine: _measuresPerLine,
      breakInterval: _breakInterval,
      breakLength: _breakLength,
      endRests: _endRests,
      tabOutput: _generatedTab,
      createdAt: DateTime.now(),
    );

    setState(() {
      _savedPresets.insert(0, preset);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved Preset: '$presetName'")),
    );
  }

  void _loadPreset(LickPreset preset) {
    setState(() {
      _selectedKey = preset.key;
      _selectedScale = preset.scale;
      _selectedTuning = preset.tuning;
      _selectedSystem = preset.system;
      _selectedFragment = preset.fragment;
      _startFret = preset.startFret;
      _selectedPathway = preset.pathway;
      
      String loadedDir = preset.direction;
      if (loadedDir == "One-Way") loadedDir = "One-Way (Ascend)";
      _selectedDirection = loadedDir;
      
      _motifPairDirection = preset.motifPairDirection;
      _motifController.text = preset.motifString;
      _selectedRhythm = preset.rhythm;
      _tempo = preset.tempo;
      _measuresPerLine = preset.measuresPerLine;
      _breakInterval = preset.breakInterval;
      _breakLength = preset.breakLength;
      _endRests = preset.endRests;
      _generatedTab = preset.tabOutput;
    });

    _generateTab();
    _pageController.animateToPage(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _exportAllPresets() {
    if (_savedPresets.isEmpty) return;
    final jsonList = _savedPresets.map((e) => e.toJson()).toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
    Clipboard.setData(ClipboardData(text: jsonString));
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
      
      if (_selectedDirection == "Descend -> Ascend" || _selectedDirection == "One-Way (Descend)") {
        baseNotes = baseNotes.reversed.toList();
      }

      List<List<int>> patternNotes;
      if (_selectedPathway == "3-Step Triplet") {
        patternNotes = _engine.apply3StepSequence(baseNotes);
        beatsPerMeasure = 3;
      } else if (_selectedPathway == "4-Step 16th") {
        patternNotes = _engine.apply4StepSequence(baseNotes);
      } else if (_selectedPathway == "Note Skipping") {
        patternNotes = _engine.applyNoteSkipping(baseNotes);
      } else {
        patternNotes = baseNotes;
      }

      if (_selectedDirection.startsWith("One-Way")) {
        _currentSequence = patternNotes;
      } else {
        var returnLoop = patternNotes.reversed.skip(1).toList();
        _currentSequence = [...patternNotes, ...returnLoop];
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
        rhythmStr: _selectedRhythm,
        measuresPerSystem: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
        beatsPerMeasure: beatsPerMeasure,
        tempo: _tempo,
      );
    });
  }

  void _playLick() {
    if (!_isMidiReady || _currentSequence.isEmpty || _isPlaying) return;

    setState(() => _isPlaying = true);

    double beatMultiplier = {"Quarter": 1.0, "8th": 0.5, "16th": 0.25}[_selectedRhythm] ?? 0.25;
    int msPerNote = ((60000 / _tempo) * beatMultiplier).round();

    int startIdx = 0;
    int endIdx = _currentSequence.length - 1;

    if (_selectionStart != -1 && _selectionEnd != -1) {
      startIdx = _selectionStart.clamp(0, _currentSequence.length - 1);
      endIdx = _selectionEnd.clamp(startIdx, _currentSequence.length - 1);
    }

    int currentIndex = startIdx;
    List<int> notesToStop = [];

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(Duration(milliseconds: msPerNote), (timer) {
      if (!mounted || !_isPlaying) {
        timer.cancel();
        _stopPlayback();
        return;
      }

      if (currentIndex > endIdx) {
        if (_isLooping) {
          currentIndex = startIdx; 
        } else {
          timer.cancel();
          _stopPlayback();
          return;
        }
      }

      var note = _currentSequence[currentIndex];
      int str = note[0];
      int fret = note[1];
      
      if (notesToStop.isNotEmpty) {
        for (var pitch in notesToStop) {
          _midiPro.stopMidiNote(midi: pitch);
          _activeMidiNotes.remove(pitch);
        }
        notesToStop.clear();
      }

      if (str != -1) {
        int pitch = _engine.openStrings[str]! + fret;
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

    for (int pitch in _activeMidiNotes) {
      _midiPro.stopMidiNote(midi: pitch);
    }
    _activeMidiNotes.clear();
    _currentPlayingNoteIndex.value = -1;

    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _generatedTab));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tab Generator Studio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Save Lick Preset',
            onPressed: _saveCurrentLick,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("Form Controls"),
                  selected: _selectedPageIndex == 0,
                  onSelected: (selected) {
                    if (selected) {
                      _pageController.animateToPage(0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Interactive Fretboard"),
                  selected: _selectedPageIndex == 1,
                  onSelected: (selected) {
                    if (selected) {
                      _pageController.animateToPage(1,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Saved Presets"),
                  selected: _selectedPageIndex == 2,
                  onSelected: (selected) {
                    if (selected) {
                      _pageController.animateToPage(2,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    }
                  },
                ),
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
            onDeletePreset: (idx) => setState(() => _savedPresets.removeAt(idx)),
            onExportAll: _exportAllPresets,
          ),
        ],
      ),
    );
  }

  Widget _buildFormScreen() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: ListView(
            children: [
              ExpansionTile(
                title: const Text("🎸 1. Theory & Fretboard",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                initiallyExpanded: true,
                childrenPadding: const EdgeInsets.all(12.0),
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildDropdown(
                              'Key', _selectedKey, _engine.noteMap.keys.toList(),
                              (v) {
                        setState(() => _selectedKey = v!);
                        _generateTab();
                      })),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: _buildDropdown(
                              'Scale',
                              _selectedScale,
                              _engine.scaleFormulas.keys.toList(), (v) {
                        setState(() => _selectedScale = v!);
                        _generateTab();
                      })),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: _buildDropdown('Tuning', _selectedTuning,
                              _engine.tunings.keys.toList(), (v) {
                        setState(() => _selectedTuning = v!);
                        _generateTab();
                      })),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: _buildDropdown(
                              'System', _selectedSystem, _systems, (v) {
                        setState(() => _selectedSystem = v!);
                        _generateTab();
                      })),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _selectedSystem == "Single String Horizontal"
                            ? _buildDropdown('String',
                                _singleStringTarget.toString(), ["1", "2", "3", "4", "5", "6"], (v) {
                                setState(() => _singleStringTarget = int.parse(v!));
                                _generateTab();
                              })
                            : _buildDropdown(
                                'Fragment', _selectedFragment, _fragments, (v) {
                                setState(() => _selectedFragment = v!);
                                _generateTab();
                              }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text("Start Fret: $_startFret"),
                      Expanded(
                        child: Slider(
                          value: _startFret.toDouble(),
                          min: 0,
                          max: 24,
                          divisions: 24,
                          label: _startFret.toString(),
                          onChanged: (val) {
                            setState(() => _startFret = val.toInt());
                            _generateTab();
                          },
                        ),
                      ),
                    ],
                  )
                ],
              ),
              ExpansionTile(
                title: const Text("🎼 2. Pathways & Motifs",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                childrenPadding: const EdgeInsets.all(12.0),
                children: [
                  Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: _buildDropdown(
                              'Pathway', _selectedPathway, _pathways, (v) {
                        setState(() => _selectedPathway = v!);
                        _generateTab();
                      })),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _selectedPathway == "Custom Motif Builder"
                            ? _buildDropdown('Pair Direction',
                                _motifPairDirection, const [
                                "Descend (High -> Low)",
                                "Ascend (Low -> High)"
                              ], (v) {
                                setState(() => _motifPairDirection = v!);
                                _generateTab();
                              })
                            : _buildDropdown(
                                'Loop Direction', _selectedDirection, _directions, (v) {
                                setState(() => _selectedDirection = v!);
                                _generateTab();
                              }),
                      ),
                    ],
                  ),
                  if (_selectedPathway == "Custom Motif Builder")
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextField(
                        controller: _motifController,
                        decoration: const InputDecoration(
                            labelText: "Motif Sequence (e.g., L2,L1,L2,H1,H2)",
                            border: OutlineInputBorder(),
                            isDense: true),
                        onChanged: (_) => _generateTab(),
                      ),
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text("⏱️ 3. Formatting & Rhythm",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                childrenPadding: const EdgeInsets.all(12.0),
                children: [
                  Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: _buildDropdown(
                              'Rhythm', _selectedRhythm, _rhythms, (v) {
                        setState(() => _selectedRhythm = v!);
                        _generateTab();
                      })),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: _buildNumberField('Tempo\nBPM', _tempo,
                              (v) => setState(() => _tempo = v))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildNumberField('Wrap\nLines', _measuresPerLine,
                              (v) => setState(() => _measuresPerLine = v))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildDropdown(
                          'Guitar Sound',
                          _guitarSounds.keys.firstWhere(
                              (k) => _guitarSounds[k] == _selectedInstrumentIndex),
                          _guitarSounds.keys.toList(),
                          (v) {
                            if (v != null) _changeGuitarSound(_guitarSounds[v]!);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildNumberField('Break\nInterval',
                              _breakInterval, (v) => setState(() => _breakInterval = v))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildNumberField('Break\nLength', _breakLength,
                              (v) => setState(() => _breakLength = v))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildNumberField(
                              'End\nRests', _endRests, (v) => setState(() => _endRests = v))),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildActionButtons(),
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
              Expanded(
                child: _buildDropdown(
                  'Scale',
                  _selectedScale,
                  _engine.scaleFormulas.keys.toList(),
                  (v) {
                    setState(() {
                      _selectedScale = v!;
                      _generateTab();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(Icons.music_note,
                    color: Colors.redAccent, size: 16),
                label: Text('Root: $_selectedKey | Fret: $_startFret'),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ValueListenableBuilder<int>(
            valueListenable: _currentPlayingNoteIndex,
            builder: (context, playingIndex, child) {
              int? activeString;
              int? activeFret;
              if (playingIndex != -1 && playingIndex < _currentSequence.length) {
                var activeNote = _currentSequence[playingIndex];
                activeString = activeNote[0];
                activeFret = activeNote[1];
              }
              return InteractiveFretboard(
                engine: _engine,
                selectedKey: _selectedKey,
                selectedScale: _selectedScale,
                startFret: _startFret,
                selectedTuning: _selectedTuning,
                activeString: activeString,
                activeFret: activeFret,
                scrollController: _fretboardScrollController, 
                onNoteTapped: (newKey, fret) {
                  setState(() {
                    _selectedKey = newKey;
                    _startFret = fret;
                    _generateTab();
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildDropdown(
                      'Pathway',
                      _selectedPathway,
                      _pathways,
                      (v) => setState(() {
                        _selectedPathway = v!;
                        _generateTab();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _selectedPathway == "Custom Motif Builder"
                        ? _buildDropdown(
                            'Pair Direction',
                            _motifPairDirection,
                            const ["Descend (High -> Low)", "Ascend (Low -> High)"],
                            (v) => setState(() {
                              _motifPairDirection = v!;
                              _generateTab();
                            }),
                          )
                        : _buildDropdown(
                            'Loop Direction',
                            _selectedDirection,
                            _directions,
                            (v) => setState(() {
                              _selectedDirection = v!;
                              _generateTab();
                            }),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdown(
                      'Rhythm',
                      _selectedRhythm,
                      _rhythms,
                      (v) => setState(() {
                        _selectedRhythm = v!;
                        _generateTab();
                      }),
                    ),
                  ),
                ],
              ),
              if (_selectedPathway == "Custom Motif Builder")
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextField(
                    controller: _motifController,
                    decoration: const InputDecoration(
                      labelText: "Motif Sequence (e.g., L2,L1,L2,H1,H2)",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _generateTab(),
                  ),
                ),
            ],
          ),
        ),
        _buildActionButtons(),
        _buildInteractiveTabOutput(),
      ],
    );
  }

  Widget _buildActionButtons() {
    bool hasSelection = _selectionStart != -1 && _selectionEnd != -1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _generateTab,
                  icon: const Icon(Icons.bolt),
                  label: const Text("Generate"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                if (_isPlaying)
                  ElevatedButton.icon(
                    onPressed: _stopPlayback,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (_isMidiReady && _currentSequence.isNotEmpty)
                        ? _playLick
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(hasSelection ? "Play Selection" : "Play Lick"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.repeat,
                    color: _isLooping ? Colors.amberAccent : Colors.grey,
                  ),
                  tooltip: _isLooping ? 'Looping ON' : 'Looping OFF',
                  onPressed: () => setState(() => _isLooping = !_isLooping),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_add),
                  tooltip: 'Save Preset',
                  onPressed: _saveCurrentLick,
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy Output',
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Selected Notes: ${_selectionStart + 1} to ${_selectionEnd + 1}",
                    style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _clearSelection,
                    child: const Icon(Icons.cancel, size: 16, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveTabOutput() {
    if (_currentSequence.isEmpty) {
      return Expanded(
        flex: 3,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          width: double.infinity,
          child: Text(
            _generatedTab,
            style: const TextStyle(
                fontFamily: 'monospace', color: Colors.greenAccent),
          ),
        ),
      );
    }
    return Expanded(
      flex: 3,
      child: ValueListenableBuilder<int>(
        valueListenable: _currentPlayingNoteIndex,
        builder: (context, playingIndex, child) {
          return InteractiveTabDisplay(
            sequence: _currentSequence,
            rhythmStr: _selectedRhythm,
            measuresPerLine: _measuresPerLine <= 0 ? 999 : _measuresPerLine,
            currentPlayingIndex: playingIndex,
            selectionStart: _selectionStart,
            selectionEnd: _selectionEnd,
            tuningStr: _selectedTuning,
            onBeatTapped: (index) {
              setState(() {
                if (_selectionStart == -1 ||
                    (_selectionStart != -1 && _selectionEnd != _selectionStart)) {
                  _selectionStart = index;
                  _selectionEnd = index;
                  _tapAnchorIndex = index;
                } else {
                  _selectionStart = min(_tapAnchorIndex!, index);
                  _selectionEnd = max(_tapAnchorIndex!, index);
                }
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
      value: value,
      items: items
          .map((e) => DropdownMenuItem(
              value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField(
      String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11, height: 1.1),
          floatingLabelAlignment: FloatingLabelAlignment.center,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          alignLabelWithHint: true,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          border: const OutlineInputBorder()),
      onChanged: (val) {
        int? parsed = int.tryParse(val);
        if (parsed != null && parsed >= 0) {
          onChanged(parsed);
          _generateTab();
        }
      },
    );
  }
}