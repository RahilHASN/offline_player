import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../music/lyrics_service.dart';
import '../music/track.dart';
import '../services/native_bridge.dart';
import '../widgets/youtube_badge.dart';
import 'compliance.dart';
import 'handoff.dart';
import 'playlist_store.dart';
import 'provider.dart';
import 'youtube_history.dart';

enum _View { video, poster, lyrics }

/// YouTube's official player (IFrame Player API) inside a WebView, with
/// song-style controls driven through the official API. The player always
/// stays visible (at least 200 px high) and nothing is drawn over it.
class YouTubeEmbedScreen extends StatefulWidget {
  final List<MediaItem> queue;
  final int index;
  const YouTubeEmbedScreen({super.key, required this.queue, required this.index});

  @override
  State<YouTubeEmbedScreen> createState() => _YouTubeEmbedScreenState();
}

class _YouTubeEmbedScreenState extends State<YouTubeEmbedScreen> {
  static const _origin = 'https://com.example.offlineplayer';
  static const _base = '$_origin/';

  late final WebViewController _c;
  final GlobalKey _webKey = GlobalKey();
  final Random _rng = Random();
  final List<int> _back = <int>[];
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);
  final ValueNotifier<double> _dur = ValueNotifier<double>(0);
  final ScrollController _lyricScroll = ScrollController();

  late int _i = widget.index;
  _View _view = _View.poster;
  bool _playing = false;
  bool _shuffle = false;
  int _repeat = 0; // 0 off, 1 all, 2 one
  bool _listOpen = false;
  double? _drag;
  int _errorStreak = 0;

  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  String? _lyricsFor;
  int _lastCur = -2;

  MediaItem get _cur => widget.queue[_i];

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
      'playerVars:{playsinline:1,rel:0,autoplay:1,origin:"$_origin"},'
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

  @override
  void initState() {
    super.initState();
    final id = _cur.videoId!;
    try {
      Compliance.assertHandoff(EmbedHandoff(providerId: 'youtube', videoId: id));
    } on ComplianceError {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    YouTubeHistory.instance.add(_cur);
    PlaylistStore.instance.load();
    _c = WebViewController()
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
    final plat = _c.platform;
    if (plat is AndroidWebViewController) {
      plat.setMediaPlaybackRequiresUserGesture(false);
    }
    _c.loadHtmlString(_html(id), baseUrl: _base);
  }

  @override
  void dispose() {
    NativeBridge.setAutoPip(false);
    try {
      _c.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    _pos.dispose();
    _dur.dispose();
    _lyricScroll.dispose();
    super.dispose();
  }

  // ---------- messages from the player ----------

  void _onMsg(String m) {
    if (!mounted) return;
    if (m.startsWith('pos:')) {
      final p = m.split(':');
      if (p.length >= 3) {
        final c = double.tryParse(p[1]);
        final d = double.tryParse(p[2]);
        if (c != null) _pos.value = c;
        if (d != null && d > 0) _dur.value = d;
      }
    } else if (m.startsWith('state:')) {
      final s = int.tryParse(m.substring(6));
      final pl = s == 1;
      if (pl) _errorStreak = 0;
      if (pl != _playing) {
        setState(() => _playing = pl);
        NativeBridge.setAutoPip(pl);
      }
    } else if (m == 'ended') {
      _onEnded();
    } else if (m.startsWith('error')) {
      _errorStreak++;
      if (_errorStreak > 3) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("YouTube can't play this one here. Skipping.")));
      _next(auto: true);
    }
  }

  void _onEnded() {
    if (_repeat == 2) {
      _c.runJavaScript('ctl("seek",0);ctl("play")');
      return;
    }
    _next(auto: true);
  }

  // ---------- transport ----------

  void _toggle() => _c.runJavaScript(_playing ? 'ctl("pause")' : 'ctl("play")');

  void _seek(double s) => _c.runJavaScript('ctl("seek",$s)');

  void _next({bool auto = false}) {
    final n = widget.queue.length;
    if (n == 0) return;
    int t;
    if (_shuffle && n > 1) {
      do {
        t = _rng.nextInt(n);
      } while (t == _i);
    } else {
      t = _i + 1;
      if (t >= n) {
        if (_repeat == 1 || !auto) {
          t = 0;
        } else {
          return;
        }
      }
    }
    _go(t);
  }

  void _prev() {
    if (_pos.value > 3) {
      _seek(0);
      return;
    }
    if (_back.isNotEmpty) {
      _go(_back.removeLast(), push: false);
      return;
    }
    if (_i > 0) _go(_i - 1, push: false);
  }

  void _go(int i, {bool push = true}) {
    if (i < 0 || i >= widget.queue.length) return;
    final id = widget.queue[i].videoId;
    if (id == null || !Compliance.validVideoId(id)) return;
    try {
      Compliance.assertHandoff(EmbedHandoff(providerId: 'youtube', videoId: id));
    } on ComplianceError {
      return;
    }
    if (push) _back.add(_i);
    setState(() {
      _i = i;
      _lyrics = null;
      _lyricsFor = null;
      _lastCur = -2;
    });
    _pos.value = 0;
    _dur.value = widget.queue[i].durationSec.toDouble();
    YouTubeHistory.instance.add(widget.queue[i]);
    _c.runJavaScript("loadVideo('$id')");
    if (_view == _View.lyrics) _ensureLyrics();
  }

  // ---------- lyrics ----------

  Future<void> _ensureLyrics() async {
    final cur = _cur;
    if (_lyricsFor == cur.id) return;
    _lyricsFor = cur.id;
    setState(() {
      _lyrics = null;
      _lyricsLoading = true;
    });
    final t = Track(
      id: cur.id,
      title: cur.title,
      artist: cur.creator.isEmpty ? 'Unknown artist' : cur.creator,
      album: '',
      uri: '',
      source: TrackSource.web,
      durationSec: cur.durationSec,
    );
    Lyrics? r;
    try {
      r = await LyricsService.instance.forTrack(t);
    } catch (_) {}
    if (!mounted || _lyricsFor != cur.id) return;
    setState(() {
      _lyrics = r;
      _lyricsLoading = false;
    });
  }

  // ---------- helpers ----------

  String _fmt(double s) {
    final t = s.isNaN || s < 0 ? 0 : s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  Widget _thumb(MediaItem m, double w, double h, {double r = 8}) => SizedBox(
        width: w,
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: m.thumb == null
              ? Container(color: Colors.white10)
              : Image.network(m.thumb!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
        ),
      );

  // ---------- pieces of the screen ----------

  PreferredSizeWidget _appBar() {
    final watch = Uri.https('www.youtube.com', '/watch', {'v': _cur.videoId!});
    return AppBar(
      toolbarHeight: 46,
      title: const YouTubeBadge(size: 15),
      actions: [
        ToggleButtons(
          isSelected: [
            _view == _View.video,
            _view == _View.poster,
            _view == _View.lyrics,
          ],
          onPressed: (i) {
            setState(() => _view = _View.values[i]);
            if (_view == _View.lyrics) _ensureLyrics();
          },
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          borderRadius: BorderRadius.circular(8),
          children: const [
            Icon(Icons.ondemand_video, size: 18),
            Icon(Icons.image_outlined, size: 18),
            Icon(Icons.lyrics_outlined, size: 18),
          ],
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'pip') NativeBridge.enterPip();
            if (v == 'yt') launchUrl(watch, mode: LaunchMode.externalApplication);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'pip', child: Text('Floating window (keeps playing)')),
            PopupMenuItem(value: 'yt', child: Text('Open in YouTube')),
          ],
        ),
      ],
    );
  }

  Widget _titleRow() {
    final cur = _cur;
    final id = cur.videoId!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cur.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(cur.creator,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: PlaylistStore.instance,
            builder: (context, _) {
              final fav = PlaylistStore.instance.isFav(id);
              return IconButton(
                tooltip: 'Favourite',
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                    color: fav ? Colors.redAccent : null),
                onPressed: () => PlaylistStore.instance.toggleFav(id),
              );
            },
          ),
          IconButton(
            tooltip: 'Add to playlist',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showAddToPlaylist(context, id),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_view) {
      case _View.video:
        return _fullList();
      case _View.poster:
        return _poster();
      case _View.lyrics:
        return _lyricsView();
    }
  }

  Widget _poster() {
    return LayoutBuilder(
      builder: (context, c) {
        final size = max(80.0, min(c.maxHeight - 8, c.maxWidth - 64));
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: size,
              height: size,
              child: _cur.thumb == null
                  ? Container(color: Colors.white10)
                  : Image.network(_cur.thumb!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
            ),
          ),
        );
      },
    );
  }

  Widget _lyricsView() {
    if (_lyricsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final l = _lyrics;
    if (l == null || l.lines.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No lyrics found for this song.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    const h = 44.0;
    return ValueListenableBuilder<double>(
      valueListenable: _pos,
      builder: (context, p, _) {
        var cur = -1;
        if (l.synced) {
          for (var k = 0; k < l.lines.length; k++) {
            if (l.lines[k].ms <= p * 1000) {
              cur = k;
            } else {
              break;
            }
          }
          if (cur != _lastCur) {
            _lastCur = cur;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_lyricScroll.hasClients || cur < 0) return;
              final to = max(0.0, cur * h - 70);
              _lyricScroll.animateTo(
                min(to, _lyricScroll.position.maxScrollExtent),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            });
          }
        }
        return ListView.builder(
          controller: _lyricScroll,
          itemExtent: h,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: l.lines.length,
          itemBuilder: (context, k) {
            final on = k == cur;
            return InkWell(
              onTap: l.synced ? () => _seek(l.lines[k].ms / 1000) : null,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.lines[k].text.isEmpty ? '♪' : l.lines[k].text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: on ? 19 : 16,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _controls() {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _pos,
            builder: (context, p, _) => ValueListenableBuilder<double>(
              valueListenable: _dur,
              builder: (context, d, _) {
                final max0 = d > 0 ? d : 1.0;
                final v = (_drag ?? p).clamp(0.0, max0).toDouble();
                return Row(
                  children: [
                    SizedBox(
                        width: 40,
                        child: Text(_fmt(v),
                            style: const TextStyle(fontSize: 11, color: Colors.white54))),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: v,
                          max: max0,
                          onChanged: (x) => setState(() => _drag = x),
                          onChangeEnd: (x) {
                            _seek(x);
                            setState(() => _drag = null);
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                        width: 40,
                        child: Text(_fmt(d),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11, color: Colors.white54))),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Shuffle',
                icon: Icon(Icons.shuffle, color: _shuffle ? primary : Colors.white54),
                onPressed: () => setState(() => _shuffle = !_shuffle),
              ),
              IconButton(
                iconSize: 34,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _prev,
              ),
              IconButton.filled(
                iconSize: 34,
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: _toggle,
              ),
              IconButton(
                iconSize: 34,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: () => _next(),
              ),
              IconButton(
                tooltip: 'Repeat',
                icon: Icon(
                  _repeat == 2 ? Icons.repeat_one : Icons.repeat,
                  color: _repeat == 0 ? Colors.white54 : primary,
                ),
                onPressed: () => setState(() => _repeat = (_repeat + 1) % 3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<int> _upIdx() => <int>[for (var k = _i + 1; k < widget.queue.length; k++) k];

  Widget _tile(int k) {
    final m = widget.queue[k];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () => _go(k),
      leading: _thumb(m, 52, 52),
      title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [m.creator, if (m.durationSec > 0) _fmt(m.durationSec.toDouble())].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
    );
  }

  Widget _fullList() {
    final up = _upIdx();
    if (up.isEmpty) {
      return const Center(
        child: Text('End of the list.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Up next',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        for (final k in up) _tile(k),
      ],
    );
  }

  Widget _card(int k) {
    final m = widget.queue[k];
    return InkWell(
      onTap: () => _go(k),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              child: SizedBox(
                width: 72,
                height: 72,
                child: m.thumb == null
                    ? Container(color: Colors.white10)
                    : Image.network(m.thumb!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    Text(m.creator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upNext() {
    final up = _upIdx();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _listOpen = !_listOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Text('Up next',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${up.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Spacer(),
                Icon(_listOpen ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        if (up.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('End of the list.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else if (_listOpen)
          SizedBox(
            height: 230,
            child: ListView(children: [for (final k in up) _tile(k)]),
          )
        else
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: up.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, n) => _card(up[n]),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _below() {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _titleRow(),
          Expanded(child: _content()),
          _controls(),
          if (_view != _View.video) _upNext(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final land = c.maxWidth > c.maxHeight;
        final web = WebViewWidget(key: _webKey, controller: _c);
        // YouTube requires the player to be at least 200 x 200 px.
        final playerH = max(200.0, c.maxWidth * 9 / 16);
        return Scaffold(
          appBar: land ? null : _appBar(),
          body: land
              ? ColoredBox(color: Colors.black, child: web)
              : Column(
                  children: [
                    SizedBox(height: playerH, child: web),
                    Expanded(child: _below()),
                  ],
                ),
        );
      },
    );
  }
}
