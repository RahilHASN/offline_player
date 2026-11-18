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
