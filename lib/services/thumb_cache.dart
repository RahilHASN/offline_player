import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory?> _thumbDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}thumbs');
  if (await d.exists()) return d;
  return null;
}

Future<int> thumbCacheBytes() async {
  var total = 0;
  try {
    final d = await _thumbDir();
    if (d == null) return 0;
    await for (final e in d.list()) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

Future<void> clearThumbCache() async {
  try {
    final d = await _thumbDir();
    if (d == null) return;
    await for (final e in d.list()) {
      if (e is File) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Deletes the oldest files until the cache is below [maxBytes].
Future<void> trimThumbCache(int maxBytes) async {
  if (maxBytes <= 0) return;
  try {
    final d = await _thumbDir();
    if (d == null) return;
    final files = <File>[];
    final stats = <String, FileStat>{};
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) {
        final st = await e.stat();
        files.add(e);
        stats[e.path] = st;
        total += st.size;
      }
    }
    if (total <= maxBytes) return;
    files.sort(
      (a, b) => stats[a.path]!.modified.compareTo(stats[b.path]!.modified),
    );
    for (final f in files) {
      if (total <= maxBytes) break;
      total -= stats[f.path]!.size;
      try {
        await f.delete();
      } catch (_) {}
    }
  } catch (_) {}
}
