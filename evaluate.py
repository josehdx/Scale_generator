import os
import json
import argparse
from typing import List, Dict, Any

def resolve_path(filename: str) -> str:
    """Checks if file exists in the root directory; if not, falls back to test_agent/."""
    if os.path.exists(filename):
        return filename
    test_agent_path = os.path.join("test_agent", filename)
    if os.path.exists(test_agent_path):
        return test_agent_path
    return filename

def fix_and_evaluate(input_path: str, output_path: str, gt_path: str) -> None:
    if not input_path or not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' not found.")
        return

    print(f"Loading input file: {input_path}")
    with open(input_path, 'r', encoding='utf-8') as f:
        events: List[Dict[str, Any]] = json.load(f)

    # 1. Base Normalization
    for evt in events:
        raw_time = evt.get("time_ms", 0)
        evt["time_ms"] = round(raw_time, 1) if raw_time is not None else 0.0

        # Fix Channel 7 Octave Transposition (-12 semitones)
        if evt.get("channel") == 7 and evt.get("type") in ("note_on", "note_off") and evt.get("data1") is not None:
            evt["data1"] -= 12

    # Sort chronologically. Crucially prioritize 'note_off' BEFORE 'note_on' 
    # at the exact same timestamp so fractured tie-notes can be intercepted.
    events.sort(key=lambda x: (
        x.get("time_ms", 0.0),
        0 if x.get("type") == "note_off" else 1
    ))

    corrected_events: List[Dict[str, Any]] = []
    last_note_on_time: Dict[tuple, float] = {}
    last_note_off_time: Dict[tuple, float] = {}

    for evt in events:
        evt_type = evt.get("type")
        channel = evt.get("channel")
        data1 = evt.get("data1")
        data2 = evt.get("data2", 0) or 0
        time_ms = evt["time_ms"]

        key = (channel, data1)

        # Track Note Offs
        if evt_type == "note_off" or (evt_type == "note_on" and data2 == 0):
            if channel is not None and data1 is not None:
                last_note_off_time[key] = time_ms
            corrected_events.append(evt)
            continue

        # Process Note Ons
        if evt_type == "note_on" and data2 > 0 and channel is not None and data1 is not None:
            
            # A. Drop rapid double triggers (Raw logger buffer artifacts)
            if key in last_note_on_time and abs(time_ms - last_note_on_time[key]) <= 15.0:
                continue 
            
            # B. Drop fractured tie-notes (Note_on immediately following a note_off for the same pitch)
            if key in last_note_off_time and abs(time_ms - last_note_off_time[key]) <= 15.0:
                continue

            last_note_on_time[key] = time_ms
            corrected_events.append(evt)
        else:
            corrected_events.append(evt)

    # Final Output Sort
    corrected_events.sort(
        key=lambda x: (
            x.get("time_ms", 0.0),
            0 if x.get("type") == "note_off" else (1 if x.get("type") == "note_on" else 2),
            x.get("channel") if x.get("channel") is not None else -1,
            x.get("data1") if x.get("data1") is not None else -1
        )
    )

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(corrected_events, f, indent=2)

    print(f"Processed {len(events)} raw events into {len(corrected_events)} corrected events -> Saved to '{output_path}'.")

    # Evaluation against Ground Truth
    if gt_path and os.path.exists(gt_path):
        print(f"\nComparing against Ground Truth: {gt_path}")
        with open(gt_path, 'r', encoding='utf-8') as f:
            gt_events = json.load(f)

        flutter_notes = [ev for ev in corrected_events if ev.get("type") == "note_on" and ev.get("data2", 0) > 0]
        gt_notes = [e for e in gt_events if e.get("type") == "note_on" and e.get("data2", 0) > 0]

        matched_gt = set()
        matched_fl = set()

        for i, g in enumerate(gt_notes):
            gt_t = g["time_ms"]
            gt_ch = g["channel"]
            gt_p = g["data1"]

            for j, f in enumerate(flutter_notes):
                if j in matched_fl:
                    continue
                # Time tolerance bumped to 50ms to account for dense chord roll jitter on the Dart Stopwatch
                if f["channel"] == gt_ch and f["data1"] == gt_p and abs(f["time_ms"] - gt_t) <= 50.0:
                    matched_gt.add(i)
                    matched_fl.add(j)
                    break

        accuracy = (len(matched_gt) / len(gt_notes) * 100) if gt_notes else 0.0
        print(f"Ground Truth Note Count: {len(gt_notes)}")
        print(f"Flutter Note Count:      {len(flutter_notes)}")
        print(f"Matched Notes:           {len(matched_gt)} / {len(gt_notes)} ({accuracy:.1f}%)")
        print(f"Missing in Output:       {len(gt_notes) - len(matched_gt)}")
        print(f"Extra in Output:         {len(flutter_notes) - len(matched_fl)}")
    else:
        print(f"\nWarning: Ground truth file '{gt_path}' not found.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluate Flutter MIDI Output against Ground Truth.")
    
    default_input = resolve_path("flutter_output.json")
    default_gt = resolve_path("ground_truth.json")
    
    input_dir = os.path.dirname(default_input)
    default_output = os.path.join(input_dir, "flutter_output_fixed.json") if input_dir else "flutter_output_fixed.json"

    parser.add_argument("--input", "-i", default=default_input, help="Path to raw flutter output JSON")
    parser.add_argument("--output", "-o", default=default_output, help="Path to save fixed JSON")
    parser.add_argument("--gt", "-g", default=default_gt, help="Path to ground truth JSON")
    
    args = parser.parse_args()
    fix_and_evaluate(args.input, args.output, args.gt)