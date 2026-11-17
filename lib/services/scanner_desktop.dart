import 'dart:io';

import '../models/video_item.dart';

class DesktopScanner {
  static const videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg',
    'mpeg', 'ts', 'm2ts', 'mts', '3gp', 'vob', 'ogv',
  };

  static Future<List<VideoItem>> scanFolder(String folder) async {
    final out = <VideoItem>[];
    final dir = Directory(folder);
    if (!await dir.exists()) return out;

    final stream = dir
        .list(recursive: true, followLinks: false)
        .handleError((_) {});

    await for (final entity in stream) {
      if (entity is! File) continue;
      final filePath = entity.path;
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
          source: VideoSource.pc,
        ));
      } catch (_) {
        // skip unreadable file
      }
    }
    return out;
  }
}
