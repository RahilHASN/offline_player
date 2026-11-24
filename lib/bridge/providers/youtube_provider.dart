import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_mode.dart';
import '../../services/net.dart';
import '../compliance.dart';
import '../handoff.dart';
import '../provider.dart';

/// Counts the YouTube Data API units used today (resets about midnight Pacific).
class YouTubeQuota {
  YouTubeQuota._();
  static final YouTubeQuota instance = YouTubeQuota._();

  static const int searchCost = 100;
  static const int videoCost = 1;
  static const int budget = 9500; // of the default 10,000 a day

  int used = 0;
  String _day = '';
  bool _loaded = false;

  static String _today() {
    final d = DateTime.now().toUtc().subtract(const Duration(hours: 8));
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    _day = p.getString('ytDay') ?? '';
    used = p.getInt('ytUsed') ?? 0;
    _roll();
  }

  void _roll() {
    final t = _today();
    if (_day != t) {
      _day = t;
      used = 0;
    }
  }

  bool canSpend(int cost) {
    _roll();
    return used + cost <= budget;
  }

  Future<void> spend(int cost) async {
    _roll();
    used += cost;
    final p = await SharedPreferences.getInstance();
    await p.setString('ytDay', _day);
    await p.setInt('ytUsed', used);
  }
}

class _Hit {
  final DateTime at;
  final List<MediaItem> items;
  _Hit(this.items) : at = DateTime.now();
}

/// YouTube: metadata through the official Data API, playback only through
/// YouTube's official embedded player. Never a stream address.
class YouTubeProvider implements MediaProvider {
  YouTubeProvider._();
  static final YouTubeProvider instance = YouTubeProvider._();

  @override
  String get id => 'youtube';
  @override
  String get name => 'YouTube';
  @override
  ProviderCaps get caps => const ProviderCaps(
        search: true,
        officialEmbed: true,
        needsKey: true,
      );

  // Short-lived, in memory only.
  static const _ttl = Duration(minutes: 10);
  static const _maxEntries = 30;
  final Map<String, _Hit> _cache = <String, _Hit>{};

  List<MediaItem>? _get(String k) {
    final h = _cache.remove(k);
    if (h == null) return null;
    if (DateTime.now().difference(h.at) > _ttl) return null;
    _cache[k] = h;
    return h.items;
  }

  void _put(String k, List<MediaItem> items) {
    _cache.remove(k);
    _cache[k] = _Hit(items);
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// Parses ISO-8601 durations such as PT1H2M3S.
  static int parseDuration(String? s) {
    if (s == null) return 0;
    final m = RegExp(r'^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$')
        .firstMatch(s);
    if (m == null) return 0;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return g(1) * 86400 + g(2) * 3600 + g(3) * 60 + g(4);
  }

  /// Splits "Artist - Song (Official Video)" into (song, artist).
  /// Without " - " in the title, the channel name is used as the artist.
  static (String, String) split(String title, String channel) {
    var t = _decode(title);
    t = t
        .replaceAll(
            RegExp(
                r'\s*[\(\[](official|lyrics?|lyric video|audio|video|music video|hd|4k|visuali[sz]er)[^\)\]]*[\)\]]',
                caseSensitive: false),
            '')
        .trim();
    final ch = _decode(channel)
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .trim();
    final i = t.indexOf(' - ');
    if (i > 0 && i < t.length - 3) {
      return (t.substring(i + 3).trim(), t.substring(0, i).trim());
    }
    return (t, ch);
  }

  /// Video id from a pasted YouTube link, or null.
  static String? idFromUri(Uri u) {
    final h = u.host.toLowerCase();
    String? id;
    if (h == 'youtu.be') {
      if (u.pathSegments.isNotEmpty) id = u.pathSegments.first;
    } else if (h == 'youtube.com' ||
        h.endsWith('.youtube.com') ||
        h == 'youtube-nocookie.com' ||
        h.endsWith('.youtube-nocookie.com')) {
      id = u.queryParameters['v'];
      final s = u.pathSegments;
      if (id == null &&
          s.length >= 2 &&
          const <String>['embed', 'shorts', 'live', 'v'].contains(s.first)) {
        id = s[1];
      }
    }
    if (id != null && Compliance.validVideoId(id)) return id;
    return null;
  }

  MediaItem? _item(dynamic m) {
    if (m is! Map) return null;
    final id = m['id'];
    if (id is! String || !Compliance.validVideoId(id)) return null;
    final st = m['status'];
    if (st is! Map || st['embeddable'] != true) return null;
    final sn = m['snippet'] is Map ? m['snippet'] as Map : const {};
    final th = sn['thumbnails'] is Map ? sn['thumbnails'] as Map : const {};
    String? thumb;
    for (final k in const <String>['standard', 'high', 'medium', 'default']) {
      final t = th[k];
      if (t is Map && t['url'] is String) {
        thumb = t['url'] as String;
        break;
      }
    }
    final cd = m['contentDetails'] is Map ? m['contentDetails'] as Map : const {};
    final (song, artist) =
        split('${sn['title'] ?? 'Untitled'}', '${sn['channelTitle'] ?? ''}');
    return MediaItem(
      id: 'y:$id',
      providerId: 'youtube',
      title: song,
      creator: artist,
      thumb: thumb,
      durationSec: parseDuration(cd['duration'] as String?),
      kind: MediaKind.video,
      videoId: id,
    );
  }

  Future<List<MediaItem>> _videos(List<String> ids, String key) async {
    final qt = YouTubeQuota.instance;
    final v = await Net.json(Uri.https('www.googleapis.com', '/youtube/v3/videos', {
      'part': 'snippet,contentDetails,status',
      'id': ids.join(','),
      'key': key,
    }));
    await qt.spend(YouTubeQuota.videoCost);
    final out = <MediaItem>[];
    if (v is Map && v['items'] is List) {
      for (final e in v['items'] as List) {
        final it = _item(e);
        if (it != null) out.add(it);
      }
    }
    return out;
  }

  /// [music] true limits results to YouTube's Music category.
  Future<List<MediaItem>> find(String query, {required bool music}) async {
    final key = AppMode.instance.youtubeKey.trim();
    if (key.isEmpty) throw 'Add your YouTube API key in Online settings';
    final q = query.trim();
    if (q.length < 2) return <MediaItem>[];
    final ck = '${music ? 'm' : 'v'}:${q.toLowerCase()}';
    final hit = _get(ck);
    if (hit != null) return hit;

    final qt = YouTubeQuota.instance;
    await qt.load();
    if (!qt.canSpend(YouTubeQuota.searchCost + YouTubeQuota.videoCost)) {
      throw 'Daily YouTube budget reached (${qt.used}/${YouTubeQuota.budget} units). It resets daily.';
    }
    final params = <String, String>{
      'part': 'snippet',
      'type': 'video',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
      'safeSearch': 'moderate',
      'maxResults': '20',
      'q': q,
      'key': key,
      if (music) 'videoCategoryId': '10',
    };
    final s = await Net.json(
        Uri.https('www.googleapis.com', '/youtube/v3/search', params));
    await qt.spend(YouTubeQuota.searchCost);
    final ids = <String>[];
    if (s is Map && s['items'] is List) {
      for (final e in s['items'] as List) {
        final idObj = e is Map ? e['id'] : null;
        final vid = idObj is Map ? idObj['videoId'] : null;
        if (vid is String && Compliance.validVideoId(vid)) ids.add(vid);
      }
    }
    if (ids.isEmpty) return <MediaItem>[];
    final items = await _videos(ids, key);
    _put(ck, items);
    return items;
  }
    /// Fetches details for saved video ids (1 unit per 50 ids), in the same order.
  Future<List<MediaItem>> byIds(List<String> ids) async {
    if (ids.isEmpty) return <MediaItem>[];
    final found = <String, MediaItem>{};
    final missing = <String>[];
    for (final id in ids) {
      final h = _get('v:$id');
      if (h != null && h.isNotEmpty) {
        found[id] = h.first;
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      final key = AppMode.instance.youtubeKey.trim();
      if (key.isEmpty) throw 'Add your YouTube API key in Online settings';
      final qt = YouTubeQuota.instance;
      await qt.load();
      for (var s = 0; s < missing.length; s += 50) {
        final end = s + 50 > missing.length ? missing.length : s + 50;
        if (!qt.canSpend(YouTubeQuota.videoCost)) {
          throw 'Daily YouTube budget reached (${qt.used}/${YouTubeQuota.budget} units).';
        }
        for (final it in await _videos(missing.sublist(s, end), key)) {
          _put('v:${it.videoId}', <MediaItem>[it]);
          found[it.videoId!] = it;
        }
      }
    }
    return <MediaItem>[
      for (final id in ids)
        if (found[id] != null) found[id]!,
    ];
  }

  @override
  Future<List<MediaItem>> search(String query) => find(query, music: false);

  /// Resolves a pasted YouTube link. Uses the Data API when a key is set
  /// (1 unit), otherwise the public oEmbed endpoint.
  Future<MediaItem> fromId(String videoId) async {
    final key = AppMode.instance.youtubeKey.trim();
    final ck = 'v:$videoId';
    final hit = _get(ck);
    if (hit != null && hit.isNotEmpty) return hit.first;

    if (key.isNotEmpty) {
      final qt = YouTubeQuota.instance;
      await qt.load();
      if (qt.canSpend(YouTubeQuota.videoCost)) {
        final l = await _videos(<String>[videoId], key);
        if (l.isEmpty) {
          throw 'Video not found, private, or the owner disabled embedding.';
        }
        _put(ck, l);
        return l.first;
      }
    }
    dynamic j;
    try {
      j = await Net.json(Uri.https('www.youtube.com', '/oembed', {
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'json',
      }));
    } catch (_) {
      throw 'Video not found, private, or the owner disabled embedding.';
    }
    if (j is! Map) throw 'Video not found or private.';
    final (song, artist) =
        split('${j['title'] ?? 'YouTube video'}', '${j['author_name'] ?? ''}');
    final item = MediaItem(
      id: 'y:$videoId',
      providerId: 'youtube',
      title: song,
      creator: artist,
      thumb: j['thumbnail_url'] is String ? j['thumbnail_url'] as String : null,
      kind: MediaKind.video,
      videoId: videoId,
    );
    _put(ck, <MediaItem>[item]);
    return item;
  }

  @override
  List<Handoff> handoffs(MediaItem item) {
    final v = item.videoId;
    if (v == null || !Compliance.validVideoId(v)) {
      return <Handoff>[
        UnavailableHandoff(providerId: id, reason: 'Missing video id.'),
      ];
    }
    return <Handoff>[
      EmbedHandoff(providerId: id, videoId: v),
      ExternalLinkHandoff(
        providerId: id,
        url: Uri.https('www.youtube.com', '/watch', {'v': v}),
        reason: 'Opens in your browser or the YouTube app.',
      ),
    ];
  }
}
