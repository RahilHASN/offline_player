import 'dart:io';

import 'package:flutter/foundation.dart';

class FileClipboard extends ChangeNotifier {
  FileClipboard._();
  static final FileClipboard instance = FileClipboard._();

  String? path;
  bool isCut = false;

  void set(String p, {required bool cut}) {
    path = p;
    isCut = cut;
    notifyListeners();
  }

  void clear() {
    path = null;
    notifyListeners();
  }
}

class FileOps {
  static String get _sep => Platform.pathSeparator;

  static String _parent(String p) {
    final i = p.lastIndexOf(_sep);
    return i <= 0 ? '' : p.substring(0, i);
  }

  static String _name(String p) => p.split(RegExp(r'[\\/]')).last;

  /// Renames a file in its own folder. Returns the new path.
  static Future<String> rename(String path, String newName) async {
    if (newName.contains('/') || newName.contains('\\')) {
      throw 'The name cannot contain / or \\';
    }
    final target = '${_parent(path)}$_sep$newName';
    if (target == path) return path;
    if (await File(target).exists()) {
      throw 'A file with that name already exists';
    }
    await File(path).rename(target);
    return target;
  }

  static String _unique(String dir, String name) {
    var candidate = '$dir$_sep$name';
    if (!File(candidate).existsSync()) return candidate;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var n = 1;
    while (true) {
      final label = n == 1 ? ' (copy)' : ' (copy $n)';
      candidate = '$dir$_sep$base$label$ext';
      if (!File(candidate).existsSync()) return candidate;
      n++;
    }
  }

  /// Copies or moves [srcPath] into [destDir]. Returns the new path.
  static Future<String> paste(
    String srcPath,
    String destDir, {
    required bool move,
  }) async {
    final src = File(srcPath);
    if (!await src.exists()) throw 'The original file no longer exists';

    if (move && _parent(srcPath) == destDir) return srcPath;

    final target = _unique(destDir, _name(srcPath));
    if (move) {
      try {
        await src.rename(target);
      } on FileSystemException {
        // different drive: copy, then delete the original
        await src.copy(target);
        await src.delete();
      }
    } else {
      await src.copy(target);
    }
    return target;
  }
}
