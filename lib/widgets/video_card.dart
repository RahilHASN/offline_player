import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/preview_controller.dart';
import '../services/thumbnail_service.dart';
import '../utils/format.dart';

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onOpen;
  const VideoCard({super.key, required this.item, required this.onOpen});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  ThumbHandle? _handle;
  File? _thumb;
  Duration? _duration;
  Timer? _hoverTimer;

  bool get _isWindows => Platform.isWindows;
  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _handle?.cancel();
      _thumb = null;
      _duration = null;
      _load();
    }
  }

  @override
  void dispose() {
    _handle?.cancel();
    _hoverTimer?.cancel();
    final id = widget.item.id;
    Future.microtask(() {
      final pc = PreviewController.instance;
      if (pc.state.value.id == id) pc.stop();
    });
    super.dispose();
  }

  void _load() {
    final h = ThumbnailService.instance.request(widget.item);
    _handle = h;
    h.future.then((r) {
      if (!mounted || _handle != h) return;
      setState(() {
        _thumb = r?.file;
        _duration = r?.duration;
      });
    });
  }

  void _startPreview() {
    PreviewController.instance.start(widget.item);
  }

  void _stopPreview() {
    _hoverTimer?.cancel();
    final pc = PreviewController.instance;
    if (pc.state.value.id == widget.item.id) pc.stop();
  }

  void _open() {
    _stopPreview();
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final shownDuration =
        _duration ?? ThumbnailService.instance.durations[item.id] ?? item.duration;

    Widget card = Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFF1E1E2A),
                  child: const Icon(
                    Icons.movie_outlined,
                    size: 36,
                    color: Colors.white24,
                  ),
                ),
                if (_thumb != null)
                  Image.file(
                    _thumb!,
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                Positioned.fill(
                  child: ValueListenableBuilder<PreviewState>(
                    valueListenable: PreviewController.instance.state,
                    builder: (context, s, _) {
                      if (s.id != item.id || s.video == null) {
                        return const SizedBox.shrink();
                      }
                      return IgnorePointer(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedOpacity(
                              opacity: s.ready ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Video(
                                controller: s.video!,
                                controls: NoVideoControls,
                                fit: BoxFit.cover,
                                fill: Colors.black,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _CutBar(cut: s.cut, total: s.total),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: _Badge(text: item.source.label),
                ),
                Positioned(
                  right: 6,
                  bottom: 8,
                  child: _Badge(text: formatDuration(shownDuration)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    formatSize(item.sizeBytes),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    card = GestureDetector(
      onTap: _open,
      onLongPressStart: _isAndroid ? (_) => _startPreview() : null,
      onLongPressEnd: _isAndroid ? (_) => _stopPreview() : null,
      onLongPressCancel: _isAndroid ? _stopPreview : null,
      child: card,
    );

    if (_isWindows) {
      card = MouseRegion(
        onEnter: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = Timer(const Duration(milliseconds: 250), _startPreview);
        },
        onExit: (_) => _stopPreview(),
        child: card,
      );
    }
    return card;
  }
}

class _CutBar extends StatelessWidget {
  final int cut;
  final int total;
  const _CutBar({required this.cut, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox(height: 3);
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 3,
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: i <= cut ? color : Colors.white30,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
