import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../services/app_mode.dart';
import '../services/net.dart';
import 'track.dart';

class LyricLine {
  final int ms;
  final String text;
  const LyricLine(this.ms, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final bool synced;
  const Lyrics(this.lines, this.synced);
}

class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  final Map<String, Lyrics?> _mem = <String, Lyrics?>{};

  /// Reads .lrc text (timed lines) or plain lyrics.
  static Lyrics? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final re = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final timed = <LyricLine>[];
    final plain = <LyricLine>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final ms = re.allMatches(line).toList();
      if (ms.isEmpty) {
        final s = line.trim();
        if (s.isNotEmpty && !RegExp(r'^\[[a-zA-Z]+:').hasMatch(s)) {
          plain.add(LyricLine(0, s));
        }
        continue;
      }
      final s = line.substring(ms.last.end).trim();
      for (final m in ms) {
        final mm = int.parse(m.group(1)!);
        final ss = int.parse(m.group(2)!);
        var frac = 0;
        final f = m.group(3);
        if (f != null) frac = int.parse(f.padRight(3, '0').substring(0, 3));
        timed.add(LyricLine((mm * 60 + ss) * 1000 + frac, s));
      }
    }
    if (timed.length >= 2) {
      timed.sort((a, b) => a.ms.compareTo(b.ms));
      return Lyrics(timed, true);
    }
    return plain.isEmpty ? null : Lyrics(plain, false);
  }

  String _h(String s) {
    var h1 = 5381;
    var h2 = 7919;
    for (final c in s.codeUnits) {
      h1 = ((h1 * 33) ^ c) & 0xFFFFFFFF;
      h2 = ((h2 * 131) + c) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16) + h2.toRadixString(16);
  }

  Future<File> _diskFile(Track t) async {
    final b = await getApplicationSupportDirectory();
    final d = Directory('${b.path}${Platform.pathSeparator}lyrics');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}${_h(t.id)}.txt');
  }

  Future<Lyrics?> _fromLrcFile(Track t) async {
    try {
      final dot = t.uri.lastIndexOf('.');
      if (dot < 0) return null;
      final f = File('${t.uri.substring(0, dot)}.lrc');
      if (await f.exists()) return parse(await f.readAsString());
    } catch (_) {}
    return null;
  }

  Future<Lyrics?> _fromDisk(Track t) async {
    try {
      final f = await _diskFile(t);
      if (await f.exists()) return parse(await f.readAsString());
    } catch (_) {}
    return null;
  }

  Future<String?> _fromNet(Track t) async {
    String? pickAny(dynamic m) {
      if (m is! Map) return null;
      final s = m['syncedLyrics'];
      if (s is String && s.trim().isNotEmpty) return s;
      final p = m['plainLyrics'];
      if (p is String && p.trim().isNotEmpty) return p;
      return null;
    }

    final hasArtist = t.artist != 'Unknown artist';
    if (hasArtist) {
      final j = await Net.json(Uri.https('lrclib.net', '/api/get', {
        'artist_name': t.artist,
        'track_name': t.title,
        if (t.album.isNotEmpty) 'album_name': t.album,
        if (t.durationSec > 0) 'duration': '${t.durationSec}',
      }));
      final r = pickAny(j);
      if (r != null) return r;
    }
    final j = await Net.json(Uri.https('lrclib.net', '/api/search', {
      if (hasArtist) 'artist_name': t.artist,
      'track_name': t.title,
    }));
    if (j is List) {
      String? firstPlain;
      for (final m in j) {
        if (m is! Map) continue;
        final s = m['syncedLyrics'];
        if (s is String && s.trim().isNotEmpty) return s;
        firstPlain ??= pickAny(m);
      }
      return firstPlain;
    }
    return null;
  }

  Future<Lyrics?> forTrack(Track t) async {
    if (_mem.containsKey(t.id)) return _mem[t.id];
    Lyrics? r;
    if (t.isLocal) r = await _fromLrcFile(t);
    r ??= await _fromDisk(t);
    if (r == null && AppMode.instance.online) {
      try {
        final raw = await _fromNet(t);
        if (raw != null) {
          r = parse(raw);
          if (r != null) {
            final f = await _diskFile(t);
            await f.writeAsString(raw, flush: true);
          }
        }
      } catch (_) {}
      _mem[t.id] = r;
    } else if (r != null) {
      _mem[t.id] = r;
    }
    return r;
  }
}
