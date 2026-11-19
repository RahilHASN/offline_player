import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';

/// Saves the last video list so the app can show it instantly on launch.
class LibraryIndex {
  static Future<File> _file() async {
    final b = await getApplicationSupportDirectory();
    return File('${b.path}${Platform.pathSeparator}index.json');
  }

  static Future<List<VideoItem>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <VideoItem>[];
      final data = jsonDecode(await f.readAsString()) as List<dynamic>;
      final out = <VideoItem>[];
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        final d = m['d'];
        out.add(VideoItem(
          id: m['i'] as String,
          path: m['p'] as String,
          name: m['n'] as String,
          sizeBytes: (m['s'] as num).toInt(),
          duration: d == null ? null : Duration(milliseconds: (d as num).toInt()),
          date: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
          source: VideoSource.values[(m['o'] as num).toInt()],
        ));
      }
      return out;
    } catch (_) {
      return <VideoItem>[];
    }
  }

  static Future<void> save(List<VideoItem> items) async {
    try {
      final f = await _file();
      final data = [
        for (final v in items)
          <String, dynamic>{
            'i': v.id,
            'p': v.path,
            'n': v.name,
            's': v.sizeBytes,
            'd': v.duration?.inMilliseconds,
            't': v.date.millisecondsSinceEpoch,
            'o': v.source.index,
          },
      ];
      await f.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }
}
