import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorites and tags, saved on the device. Videos are identified by file path.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore instance = LibraryStore._();

  SharedPreferences? _prefs;
  final List<String> _tags = <String>[];
  final Set<String> _favs = <String>{};
  final Map<String, Set<String>> _map = <String, Set<String>>{};

  // filters (not saved)
  final Set<String> selected = <String>{};
  bool matchAll = false;
  bool favoritesOnly = false;

  List<String> get tags => List<String>.unmodifiable(_tags);
  bool get filtering => favoritesOnly || selected.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _tags
      ..clear()
      ..addAll(p.getStringList('tagList') ?? <String>[]);
    _favs
      ..clear()
      ..addAll(p.getStringList('favorites') ?? <String>[]);
    _map.clear();
    final raw = p.getString('tagMap');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          _map[k] = <String>{...(v as List<dynamic>).cast<String>()};
        });
      } catch (_) {}
    }
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setStringList('tagList', _tags);
    p.setStringList('favorites', _favs.toList());
    p.setString(
      'tagMap',
      jsonEncode(_map.map((k, v) => MapEntry(k, v.toList()))),
    );
  }

  bool isFav(String path) => _favs.contains(path);

  void toggleFav(String path) {
    if (path.isEmpty) return;
    if (!_favs.add(path)) _favs.remove(path);
    _save();
    notifyListeners();
  }

  Set<String> tagsFor(String path) => _map[path] ?? const <String>{};

  /// Returns the tag name that was created (or already existed), or null.
  String? createTag(String raw) {
    var n = raw.trim();
    while (n.startsWith('#')) {
      n = n.substring(1);
    }
    n = n.trim();
    if (n.isEmpty) return null;
    for (final t in _tags) {
      if (t.toLowerCase() == n.toLowerCase()) return t;
    }
    _tags.add(n);
    _tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _save();
    notifyListeners();
    return n;
  }

  void deleteTag(String tag) {
    _tags.remove(tag);
    for (final s in _map.values) {
      s.remove(tag);
    }
    _map.removeWhere((_, v) => v.isEmpty);
    selected.remove(tag);
    _save();
    notifyListeners();
  }

  void setTags(String path, Set<String> tags) {
    if (path.isEmpty) return;
    if (tags.isEmpty) {
      _map.remove(path);
    } else {
      _map[path] = <String>{...tags};
    }
    _save();
    notifyListeners();
  }

  int countFor(String tag) =>
      _map.values.where((s) => s.contains(tag)).length;

  void renamePath(String oldPath, String newPath) {
    if (oldPath == newPath) return;
    if (_favs.remove(oldPath)) _favs.add(newPath);
    final t = _map.remove(oldPath);
    if (t != null) _map[newPath] = t;
    _save();
    notifyListeners();
  }

  void toggleSelected(String tag) {
    if (!selected.add(tag)) selected.remove(tag);
    notifyListeners();
  }

  void setMatchAll(bool v) {
    matchAll = v;
    notifyListeners();
  }

  void setFavoritesOnly(bool v) {
    favoritesOnly = v;
    notifyListeners();
  }

  void clearFilters() {
    selected.clear();
    favoritesOnly = false;
    notifyListeners();
  }

  bool matches(String path) {
    if (favoritesOnly && !_favs.contains(path)) return false;
    if (selected.isNotEmpty) {
      final t = tagsFor(path);
      final ok = matchAll
          ? selected.every(t.contains)
          : selected.any(t.contains);
      if (!ok) return false;
    }
    return true;
  }
}
