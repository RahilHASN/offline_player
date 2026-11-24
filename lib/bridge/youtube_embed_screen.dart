import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../widgets/youtube_badge.dart';
import 'compliance.dart';
import 'handoff.dart';
import 'provider.dart';
import 'youtube_history.dart';

/// YouTube's official player (IFrame Player API) inside a WebView.
/// The player stays visible. There is no audio-only or background mode.
/// Songs advance with the player's own "ended" event.
class YouTubeEmbedScreen extends StatefulWidget {
  final List<MediaItem> queue;
  final int index;
  const YouTubeEmbedScreen({super.key, required this.queue, required this.index});

  @override
  State<YouTubeEmbedScreen> createState() => _YouTubeEmbedScreenState();
}

class _YouTubeEmbedScreenState extends State<YouTubeEmbedScreen> {
  static const _base = 'https://com.example.offlineplayer/';
  late final WebViewController _c;
  late int _i = widget.index;

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
      'playerVars:{playsinline:1,rel:0,autoplay:1,origin:"https://com.example.offlineplayer"},'
      'events:{onStateChange:function(e){if(e.data===0){Bridge.postMessage("ended");}},'
      'onError:function(e){Bridge.postMessage("error:"+e.data);}}});}'
      'function loadVideo(v){if(player&&player.loadVideoById){player.loadVideoById(v);}}'
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
    try {
      _c.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  void _onMsg(String m) {
    if (!mounted) return;
    if (m == 'ended') {
      if (_i + 1 < widget.queue.length) _go(_i + 1);
    } else if (m.startsWith('error')) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("YouTube can't play this one here. Skipping.")));
      if (_i + 1 < widget.queue.length) _go(_i + 1);
    }
  }

  void _go(int i) {
    if (i < 0 || i >= widget.queue.length) return;
    final id = widget.queue[i].videoId;
    if (id == null || !Compliance.validVideoId(id)) return;
    try {
      Compliance.assertHandoff(EmbedHandoff(providerId: 'youtube', videoId: id));
    } on ComplianceError {
      return;
    }
    setState(() => _i = i);
    YouTubeHistory.instance.add(widget.queue[i]);
    _c.runJavaScript("loadVideo('$id')");
  }

  String _fmt(int s) {
    final r = s % 60;
    return '${s ~/ 60}:${r.toString().padLeft(2, '0')}';
  }

  Widget _info() {
    final cur = _cur;
    final upNext = <int>[
      for (var k = _i + 1; k < widget.queue.length; k++) k,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(cur.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(cur.creator,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              onPressed: _i > 0 ? () => _go(_i - 1) : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            const SizedBox(width: 24),
            IconButton(
              iconSize: 36,
              onPressed:
                  _i + 1 < widget.queue.length ? () => _go(_i + 1) : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        if (upNext.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Up next',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          for (final k in upNext)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _go(k),
              leading: SizedBox(
                width: 52,
                height: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: widget.queue[k].thumb == null
                      ? Container(color: Colors.white10)
                      : Image.network(widget.queue[k].thumb!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Colors.white10)),
                ),
              ),
              title: Text(widget.queue[k].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  widget.queue[k].creator,
                  if (widget.queue[k].durationSec > 0)
                    _fmt(widget.queue[k].durationSec),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text(
          "Playing in YouTube's official player. Ads and controls are YouTube's. "
          'Audio-only and background playback are not available for YouTube.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final watch = Uri.https('www.youtube.com', '/watch', {'v': _cur.videoId!});
    final web = WebViewWidget(controller: _c);
    return Scaffold(
      appBar: AppBar(
        title: const YouTubeBadge(size: 17),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(watch, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, o) {
          if (o == Orientation.landscape) {
            return ColoredBox(color: Colors.black, child: web);
          }
          return Column(
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: web),
              Expanded(child: _info()),
            ],
          );
        },
      ),
    );
  }
}
