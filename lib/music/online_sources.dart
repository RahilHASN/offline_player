import '../services/app_mode.dart';
import '../services/net.dart';
import 'track.dart';

class ArchiveVideo {
  final String id;
  final String title;
  final String creator;
  const ArchiveVideo(this.id, this.title, this.creator);
  String get thumb => 'https://archive.org/services/img/$id';
}

class OnlineSources {
  static Track? _jt(dynamic m) {
    if (m is! Map) return null;
    final audio = m['audio'];
    if (audio is! String || audio.isEmpty) return null;
    final img = m['image'] ?? m['album_image'];
    return Track(
      id: 'j:${m['id']}',
      title: (m['name'] ?? 'Untitled').toString(),
      artist: (m['artist_name'] ?? 'Unknown artist').toString(),
      album: (m['album_name'] ?? '').toString(),
      uri: audio,
      art: (img is String && img.isNotEmpty) ? img : null,
      durationSec: int.tryParse('${m['duration']}') ?? 0,
      source: TrackSource.jamendo,
      license: (m['license_ccurl'] ?? '').toString(),
    );
  }

  /// Free Creative Commons music from Jamendo.
  static Future<List<Track>> jamendo({
    String? tags,
    String? search,
    String order = 'popularity_month',
    int limit = 24,
  }) async {
    final id = AppMode.instance.jamendoId.trim();
    if (id.isEmpty) {
      throw 'Add your free Jamendo client ID in Online settings';
    }
    final j = await Net.json(Uri.https('api.jamendo.com', '/v3.0/tracks/', {
      'client_id': id,
      'format': 'json',
      'limit': '$limit',
      'order': order,
      'imagesize': '400',
      'audioformat': 'mp32',
      if (tags != null) 'tags': tags,
      if (search != null) 'search': search,
    }));
    if (j is! Map) return <Track>[];
    final h = j['headers'];
    if (h is Map && h['status'] == 'failed') {
      throw (h['error_message'] ?? 'Jamendo refused the request').toString();
    }
    final r = j['results'];
    final out = <Track>[];
    if (r is List) {
      for (final e in r) {
        final t = _jt(e);
        if (t != null) out.add(t);
      }
    }
    return out;
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'["()\[\]:]'), ' ').trim();

  /// Music videos on the Internet Archive.
  static Future<List<ArchiveVideo>> musicVideos({String? search}) async {
    final s = search == null ? '' : _safe(search);
    final q = s.isEmpty
        ? 'mediatype:movies AND subject:"music video"'
        : 'mediatype:movies AND subject:"music video" AND ($s)';
    final j = await Net.json(Uri.https('archive.org', '/advancedsearch.php', {
      'q': q,
      'fl[]': <String>['identifier', 'title', 'creator'],
      'rows': '40',
      'page': '1',
      'output': 'json',
      'sort[]': 'downloads desc',
    }));
    final r = j is Map ? j['response'] : null;
    final docs = r is Map ? r['docs'] : null;
    final out = <ArchiveVideo>[];
    if (docs is List) {
      for (final d in docs) {
        if (d is Map && d['identifier'] is String) {
          final c = d['creator'];
          out.add(ArchiveVideo(
            d['identifier'] as String,
            '${d['title'] ?? d['identifier']}',
            c is List ? c.join(', ') : '${c ?? ''}',
          ));
        }
      }
    }
    return out;
  }

  /// Finds a playable video file inside an Internet Archive item.
  static Future<String?> videoUrl(String id) async {
    final j = await Net.json(Uri.https('archive.org', '/metadata/$id'));
    if (j is! Map) return null;
    final files = j['files'];
    if (files is! List) return null;
    final cands = <MapEntry<String, int>>[];
    for (final f in files) {
      if (f is! Map || f['name'] is! String) continue;
      final name = f['name'] as String;
      final low = name.toLowerCase();
      if (!(low.endsWith('.mp4') || low.endsWith('.m4v') || low.endsWith('.ogv'))) {
        continue;
      }
      final size = int.tryParse('${f['size']}') ?? 0;
      if (size > 0) cands.add(MapEntry(name, size));
    }
    if (cands.isEmpty) return null;
    cands.sort((a, b) => a.value.compareTo(b.value));
    final pick = cands.firstWhere(
      (e) => e.value > 1000000,
      orElse: () => cands.first,
    );
    return Uri.https('archive.org', '/download/$id/${pick.key}').toString();
  }
}
