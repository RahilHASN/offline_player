import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider.dart';

/// What you played on YouTube. Kept on this device only,
/// at most 30 items, each deleted after 30 days.
class YouTubeHistory extends ChangeNotifier {
  YouTubeHistory._();
  static final YouTubeHistory instance = YouTubeHistory._();

  static const _key = 'ytHistory';
  static const _maxItems = 30;
  static const _maxAge = Duration(days: 30);

  List<MediaItem> items = <MediaItem>[];
  final Map<String, int> _stamp = <String, int>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      final l = jsonDecode(raw);
      if (l is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final e in l) {
          if (e is! Map) continue;
          final ts = (e['ts'] as num?)?.toInt() ?? 0;
          if (now - ts > _maxAge.inMilliseconds) continue;
          final v = e['v'];
          if (v is! String) continue;
          items.add(MediaItem(
            id: 'y:$v',
            providerId: 'youtube',
            title: '${e['t'] ?? ''}',
            creator: '${e['a'] ?? ''}',
            thumb: e['th'] is String ? e['th'] as String : null,
            durationSec: (e['d'] as num?)?.toInt() ?? 0,
            kind: MediaKind.video,
            videoId: v,
          ));
          _stamp[v] = ts;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final l = <Map<String, Object?>>[
      for (final m in items)
        {
          'v': m.videoId,
          't': m.title,
          'a': m.creator,
          'th': m.thumb,
          'd': m.durationSec,
          'ts': _stamp[m.videoId] ?? 0,
        },
    ];
    await p.setString(_key, jsonEncode(l));
  }

  Future<void> add(MediaItem m) async {
    final v = m.videoId;
    if (v == null || m.providerId != 'youtube') return;
    await load();
    items.removeWhere((x) => x.videoId == v);
    items.insert(0, m);
    _stamp[v] = DateTime.now().millisecondsSinceEpoch;
    while (items.length > _maxItems) {
      final last = items.removeLast();
      _stamp.remove(last.videoId);
    }
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    items = <MediaItem>[];
    _stamp.clear();
    notifyListeners();
    await _save();
  }
}
