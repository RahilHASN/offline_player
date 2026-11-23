import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/provider.dart';
import '../bridge/providers/youtube_provider.dart';
import '../bridge/registry.dart';
import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import '../widgets/youtube_badge.dart';

enum _Mode { songs, videos, device }

class MusicSearchScreen extends StatefulWidget {
  const MusicSearchScreen({super.key});

  @override
  State<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends State<MusicSearchScreen> {
  final TextEditingController _c = TextEditingController();
  _Mode _mode = AppMode.instance.online ? _Mode.songs : _Mode.device;
  List<MediaItem> _songs = <MediaItem>[];
  List<MediaItem> _videos = <MediaItem>[];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _isLink(String q) => q.startsWith('http://') || q.startsWith('https://');

  Future<void> _searchYt(String q) async {
    final music = _mode == _Mode.songs;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await YouTubeProvider.instance.find(q, music: music);
      if (!mounted) return;
      setState(() {
        if (music) {
          _songs = r;
        } else {
          _videos = r;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openLink(String q) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final item = await ProviderRegistry.instance.resolveUrl(q);
      if (!mounted) return;
      setState(() => _busy = false);
      await Playback.play(context, item);
      return;
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _submit(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    if (!AppMode.instance.online && (_isLink(t) || _mode != _Mode.device)) {
      setState(() => _err = 'Switch to Online mode first.');
      return;
    }
    if (_isLink(t)) {
      _openLink(t);
    } else if (_mode != _Mode.device) {
      _searchYt(t);
    }
  }

  String _fmt(int s) {
    final r = s % 60;
    return '${s ~/ 60}:${r.toString().padLeft(2, '0')}';
  }

  Widget _spinner() => const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _thumb(MediaItem m, double w, double h) => SizedBox(
        width: w,
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: m.thumb == null
              ? Container(color: Colors.white10)
              : Image.network(m.thumb!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
        ),
      );

  Widget _songTile(MediaItem m, List<MediaItem> list) => ListTile(
        onTap: () => Playback.play(context, m, queue: list),
        leading: _thumb(m, 56, 56),
        title: Text(m.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [m.creator, if (m.durationSec > 0) _fmt(m.durationSec)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        trailing: const Icon(Icons.play_circle_outline, color: Colors.white54),
      );

  Widget _videoTile(MediaItem m, List<MediaItem> list) => ListTile(
        onTap: () => Playback.play(context, m, queue: list),
        leading: _thumb(m, 96, 54),
        title: Text(m.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          [m.creator, if (m.durationSec > 0) _fmt(m.durationSec)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        trailing: const Icon(Icons.play_circle_outline, color: Colors.white54),
      );

  @override
  Widget build(BuildContext context) {
    final raw = _c.text.trim();
    final q = raw.toLowerCase();
    final online = AppMode.instance.online;
    final isDevice = _mode == _Mode.device;
    final all = MusicLibrary.instance.tracks;
    final List<Track> local = (!isDevice || _isLink(raw))
        ? <Track>[]
        : (q.isEmpty
            ? all
            : all
                .where((t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q) ||
                    t.album.toLowerCase().contains(q))
                .toList());
    final list = _mode == _Mode.songs ? _songs : _videos;

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: _submit,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search songs, artists, or paste a link',
            border: InputBorder.none,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in _Mode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(const {
                        _Mode.songs: 'Songs',
                        _Mode.videos: 'Videos',
                        _Mode.device: 'On device',
                      }[s]!),
                      selected: _mode == s,
                      onSelected: (_) => setState(() {
                        _mode = s;
                        _err = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          if (_isLink(raw))
            SliverToBoxAdapter(
              child: ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Open this link'),
                subtitle: const Text(
                    'YouTube links play in the official player. Other links must be plain audio or video files.',
                    style: TextStyle(fontSize: 12)),
                trailing: _busy ? _spinner() : null,
                onTap: () => _submit(raw),
              ),
            ),
          if (_err != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(_err!, style: const TextStyle(color: Colors.orangeAccent)),
              ),
            ),
          if (isDevice) ...[
            if (local.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          q.isEmpty ? 'All songs (${local.length})' : 'On your device',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => MusicPlayer.instance.playQueue(
                            local, Random().nextInt(local.length),
                            shuffle: true),
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: local.length,
              itemBuilder: (context, i) => TrackTile(
                track: local[i],
                onTap: () => MusicPlayer.instance.playQueue(local, i),
              ),
            ),
            if (local.isEmpty && !_isLink(raw))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('Nothing found.',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
              ),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    const YouTubeBadge(),
                    const SizedBox(width: 8),
                    Text(_mode == _Mode.songs ? 'Songs' : 'Videos',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_busy) _spinner(),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  !online
                      ? 'Switch to Online mode to search YouTube.'
                      : list.isEmpty && !_busy
                          ? 'Type a song or artist and press search on the keyboard. '
                              'Results play in YouTube\'s official player. '
                              'Each search uses ${YouTubeQuota.searchCost} of your free daily units.'
                          : 'Plays in YouTube\'s official player.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _mode == _Mode.songs
                  ? _songTile(list[i], list)
                  : _videoTile(list[i], list),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
