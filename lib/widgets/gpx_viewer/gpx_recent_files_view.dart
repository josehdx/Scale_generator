import 'package:flutter/material.dart';

/// Displays an empty-state prompt and, when [recentFiles] is non-empty, a
/// scrollable list of recently opened GP files.
///
/// This widget is purely presentational — file I/O and state mutation are
/// performed by [onOpen] and [onRemove] callbacks supplied by the parent.
class GpxRecentFilesView extends StatelessWidget {
  /// Recently opened GP files. Each entry has `'name'` and `'path'` keys.
  final List<Map<String, String>> recentFiles;

  /// Called when the user taps a recent file entry.
  final void Function(String name, String path) onOpen;

  /// Called when the user taps the remove (×) button on an entry.
  final void Function(String path) onRemove;

  const GpxRecentFilesView({
    super.key,
    required this.recentFiles,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Empty-state hint ─────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No GP file loaded yet.\nTap "Open .gp File" to start.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),

        // ── Recent files list ────────────────────────────────────────────────
        if (recentFiles.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Recent Files',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: recentFiles.length,
              itemBuilder: (context, index) {
                final recent = recentFiles[index];
                final name = recent['name'] ?? 'Unknown';
                final path = recent['path'] ?? '';
                return ListTile(
                  leading: const Icon(Icons.history, color: Colors.grey),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    path,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: () => onRemove(path),
                  ),
                  onTap: () => onOpen(name, path),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

