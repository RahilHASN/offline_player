import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/thumbnail_service.dart';
import '../utils/format.dart';

class VideoCard extends StatefulWidget {
  final VideoItem item;
  const VideoCard({super.key, required this.item});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  ThumbHandle? _handle;
  File? _thumb;
  Duration? _duration;

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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final shownDuration =
        _duration ?? ThumbnailService.instance.durations[item.id] ?? item.duration;

    return Card(
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
                Positioned(
                  left: 6,
                  top: 6,
                  child: _Badge(text: item.source.label),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
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
