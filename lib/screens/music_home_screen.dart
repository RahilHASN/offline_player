import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/online_sources.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/online_settings.dart';
import '../widgets/poster.dart';
import 'music_search_screen.dart';
import 'player_screen.dart';

class _RowDef {
  final String title;
  final String? tags;
  final String order;
  const _RowDef(this.title, this.tags, this.order);
}

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
  static const _defs = <_RowDef>[
    _RowDef('Trending this week', null, 'popularity_week'),
    _RowDef('New releases', null, 'releasedate_desc'),
    _RowDef('Electronic', 'electronic', 'popularity_month'),
    _RowDef('Pop', 'pop', 'popularity_month'),
    _RowDef('Rock', 'rock', 'popularity_month'),
    _RowDef('Hip-hop', 'hiphop', 'popularity_month'),
    _RowDef('Chill & lounge', 'lounge', 'popularity_month'),
    _RowDef('Jazz', 'jazz', 'popularity_month'),
    _RowDef('Classical', 'classical', 'popularity_month'),
  ];

  final MusicLibrary lib = MusicLibrary.instance;
  final Map<String, List<Track>> _rows = <String, List<Track>>{};
  List<ArchiveVideo> _videos = <ArchiveVideo>[];
  String? _err;
  bool _loadingOnline = false;
  bool _reload = false;

  @override
  void initState() {
    super.initState();
    lib.init();
    AppMode.instance.addListener(_loadOnline);
    _loadOnline();
  }

  @override
  void dispose() {
    AppMode.instance.removeListener(_loadOnline);
    super.dispose();
  }

  Future<void> _loadOnline() async {
    final m = AppMode.instance;
    if (!m.online) {
      if (mounted) {
        setState(() {
          _rows.clear();
          _videos = <ArchiveVideo>[];
          _err = null;
        });
      }
      return;
    }
    if (_loadingOnline) {
      _reload = true;
      return;
    }
    setState(() {
      _loadingOnline = true;
      _err = null;
      _rows.clear();
    });
    try {
      if (m.jamendoId.trim().isNotEmpty) {
        for (final d in _defs) {
          final l = await OnlineSources.jamendo(
              tags: d.tags, order: d.order, limit: 24);
          if (!mounted) return;
          if (l.isNotEmpty) setState(() => _rows[d.title] = l);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    try {
      final v = await OnlineSources.musicVideos();
      if (mounted) setState(() => _videos = v);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loadingOnline = false);
    if (_reload) {
      _reload = false;
      _loadOnline();
    }
  }

  _Feat? _featured() {
    if (AppMode.instance.online && _rows.isNotEmpty) {
      final l = _rows.values.first;
      return _Feat(l.first, l, 'FEATURED');
    }
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

  Future<void> _playVideo(ArchiveVideo v) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String? url;
    try {
      url = await OnlineSources.videoUrl(v.id);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playable file found for this video.')),
      );
      return;
    }
    MusicPlayer.instance.pause();
    final item = VideoItem(
      id: 'net:${v.id}',
      path: url,
      name: v.title,
      sizeBytes: v.id.hashCode.abs(),
      duration: null,
      date: DateTime.fromMillisecondsSinceEpoch(0),
      source: VideoSource.pc,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(queue: [item], index: 0),
    ));
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MusicSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([lib, AppMode.instance]),
      builder: (context, _) {
        final m = AppMode.instance;
        final feat = _featured();
        final recent = List<Track>.of(lib.tracks)
          ..sort((a, b) => b.addedMs.compareTo(a.addedMs));

        return Scaffold(
          bottomNavigationBar: const MiniPlayer(),
          body: RefreshIndicator(
            onRefresh: () async {
              await lib.scan();
              await _loadOnline();
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
                    const ModeChip(),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rescan') lib.scan();
                        if (v == 'folder') lib.addFolder();
                        if (v == 'online') showOnlineSettings(context);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rescan', child: Text('Rescan music')),
                        PopupMenuItem(
                            value: 'folder', child: Text('Add music folder')),
                        PopupMenuItem(
                            value: 'online', child: Text('Online settings')),
                      ],
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _hero(feat)),
                SliverToBoxAdapter(child: _notices(m)),
                if (lib.loading && lib.tracks.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (lib.tracks.isNotEmpty)
                  _row('Recently added', recent.take(20).toList()),
                if (lib.tracks.isNotEmpty)
                  _row('Your songs', lib.tracks.take(30).toList(),
                      onMore: _openSearch),
                for (final e in _rows.entries) _row(e.key, e.value),
                if (_videos.isNotEmpty) _videoRow(),
                if (_loadingOnline)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
                  ),
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
                'for trending music, lyrics and posters.'
            : 'Offline-only build: your own music, no internet.',
      ));
    } else if (m.jamendoId.isEmpty) {
      items.add(_notice(
        Icons.key,
        'Add your free Jamendo client ID to see online music.',
        button: 'Add',
        onTap: () => showOnlineSettings(context),
      ));
    }
    if (_err != null) {
      items.add(_notice(Icons.error_outline, 'Online problem: $_err',
          button: 'Retry', onTap: _loadOnline));
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

  SliverToBoxAdapter _videoRow() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Text('Music videos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _videos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final v = _videos[i];
                return GestureDetector(
                  onTap: () => _playVideo(v),
                  child: SizedBox(
                    width: 230,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: AppColors.card),
                          Image.network(
                            v.thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.movie_outlined,
                                    color: Colors.white24, size: 40)),
                          ),
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
                            bottom: 8,
                            child: Text(v.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ),
                          const Center(
                              child: Icon(Icons.play_circle_fill,
                                  size: 38, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
