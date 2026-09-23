import 'package:flutter/material.dart';
import '../../models/gp_track.dart';

/// Shows a modal bottom sheet that lists all [tracks] with per-track Solo (S)
/// and Mute (M) toggles.
void showGpxTrackMenu(
  BuildContext context, {
  required List<GpTrack> tracks,
  required int selectedTrackIndex,
  required Set<int> soloedTracks,
  required Set<int> mutedTracks,
  required ValueChanged<int> onSelectTrack,
  required void Function(int trackIndex) onToggleSolo,
  required void Function(int trackIndex) onToggleMute,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey.shade900,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Tracks & Instruments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.grey),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final track = tracks[i];
                    final isSelected = selectedTrackIndex == i;
                    final isSolo = soloedTracks.contains(i);
                    final isMuted = mutedTracks.contains(i);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blueAccent.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: Colors.blueAccent.withOpacity(0.3)) : Border.all(color: Colors.transparent),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.music_note,
                          color: isSelected ? Colors.blueAccent : Colors.grey,
                        ),
                        title: Text(
                          track.name,
                          style: TextStyle(
                            color: isSelected ? Colors.blueAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          onSelectTrack(i);
                          setModalState(() {});
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                onToggleSolo(i);
                                setModalState(() {});
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSolo ? Colors.amber : Colors.transparent,
                                  border: Border.all(color: Colors.amber),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'S',
                                  style: TextStyle(
                                    color: isSolo ? Colors.black : Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                onToggleMute(i);
                                setModalState(() {});
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isMuted ? Colors.redAccent : Colors.transparent,
                                  border: Border.all(color: Colors.redAccent),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'M',
                                  style: TextStyle(
                                    color: isMuted ? Colors.white : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}