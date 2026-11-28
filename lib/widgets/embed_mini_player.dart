import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../bridge/embed_session.dart';

/// The official player in a floating 200 x 200 window. It stays on screen
/// while you browse the app. Drag the title bar to move it. Tap the expand
/// button for the full player. Nothing is drawn over the video itself.
class EmbedMiniPlayer extends StatefulWidget {
  const EmbedMiniPlayer({super.key});

  @override
  State<EmbedMiniPlayer> createState() => _EmbedMiniPlayerState();
}

class _EmbedMiniPlayerState extends State<EmbedMiniPlayer> {
  static const double _w = 200; // YouTube's minimum player size
  static const double _bar = 38;
  Offset? _at;

  @override
  Widget build(BuildContext context) {
    final s = EmbedSession.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!s.active || s.screenOpen) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);
        const total = _w + _bar;
        final at = _at ??
            Offset(size.width - _w - 12, size.height - total - pad.bottom - 150);
        final maxX = size.width - _w;
        final maxY = size.height - total - pad.bottom;
        final x = at.dx.clamp(0.0, maxX < 0 ? 0.0 : maxX).toDouble();
        final y = at.dy.clamp(pad.top, maxY < pad.top ? pad.top : maxY).toDouble();

        return Positioned(
          left: x,
          top: y,
          width: _w,
          height: total,
          child: Material(
            color: Colors.black,
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => setState(() => _at = Offset(x, y) + d.delta),
                  child: SizedBox(
                    height: _bar,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.cur.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        _btn(s.playing ? Icons.pause : Icons.play_arrow, s.toggle),
                        _btn(Icons.open_in_full, s.openFull),
                        _btn(Icons.close, s.stop),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _w,
                  height: _w,
                  child: WebViewWidget(controller: s.controller!),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        visualDensity: VisualDensity.compact,
      );
}
