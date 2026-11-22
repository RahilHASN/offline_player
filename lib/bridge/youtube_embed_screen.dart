import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'handoff.dart';

/// YouTube's official embedded player inside a WebView.
/// The player stays visible. There is no audio-only or background mode.
class YouTubeEmbedScreen extends StatefulWidget {
  final EmbedHandoff handoff;
  final String title;
  const YouTubeEmbedScreen({super.key, required this.handoff, required this.title});

  @override
  State<YouTubeEmbedScreen> createState() => _YouTubeEmbedScreenState();
}

class _YouTubeEmbedScreenState extends State<YouTubeEmbedScreen> {
  static const _base = 'https://www.youtube.com/';
  late final WebViewController _c;

  @override
  void initState() {
    super.initState();
    final embed = widget.handoff.embedUrl.toString();
    final html = '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000}'
        'iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>'
        '</head><body><iframe src="$embed" title="YouTube video player" '
        'allow="accelerometer; encrypted-media; gyroscope; picture-in-picture" '
        'allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>'
        '</body></html>';
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!r.isMainFrame) return NavigationDecision.navigate;
          final u = r.url;
          if (u.startsWith('about:') ||
              u.startsWith('data:') ||
              u == _base ||
              u.startsWith('https://www.youtube.com/embed/')) {
            return NavigationDecision.navigate;
          }
          final uri = Uri.tryParse(u);
          if (uri != null && uri.scheme == 'https') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadHtmlString(html, baseUrl: _base);
  }

  @override
  void dispose() {
    try {
      _c.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watch = Uri.https('www.youtube.com', '/watch', {'v': widget.handoff.videoId});
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(watch, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _c)),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              "Playing in YouTube's official player. Ads and controls are YouTube's. "
              'Audio-only and background playback are not available for YouTube.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
