# Agent Objective: 1:1 MIDI Playback Parity

Your goal is to achieve flawless playback alignment between our Flutter app's internal engine and official Guitar Pro MIDI output. 

I have generated `ground_truth.json` using the official software. 
I have executed our headless Dart test to generate `flutter_output.json`.

## Your Task
1. Run `python evaluate.py`.
2. Analyze the terminal output to identify timing drifts, missing notes, or incorrect pitch bend envelopes.
3. Modify the Dart parsing engine (`lib/services/gpx_parser_service.dart`) or the Dart playback timeline logic (`lib/screens/gpx_tab_screen.dart`).
4. Re-run the headless flutter test to generate a new `flutter_output.json` (I have mapped this to a local shell script `./generate_test_json.sh`).
5. Run `python evaluate.py` again.
6. Repeat this loop autonomously until `evaluate.py` exits with code 0.