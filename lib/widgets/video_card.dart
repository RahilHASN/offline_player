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

enum VideoAction {
  play,
  favorite,
  tags,
  playlists,
  bookmarks,
  select,
  rename,
  moveTo,
  copyTo,
  vault,
  delete,
}

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onOpen;
  final void Function(VideoAction) onAction;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;
  const VideoCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
    required this.onToggleSelect,
    this.selecting = false,
    this.selected = false,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  static const _hoverDelay = Duration(milliseconds: 700);

  ThumbHandle? _handle;
  File? _thumb;
  Duration? _duration;
  Timer? _hoverTimer;
  Timer? _retryTimer;
  int _retries = 0;
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
      _retryTimer?.cancel();
      _retries = 0;
      _thumb = null;
      _duration = null;
      _load();
    }
  }

  @override
  void dispose() {
    _handle?.cancel();
    _hoverTimer?.cancel();
    _retryTimer?.cancel();
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
      if (r == null) {
        if (_retries < 2) {
          _retries++;
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) _load();
          });
        }
        return;
      }
      setState(() {
        _thumb = r.file;
        _duration = r.duration;
      });
    });
  }

  void _startPreview() {
    if (widget.selecting) return;
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
    final key = item.key;
    final selecting = widget.selecting;
    final selected = widget.selected;
    final primary = Theme.of(context).colorScheme.primary;
    final shownDuration =
        _duration ?? ThumbnailService.instance.durations[item.id] ?? item.duration;
    final fav = store.isFav(key);
    final hidden = store.isHidden(key);
    final tags = store.tagsFor(key);
    final prog = store.progressFor(key);
    final frac = prog?.fraction ?? 0.0;
    final sub = StringBuffer(formatSize(item.sizeBytes));
    if (tags.isNotEmpty) {
      sub.write('  ·  ${tags.map((t) => '#$t').join(' ')}');
    }

    Widget thumbnail = AspectRatio(
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
          if (frac > 0.02 && frac < 0.97)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 3,
                backgroundColor: Colors.black38,
                color: Colors.redAccent,
              ),
            ),
          if (!settings.largePreview && !selecting)
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
                            fit: s.aspect < 1 ? BoxFit.contain : BoxFit.cover,
                            fill: Colors.black,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PreviewBar(state: s),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (selected)
            const Positioned.fill(
              child: ColoredBox(color: Color(0x553F51B5)),
            ),
          if (selecting)
            Positioned(
              left: 6,
              top: 6,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 26,
                color: selected ? primary : Colors.white70,
              ),
            )
          else
            Positioned(
              left: 6,
              top: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Badge(text: item.source.label),
                  if (hidden)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock, size: 16, color: Colors.amber),
                    ),
                ],
              ),
            ),
          if (item.path.isNotEmpty && !selecting)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => store.toggleFav(key),
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
    );

    // Windows: hover works on the picture only, so the ⋮ button stays usable.
    if (_isWindows) {
      thumbnail = MouseRegion(
        onEnter: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = Timer(_hoverDelay, _startPreview);
        },
        onExit: (_) => _stopPreview(),
        child: thumbnail,
      );
    }

    Widget card = Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: primary, width: 2.5)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          thumbnail,
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
                    enabled: !selecting,
                    onOpened: _stopPreview,
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
                      const PopupMenuItem(
                        value: VideoAction.playlists,
                        child: Text('Playlists...'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.bookmarks,
                        child: Text('Bookmarks...'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.select,
                        child: Text('Select'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: VideoAction.rename,
                        child: Text('Rename'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.moveTo,
                        child: Text('Move to...'),
                      ),
                      const PopupMenuItem(
                        value: VideoAction.copyTo,
                        child: Text('Copy to...'),
                      ),
                      PopupMenuItem(
                        value: VideoAction.vault,
                        child: Text(
                            hidden ? 'Remove from vault' : 'Move to vault'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: VideoAction.delete,
                        child: Text('Delete (to trash)'),
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
      onTap: selecting ? widget.onToggleSelect : _open,
      onSecondaryTap: (_isWindows && !selecting)
          ? () => _menuKey.currentState?.showButtonMenu()
          : null,
      onLongPressStart: (_isAndroid && !selecting) ? (_) => _startPreview() : null,
      onLongPressEnd: (_isAndroid && !selecting) ? (_) => _stopPreview() : null,
      onLongPressCancel: (_isAndroid && !selecting) ? _stopPreview : null,
      child: card,
    );

    return card;
  }
}

/// Animates smoothly across the whole preview. Restarts on every cut.
class PreviewProgress extends StatelessWidget {
  final PreviewState state;
  final Widget Function(BuildContext context, double value) builder;
  const PreviewProgress({
    super.key,
    required this.state,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final total = state.total;
    if (total <= 0) return builder(context, 0);
    final from = state.cut / total;
    final to = (state.cut + 1) / total;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(state.seq),
      tween: Tween<double>(begin: from, end: to),
      duration: Duration(milliseconds: state.clipMs < 1 ? 1 : state.clipMs),
      curve: Curves.linear,
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// Thin smooth bar along the bottom of the preview.
class PreviewBar extends StatelessWidget {
  final PreviewState state;
  const PreviewBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return PreviewProgress(
      state: state,
      builder: (context, v) => LinearProgressIndicator(
        value: v,
        minHeight: 3,
        backgroundColor: Colors.white24,
      ),
    );
  }
}

/// Small circle for the top-right corner of the large preview.
class PreviewRing extends StatelessWidget {
  final PreviewState state;
  const PreviewRing({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(5),
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: PreviewProgress(
        state: state,
        builder: (context, v) => CircularProgressIndicator(
          value: v,
          strokeWidth: 3,
          backgroundColor: Colors.white24,
        ),
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
