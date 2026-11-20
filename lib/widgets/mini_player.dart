import 'package:flutter/material.dart';

import '../music/music_player.dart';
import '../screens/now_playing_screen.dart';
import 'poster.dart';

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const NowPlayingScreen(),
    ),
  );
}

/// Small player bar shown at the bottom of the music screens.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MusicPlayer.instance,
      builder: (context, _) {
        final mp = MusicPlayer.instance;
        final t = mp.current;
        if (t == null) return const SizedBox.shrink();
        final g = gradientFor('${t.artist}${t.title}');
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => openNowPlaying(context),
                child: Container(
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(colors: g),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Poster(track: t),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(t.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(mp.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              iconSize: 30,
                              onPressed: mp.playOrPause,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              iconSize: 28,
                              onPressed: mp.next,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              iconSize: 20,
                              onPressed: mp.stop,
                            ),
                          ],
                        ),
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: mp.position,
                        builder: (context, pos, _) {
                          final d = mp.duration.value.inMilliseconds;
                          return LinearProgressIndicator(
                            value: d > 0
                                ? (pos.inMilliseconds / d).clamp(0.0, 1.0).toDouble()
                                : 0.0,
                            minHeight: 2.5,
                            backgroundColor: Colors.black26,
                            color: Colors.white,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
