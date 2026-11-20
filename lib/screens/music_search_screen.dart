import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../music/music_library.dart';
import '../music/music_player.dart';
import '../music/online_sources.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

class MusicSearchScreen extends StatefulWidget {
  const MusicSearchScreen({super.key});

  @override
  State<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends State<MusicSearchScreen> {
  final TextEditingController _c = TextEditingController();
  Timer? _t;
  List<Track> _online = <Track>[];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _changed(String q) {
    setState(() {});
    _t?.cancel();
    final m = AppMode.instance;
    if (!m.online || q.trim().length < 2 || m.jamendoId.isEmpty) {
      setState(() => _online = <Track>[]);
      return;
    }
    _t = Timer(const Duration(milliseconds: 500), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _busy = true);
    try {
      final r =
          await OnlineSources.jamendo(search: q, order: 'relevance', limit: 30);
      if (!mounted || _c.text.trim() != q) return;
      setState(() {
        _online = r;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _header(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _c.text.trim().toLowerCase();
    final all = MusicLibrary.instance.tracks;
    final local = q.isEmpty
        ? all
        : all
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q) ||
                t.album.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          onChanged: _changed,
          decoration: const InputDecoration(
            hintText: 'Search songs, artists',
            border: InputBorder.none,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          if (local.isNotEmpty)
            SliverToBoxAdapter(
              child: _header(
                q.isEmpty ? 'All songs (${local.length})' : 'On your device',
                trailing: TextButton.icon(
                  onPressed: () => MusicPlayer.instance.playQueue(
                      local, Random().nextInt(local.length),
                      shuffle: true),
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Shuffle'),
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
          if (AppMode.instance.online && q.length >= 2) ...[
            SliverToBoxAdapter(
              child: _header(
                'Online (Jamendo)',
                trailing: _busy
                    ? const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            if (_err != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_err!,
                      style: const TextStyle(color: Colors.orangeAccent)),
                ),
              ),
            SliverList.builder(
              itemCount: _online.length,
              itemBuilder: (context, i) => TrackTile(
                track: _online[i],
                onTap: () => MusicPlayer.instance.playQueue(_online, i),
              ),
            ),
          ],
          if (local.isEmpty && _online.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('Nothing found.',
                      style: TextStyle(color: Colors.white54)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
