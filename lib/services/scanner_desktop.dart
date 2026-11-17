import 'dart:io';

import '../models/video_item.dart';

/// Scans a folder recursively using normal file access.
/// Used on Windows, and on Android for pendrives / picked folders.
class DesktopScanner {
  static const videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg',
    'mpeg', 'ts', 'm2ts', 'mts', '3gp', 'vob', 'ogv',
  };

  static Future<List<VideoItem>> scanFolder(
    String folder, {
    required VideoSource source,
  }) async {
    final out = <VideoItem>[];
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) return out;

      final stream = dir
          .list(recursive: true, followLinks: false)
          .handleError((_) {});

      await for (final entity in stream) {
        if (entity is! File) continue;
        final filePath = entity.path;

        // skip hidden files and folders (e.g. .thumbnails, .Trash)
        if (filePath.contains('/.') || filePath.contains('\\.')) continue;

        final dot = filePath.lastIndexOf('.');
        if (dot < 0) continue;
        final ext = filePath.substring(dot + 1).toLowerCase();
        if (!videoExtensions.contains(ext)) continue;

        try {
          final st = await entity.stat();
          out.add(VideoItem(
            id: 'f:$filePath',
            path: filePath,
            name: filePath.split(RegExp(r'[\\/]')).last,
            sizeBytes: st.size,
            duration: null,
            date: st.modified,
            source: source,
          ));
        } catch (_) {
          // skip unreadable file
        }
      }
    } catch (_) {
      // folder not readable
    }
    return out;
  }
}
