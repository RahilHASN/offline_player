import 'package:flutter/material.dart';

import '../music/music_player.dart';
import '../music/track.dart';
import 'poster.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  const TrackTile({super.key, required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cur = MusicPlayer.instance.current?.id == track.id;
    final primary = Theme.of(context).colorScheme.primary;
    final sub = <String>[
      track.artist,
      if (track.album.isNotEmpty) track.album,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 52,
        height: 52,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Poster(track: track),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: cur ? primary : null,
          fontWeight: cur ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'next') {
            MusicPlayer.instance.playNext(track);
          } else {
            MusicPlayer.instance.addToQueue(track);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'next', child: Text('Play next')),
          PopupMenuItem(value: 'queue', child: Text('Add to queue')),
        ],
      ),
    );
  }
}
