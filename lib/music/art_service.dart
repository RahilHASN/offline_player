import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_mode.dart';
import '../services/net.dart';
import 'track.dart';

/// Finds cover art for your own songs (online mode only), one lookup
/// per second, and remembers the answers on the device.
class ArtService {
  ArtService._();
  static final ArtService instance = ArtService._();

  final Map<String, String> _cache = <String, String>{};
  final List<Track> _queue = <Track>[];
  final Set<String> _asked = <String>{};
  bool _loaded = false;
  bool _running = false;

  /// Goes up whenever a new picture address is known.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  String _k(Track t) => '${t.artist.toLowerCase()}|${t.title.toLowerCase()}';

  Future<File> _file() async {
    final b = await getApplicationSupportDirectory();
    return File('${b.path}${Platform.pathSeparator}artcache.json');
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString());
      if (m is Map) {
        m.forEach((k, v) {
          if (v is String) _cache['$k'] = v;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_cache), flush: true);
    } catch (_) {}
  }

  String? artFor(Track t) {
    if (t.art != null) return t.art;
    final v = _cache[_k(t)];
    return (v == null || v.isEmpty) ? null : v;
  }

  void want(Track t) {
    if (t.art != null || !AppMode.instance.online) return;
    if (t.artist == 'Unknown artist') return;
    final k = _k(t);
    if (_cache.containsKey(k) || !_asked.add(k)) return;
    _queue.add(t);
    _run();
  }

  String _clean(String s) => s.replaceAll('"', ' ').trim();

  Future<String?> _lookup(Track t) async {
    final q = 'recording:"${_clean(t.title)}" AND artist:"${_clean(t.artist)}"';
    final j = await Net.json(Uri.https('musicbrainz.org', '/ws/2/recording/', {
      'query': q,
      'fmt': 'json',
      'limit': '3',
    }));
    if (j is! Map) return null;
    final recs = j['recordings'];
    if (recs is! List) return null;
    for (final r in recs) {
      if (r is! Map) continue;
      final rel = r['releases'];
      if (rel is List && rel.isNotEmpty && rel.first is Map) {
        final id = (rel.first as Map)['id'];
        if (id is String) {
          return 'https://coverartarchive.org/release/$id/front-250';
        }
      }
    }
    return null;
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      await _load();
      while (_queue.isNotEmpty) {
        if (!AppMode.instance.online) {
          _queue.clear();
          _asked.clear();
          break;
        }
        final t = _queue.removeAt(0);
        final k = _k(t);
        if (_cache.containsKey(k)) continue;
        try {
          _cache[k] = (await _lookup(t)) ?? '';
          await _save();
          version.value++;
        } catch (_) {
          _asked.remove(k);
        }
        // MusicBrainz asks for at most one request per second
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
    } finally {
      _running = false;
    }
  }
}
