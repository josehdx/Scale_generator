import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/playback_scheduler.dart';

/// Elapsed / total time and a seek slider for the GP viewer.
///
/// Times are song time at 100% speed ("1:05 / 3:30"), whatever the playback
/// speed is. While idle it shows 0:00 and the total; the slider works as soon
/// as a schedule is loaded.
class GpxSeekBar extends StatefulWidget {
  final PlaybackScheduler scheduler;

  /// Total length to show when nothing is loaded yet (null = unknown).
  final double? idleDurationMs;

  /// True while the scheduler is playing (drives the refresh timer).
  final bool isPlaying;

  /// Called whenever the user moves the slider.
  final VoidCallback? onSeeked;

  const GpxSeekBar({
    super.key,
    required this.scheduler,
    this.idleDurationMs,
    required this.isPlaying,
    this.onSeeked,
  });

  @override
  State<GpxSeekBar> createState() => _GpxSeekBarState();
}

class _GpxSeekBarState extends State<GpxSeekBar> {
  Timer? _timer;
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant GpxSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.isPlaying) {
      _timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (mounted && _dragMs == null) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _fmt(double ms) {
    final int total = (ms / 1000).floor().clamp(0, 359999);
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackScheduler sch = widget.scheduler;
    final bool loaded = sch.hasSchedule && sch.durationMs > 0;
    final double total = loaded ? sch.durationMs : (widget.idleDurationMs ?? 0.0);
    final double pos = _dragMs ?? (loaded ? sch.positionMs : 0.0);
    final double value = total <= 0 ? 0.0 : pos.clamp(0.0, total).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(_fmt(value), style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Semantics(
                label: 'Playback position',
                child: Slider(
                  value: value,
                  min: 0,
                  max: total <= 0 ? 1 : total,
                  activeColor: Colors.blueAccent,
                  inactiveColor: Colors.grey.shade800,
                  onChanged: loaded
                      ? (v) {
                          setState(() => _dragMs = v);
                          sch.seekMs(v);
                          widget.onSeeked?.call();
                        }
                      : null,
                  onChangeEnd: (_) => setState(() => _dragMs = null),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              total > 0 ? _fmt(total) : '--:--',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
