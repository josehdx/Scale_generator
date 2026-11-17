import 'package:flutter/material.dart';

import '../../models/gp_track.dart';

/// Shows a modal bottom sheet that lists all [tracks] and lets the user
/// select, solo, or mute each one.
///
/// * [selectedTrackIndex] – the currently displayed track (highlighted).
/// * [soloedTracks]       – set of track indices currently soloed.
/// * [mutedTracks]        – set of track indices currently muted.
/// * [onSelectTrack]      – called with the tapped track index.
/// * [onToggleSolo]       – called with the tapped track index.
/// * [onToggleMute]       – called with the tapped track index.
void showGpxTrackMenu(
  BuildContext context, {
  required List<GpTrack> tracks,
  required int selectedTrackIndex,
  required Set<int> soloedTracks,
  required Set<int> mutedTracks,
  required void Function(int index) onSelectTrack,
  required void Function(int index) onToggleSolo,
  required void Function(int index) onToggleMute,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _GpxTrackMenuSheet(
        tracks: tracks,
        selectedTrackIndex: selectedTrackIndex,
        soloedTracks: Set.of(soloedTracks),
        mutedTracks: Set.of(mutedTracks),
        onSelectTrack: (i) {
          Navigator.of(ctx).pop();
          onSelectTrack(i);
        },
        onToggleSolo: onToggleSolo,
        onToggleMute: onToggleMute,
      );
    },
  );
}

/// Stateful sheet so solo/mute toggles update immediately without closing.
class _GpxTrackMenuSheet extends StatefulWidget {
  final List<GpTrack> tracks;
  final int selectedTrackIndex;
  final Set<int> soloedTracks;
  final Set<int> mutedTracks;
  final void Function(int) onSelectTrack;
  final void Function(int) onToggleSolo;
  final void Function(int) onToggleMute;

  const _GpxTrackMenuSheet({
    required this.tracks,
    required this.selectedTrackIndex,
    required this.soloedTracks,
    required this.mutedTracks,
    required this.onSelectTrack,
    required this.onToggleSolo,
    required this.onToggleMute,
  });

  @override
  State<_GpxTrackMenuSheet> createState() => _GpxTrackMenuSheetState();
}

class _GpxTrackMenuSheetState extends State<_GpxTrackMenuSheet> {
  late Set<int> _soloed;
  late Set<int> _muted;

  @override
  void initState() {
    super.initState();
    _soloed = Set.of(widget.soloedTracks);
    _muted = Set.of(widget.mutedTracks);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tracks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.tracks.length,
              itemBuilder: (_, i) {
                final GpTrack track = widget.tracks[i];
                final bool isSelected = i == widget.selectedTrackIndex;
                final bool isSoloed = _soloed.contains(i);
                final bool isMuted = _muted.contains(i);

                return ListTile(
                  tileColor: isSelected ? Colors.blueGrey.shade900 : null,
                  leading: Icon(
                    track.isPercussion ? Icons.music_note : Icons.queue_music,
                    color: isSelected ? Colors.blueAccent : Colors.white54,
                    size: 20,
                  ),
                  title: Text(
                    track.name.isEmpty ? 'Track ${i + 1}' : track.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    track.isPercussion
                        ? 'Drums'
                        : '${track.stringCount} strings',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Solo button
                      _TrackChip(
                        label: 'S',
                        active: isSoloed,
                        activeColor: Colors.amberAccent,
                        onTap: () {
                          setState(() {
                            if (isSoloed) {
                              _soloed.remove(i);
                            } else {
                              _soloed.add(i);
                              _muted.remove(i);
                            }
                          });
                          widget.onToggleSolo(i);
                        },
                      ),
                      const SizedBox(width: 6),
                      // Mute button
                      _TrackChip(
                        label: 'M',
                        active: isMuted,
                        activeColor: Colors.redAccent,
                        onTap: () {
                          setState(() {
                            if (isMuted) {
                              _muted.remove(i);
                            } else {
                              _muted.add(i);
                              _soloed.remove(i);
                            }
                          });
                          widget.onToggleMute(i);
                        },
                      ),
                    ],
                  ),
                  onTap: () => widget.onSelectTrack(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _TrackChip({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
            color: active ? activeColor : Colors.white24,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? activeColor : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
