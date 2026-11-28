import 'dart:math';

import 'package:flutter/material.dart';

import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/track.dart';
import '../widgets/mini_player.dart';
import '../widgets/poster.dart';
import '../widgets/track_tile.dart';

/// All the songs found on this device, kept off the main music page.
class LocalPlaylistScreen extends StatelessWidget {
  const LocalPlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = MusicLibrary.instance;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final all = lib.tracks;
        final recent = List<Track>.of(all)
          ..sort((a, b) => b.addedMs.compareTo(a.addedMs));
        final recentTop = recent.take(20).toList();

        return Scaffold(
          bottomNavigationBar: const MiniPlayer(),
          appBar: AppBar(title: const Text('Local playlist')),
          body: RefreshIndicator(
            onRefresh: () async {
              await lib.scan();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (lib.loading && all.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (!lib.loading && all.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Text('No songs found on this device.',
                              style: TextStyle(color: Colors.white54)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: lib.scan,
                            child: const Text('Rescan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (all.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                MusicPlayer.instance.playQueue(all, 0, shuffle: false),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play all'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => MusicPlayer.instance.playQueue(
                                all, Random().nextInt(all.length),
                                shuffle: true),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 18, 8, 8),
                      child: Text('Recently added',
                          style:
                              TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: recentTop.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => _PosterCard(
                          track: recentTop[i],
                          onTap: () =>
                              MusicPlayer.instance.playQueue(recentTop, i),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 8, 4),
                      child: Text('Your songs (${all.length})',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: all.length,
                    itemBuilder: (context, i) => TrackTile(
                      track: all[i],
                      onTap: () => MusicPlayer.instance.playQueue(all, i),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  const _PosterCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 138,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(track: track),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
