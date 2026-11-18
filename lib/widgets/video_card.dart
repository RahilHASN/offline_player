import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/library_store.dart';
import '../services/preview_controller.dart';
import '../services/thumbnail_service.dart';
import '../utils/format.dart';

enum Videaimport 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/library_store.dart';
import '../services/preview_controller.dart';
import '../services/thumbnail_service.dart';
import '../utils/format.dart';

enum VideoAction { play, favorite, tags, rename, copy, cut }

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onOpen;
  final void Function(VideoAction) onAction;
  const VideoCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  ThumbHandle? _handle;
  File? _thumb;
  Duration? _duration;
  Timer? _hoverTimer;
  final GlobalKey<PopupMenuButtonState<VideoAction>> _menuKey =
      GlobalKey<PopupMenuButtonState<VideoAction>>();

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
    final settings = AppSettings.instance;
    final store = LibraryStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store]),
      builder: (context, _) => _buildCard(settings, store),
    );
  }

  Widget _buildCard(AppSettings settings, LibraryStore store) {
    final item = widget.item;
    final shownDuration =
        _duration ?? ThumbnailService.instance.durations[item.id] ?? item.duration;
    final fav = store.isFav(item.path);
    final tags = store.tagsFor(item.path);
    final sub = StringBuffer(formatSize(item.sizeBytes));
    if (tags.isNotEmpty) {
      sub.write('  ·  ${tags.map((t) => '#$t').join(' ')}');
    }

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
                if (!settings.largePreview)
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
                                child: CutBar(cut: s.cut, total: s.total),
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
                if (item.path.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => store.toggleFav(item.path),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          fav ? Icons.favorite : Icons.favorite_border,
                          size: 20,
                          color: fav ? Colors.redAccent : Colors.white70,
                        ),
                      ),
                    ),
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
              padding: const EdgeInsets.only(left: 8, top: 6, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                          sub.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<VideoAction>(
                    key: _menuKey,
                    tooltip: 'More',
                    onSelected: widget.onAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: VideoAction.play,
                        child: Text('Play'),
                      ),
                      PopupMenuItem(
                        value: VideoAction.favorite,
                        child: Text(fav
                            ? 'Remove from favorites'
                            : 'Add to favorites'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.tags,
                        child: Text('Tags...'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: VideoAction.rename,
                        child: Text('Rename'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.copy,
                        child: Text('Copy'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.cut,
                        child: Text('Cut'),
                      ),
                    ],
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.more_vert, size: 20),
                    ),
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
      onSecondaryTap: _isWindows
          ? () => _menuKey.currentState?.showButtonMenu()
          : null,
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

class CutBar extends StatelessWidget {
  final int cut;
  final int total;
  const CutBar({super.key, required this.cut, required this.total});

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
}oAction { play, favorite, tags, rename, copy, cut }

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onOpen;
  final void Function(VideoAction) onAction;
  const VideoCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  ThumbHandle? _handle;
  File? _thumb;
  Duration? _duration;
  Timer? _hoverTimer;
  final GlobalKey<PopupMenuButtonState<VideoAction>> _menuKey =
      GlobalKey<PopupMenuButtonState<VideoAction>>();

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
    final settings = AppSettings.instance;
    final store = LibraryStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store]),
      builder: (context, _) => _buildCard(settings, store),
    );
  }

  Widget _buildCard(AppSettings settings, LibraryStore store) {
    final item = widget.item;
    final shownDuration =
        _duration ?? ThumbnailService.instance.durations[item.id] ?? item.duration;
    final fav = store.isFav(item.path);
    final tags = store.tagsFor(item.path);
    final sub = StringBuffer(formatSize(item.sizeBytes));
    if (tags.isNotEmpty) {
      sub.write('  ·  ${tags.map((t) => '#$t').join(' ')}');
    }

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
                if (!settings.largePreview)
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
                                child: CutBar(cut: s.cut, total: s.total),
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
                if (item.path.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => store.toggleFav(item.path),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          fav ? Icons.favorite : Icons.favorite_border,
                          size: 20,
                          color: fav ? Colors.redAccent : Colors.white70,
                        ),
                      ),
                    ),
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
              padding: const EdgeInsets.only(left: 8, top: 6, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                          sub.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<VideoAction>(
                    key: _menuKey,
                    tooltip: 'More',
                    onSelected: widget.onAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: VideoAction.play,
                        child: Text('Play'),
                      ),
                      PopupMenuItem(
                        value: VideoAction.favorite,
                        child: Text(fav
                            ? 'Remove from favorites'
                            : 'Add to favorites'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.tags,
                        child: Text('Tags...'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: VideoAction.rename,
                        child: Text('Rename'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.copy,
                        child: Text('Copy'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.cut,
                        child: Text('Cut'),
                      ),
                    ],
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.more_vert, size: 20),
                    ),
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
      onSecondaryTap: _isWindows
          ? () => _menuKey.currentState?.showButtonMenu()
          : null,
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

class CutBar extends StatelessWidget {
  final int cut;
  final int total;
  const CutBar({super.key, required this.cut, required this.total});

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
