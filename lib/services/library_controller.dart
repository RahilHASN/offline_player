import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';
import 'scanner_android.dart';
import 'scanner_desktop.dart';

class LibraryController extends ChangeNotifier {
  List<VideoItem> items = <VideoItem>[];
  List<String> folders = <String>[];
  bool loading = false;
  bool permissionDenied = false;
  int unresolved = 0;
  String? error;

  bool get isAndroid => Platform.isAndroid;
  bool get isWindows => Platform.isWindows;

  Future<void> init() async {
    if (isWindows) {
      final prefs = await SharedPreferences.getInstance();
      folders = prefs.getStringList('folders') ?? <String>[];
    }
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = <String, VideoItem>{};
      if (isAndroid) {
        final r = await AndroidScanner.scan();
        permissionDenied = r.permissionDenied;
        unresolved = r.unresolved;
        for (final v in r.items) {
          result[v.id] = v;
        }
      } else if (isWindows) {
        for (final f in folders) {
          final found = await DesktopScanner.scanFolder(f);
          for (final v in found) {
            result[v.id] = v;
          }
        }
      }
      final list = result.values.toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      items = list;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || folders.contains(dir)) return;
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
