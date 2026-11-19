import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';

class Progress {
  final int pos;
  final int dur;
  final int ts;
  const Progress(this.pos, this.dur, this.ts);

  double get fraction =>
      dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0).toDouble();
}

/// Favorites, tags, playlists, bookmarks, watch progress and the vault.
/// Saved on the device. Videos are identified by VideoItem.key.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore instance = LibraryStore._();
  static final RegExp _keyRe = RegExp(r'^\d+-\d+$');

  SharedPreferences? _prefs;
  Timer? _saveTimer;

  final List<String> _tags = <String>[];
  final Set<String> _favs = <String>{};
  final Map<String, Set<String>> _map = <String, Set<String>>{};
  final Map<String, List<String>> _playlists = <String, List<String>>{};
  final Map<String, List<int>> _bookmarks = <String, List<int>>{};
  final Map<String, Progress> _progress = <String, Progress>{};
  final Set<String> _vault = <String>{};
  String _pin = '';

  // filters and session state (not saved)
  final Set<String> selected = <String>{};
  bool matchAll = false;
  bool favoritesOnly = false;
  bool vaultUnlocked = false;

  List<String> get tags => List<String>.unmodifiable(_tags);
  bool get filtering => favoritesOnly || selected.isNotEmpty;

  // ---------- load / save ----------

  Iterable<String> _strList(dynamic v) =>
      v is List ? v.whereType<String>() : const <String>[];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final raw = p.getString('store2');
    if (raw != null && raw.isNotEmpty) {
      try {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
      return;
    }
    // older version: tags and favorites were keyed by file path
    _tags
      ..clear()
      ..addAll(p.getStringList('tagList') ?? <String>[]);
    _favs
      ..clear()
      ..addAll(p.getStringList('favorites') ?? <String>[]);
    _map.clear();
    final old = p.getString('tagMap');
    if (old != null && old.isNotEmpty) {
      try {
        final decoded = jsonDecode(old) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          _map[k] = <String>{...(v as List<dynamic>).cast<String>()};
        });
      } catch (_) {}
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tags': _tags,
        'map': _map.map((k, v) => MapEntry(k, v.toList())),
        'favs': _favs.toList(),
        'playlists': _playlists,
        'bookmarks': _bookmarks,
        'progress':
            _progress.map((k, v) => MapEntry(k, [v.pos, v.dur, v.ts])),
        'vault': _vault.toList(),
        'pin': _pin,
      };

  void _fromJson(Map<String, dynamic> j) {
    _tags
      ..clear()
      ..addAll(_strList(j['tags']));
    _favs
      ..clear()
      ..addAll(_strList(j['favs']));
    _vault
      ..clear()
      ..addAll(_strList(j['vault']));
    _pin = j['pin'] is String ? j['pin'] as String : '';

    _map.clear();
    final m = j['map'];
    if (m is Map) {
      m.forEach((k, v) {
        final s = _strList(v).toSet();
        if (s.isNotEmpty) _map['$k'] = s;
      });
    }
    _playlists.clear();
    final pl = j['playlists'];
    if (pl is Map) {
      pl.forEach((k, v) {
        _playlists['$k'] = _strList(v).toList();
      });
    }
    _bookmarks.clear();
    final bm = j['bookmarks'];
    if (bm is Map) {
      bm.forEach((k, v) {
        if (v is List) {
          _bookmarks['$k'] = v.whereType<num>().map((e) => e.toInt()).toList();
        }
      });
    }
    _progress.clear();
    final pr = j['progress'];
    if (pr is Map) {
      pr.forEach((k, v) {
        if (v is List && v.length >= 3) {
          _progress['$k'] = Progress(
            (v[0] as num).toInt(),
            (v[1] as num).toInt(),
            (v[2] as num).toInt(),
          );
        }
      });
    }
  }

  /// Used by Restore: replaces everything with the backup.
  void replaceAll(Map<String, dynamic> j) {
    _fromJson(j);
    flush();
    notifyListeners();
  }

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), flush);
  }

  void flush() {
    _saveTimer?.cancel();
    _prefs?.setString('store2', jsonEncode(toJson()));
  }

  /// Tell listeners something changed (no saving).
  void touch() => notifyListeners();

  /// Turns old path-based entries into key-based ones.
  void migrate(List<VideoItem> items) {
    final legacy = <String>{
      for (final k in _favs)
        if (!_keyRe.hasMatch(k)) k,
      for (final k in _map.keys)
        if (!_keyRe.hasMatch(k)) k,
    };
    if (legacy.isEmpty) return;
    final byPath = <String, String>{
      for (final v in items)
        if (v.path.isNotEmpty) v.path: v.key,
    };
    var changed = false;
    for (final p in legacy) {
      final nk = byPath[p];
      if (nk == null) continue;
      if (_favs.remove(p)) _favs.add(nk);
      final t = _map.remove(p);
      if (t != null) {
        _map[nk] = <String>{...(_map[nk] ?? const <String>{}), ...t};
      }
      changed = true;
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  /// A video was renamed or moved by the app and now has a new key.
  void remapKey(String o, String n) {
    if (o == n) return;
    if (_favs.remove(o)) _favs.add(n);
    final t = _map.remove(o);
    if (t != null) _map[n] = t;
    for (final l in _playlists.values) {
      final i = l.indexOf(o);
      if (i >= 0) l[i] = n;
    }
    final b = _bookmarks.remove(o);
    if (b != null) _bookmarks[n] = b;
    final p = _progress.remove(o);
    if (p != null) _progress[n] = p;
    if (_vault.remove(o)) _vault.add(n);
    _save();
    notifyListeners();
  }

  // ---------- favorites ----------

  bool isFav(String key) => _favs.contains(key);

  void toggleFav(String key) {
    if (!_favs.add(key)) _favs.remove(key);
    _save();
    notifyListeners();
  }

  // ---------- tags ----------

  Set<String> tagsFor(String key) => _map[key] ?? const <String>{};

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

  void setTags(String key, Set<String> tags) {
    if (tags.isEmpty) {
      _map.remove(key);
    } else {
      _map[key] = <String>{...tags};
    }
    _save();
    notifyListeners();
  }

  int countFor(String tag) =>
      _map.values.where((s) => s.contains(tag)).length;

  // ---------- playlists ----------

  List<String> get playlistNames {
    final l = _playlists.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return l;
  }

  List<String> playlistKeys(String name) =>
      List<String>.unmodifiable(_playlists[name] ?? const <String>[]);

  bool inPlaylist(String name, String key) =>
      (_playlists[name] ?? const <String>[]).contains(key);

  String? createPlaylist(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return null;
    for (final k in _playlists.keys) {
      if (k.toLowerCase() == n.toLowerCase()) return k;
    }
    _playlists[n] = <String>[];
    _save();
    notifyListeners();
    return n;
  }

  void deletePlaylist(String name) {
    _playlists.remove(name);
    _save();
    notifyListeners();
  }

  void togglePlaylist(String name, String key, bool on) {
    final l = _playlists.putIfAbsent(name, () => <String>[]);
    if (on) {
      if (!l.contains(key)) l.add(key);
    } else {
      l.remove(key);
    }
    _save();
    notifyListeners();
  }

  // ---------- bookmarks ----------

  List<int> bookmarksFor(String key) =>
      List<int>.unmodifiable(_bookmarks[key] ?? const <int>[]);

  void addBookmark(String key, int ms) {
    final l = _bookmarks.putIfAbsent(key, () => <int>[]);
    if (!l.contains(ms)) l.add(ms);
    l.sort();
    _save();
    notifyListeners();
  }

  void removeBookmark(String key, int ms) {
    _bookmarks[key]?.remove(ms);
    _save();
    notifyListeners();
  }

  // ---------- watch progress ----------

  Progress? progressFor(String key) => _progress[key];

  /// Saved quietly: no listeners are told.
  void setProgress(String key, int pos, int dur) {
    if (dur <= 0) return;
    _progress[key] = Progress(pos, dur, DateTime.now().millisecondsSinceEpoch);
    _save();
  }

  // ---------- vault ----------

  bool get hasPin => _pin.isNotEmpty;
  bool isHidden(String key) => _vault.contains(key);

  String _hash(String pin) {
    var h1 = 0x811C9DC5;
    var h2 = 5381;
    final s = 'op-vault:$pin';
    for (var r = 0; r < 300; r++) {
      for (final c in s.codeUnits) {
        h1 = ((h1 ^ c) * 16777619) & 0xFFFFFFFF;
        h2 = ((h2 * 33) + c) & 0xFFFFFFFF;
      }
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  void setPin(String pin) {
    _pin = _hash(pin);
    _save();
    notifyListeners();
  }

  bool checkPin(String pin) => _pin.isNotEmpty && _hash(pin) == _pin;

  void unlockVault() {
    vaultUnlocked = true;
    notifyListeners();
  }

  void lockVault() {
    if (!vaultUnlocked) return;
    vaultUnlocked = false;
    notifyListeners();
  }

  void hide(String key) {
    _vault.add(key);
    _save();
    notifyListeners();
  }

  void unhide(String key) {
    _vault.remove(key);
    _save();
    notifyListeners();
  }

  void clearVault() {
    _vault.clear();
    _pin = '';
    vaultUnlocked = false;
    _save();
    notifyListeners();
  }

  // ---------- filters ----------

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

  bool matches(String key) {
    if (favoritesOnly && !_favs.contains(key)) return false;
    if (selected.isNotEmpty) {
      final t = tagsFor(key);
      final ok =
          matchAll ? selected.every(t.contains) : selected.any(t.contains);
      if (!ok) return false;
    }
    return true;
  }
}
