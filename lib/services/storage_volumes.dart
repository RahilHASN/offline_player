import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';

class DriveInfo {
  final String root;
  final bool removable;
  const DriveInfo(this.root, this.removable);
}

class StorageVolumes {
  static int Function(Pointer<Utf16>)? _getDriveType;

  // Windows: 2 = removable, 3 = fixed, 4 = network
  static int _driveType(String root) {
    _getDriveType ??= DynamicLibrary.open('kernel32.dll').lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('GetDriveTypeW');
    final p = root.toNativeUtf16();
    try {
      return _getDriveType!(p);
    } finally {
      calloc.free(p);
    }
  }

  static List<DriveInfo> windowsDrives() {
    if (!Platform.isWindows) return <DriveInfo>[];
    final out = <DriveInfo>[];
    for (var c = 65; c <= 90; c++) {
      final root = '${String.fromCharCode(c)}:\\';
      try {
        final t = _driveType(root);
        if (t == 2 || t == 3 || t == 4) {
          if (t == 2 && !Directory(root).existsSync()) continue;
          out.add(DriveInfo(root, t == 2));
        }
      } catch (_) {
        // ignore this letter
      }
    }
    return out;
  }

  static bool windowsIsRemovable(String folder) {
    if (!Platform.isWindows) return false;
    if (folder.length < 2 || folder[1] != ':') return false;
    try {
      return _driveType('${folder[0].toUpperCase()}:\\') == 2;
    } catch (_) {
      return false;
    }
  }

  /// Android: finds SD cards / pendrives mounted under /storage.
  static Future<List<DriveInfo>> androidVolumes() async {
    final roots = <String>{};

    try {
      final dirs = await getExternalStorageDirectories();
      for (final d in dirs ?? <Directory>[]) {
        final i = d.path.indexOf('/Android/');
        if (i <= 0) continue;
        final root = d.path.substring(0, i);
        if (root.startsWith('/storage/emulated') || root == '/sdcard') continue;
        roots.add(root);
      }
    } catch (_) {
      // ignore
    }

    try {
      await for (final e in Directory('/storage').list(followLinks: false)) {
        final name = e.path.split('/').last;
        if (name == 'emulated' || name == 'self') continue;
        roots.add(e.path);
      }
    } catch (_) {
      // /storage may not be listable on some phones
    }

    return [for (final r in roots) DriveInfo(r, true)];
  }

  static VideoSource androidSourceFor(String path) {
    if (path.startsWith('/storage/emulated') || path.startsWith('/sdcard')) {
      return VideoSource.phone;
    }
    return VideoSource.pendrive;
  }
}
