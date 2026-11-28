import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../music/music_player.dart';
import '../services/native_bridge.dart';
import 'compliance.dart';
import 'handoff.dart';
import 'provider.dart';
import 'youtube_embed_screen.dart';
import 'youtube_history.dart';

/// Lets code outside a screen (the floating player) open screens.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Owns the official player (IFrame Player API in a WebView) so it keeps
/// playing when you leave the full player screen. The player is always
/// visible: either on the full screen or in the floating 200 x 200 window.
/// It is never hidden, audio-only or played with nothing on screen.
class EmbedSession extends ChangeNotifier {
  EmbedSession._() {
    MusicPlayer.instance.addListener(_onLocalMusic);
  }
  static final EmbedSession instance = EmbedSession._();

  static const String origin = 'https://com.example.offlineplayer';
  static const String _base = '$origin/';

  WebViewController? controller;
  List<MediaItem> queue = <MediaItem>[];
  int index = 0;
  bool playing = false;
  bool shuffle = false;
  int repeat = 0; // 0 off, 1 all, 2 one

  /// True while the full player screen is open (the floating window hides).
  bool screenOpen = false;

  final ValueNotifier<double> pos = ValueNotifier<double>(0);
  final ValueNotifier<double> dur = ValueNotifier<double>(0);

  /// Set by the full screen so errors can show a message.
  void Function(String)? onNotice;

  final List<int> _back = <int>[];
  final Random _rng = Random();
  int _errorStreak = 0;

  bool get active => controller != null && queue.isNotEmpty;
  MediaItem get cur => queue[index];

  static String _html(String id) =>
      '<!DOCTYPE html><html><head>'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>html,body{margin:0;height:100%;background:#000}'
      '#p{position:absolute;top:0;left:0;width:100%;height:100%}</style>'
      '</head><body><div id="p"></div>'
      '<script src="https://www.youtube.com/iframe_api"></script>'
      '<script>var player;'
      'function onYouTubeIframeAPIReady(){'
      'player=new YT.Player("p",{width:"100%",height:"100%",videoId:"$id",'
      'playerVars:{playsinline:1,rel:0,autoplay:1,origin:"$origin"},'
      'events:{onStateChange:function(e){Bridge.postMessage("state:"+e.data);'
      'if(e.data===0){Bridge.postMessage("ended");}},'
      'onError:function(e){Bridge.postMessage("error:"+e.data);}}});}'
      'function loadVideo(v){if(player&&player.loadVideoById){player.loadVideoById(v);}}'
      'function ctl(a,v){if(!player){return;}'
      'if(a==="play"){player.playVideo();}'
      'else if(a==="pause"){player.pauseVideo();}'
      'else if(a==="seek"){player.seekTo(v,true);}}'
      'setInterval(function(){if(player&&player.getCurrentTime){'
      'Bridge.postMessage("pos:"+player.getCurrentTime()+":"+(player.getDuration()||0));}},500);'
      '</script></body></html>';

  void _create(String id) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Bridge', onMessageReceived: (m) => _onMsg(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!r.isMainFrame) return NavigationDecision.navigate;
          final u = r.url;
          if (u.startsWith('about:') || u.startsWith('data:') || u == _base) {
            return NavigationDecision.navigate;
          }
          final uri = Uri.tryParse(u);
          if (uri != null && uri.scheme == 'https') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ));
    final plat = c.platform;
    if (plat is AndroidWebViewController) {
      plat.setMediaPlaybackRequiresUserGesture(false);
    }
    c.loadHtmlString(_html(id), baseUrl: _base);
    controller = c;
  }

  /// Starts a list. Returns false if the song may not be played here.
  bool start(List<MediaItem> q, int i) {
    if (q.isEmpty) return false;
    final idx = i < 0 || i >= q.length ? 0 : i;
    final id = q[idx].videoId;
    if (id == null || !Compliance.validVideoId(id)) return false;
    try {
      Compliance.assertHandoff(EmbedHandoff(providerId: 'youtube', videoId: id));
    } on ComplianceError {
      return false;
    }
    MusicPlayer.instance.pause();
    queue = q;
    index = idx;
    _back.clear();
    _errorStreak = 0;
    pos.value = 0;
    dur.value = cur.durationSec.toDouble();
    YouTubeHistory.instance.add(cur);
    if (controller == null) {
      _create(id);
    } else {
      controller!.runJavaScript("loadVideo('$id')");
    }
    notifyListeners();
    return true;
  }

  void _syncPip() => NativeBridge.setAutoPip(playing && screenOpen);

  /// Shows the full player screen. The floating window hides first, so the
  /// one player is never on screen twice.
  Future<void> openFull() async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null || !active || screenOpen) return;
    screenOpen = true;
    _syncPip();
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await nav.push(
      MaterialPageRoute<void>(builder: (_) => const YouTubeEmbedScreen()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    screenOpen = false;
    _syncPip();
    notifyListeners();
  }

  /// Closes the player completely.
  void stop() {
    if (controller == null && queue.isEmpty) return;
    try {
      controller?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    controller = null;
    queue = <MediaItem>[];
    playing = false;
    pos.value = 0;
    dur.value = 0;
    NativeBridge.setAutoPip(false);
    notifyListeners();
  }

  void _onLocalMusic() {
    if (MusicPlayer.instance.playing && playing) {
      controller?.runJavaScript('ctl("pause")');
    }
  }

  // ---------- messages from the player ----------

  void _onMsg(String m) {
    if (m.startsWith('pos:')) {
      final p = m.split(':');
      if (p.length >= 3) {
        final c = double.tryParse(p[1]);
        final d = double.tryParse(p[2]);
        if (c != null) pos.value = c;
        if (d != null && d > 0) dur.value = d;
      }
    } else if (m.startsWith('state:')) {
      final s = int.tryParse(m.substring(6));
      final pl = s == 1;
      if (pl) _errorStreak = 0;
      if (pl != playing) {
        playing = pl;
        _syncPip();
        notifyListeners();
      }
    } else if (m == 'ended') {
      _onEnded();
    } else if (m.startsWith('error')) {
      _errorStreak++;
      if (_errorStreak > 3) return;
      onNotice?.call("This one can't play here. Skipping.");
      next(auto: true);
    }
  }

  void _onEnded() {
    if (repeat == 2) {
      controller?.runJavaScript('ctl("seek",0);ctl("play")');
      return;
    }
    next(auto: true);
  }

  // ---------- transport ----------

  void toggle() =>
      controller?.runJavaScript(playing ? 'ctl("pause")' : 'ctl("play")');

  void seek(double s) => controller?.runJavaScript('ctl("seek",$s)');

  void setShuffle(bool v) {
    shuffle = v;
    notifyListeners();
  }

  void setRepeat(int v) {
    repeat = v;
    notifyListeners();
  }

  void next({bool auto = false}) {
    final n = queue.length;
    if (n == 0) return;
    int t;
    if (shuffle && n > 1) {
      do {
        t = _rng.nextInt(n);
      } while (t == index);
    } else {
      t = index + 1;
      if (t >= n) {
        if (repeat == 1 || !auto) {
          t = 0;
        } else {
          return;
        }
      }
    }
    go(t);
  }

  void prev() {
    if (pos.value > 3) {
      seek(0);
      return;
    }
    if (_back.isNotEmpty) {
      go(_back.removeLast(), push: false);
      return;
    }
    if (index > 0) go(index - 1, push: false);
  }

  void go(int i, {bool push = true}) {
    if (i < 0 || i >= queue.length) return;
    final id = queue[i].videoId;
    if (id == null || !Compliance.validVideoId(id)) return;
    try {
      Compliance.assertHandoff(EmbedHandoff(providerId: 'youtube', videoId: id));
    } on ComplianceError {
      return;
    }
    if (push) _back.add(index);
    index = i;
    pos.value = 0;
    dur.value = queue[i].durationSec.toDouble();
    YouTubeHistory.instance.add(queue[i]);
    controller?.runJavaScript("loadVideo('$id')");
    notifyListeners();
  }
}
