import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';

class TrashEntry {
  final String trashPath;
  final String originalPath;
  final String name;
  final int size;
  final int deletedMs;
  const TrashEntry(
      this.trashPath, this.originalPath, this.name, this.size, this.deletedMs);

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': trashPath,
        'o': originalPath,
        'n': name,
        's': size,
        'd': deletedMs,
      };

  static TrashEntry? from(dynamic e) {
    if (e is! Map) return null;
    try {
      return TrashEntry(
        e['t'] as String,
        e['o'] as String,
        e['n'] as String,
        (e['s'] as num).toInt(),
        (e['d'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A recycle bin: deleted videos wait here for 30 days.
class TrashService extends ChangeNotifier {
  TrashService._();
  static final TrashService instance = TrashService._();

  static const int keepDays = 30;
  static const String folderName = '.OfflinePlayerTrash';

  final List<TrashEntry> entries = <TrashEntry>[];

  String get _sep => Platform.pathSeparator;

  Future<File> _index() async {
    final b = await getApplicationSupportDirectory();
    return File('${b.path}$_sep' 'trash.json');
  }

  Future<void> _save() async {
    try {
      final f = await _index();
      await f.writeAsString(
        jsonEncode([for (final e in entries) e.toJson()]),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> load() async {
    entries.clear();
    try {
      final f = await _index();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as List<dynamic>;
        for (final d in data) {
          final e = TrashEntry.from(d);
          if (e != null && File(e.trashPath).existsSync()) entries.add(e);
        }
      }
    } catch (_) {}
    final cutoff = DateTime.now()
        .subtract(const Duration(days: keepDays))
        .millisecondsSinceEpoch;
    for (final e in entries.where((e) => e.deletedMs < cutoff).toList()) {
      try {
        await File(e.trashPath).delete();
      } catch (_) {}
      entries.remove(e);
    }
    await _save();
    notifyListeners();
  }

  String _parent(String p) {
    final i = p.lastIndexOf(_sep);
    return i <= 0 ? p : p.substring(0, i);
  }

  String _volumeRoot(String path) {
    if (Platform.isWindows) {
      if (path.length >= 3 && path[1] == ':') return path.substring(0, 2);
      return _parent(path);
    }
    if (path.startsWith('/storage/emulated/0')) return '/storage/emulated/0';
    final parts = path.split('/');
    if (path.startsWith('/storage/') && parts.length > 3) {
      return '/storage/${parts[2]}';
    }
    return _parent(path);
  }

  Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  Future<void> moveToTrash(VideoItem v) async {
    var dir = Directory('${_volumeRoot(v.path)}$_sep$folderName');
    try {
      await dir.create(recursive: true);
    } catch (_) {
      dir = Directory('${_parent(v.path)}$_sep$folderName');
      await dir.create(recursive: true);
    }
    final target =
        '${dir.path}$_sep${DateTime.now().millisecondsSinceEpoch}_${v.name}';
    await _move(v.path, target);
    entries.add(TrashEntry(
      target,
      v.path,
      v.name,
      v.sizeBytes,
      DateTime.now().millisecondsSinceEpoch,
    ));
    await _save();
    notifyListeners();
  }

  Future<void> restore(TrashEntry e) async {
    var dest = e.originalPath;
    if (File(dest).existsSync()) {
      final dot = dest.lastIndexOf('.');
      dest = dot > 0
          ? '${dest.substring(0, dot)} (restored)${dest.substring(dot)}'
          : '$dest (restored)';
    }
    await Directory(_parent(dest)).create(recursive: true);
    await _move(e.trashPath, dest);
    entries.remove(e);
    await _save();
    notifyListeners();
  }

  Future<void> deleteForever(TrashEntry e) async {
    try {
      await File(e.trashPath).delete();
    } catch (_) {}
    entries.remove(e);
    await _save();
    notifyListeners();
  }

  Future<void> empty() async {
    for (final e in entries.toList()) {
      try {
        await File(e.trashPath).delete();
      } catch (_) {}
    }
    entries.clear();
    await _save();
    notifyListeners();
  }
}
