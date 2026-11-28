import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/provider.dart';

/// The full list behind a row on the music page.
class SeeAllScreen extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  const SeeAllScreen({super.key, required this.title, required this.items});

  String _fmt(int s) {
    final r = s % 60;
    return '${s ~/ 60}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Playback.play(context, items.first, queue: items),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('Nothing here yet.',
                  style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final m = items[i];
                return ListTile(
                  onTap: () => Playback.play(context, m, queue: items),
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: m.thumb == null
                          ? Container(color: Colors.white10)
                          : Image.network(m.thumb!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.white10)),
                    ),
                  ),
                  title: Text(m.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [m.creator, if (m.durationSec > 0) _fmt(m.durationSec)]
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                );
              },
            ),
    );
  }
}
