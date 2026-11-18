import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;

  bool previewAudio = false;
  int cuts = 6;
  double clipSeconds = 1.5;
  String sortKey = 'name'; // name, date, length, size
  bool sortAsc = true;

  /// 0 = auto, otherwise 1, 2 or 3 columns.
  int columns = 0;
  bool largePreview = true;
  bool viewFolders = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    previewAudio = p.getBool('previewAudio') ?? false;
    cuts = (p.getInt('cuts') ?? 6).clamp(2, 12).toInt();
    clipSeconds = (p.getDouble('clipSeconds') ?? 1.5).clamp(1.0, 3.0).toDouble();
    sortKey = p.getString('sortKey') ?? 'name';
    sortAsc = p.getBool('sortAsc') ?? true;
    columns = (p.getInt('columns') ?? 0).clamp(0, 3).toInt();
    largePreview = p.getBool('largePreview') ?? true;
    viewFolders = p.getBool('viewFolders') ?? false;
  }

  void setPreviewAudio(bool v) {
    previewAudio = v;
    _prefs?.setBool('previewAudio', v);
    notifyListeners();
  }

  void setCuts(int v) {
    cuts = v.clamp(2, 12).toInt();
    _prefs?.setInt('cuts', cuts);
    notifyListeners();
  }

  void setClipSeconds(double v) {
    clipSeconds = v.clamp(1.0, 3.0).toDouble();
    _prefs?.setDouble('clipSeconds', clipSeconds);
    notifyListeners();
  }

  void setSort(String key, bool asc) {
    sortKey = key;
    sortAsc = asc;
    _prefs?.setString('sortKey', key);
    _prefs?.setBool('sortAsc', asc);
    notifyListeners();
  }

  void setColumns(int v) {
    columns = v.clamp(0, 3).toInt();
    _prefs?.setInt('columns', columns);
    notifyListeners();
  }

  void setLargePreview(bool v) {
    largePreview = v;
    _prefs?.setBool('largePreview', v);
    notifyListeners();
  }

  void setViewFolders(bool v) {
    viewFolders = v;
    _prefs?.setBool('viewFolders', v);
    notifyListeners();
  }
}
