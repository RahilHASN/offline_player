import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';
import 'folder_tree.dart';
import 'library_index.dart';
import 'scanner_android.dart';
import 'scanner_desktop.dart';
import 'storage_volumes.dart';

class LibraryController extends ChangeNotifier {
  static const phoneRoot = '/storage/emulated/0';

  List<VideoItem> items = <VideoItem>[];
  List<String> folders = <String>[];
  List<DriveInfo> drives = <DriveInfo>[];
  bool loading = false;
  bool permissionDenied = false;
  bool allFilesAccess = false;
  int unresolved = 0;
  String? error;
  String? notice;
  bool _pending = false;

  /// Called when a new pendrive / SD card shows up (Android).
  void Function(List<String> roots)? onDriveAdded;

  Set<String> _known = <String>{};
  bool _firstDone = false;
  Timer? _watch;

  bool get isAndroid => Platform.isAndroid;
  bool get isWindows => Platform.isWindows;
  bool get canScanFiles => isWindows || (isAndroid && allFilesAccess);

  /// Starting points for the folder view.
  List<String> get browseRoots {
    if (isAndroid) {
      return <String>[phoneRoot, ...drives.map((d) => d.root), ...folders];
    }
    return List<String>.of(folders);
  }

  String labelFor(String path) {
    if (isAndroid && path == phoneRoot) return 'Phone storage';
    return FolderTree.nameOf(path);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    folders = prefs.getStringList('folders') ?? <String>[];

    // show the last list straight away, then update it
    final cached = await LibraryIndex.load();
    if (cached.isNotEmpty) {
      items = cached;
      notifyListeners();
    }
    await refresh();
  }

  /// Checks every few seconds for a plugged-in or removed drive.
  void startWatching() {
    if (!isAndroid) return;
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (loading) return;
      try {
        final v = await StorageVolumes.androidVolumes();
        final r = v.map((d) => d.root).toSet();
        if (r.length != _known.length || !r.containsAll(_known)) {
          await refresh();
        }
      } catch (_) {}
    });
  }

  void stopWatching() {
    _watch?.cancel();
    _watch = null;
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  List<String> _minimal(Iterable<String> roots) {
    final list = roots.map(FolderTree.trim).toSet().toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final out = <String>[];
    for (final r in list) {
      if (!out.any((o) => r == o || r.startsWith('$o/'))) out.add(r);
    }
    return out;
  }

  Future<void> refresh() async {
    if (loading) {
      _pending = true;
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    var added = <String>[];

    try {
      final result = <String, VideoItem>{};

      if (isAndroid) {
        allFilesAccess = await Permission.manageExternalStorage.isGranted;
        drives = await StorageVolumes.androidVolumes();

        final now = drives.map((d) => d.root).toSet();
        if (_firstDone) {
          added = now.difference(_known).toList();
        }
        _known = now;
        _firstDone = true;

        final r = await AndroidScanner.scan();
        permissionDenied = r.permissionDenied;

        final fileItems = <VideoItem>[];
        if (allFilesAccess) {
          final roots = _minimal(
            <String>{phoneRoot, ...drives.map((d) => d.root), ...folders},
          );
          for (final root in roots) {
            final found = await DesktopScanner.scanFolder(
              root,
              source: StorageVolumes.androidSourceFor(root),
            );
            fileItems.addAll(found);
          }
        }

        final mediaPaths = <String>{
          for (final v in r.items)
            if (v.path.isNotEmpty) v.path,
        };

        for (final v in r.items) {
          if (allFilesAccess) {
            // with full file access, entries whose file is gone are stale
            if (v.path.isEmpty) continue;
            if (!File(v.path).existsSync()) continue;
          }
          result[v.id] = v;
        }
        for (final v in fileItems) {
          if (mediaPaths.contains(v.path)) continue;
          result[v.id] = v;
        }
      } else if (isWindows) {
        drives = StorageVolumes.windowsDrives();
        for (final f in folders) {
          final src = StorageVolumes.windowsIsRemovable(f)
              ? VideoSource.pendrive
              : VideoSource.pc;
          final found = await DesktopScanner.scanFolder(f, source: src);
          for (final v in found) {
            result[v.id] = v;
          }
        }
      }

      final list = result.values.toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      items = list;
      unresolved = list.where((v) => v.path.isEmpty).length;
      LibraryIndex.save(list);
    } catch (e) {
      error = e.toString();
    }

    loading = false;
    notifyListeners();

    if (added.isNotEmpty) {
      onDriveAdded?.call(added);
    }

    if (_pending) {
      _pending = false;
      await refresh();
    }
  }

  /// Called when the app comes back to the foreground.
  Future<void> onResumed() async {
    if (!isAndroid) return;
    final granted = await Permission.manageExternalStorage.isGranted;
    if (granted != allFilesAccess) {
      await refresh();
    }
  }

  Future<void> requestAllFilesAccess() async {
    await Permission.manageExternalStorage.request();
    await refresh();
  }

  Future<void> addFolder() async {
    if (isAndroid && !allFilesAccess) {
      notice = 'Allow "All files access" first.';
      notifyListeners();
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    await addPath(dir);
  }

  Future<void> addPath(String dir) async {
    if (isAndroid && !dir.startsWith('/')) {
      notice = 'Could not read that folder as a path. '
          'Try choosing the folder on the drive itself.';
      notifyListeners();
      return;
    }
    notice = null;
    if (folders.contains(dir)) {
      notifyListeners();
      return;
    }
    folders = [...folders, dir];
    await _saveFolders();
    await refresh();
  }

  Future<void> removeFolder(String dir) async {
    folders = folders.where((f) => f != dir).toList();
    await _saveFolders();
    await refresh();
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('folders', folders);
  }
}
