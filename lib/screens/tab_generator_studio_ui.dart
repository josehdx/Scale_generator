part of 'tab_generator_screen.dart';

extension TabGeneratorStudioUI on _TabGeneratorScreenState {
  
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

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)), value: value, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged);
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(initialValue: value.toString(), keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11, height: 1.1), floatingLabelAlignment: FloatingLabelAlignment.center, floatingLabelBehavior: FloatingLabelBehavior.always, alignLabelWithHint: true, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), border: const OutlineInputBorder()), onChanged: (val) { int? parsed = int.tryParse(val); if (parsed != null && parsed >= 0) { onChanged(parsed); } });
  }
}