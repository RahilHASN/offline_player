import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online / offline mode. The online build has the internet permission;
/// the offline build does not and can never go online.
class AppMode extends ChangeNotifier {
  AppMode._();
  static final AppMode instance = AppMode._();

  static const bool onlineBuild = bool.fromEnvironment('ONLINE');

  SharedPreferences? _p;
  bool _enabled = false;
  String youtubeKey = '';

  bool get enabled => _enabled;

  /// True only when this is an online build AND the switch is on.
  bool get online => onlineBuild && _enabled;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    _enabled = p.getBool('onlineEnabled') ?? false;
    youtubeKey = p.getString('youtubeKey') ?? '';
  }

  void setOnline(bool v) {
    if (!onlineBuild) return;
    _enabled = v;
    _p?.setBool('onlineEnabled', v);
    notifyListeners();
  }

  void setYoutubeKey(String v) {
    youtubeKey = v.trim();
    _p?.setString('youtubeKey', youtubeKey);
    notifyListeners();
  }
}
