import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/playlist_store.dart';
import '../bridge/provider.dart';
import '../bridge/suggestions.dart';
import '../bridge/youtube_history.dart';
import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/online_settings.dart';
import '../widgets/poster.dart';
import 'local_playlist_screen.dart';
import 'music_search_screen.dart';
import 'see_all_screen.dart';
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
    Suggestions.instance.init();
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

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const YtLibraryScreen()),
    );
  }

  void _seeAll(String title, List<MediaItem> items) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => SeeAllScreen(title: title, items: List.of(items))),
    );
  }

  void _showFeatured() {
    final f = _featured();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: f == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No songs found on this device yet.',
                    style: TextStyle(color: Colors.white54)),
              )
            : _hero(f, onPlayed: () => Navigator.pop(ctx)),
      ),
    );
  }

  void _openLocalPlaylist() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LocalPlaylistScreen()),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MusicSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [lib, AppMode.instance, YouTubeHistory.instance, Suggestions.instance]),
      builder: (context, _) {
        final m = AppMode.instance;
        final hist = YouTubeHistory.instance.items;
        final sug = Suggestions.instance;
        final store = PlaylistStore.instance;

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
                        if (v == 'featured') _showFeatured();
                        if (v == 'rescan') lib.scan();
                        if (v == 'folder') lib.addFolder();
                        if (v == 'online') showOnlineSettings(context);
                        if (v == 'clear') YouTubeHistory.instance.clear();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: 'featured', child: Text('From your library')),
                        PopupMenuItem(value: 'rescan', child: Text('Rescan music')),
                        PopupMenuItem(
                            value: 'folder', child: Text('Add music folder')),
                        PopupMenuItem(
                            value: 'online', child: Text('Online settings')),
                        PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear play history')),
                      ],
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _notices(m)),
                if (m.online)
                  SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: ListTile(
                        onTap: _openSearch,
                        leading: const Icon(Icons.public),
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
                SliverToBoxAdapter(
                  child: Card(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: ListTile(
                      onTap: _openLocalPlaylist,
                      leading: const Icon(Icons.queue_music),
                      title: const Text('Local playlist'),
                      subtitle: Text('${lib.tracks.length} songs on this device'),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
                if (m.online && hist.isNotEmpty)
                  _songRow('Recently played', hist,
                      onMore: () => _seeAll('Recently played', hist)),
                if (m.online && YouTubeHistory.instance.onRepeat.isNotEmpty)
                  _songRow('On repeat', YouTubeHistory.instance.onRepeat,
                      onMore: () =>
                          _seeAll('On repeat', YouTubeHistory.instance.onRepeat)),
                if (m.online && sug.favourites.isNotEmpty)
                  _songRow('Your favourites', sug.favourites,
                      onMore: _openLibrary,
                      forceArrow: store.fav.length > Suggestions.rowMax),
                if (m.online && sug.fromPlaylists.isNotEmpty)
                  _songRow('From your playlists', sug.fromPlaylists,
                      onMore: _openLibrary, forceArrow: true),
                if (m.online && sug.discover.isNotEmpty)
                  _songRow('Discover', sug.discover,
                      onMore: () => _seeAll('Discover', sug.discover)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hero(_Feat f, {VoidCallback? onPlayed}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 250,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(track: f.track),
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
                    Text(f.label,
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      f.track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    Text(f.track.artist,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              final i = f.queue.indexWhere((t) => t.id == f.track.id);
                              _play(f.queue, i < 0 ? 0 : i, shuffle: false);
                              onPlayed?.call();
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              _play(f.queue, Random().nextInt(f.queue.length),
                                  shuffle: true);
                              onPlayed?.call();
                            },
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
                'to search online.'
            : 'Offline-only build: your own music, no internet.',
      ));
    } else if (m.youtubeKey.isEmpty) {
      items.add(_notice(
        Icons.key,
        'Add your search API key to search online.',
        button: 'Add',
        onTap: () => showOnlineSettings(context),
      ));
    }
    return Column(children: items);
  }

  /// A row of at most [Suggestions.rowMax] songs, then an arrow card.
  SliverToBoxAdapter _songRow(String title, List<MediaItem> all,
      {required VoidCallback onMore, bool forceArrow = false}) {
    final shown = all.take(Suggestions.rowMax).toList();
    final arrow = all.length > Suggestions.rowMax || forceArrow;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: shown.length + (arrow ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                if (i == shown.length) return _ArrowCard(onTap: onMore);
                return _ItemCard(
                  item: shown[i],
                  onTap: () => Playback.play(context, shown[i], queue: all),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.onTap});

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
              const ColoredBox(color: AppColors.card),
              if (item.thumb != null)
                Image.network(item.thumb!,
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
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    Text(item.creator,
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

/// Last card of a row: opens the full list.
class _ArrowCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ArrowCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_rounded),
            ),
            const SizedBox(height: 8),
            const Text('See all',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
