#!/bin/bash
# 1. Run the headless Dart test to generate flutter_output.json
flutter test test/headless_midi_test.dart

# 2. Run the Python script to check for errors
python evaluate.py