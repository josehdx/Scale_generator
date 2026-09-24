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
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No GP file loaded yet.\nTap "Open .gp File" to start.',
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
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    path,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
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