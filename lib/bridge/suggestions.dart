import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_mode.dart';
import 'playlist_store.dart';
import 'provider.dart';
import 'providers/youtube_provider.dart';
import 'youtube_history.dart';

/// Songs shown on the music page: favourites, playlists and discover.
/// Online mode only. Costs almost nothing: favourites and playlists are one
/// small lookup (1 unit), Discover does at most one search per day.
class Suggestions extends ChangeNotifier {
  Suggestions._();
  static final Suggestions instance = Suggestions._();

  /// How many songs a row loads before the arrow.
  static const int rowMax = 15;

  List<MediaItem> favourites = <MediaItem>[];
  List<MediaItem> fromPlaylists = <MediaItem>[];
  List<MediaItem> discover = <MediaItem>[];

  bool _hooked = false;
  bool _busy = false;
  bool _again = false;
  String _discoverTried = '';

  void init() {
    if (_hooked) return;
    _hooked = true;
    AppMode.instance.addListener(refresh);
    PlaylistStore.instance.addListener(refresh);
    refresh();
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Ids from every playlist, one from each in turn, so no list dominates.
  List<String> _playlistIds(Set<String> skip) {
    final lists = PlaylistStore.instance.lists.values.toList();
    final out = <String>[];
    var round = 0;
    var more = true;
    while (more && out.length < rowMax) {
      more = false;
      for (final l in lists) {
        if (round < l.length) {
          more = true;
          final id = l[round];
          if (!skip.contains(id) && !out.contains(id)) out.add(id);
          if (out.length >= rowMax) break;
        }
      }
      round++;
    }
    return out;
  }

  Future<void> refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    final m = AppMode.instance;
    if (!m.online || m.youtubeKey.trim().isEmpty) {
      if (favourites.isNotEmpty ||
          fromPlaylists.isNotEmpty ||
          discover.isNotEmpty) {
        favourites = <MediaItem>[];
        fromPlaylists = <MediaItem>[];
        discover = <MediaItem>[];
        notifyListeners();
      }
      return;
    }
    _busy = true;
    try {
      final store = PlaylistStore.instance;
      await store.load();
      await YouTubeHistory.instance.load();

      final favIds = store.fav.take(rowMax).toList();
      final plIds = _playlistIds(favIds.toSet());
      final got = await YouTubeProvider.instance
          .byIds(<String>[...favIds, ...plIds]); // at most 30 ids: 1 unit
      final byId = <String, MediaItem>{
        for (final it in got)
          if (it.videoId != null) it.videoId!: it,
      };
      favourites = <MediaItem>[
        for (final id in favIds)
          if (byId[id] != null) byId[id]!,
      ];
      fromPlaylists = <MediaItem>[
        for (final id in plIds)
          if (byId[id] != null) byId[id]!,
      ];
      notifyListeners();
    } catch (_) {}
    try {
      await _loadDiscover();
    } catch (_) {}
    _busy = false;
    if (_again) {
      _again = false;
      refresh();
    }
  }

  /// The artist you play most (or played last) is the starting point.
  String? _seed() {
    final h = YouTubeHistory.instance;
    if (h.items.isEmpty) {
      return favourites.isEmpty ? null : favourites.first.creator;
    }
    var best = h.items.first;
    for (final it in h.items) {
      if (h.playsOf(it.videoId ?? '') > h.playsOf(best.videoId ?? '')) best = it;
    }
    final c = best.creator.trim();
    return c.isEmpty ? null : c;
  }

  Future<void> _loadDiscover() async {
    final today = _today();
    final p = await SharedPreferences.getInstance();
    final known = <String>{
      for (final it in YouTubeHistory.instance.items)
        if (it.videoId != null) it.videoId!,
      ...PlaylistStore.instance.fav,
    };

    // Already searched today: only look the saved ids up again (1 unit).
    if (p.getString('discDay') == today) {
      final ids = p.getStringList('discIds') ?? <String>[];
      if (ids.isNotEmpty) {
        final items = await YouTubeProvider.instance.byIds(ids);
        discover = items.where((m) => !known.contains(m.videoId)).toList();
        notifyListeners();
      }
      return;
    }

    // One search attempt per day and session, so errors never repeat.
    if (_discoverTried == today) return;
    final seed = _seed();
    if (seed == null) return;
    _discoverTried = today;

    final found = await YouTubeProvider.instance.find('$seed songs', music: true);
    final fresh = found.where((m) => !known.contains(m.videoId)).toList();
    final list = fresh.length >= 6 ? fresh : found;
    discover = list.take(20).toList();
    await p.setString('discDay', today);
    await p.setStringList('discIds', [
      for (final it in discover)
        if (it.videoId != null) it.videoId!,
    ]);
    notifyListeners();
  }
}
