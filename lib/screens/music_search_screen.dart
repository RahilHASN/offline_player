import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/provider.dart';
import '../bridge/providers/jamendo_provider.dart';
import '../bridge/providers/youtube_provider.dart';
import '../bridge/registry.dart';
import '../music/music_library.dart';
import '../music/music_player.dart';
import '../services/app_mode.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

enum _Src { all, device, jamendo, youtube }

class MusicSearchScreen extends StatefulWidget {
  const MusicSearchScreen({super.key});

  @override
  State<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends State<MusicSearchScreen> {
  final TextEditingController _c = TextEditingController();
  Timer? _t;
  _Src _src = _Src.all;
  List<MediaItem> _jam = <MediaItem>[];
  List<MediaItem> _yt = <MediaItem>[];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  bool _isLink(String q) => q.startsWith('http://') || q.startsWith('https://');

  bool get _wantsJamendo => _src == _Src.all || _src == _Src.jamendo;

  void _changed(String q) {
    setState(() {});
    _t?.cancel();
    final m = AppMode.instance;
    final t = q.trim();
    if (!_wantsJamendo || !m.online || t.length < 2 || m.jamendoId.isEmpty || _isLink(t)) {
      if (_jam.isNotEmpty) setState(() => _jam = <MediaItem>[]);
      return;
    }
    _t = Timer(const Duration(milliseconds: 500), () => _searchJam(t));
  }

  Future<void> _searchJam(String q) async {
    setState(() => _busy = true);
    try {
      final r = await JamendoProvider().search(q);
      if (!mounted || _c.text.trim() != q) return;
      setState(() {
        _jam = r;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _searchYt(String q) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await YouTubeProvider.instance.search(q);
      if (!mounted) return;
      setState(() => _yt = r);
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
    if (!AppMode.instance.online && (_isLink(t) || _src == _Src.youtube)) {
      setState(() => _err = 'Switch to Online mode first.');
      return;
    }
    if (_isLink(t)) {
      _openLink(t);
    } else if (_src == _Src.youtube) {
      _searchYt(t);
    } else if (_wantsJamendo && AppMode.instance.online) {
      _searchJam(t);
    }
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Widget _header(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _spinner() => const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _ytTile(MediaItem m) => ListTile(
        onTap: () => Playback.play(context, m, queue: _yt),
        leading: SizedBox(
          width: 96,
          height: 54,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: m.thumb == null
                ? Container(color: Colors.white10)
                : Image.network(m.thumb!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
          ),
        ),
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
        trailing: const Icon(Icons.ondemand_video, size: 18, color: Colors.white54),
      );

  @override
  Widget build(BuildContext context) {
    final raw = _c.text.trim();
    final q = raw.toLowerCase();
    final online = AppMode.instance.online;
    final all = MusicLibrary.instance.tracks;
    final showDevice = _src == _Src.all || _src == _Src.device;
    final local = !showDevice || _isLink(raw)
        ? const []
        : (q.isEmpty
            ? all
            : all
                .where((t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q) ||
                    t.album.toLowerCase().contains(q))
                .toList());

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          onChanged: _changed,
          onSubmitted: _submit,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search, or paste a link',
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
                for (final s in _Src.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(const {
                        _Src.all: 'All',
                        _Src.device: 'On device',
                        _Src.jamendo: 'Jamendo',
                        _Src.youtube: 'YouTube',
                      }[s]!),
                      selected: _src == s,
                      onSelected: (_) {
                        setState(() => _src = s);
                        _changed(_c.text);
                      },
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
          if (local.isNotEmpty)
            SliverToBoxAdapter(
              child: _header(
                q.isEmpty ? 'All songs (${local.length})' : 'On your device',
                trailing: TextButton.icon(
                  onPressed: () => MusicPlayer.instance
                      .playQueue(local, Random().nextInt(local.length), shuffle: true),
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
          if (online && _wantsJamendo && raw.length >= 2 && !_isLink(raw)) ...[
            SliverToBoxAdapter(
              child: _header('Online (Jamendo)', trailing: _busy ? _spinner() : null),
            ),
            SliverList.builder(
              itemCount: _jam.length,
              itemBuilder: (context, i) {
                final t = _jam[i].track!;
                return TrackTile(
                  track: t,
                  onTap: () => Playback.play(context, _jam[i], queue: _jam),
                );
              },
            ),
          ],
          if (_src == _Src.youtube) ...[
            SliverToBoxAdapter(
              child: _header('YouTube', trailing: _busy ? _spinner() : null),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  !online
                      ? 'Switch to Online mode to search YouTube.'
                      : 'Press search on the keyboard. Videos play in YouTube\'s official player. '
                          'Each search uses ${YouTubeQuota.searchCost} of your free daily units.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: _yt.length,
              itemBuilder: (context, i) => _ytTile(_yt[i]),
            ),
          ],
          if (local.isEmpty &&
              _jam.isEmpty &&
              _yt.isEmpty &&
              !_isLink(raw) &&
              _src != _Src.youtube)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('Nothing found.', style: TextStyle(color: Colors.white54)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
