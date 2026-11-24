import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compliance.dart';

/// Favourites and playlists. Only YouTube video ids are saved here.
/// Titles and posters are fetched again each time a list is opened.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore._();
  static final PlaylistStore instance = PlaylistStore._();

  List<String> fav = <String>[];
  final Map<String, List<String>> lists = <String, List<String>>{};
  bool _loaded = false;

  List<String> get names => lists.keys.toList();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    fav = p.getStringList('ytFav') ?? <String>[];
    final raw = p.getString('ytLists');
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          j.forEach((k, v) {
            if (v is List) {
              lists['$k'] = v.map((e) => '$e').toList();
            }
          });
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('ytFav', fav);
    await p.setString('ytLists', jsonEncode(lists));
  }

  bool isFav(String id) => fav.contains(id);

  Future<void> toggleFav(String id) async {
    if (!Compliance.validVideoId(id)) return;
    await load();
    if (fav.contains(id)) {
      fav.remove(id);
    } else {
      fav.insert(0, id);
    }
    notifyListeners();
    await _save();
  }

  bool contains(String name, String id) => lists[name]?.contains(id) ?? false;

  Future<void> createList(String name) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 40 || lists.containsKey(n)) return;
    await load();
    lists[n] = <String>[];
    notifyListeners();
    await _save();
  }

  Future<void> deleteList(String name) async {
    lists.remove(name);
    notifyListeners();
    await _save();
  }

  Future<void> toggleIn(String name, String id) async {
    if (!Compliance.validVideoId(id)) return;
    final l = lists[name];
    if (l == null) return;
    if (l.contains(id)) {
      l.remove(id);
    } else {
      l.add(id);
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeFromFav(String id) async {
    fav.remove(id);
    notifyListeners();
    await _save();
  }
}

Future<String?> _askName(BuildContext ctx) {
  final t = TextEditingController();
  return showDialog<String>(
    context: ctx,
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
}

/// Bottom sheet: tick the playlists this song belongs to, or make a new one.
Future<void> showAddToPlaylist(BuildContext context, String videoId) async {
  final s = PlaylistStore.instance;
  await s.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to playlist',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () async {
                final n = await _askName(ctx);
                if (n != null && n.isNotEmpty) {
                  await s.createList(n);
                  await s.toggleIn(n, videoId);
                }
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final name in s.names)
                    CheckboxListTile(
                      value: s.contains(name, videoId),
                      title: Text(name),
                      subtitle: Text('${s.lists[name]!.length} songs'),
                      onChanged: (_) => s.toggleIn(name, videoId),
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
