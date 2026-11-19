import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'app_settings.dart';
import 'library_store.dart';

class BackupService {
  /// Returns true if a file was saved.
  static Future<bool> export() async {
    final data = <String, dynamic>{
      'app': 'offline_player',
      'version': 2,
      'store': LibraryStore.instance.toJson(),
      'settings': AppSettings.instance.toJson(),
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent(' ').convert(data)),
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: 'offline_player_backup.json',
      bytes: bytes,
    );
    if (path == null) return false;
    if (Platform.isWindows) {
      await File(path).writeAsBytes(bytes);
    }
    return true;
  }

  /// Returns true if a backup was restored. Throws a message on a bad file.
  static Future<bool> restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.isEmpty) return false;
    final f = r.files.first;
    List<int>? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null) throw 'Could not read the file';
    final obj = jsonDecode(utf8.decode(bytes));
    if (obj is! Map || obj['app'] != 'offline_player') {
      throw 'This is not an Offline Player backup';
    }
    final store = obj['store'];
    if (store is Map) {
      LibraryStore.instance.replaceAll(Map<String, dynamic>.from(store));
    }
    final settings = obj['settings'];
    if (settings is Map) {
      AppSettings.instance.fromJson(Map<String, dynamic>.from(settings));
    }
    return true;
  }
}
