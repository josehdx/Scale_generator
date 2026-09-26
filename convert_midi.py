import json
import sys
import os

try:
    import mido
except ImportError:
    print("mido is required. Install it using: pip install mido")
    sys.exit(1)

def convert_mid_to_ground_truth(midi_path, output_json_path):
    if not os.path.exists(midi_path):
        print(f"Error: Could not find {midi_path}")
        return

    mid = mido.MidiFile(midi_path)
    events = []
    
    current_time_ms = 0.0
    tempo = 500000  # Default 120 BPM in microseconds per beat
    ticks_per_beat = mid.ticks_per_beat

    # Iterate through all tracks merged in absolute chronological order
    for msg in mido.merge_tracks(mid.tracks):
        # Convert delta ticks to milliseconds
        delta_sec = mido.tick2second(msg.time, ticks_per_beat, tempo)
        current_time_ms += delta_sec * 1000.0

        if msg.type == 'set_tempo':
            tempo = msg.tempo
            continue

        if msg.is_meta:
            continue

        channel = msg.channel + 1  # Convert 0-indexed MIDI to 1-indexed

        if msg.type == 'note_on' and msg.velocity > 0:
            events.append({
                "time_ms": round(current_time_ms, 1),
                "type": "note_on",
                "channel": channel,
                "data1": msg.note,
                "data2": msg.velocity
            })
        elif msg.type == 'note_off' or (msg.type == 'note_on' and msg.velocity == 0):
            events.append({
                "time_ms": round(current_time_ms, 1),
                "type": "note_off",
                "channel": channel,
                "data1": msg.note,
                "data2": 0
            })
        elif msg.type == 'pitchwheel':
            # mido pitch ranges from -8192 to 8191. Convert to 0..16383 range (8192 center)
            bend_val = msg.pitch + 8192
            events.append({
                "time_ms": round(current_time_ms, 1),
                "type": "pitch_bend",
                "channel": channel,
                "data1": bend_val,
                "data2": 0
            })

    # Sort chronologically
    events.sort(key=lambda x: x['time_ms'])

    # Write formatted ground_truth.json
    with open(output_json_path, 'w') as f:
        json.dump(events, f, indent=2)

    print(f"Success: Wrote {len(events)} events to {output_json_path}")

if __name__ == "__main__":
    midi_input = "benchmark.mid"
    json_output = "test_agent/ground_truth.json"
    convert_mid_to_ground_truth(midi_input, json_output)