import 'package:flutter/material.dart';

class GpxRecentFilesView extends StatelessWidget {
  final List<Map<String, String>> recentFiles;
  final void Function(String name, String path) onOpen;
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Text(
            'No Guitar Pro file loaded yet.\nTap "Open .gp File" to start.\n'
            '(Guitar Pro 7/8 .gp files; older .gpx / .gp5 files must be re-saved as .gp)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
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
                  // the absolute path is meaningless to the user (and goes stale)
                  title: Text(name, style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Remove from recent files',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
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
