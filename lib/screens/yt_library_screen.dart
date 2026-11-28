import 'package:flutter/material.dart';

import '../bridge/playback.dart';
import '../bridge/playlist_store.dart';
import '../bridge/provider.dart';
import '../bridge/providers/youtube_provider.dart';
import '../services/app_mode.dart';

/// Favourites and your own playlists.
class YtLibraryScreen extends StatefulWidget {
  const YtLibraryScreen({super.key});

  @override
  State<YtLibraryScreen> createState() => _YtLibraryScreenState();
}

class _YtLibraryScreenState extends State<YtLibraryScreen> {
  @override
  void initState() {
    super.initState();
    PlaylistStore.instance.load();
  }

  Future<void> _newList() async {
    final t = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: t,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, t.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (n != null && n.isNotEmpty) PlaylistStore.instance.createList(n);
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) PlaylistStore.instance.deleteList(name);
  }

  @override
  Widget build(BuildContext context) {
    final s = PlaylistStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Favourites & playlists'),
        ),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.redAccent),
              title: const Text('Favourites'),
              subtitle: Text('${s.fav.length} songs'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _ListScreen(title: 'Favourites', name: null))),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Playlists',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  TextButton.icon(
                    onPressed: _newList,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
            if (s.names.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No playlists yet. Open a song in the player and tap the playlist button.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            for (final n in s.names)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(n),
                subtitle: Text('${s.lists[n]!.length} songs'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(n),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _ListScreen(title: n, name: n))),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListScreen extends StatefulWidget {
  final String title;
  final String? name; // null = favourites
  const _ListScreen({required this.title, required this.name});

  @override
  State<_ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<_ListScreen> {
  List<MediaItem> _items = <MediaItem>[];
  bool _busy = false;
  String? _err;

  List<String> get _ids => widget.name == null
      ? PlaylistStore.instance.fav
      : (PlaylistStore.instance.lists[widget.name] ?? <String>[]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppMode.instance.online) {
      setState(() => _err = 'Switch to Online mode to load your songs.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await YouTubeProvider.instance.byIds(List<String>.of(_ids));
      if (!mounted) return;
      setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(MediaItem m) async {
    final id = m.videoId;
    if (id == null) return;
    if (widget.name == null) {
      await PlaylistStore.instance.removeFromFav(id);
    } else {
      await PlaylistStore.instance.toggleIn(widget.name!, id);
    }
    if (mounted) setState(() => _items = _items.where((x) => x.videoId != id).toList());
  }

  String _fmt(int s) {
    final r = s % 60;
    return '${s ~/ 60}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Playback.play(context, _items.first, queue: _items),
            ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_err!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent)),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text('Nothing here yet.',
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final m = _items[i];
                        return ListTile(
                          onTap: () => Playback.play(context, m, queue: _items),
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
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _remove(m),
                          ),
                        );
                      },
                    ),
    );
  }
}
