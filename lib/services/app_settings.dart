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
  int columns = 0; // 0 = auto
  bool largePreview = true;
  bool viewFolders = false;
  bool autoNext = true;
  bool autoResume = true;
  bool backgroundPlay = false;
  bool smartCuts = false;
  int cacheLimitMb = 300; // 0 = unlimited

  bool _b(Map<String, dynamic> j, String k, bool d) =>
      j[k] is bool ? j[k] as bool : d;
  int _i(Map<String, dynamic> j, String k, int d) =>
      j[k] is num ? (j[k] as num).toInt() : d;
  double _d(Map<String, dynamic> j, String k, double d) =>
      j[k] is num ? (j[k] as num).toDouble() : d;
  String _s(Map<String, dynamic> j, String k, String d) =>
      j[k] is String ? j[k] as String : d;

  void _apply(Map<String, dynamic> j) {
    previewAudio = _b(j, 'previewAudio', false);
    cuts = _i(j, 'cuts', 6).clamp(2, 12).toInt();
    clipSeconds = _d(j, 'clipSeconds', 1.5).clamp(1.0, 3.0).toDouble();
    sortKey = _s(j, 'sortKey', 'name');
    sortAsc = _b(j, 'sortAsc', true);
    columns = _i(j, 'columns', 0).clamp(0, 3).toInt();
    largePreview = _b(j, 'largePreview', true);
    viewFolders = _b(j, 'viewFolders', false);
    autoNext = _b(j, 'autoNext', true);
    autoResume = _b(j, 'autoResume', true);
    backgroundPlay = _b(j, 'backgroundPlay', false);
    smartCuts = _b(j, 'smartCuts', false);
    cacheLimitMb = _i(j, 'cacheLimitMb', 300).clamp(0, 100000).toInt();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _apply(<String, dynamic>{for (final k in p.getKeys()) k: p.get(k)});
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'previewAudio': previewAudio,
        'cuts': cuts,
        'clipSeconds': clipSeconds,
        'sortKey': sortKey,
        'sortAsc': sortAsc,
        'columns': columns,
        'largePreview': largePreview,
        'viewFolders': viewFolders,
        'autoNext': autoNext,
        'autoResume': autoResume,
        'backgroundPlay': backgroundPlay,
        'smartCuts': smartCuts,
        'cacheLimitMb': cacheLimitMb,
      };

  /// Used by Restore.
  void fromJson(Map<String, dynamic> j) {
    _apply(j);
        toJson().forEach((k, v) => _write(k, v as Object));
    notifyListeners();
  }

  void _write(String k, Object v) {
    final p = _prefs;
    if (p == null) return;
    if (v is bool) {
      p.setBool(k, v);
    } else if (v is int) {
      p.setInt(k, v);
    } else if (v is double) {
      p.setDouble(k, v);
    } else if (v is String) {
      p.setString(k, v);
    }
  }

  void _set(String k, Object v) {
    _write(k, v);
    notifyListeners();
  }

  void setPreviewAudio(bool v) {
    previewAudio = v;
    _set('previewAudio', v);
  }

  void setCuts(int v) {
    cuts = v.clamp(2, 12).toInt();
    _set('cuts', cuts);
  }

  void setClipSeconds(double v) {
    clipSeconds = v.clamp(1.0, 3.0).toDouble();
    _set('clipSeconds', clipSeconds);
  }

  void setSort(String key, bool asc) {
    sortKey = key;
    sortAsc = asc;
    _write('sortKey', key);
    _set('sortAsc', asc);
  }

  void setColumns(int v) {
    columns = v.clamp(0, 3).toInt();
    _set('columns', columns);
  }

  void setLargePreview(bool v) {
    largePreview = v;
    _set('largePreview', v);
  }

  void setViewFolders(bool v) {
    viewFolders = v;
    _set('viewFolders', v);
  }

  void setAutoNext(bool v) {
    autoNext = v;
    _set('autoNext', v);
  }

  void setAutoResume(bool v) {
    autoResume = v;
    _set('autoResume', v);
  }

  void setBackgroundPlay(bool v) {
    backgroundPlay = v;
    _set('backgroundPlay', v);
  }

  void setSmartCuts(bool v) {
    smartCuts = v;
    _set('smartCuts', v);
  }

  void setCacheLimitMb(int v) {
    cacheLimitMb = v;
    _set('cacheLimitMb', v);
  }
}
