import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/thumbnail_service.dart';
import '../services/trash_service.dart';
import '../utils/format.dart';

class CleanerScreen extends StatefulWidget {
  final List<VideoItem> items;
  final Future<void> Function() onChanged;
  const CleanerScreen({super.key, required this.items, required this.onChanged});

  @override
  State<CleanerScreen> createState() => _CleanerScreenState();
}

class _CleanerScreenState extends State<CleanerScreen> {
  late List<VideoItem> _items =
      widget.items.where((v) => v.path.isNotEmpty).toList();
  final Set<String> _picked = <String>{};
  bool _busy = false;

  /// Videos with exactly the same size are almost certainly copies.
  List<List<VideoItem>> _groups() {
    final m = <int, List<VideoItem>>{};
    for (final v in _items) {
      if (v.sizeBytes > 0) {
        (m[v.sizeBytes] ??= <VideoItem>[]).add(v);
      }
    }
    final g = <List<VideoItem>>[];
    for (final l in m.values) {
      if (l.length > 1) {
        g.add(List<VideoItem>.of(l)..sort((a, b) => a.date.compareTo(b.date)));
      }
    }
    g.sort((a, b) => (b.first.sizeBytes * (b.length - 1))
        .compareTo(a.first.sizeBytes * (a.length - 1)));
    return g;
  }

  int get _pickedBytes => _items
      .where((v) => _picked.contains(v.id))
      .fold<int>(0, (sum, v) => sum + v.sizeBytes);

  void _selectAllDuplicates(List<List<VideoItem>> groups) {
    setState(() {
      for (final g in groups) {
        for (var i = 1; i < g.length; i++) {
          _picked.add(g[i].id);
        }
      }
    });
  }

  Future<void> _trashPicked() async {
    final list = _items.where((v) => _picked.contains(v.id)).toList();
    if (list.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move ${list.length} videos to trash?'),
        content: Text('This frees ${formatSize(_pickedBytes)}. '
            'You can restore them from Trash for 30 days.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    var failed = 0;
    for (final v in list) {
      try {
        await TrashService.instance.moveToTrash(v);
        _items.remove(v);
        _picked.remove(v.id);
      } catch (_) {
        failed++;
      }
    }
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed could not be moved.')),
      );
    }
  }

  String _dur(VideoItem v) =>
      formatDuration(ThumbnailService.instance.durations[v.id] ?? v.duration);

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    final biggest = List<VideoItem>.of(_items)
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final top = biggest.take(100).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Storage cleaner'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Duplicates'), Tab(text: 'Biggest')],
          ),
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _duplicates(groups),
                  _biggest(top),
                ],
              ),
        bottomNavigationBar: _picked.isEmpty || _busy
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                        'Move ${_picked.length} to trash (${formatSize(_pickedBytes)})'),
                    onPressed: _trashPicked,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _duplicates(List<List<VideoItem>> groups) {
    if (groups.isEmpty) {
      return const Center(
        child: Text('No duplicates found.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '${groups.length} groups of videos with exactly the same size. '
            'These are very likely copies.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _selectAllDuplicates(groups),
            child: const Text('Select all except the oldest in each group'),
          ),
        ),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${g.length} copies · ${formatSize(g.first.sizeBytes)} each',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final v in g)
            CheckboxListTile(
              dense: true,
              value: _picked.contains(v.id),
              onChanged: (b) => setState(() {
                if (b == true) {
                  _picked.add(v.id);
                } else {
                  _picked.remove(v.id);
                }
              }),
              title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_dur(v)} · ${v.path}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          const Divider(),
        ],
      ],
    );
  }

  Widget _biggest(List<VideoItem> top) {
    if (top.isEmpty) {
      return const Center(
        child: Text('No videos.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView(
      children: [
        for (final v in top)
          CheckboxListTile(
            dense: true,
            value: _picked.contains(v.id),
            onChanged: (b) => setState(() {
              if (b == true) {
                _picked.add(v.id);
              } else {
                _picked.remove(v.id);
              }
            }),
            title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${formatSize(v.sizeBytes)} · ${_dur(v)} · ${v.source.label}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }
}
