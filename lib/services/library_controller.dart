import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';
import 'scanner_android.dart';
import 'scanner_desktop.dart';
import 'storage_volumes.dart';

class LibraryController extends ChangeNotifier {
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

  bool get isAndroid => Platform.isAndroid;
  bool get isWindows => Platform.isWindows;
  bool get canScanFiles => isWindows || (isAndroid && allFilesAccess);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    folders = prefs.getStringList('folders') ?? <String>[];
    await refresh();
  }

  Future<void> refresh() async {
    if (loading) {
      _pending = true;
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      final result = <String, VideoItem>{};

      if (isAndroid) {
        allFilesAccess = await Permission.manageExternalStorage.isGranted;
        drives = await StorageVolumes.androidVolumes();

        final r = await AndroidScanner.scan();
        permissionDenied = r.permissionDenied;

        final fileItems = <VideoItem>[];
        if (allFilesAccess) {
          final roots = <String>{...drives.map((d) => d.root), ...folders};
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
        final fileNames = <String>{
          for (final v in fileItems) v.name.toLowerCase(),
        };

        for (final v in r.items) {
          // hide library entries we cannot open if the same file was found by folder scan
          if (v.path.isEmpty && fileNames.contains(v.name.toLowerCase())) {
            continue;
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
    } catch (e) {
      error = e.toString();
    }

    loading = false;
    notifyListeners();

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
