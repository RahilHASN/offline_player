import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/storage_volumes.dart';
import 'track.dart';

/// Songs found on this device (phone, pendrive, PC).
class MusicLibrary extends ChangeNotifier {
  MusicLibrary._();
  static final MusicLibrary instance = MusicLibrary._();

  static const _exts = {'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma'};
  static const _generic = {
    'music', 'download', 'downloads', 'audio', '0', 'emulated', 'storage',
    'sdcard', 'songs', 'media',
  };

  List<Track> tracks = <Track>[];
  List<String> folders = <String>[];
  bool loading = false;
  bool needAccess = false;
  bool _started = false;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    final p = await SharedPreferences.getInstance();
    folders = p.getStringList('musicFolders') ?? <String>[];
    await scan();
  }

  List<String> _minimal(Iterable<String> roots) {
    final list = roots.toSet().toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final out = <String>[];
    for (final r in list) {
      if (!out.any((o) => r == o || r.startsWith('$o/') || r.startsWith('$o\\'))) {
        out.add(r);
      }
    }
    return out;
  }

  Future<void> scan() async {
    if (loading) return;
    loading = true;
    needAccess = false;
    notifyListeners();
    final roots = <String>{...folders};
    try {
      if (Platform.isAndroid) {
        final ok = await Permission.manageExternalStorage.isGranted;
        if (!ok) {
          needAccess = true;
          tracks = <Track>[];
          loading = false;
          notifyListeners();
          return;
        }
        roots.add('/storage/emulated/0');
        for (final d in await StorageVolumes.androidVolumes()) {
          roots.add(d.root);
        }
      } else if (Platform.isWindows && roots.isEmpty) {
        final h = Platform.environment['USERPROFILE'];
        if (h != null && Directory('$h\\Music').existsSync()) {
          roots.add('$h\\Music');
        }
      }
      final found = <String, Track>{};
      for (final r in _minimal(roots)) {
        for (final t in await _scanRoot(r)) {
          found[t.uri] = t;
        }
      }
      tracks = found.values.toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  static Future<List<Track>> _scanRoot(String root) async {
    final out = <Track>[];
    try {
      final stream =
          Directory(root).list(recursive: true, followLinks: false).handleError((_) {});
      await for (final e in stream) {
        if (e is! File) continue;
        final path = e.path;
        if (path.contains('/.') || path.contains('\\.')) continue;
        final low = path.toLowerCase();
        if (low.contains('/android/') ||
            low.contains('/ringtones/') ||
            low.contains('/notifications/') ||
            low.contains('/alarms/')) {
          continue;
        }
        final dot = path.lastIndexOf('.');
        if (dot < 0 || !_exts.contains(low.substring(dot + 1))) continue;
        FileStat st;
        try {
          st = await e.stat();
        } catch (_) {
          continue;
        }
        if (st.size < 200 * 1024) continue;
        out.add(_make(path, st));
      }
    } catch (_) {}
    return out;
  }

  static Track _make(String path, FileStat st) {
    final parts = path.split(RegExp(r'[\\/]'));
    final file = parts.last;
    final dot = file.lastIndexOf('.');
    var base = dot > 0 ? file.substring(0, dot) : file;
    base = base
        .replaceAll('_', ' ')
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-.)]\s*'), '')
        .trim();
    var title = base;
    var artist = 'Unknown artist';
    final i = base.indexOf(' - ');
    if (i > 0 && i < base.length - 3) {
      artist = base.substring(0, i).trim();
      title = base.substring(i + 3).trim();
    }
    var album = '';
    if (parts.length >= 2) {
      final f = parts[parts.length - 2];
      if (!_generic.contains(f.toLowerCase())) album = f;
    }
    return Track(
      id: 'l:$path',
      title: title.isEmpty ? file : title,
      artist: artist,
      album: album,
      uri: path,
      source: TrackSource.local,
      addedMs: st.modified.millisecondsSinceEpoch,
    );
  }

  Future<void> requestAccess() async {
    await Permission.manageExternalStorage.request();
    await scan();
  }

  Future<void> addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || folders.contains(dir)) return;
    folders = [...folders, dir];
    final p = await SharedPreferences.getInstance();
    await p.setStringList('musicFolders', folders);
    await scan();
  }
}
