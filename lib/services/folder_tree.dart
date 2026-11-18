import 'dart:io';

import '../models/video_item.dart';

class FolderEntry {
  final String path;
  final String name;
  final int count;
  const FolderEntry(this.path, this.name, this.count);
}

class FolderLevel {
  final List<FolderEntry> folders;
  final List<VideoItem> videos;
  const FolderLevel(this.folders, this.videos);
}

class FolderTree {
  static String get sep => Platform.pathSeparator;

  static String trim(String s) {
    if (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  static String parentOf(String p) {
    final i = p.lastIndexOf(sep);
    return i <= 0 ? '' : p.substring(0, i);
  }

  static String nameOf(String p) {
    final i = p.lastIndexOf(sep);
    return i < 0 ? p : p.substring(i + 1);
  }

  /// The top-level folder a video belongs to.
  static String rootKeyFor(String path, List<String> roots) {
    String? best;
    for (final r0 in roots) {
      final r = trim(r0);
      if (path.startsWith('$r$sep') && (best == null || r.length > best.length)) {
        best = r;
      }
    }
    return best ?? parentOf(path);
  }

  static Set<String> rootKeys(List<VideoItem> items, List<String> roots) {
    final out = <String>{};
    for (final v in items) {
      if (v.path.isEmpty) continue;
      out.add(rootKeyFor(v.path, roots));
    }
    return out;
  }

  static FolderLevel level(
    List<VideoItem> items,
    String? dir,
    List<String> roots,
    String Function(String) labelFor,
  ) {
    final counts = <String, int>{};
    final videos = <VideoItem>[];

    if (dir == null) {
      for (final v in items) {
        if (v.path.isEmpty) continue;
        final k = rootKeyFor(v.path, roots);
        counts[k] = (counts[k] ?? 0) + 1;
      }
    } else {
      final prefix = '$dir$sep';
      for (final v in items) {
        final p = v.path;
        if (p.isEmpty || !p.startsWith(prefix)) continue;
        final rest = p.substring(prefix.length);
        final idx = rest.indexOf(sep);
        if (idx < 0) {
          videos.add(v);
        } else {
          final sub = '$prefix${rest.substring(0, idx)}';
          counts[sub] = (counts[sub] ?? 0) + 1;
        }
      }
    }

    final folders = [
      for (final e in counts.entries)
        FolderEntry(e.key, labelFor(e.key), e.value),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return FolderLevel(folders, videos);
  }
}
