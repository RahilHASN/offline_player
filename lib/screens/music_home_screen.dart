import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/provider.dart';
import '../bridge/youtube_history.dart';
import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/online_settings.dart';
import '../widgets/poster.dart';
import '../widgets/youtube_badge.dart';
import 'music_search_screen.dart';
import 'yt_library_screen.dart';

class _Feat {
  final Track track;
  final List<Track> queue;
  final String label;
  const _Feat(this.track, this.queue, this.label);
}

class MusicHomeScreen extends StatefulWidget {
  const MusicHomeScreen({super.key});

  @override
  State<MusicHomeScreen> createState() => _MusicHomeScreenState();
}

class _MusicHomeScreenState extends State<MusicHomeScreen> {
  final MusicLibrary lib = MusicLibrary.instance;

  @override
  void initState() {
    super.initState();
    lib.init();
    YouTubeHistory.instance.load();
  }

  _Feat? _featured() {
    if (lib.tracks.isNotEmpty) {
      final recent = List<Track>.of(lib.tracks)
        ..sort((a, b) => b.addedMs.compareTo(a.addedMs));
      return _Feat(recent.first, lib.tracks, 'FROM YOUR LIBRARY');
    }
    return null;
  }

  void _play(List<Track> list, int i, {bool? shuffle}) {
    MusicPlayer.instance.playQueue(list, i, shuffle: shuffle);
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MusicSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([lib, AppMode.instance, YouTubeHistory.instance]),
      builder: (context, _) {
        final m = AppMode.instance;
        final hist = YouTubeHistory.instance.items;
        final feat = _featured();
        final recent = List<Track>.of(lib.tracks)
          ..sort((a, b) => b.addedMs.compareTo(a.addedMs));

        return Scaffold(
          bottomNavigationBar: const MiniPlayer(),
          body: RefreshIndicator(
            onRefresh: () async {
              await lib.scan();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  title: const Text('Music',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _openSearch,
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite_border),
                      tooltip: 'Favourites and playlists',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const YtLibraryScreen()),
                      ),
                    ),
                    const ModeChip(),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rescan') lib.scan();
                        if (v == 'folder') lib.addFolder();
                        if (v == 'online') showOnlineSettings(context);
                        if (v == 'clear') YouTubeHistory.instance.clear();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rescan', child: Text('Rescan music')),
                        PopupMenuItem(
                            value: 'folder', child: Text('Add music folder')),
                        PopupMenuItem(
                            value: 'online', child: Text('Online settings')),
                        PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear YouTube history')),
                      ],
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _hero(feat)),
                SliverToBoxAdapter(child: _notices(m)),
                if (m.online)
                  SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: ListTile(
                        onTap: _openSearch,
                        leading: const YouTubeBadge(),
                        title: const Text('Search songs and videos'),
                        trailing: const Icon(Icons.search),
                      ),
                    ),
                  ),
                if (lib.loading && lib.tracks.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (m.online && hist.isNotEmpty) _ytRow(hist),
                if (lib.tracks.isNotEmpty)
                  _row('Recently added', recent.take(20).toList()),
                if (lib.tracks.isNotEmpty)
                  _row('Your songs', lib.tracks.take(30).toList(),
                      onMore: _openSearch),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hero(_Feat? f) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 250,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (f != null)
                Poster(track: f.track)
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: AppColors.music),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f?.label ?? 'WELCOME',
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      f?.track.title ?? 'Your music, beautifully organised',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    if (f != null)
                      Text(f.track.artist,
                          style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    if (f != null)
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              final i = f.queue.indexWhere((t) => t.id == f.track.id);
                              _play(f.queue, i < 0 ? 0 : i, shuffle: false);
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _play(
                                f.queue, Random().nextInt(f.queue.length),
                                shuffle: true),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, {String? button, VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13, color: Colors.white70))),
            if (button != null)
              TextButton(onPressed: onTap, child: Text(button)),
          ],
        ),
      ),
    );
  }

  Widget _notices(AppMode m) {
    final items = <Widget>[];
    if (Platform.isAndroid && lib.needAccess) {
      items.add(_notice(
        Icons.lock_outline,
        'Allow "All files access" so the app can find your songs.',
        button: 'Allow',
        onTap: lib.requestAccess,
      ));
    }
    if (Platform.isWindows &&
        lib.folders.isEmpty &&
        lib.tracks.isEmpty &&
        !lib.loading) {
      items.add(_notice(
        Icons.folder_open,
        'Add a folder that contains your music.',
        button: 'Add folder',
        onTap: lib.addFolder,
      ));
    }
    if (Platform.isAndroid &&
        !lib.needAccess &&
        !lib.loading &&
        lib.tracks.isEmpty) {
      items.add(_notice(Icons.music_off, 'No songs found on this device.',
          button: 'Rescan', onTap: lib.scan));
    }
    if (!m.online) {
      items.add(_notice(
        Icons.cloud_off,
        AppMode.onlineBuild
            ? 'Offline mode: only your own music is shown. Tap "Offline" above '
                'to search YouTube.'
            : 'Offline-only build: your own music, no internet.',
      ));
    } else if (m.youtubeKey.isEmpty) {
      items.add(_notice(
        Icons.key,
        'Add your YouTube API key to search YouTube.',
        button: 'Add',
        onTap: () => showOnlineSettings(context),
      ));
    }
    return Column(children: items);
  }

  SliverToBoxAdapter _row(String title, List<Track> tracks, {VoidCallback? onMore}) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (onMore != null)
                  TextButton(onPressed: onMore, child: const Text('See all')),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _PosterCard(
                track: tracks[i],
                onTap: () => _play(tracks, i),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _ytRow(List<MediaItem> items) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Row(
              children: [
                Text('Recently played',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(width: 10),
                YouTubeBadge(size: 14),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Playback.play(context, items[i], queue: items),
                child: SizedBox(
                  width: 138,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: AppColors.card),
                        if (items[i].thumb != null)
                          Image.network(items[i].thumb!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox()),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        const Positioned(
                          top: 8,
                          left: 8,
                          child: YouTubeBadge(size: 11),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(items[i].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.bold)),
                              Text(items[i].creator,
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
              ),
            ),
          ),
        ],
      ),
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
