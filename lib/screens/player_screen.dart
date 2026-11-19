import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/library_store.dart';
import '../services/native_bridge.dart';
import '../services/seek_previewer.dart';
import '../utils/format.dart';
import '../widgets/library_sheets.dart';

/// Software brightness: 1.0 = normal, lower = darker.
final ValueNotifier<double> _brightness = ValueNotifier<double>(1.0);

class PlayerScreen extends StatefulWidget {
  final List<VideoItem> queue;
  final int index;
  final int? startMs;
  const PlayerScreen({
    super.key,
    required this.queue,
    required this.index,
    this.startMs,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  late int _index = widget.index;
  late SeekPreviewer _previewer =
      SeekPreviewer(widget.queue[widget.index].path);
  final ValueNotifier<bool> _lock = ValueNotifier<bool>(false);
  StreamSubscription<String>? _errSub;
  StreamSubscription<bool>? _doneSub;
  Timer? _saveTimer;
  String? _error;

  VideoItem get _cur => widget.queue[_index];

  @override
  void initState() {
    super.initState();
    _brightness.value = 1.0;
    _errSub = _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _doneSub = _player.stream.completed.listen((c) {
      if (c) _onDone();
    });
    _saveTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    if (AppSettings.instance.backgroundPlay) NativeBridge.keepAlive(true);
    _openCurrent(widget.startMs);
  }

  Future<void> _openCurrent(int? startMs) async {
    final item = _cur;
    _error = null;
    try {
      await _player.open(Media(item.path));
      int? at = startMs;
      if (at == null && AppSettings.instance.autoResume) {
        final pr = LibraryStore.instance.progressFor(item.key);
        if (pr != null && pr.pos > 5000 && pr.fraction < 0.95) at = pr.pos;
      }
      if (at != null) {
        if (_player.state.duration <= Duration.zero) {
          await _player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 6));
        }
        if (_cur.id != item.id) return;
        await _player.seek(Duration(milliseconds: at));
      }
      _autoSubtitle(item);
    } catch (_) {}
  }

  /// Loads a subtitle file that sits next to the video and has the same name.
  Future<void> _autoSubtitle(VideoItem item) async {
    try {
      final p = item.path;
      final dot = p.lastIndexOf('.');
      if (dot < 0) return;
      final base = p.substring(0, dot);
      for (final ext in const ['srt', 'ass', 'ssa', 'vtt']) {
        final f = File('$base.$ext');
        if (await f.exists()) {
          if (_cur.id != item.id) return;
          await _player.setSubtitleTrack(SubtitleTrack.uri(f.path));
          return;
        }
      }
    } catch (_) {}
  }

  void _saveProgress() {
    final d = _player.state.duration;
    final p = _player.state.position;
    if (d <= Duration.zero) return;
    LibraryStore.instance
        .setProgress(_cur.key, p.inMilliseconds, d.inMilliseconds);
  }

  void _onDone() {
    final d = _player.state.duration;
    if (d > Duration.zero) {
      LibraryStore.instance
          .setProgress(_cur.key, d.inMilliseconds, d.inMilliseconds);
    }
    if (AppSettings.instance.autoNext && _index + 1 < widget.queue.length) {
      _go(_index + 1);
    }
  }

  void _go(int i) {
    if (i < 0 || i >= widget.queue.length) return;
    _saveProgress();
    final old = _previewer;
    setState(() {
      _index = i;
      _previewer = SeekPreviewer(widget.queue[i].path);
    });
    old.dispose();
    _openCurrent(null);
  }

  @override
  void dispose() {
    _saveProgress();
    LibraryStore.instance.flush();
    _saveTimer?.cancel();
    _errSub?.cancel();
    _doneSub?.cancel();
    _previewer.dispose();
    _lock.dispose();
    NativeBridge.keepAlive(false);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _lock,
      builder: (context, locked, _) => PopScope(
        canPop: !locked,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: Video(
                  controller: _video,
                  controls: (state) => PlayerControls(
                    state: state,
                    player: _player,
                    previewer: _previewer,
                    item: _cur,
                    hasPrev: _index > 0,
                    hasNext: _index + 1 < widget.queue.length,
                    onPrev: () => _go(_index - 1),
                    onNext: () => _go(_index + 1),
                    lock: _lock,
                  ),
                ),
              ),
              if (_error != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 80,
                  child: Text(
                    'Playback problem: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerControls extends StatefulWidget {
  final VideoState state;
  final Player player;
  final SeekPreviewer previewer;
  final VideoItem item;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueNotifier<bool> lock;

  const PlayerControls({
    super.key,
    required this.state,
    required this.player,
    required this.previewer,
    required this.item,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.lock,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _visible = true;
  bool _dragging = false;
  double _dragValue = 0;
  Timer? _hideTimer;
  Offset _lastTap = Offset.zero;
  final FocusNode _focus = FocusNode();

  // swipe-to-seek
  Duration? _swipeTarget;
  Duration _swipeStart = Duration.zero;
  double _swipeDx = 0;

  // volume / brightness swipe
  String? _hudKind; // 'volume' or 'brightness'
  double _hudValue = 0;
  double _vValue = 0;
  Timer? _hudTimer;

  // A-B loop
  Duration? _a;
  Duration? _b;
  StreamSubscription<Duration>? _posSub;

  // hold for 2x
  bool _boost = false;
  double _prevRate = 1.0;

  // screen lock hint
  bool _lockHint = false;
  Timer? _lockTimer;

  // small message
  String? _toast;
  Timer? _toastTimer;

  Player get _p => widget.player;
  bool get _desktop => Platform.isWindows;
  bool get _locked => widget.lock.value;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    _posSub = _p.stream.position.listen((pos) {
      final a = _a;
      final b = _b;
      if (a != null && b != null && pos >= b) _p.seek(a);
    });
  }

  @override
  void didUpdateWidget(covariant PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _a = null;
      _b = null;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _lockTimer?.cancel();
    _toastTimer?.cancel();
    _posSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _flash(String m) {
    _toastTimer?.cancel();
    setState(() => _toast = m);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _p.state.playing && !_dragging) {
        setState(() => _visible = false);
      }
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _toggle() {
    if (_visible) {
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  void _seekBy(Duration delta) {
    final total = _p.state.duration;
    var t = _p.state.position + delta;
    if (t < Duration.zero) t = Duration.zero;
    if (total > Duration.zero && t > total) t = total;
    _p.seek(t);
    _show();
  }

  void _volumeBy(double d) {
    _p.setVolume((_p.state.volume + d).clamp(0.0, 100.0).toDouble());
  }

  void _toggleFullscreen() {
    widget.state.toggleFullscreen();
    _scheduleHide();
  }

  void _back() {
    if (widget.state.isFullscreen()) {
      widget.state.exitFullscreen();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ---- lock ----
  void _lockOn() {
    widget.lock.value = true;
    setState(() {
      _visible = false;
      _lockHint = false;
    });
  }

  void _unlock() {
    widget.lock.value = false;
    setState(() => _lockHint = false);
    _show();
  }

  void _showLockHint() {
    _lockTimer?.cancel();
    setState(() => _lockHint = true);
    _lockTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lockHint = false);
    });
  }

  // ---- A-B loop ----
  void _abPressed() {
    final pos = _p.state.position;
    if (_a == null) {
      setState(() => _a = pos);
      _flash('Loop start set. Tap again for the end.');
    } else if (_b == null) {
      if (pos > _a!) {
        setState(() => _b = pos);
        _flash('Looping A-B');
      } else {
        _flash('The end must be after the start');
      }
    } else {
      setState(() {
        _a = null;
        _b = null;
      });
      _flash('Loop off');
    }
  }

  // ---- bookmarks ----
  void _addBookmark() {
    LibraryStore.instance
        .addBookmark(widget.item.key, _p.state.position.inMilliseconds);
    _flash('Bookmark added');
  }

  void _showBookmarks() {
    showBookmarksSheet(
      context,
      widget.item,
      (ms) => _p.seek(Duration(milliseconds: ms)),
    );
  }

  // ---- picture in picture ----
  Future<void> _pip() async {
    setState(() => _visible = false);
    final ok = await NativeBridge.enterPip();
    if (!ok) _flash('Picture-in-picture is not available');
  }

  // ---- subtitles and audio ----
  String _trackName(String id, String? title, String? lang) {
    if (title != null && title.isNotEmpty && lang != null && lang.isNotEmpty) {
      return '$title ($lang)';
    }
    if (title != null && title.isNotEmpty) return title;
    if (lang != null && lang.isNotEmpty) return lang;
    return 'Track $id';
  }

  void _tracksSheet() {
    final tr = _p.state.tracks;
    final cur = _p.state.track;
    var selA = cur.audio.id;
    var selS = cur.subtitle.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Audio',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                for (final t in tr.audio)
                  if (t.id != 'auto' && t.id != 'no')
                    ListTile(
                      dense: true,
                      leading: Icon(selA == t.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(_trackName(t.id, t.title, t.language)),
                      onTap: () {
                        _p.setAudioTrack(t);
                        setS(() => selA = t.id);
                      },
                    ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Subtitles',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  dense: true,
                  leading: Icon(selS == 'no'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  title: const Text('Off'),
                  onTap: () {
                    _p.setSubtitleTrack(SubtitleTrack.no());
                    setS(() => selS = 'no');
                  },
                ),
                for (final t in tr.subtitle)
                  if (t.id != 'auto' && t.id != 'no')
                    ListTile(
                      dense: true,
                      leading: Icon(selS == t.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(_trackName(t.id, t.title, t.language)),
                      onTap: () {
                        _p.setSubtitleTrack(t);
                        setS(() => selS = t.id);
                      },
                    ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Load subtitle file...'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final r =
                        await FilePicker.platform.pickFiles(type: FileType.any);
                    if (r != null &&
                        r.files.isNotEmpty &&
                        r.files.first.path != null) {
                      await _p.setSubtitleTrack(
                          SubtitleTrack.uri(r.files.first.path!));
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- swipe left/right: seek ----
  void _hStart(DragStartDetails d) {
    _swipeStart = _p.state.position;
    _swipeDx = 0;
    _swipeTarget = _swipeStart;
  }

  void _hUpdate(DragUpdateDetails d) {
    final total = _p.state.duration;
    if (total <= Duration.zero) return;
    final w = context.size?.width ?? 400;
    _swipeDx += d.delta.dx;
    final span = min(total.inMilliseconds.toDouble(), 120000.0);
    final ms = (_swipeStart.inMilliseconds + _swipeDx / w * span)
        .clamp(0.0, total.inMilliseconds.toDouble())
        .toDouble();
    final t = Duration(milliseconds: ms.round());
    widget.previewer.request(t);
    setState(() => _swipeTarget = t);
  }

  void _hEnd([DragEndDetails? d]) {
    final t = _swipeTarget;
    if (t != null) _p.seek(t);
    setState(() => _swipeTarget = null);
  }

  // ---- swipe up/down: volume (left) / brightness (right) ----
  void _vStart(DragStartDetails d) {
    final w = context.size?.width ?? 400;
    _hudTimer?.cancel();
    _hudKind = d.localPosition.dx < w / 2 ? 'volume' : 'brightness';
    _vValue = _hudKind == 'volume'
        ? (_p.state.volume / 100).clamp(0.0, 1.0).toDouble()
        : _brightness.value;
    setState(() => _hudValue = _vValue);
  }

  void _vUpdate(DragUpdateDetails d) {
    final h = context.size?.height ?? 600;
    _vValue = (_vValue - d.delta.dy / (h * 0.7)).clamp(0.0, 1.0).toDouble();
    if (_hudKind == 'volume') {
      _p.setVolume(_vValue * 100);
    } else {
      _brightness.value = max(0.15, _vValue);
    }
    setState(() => _hudValue = _vValue);
  }

  void _vEnd([DragEndDetails? d]) {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hudKind = null);
    });
  }

  // ---- hold for 2x ----
  void _boostStart() {
    _prevRate = _p.state.rate;
    _p.setRate(2.0);
    setState(() => _boost = true);
  }

  void _boostEnd() {
    if (!_boost) return;
    _p.setRate(_prevRate);
    setState(() => _boost = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_locked) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      _p.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 5));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -5));
    } else if (k == LogicalKeyboardKey.keyL) {
      _seekBy(const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.keyJ) {
      _seekBy(const Duration(seconds: -10));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _volumeBy(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _volumeBy(-5);
    } else if (k == LogicalKeyboardKey.keyM) {
      _p.setVolume(_p.state.volume > 0 ? 0 : 100);
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyN) {
      if (widget.hasNext) widget.onNext();
    } else if (k == LogicalKeyboardKey.keyP) {
      if (widget.hasPrev) widget.onPrev();
    } else if (k == LogicalKeyboardKey.keyB) {
      _addBookmark();
    } else if (k == LogicalKeyboardKey.escape) {
      if (widget.state.isFullscreen()) widget.state.exitFullscreen();
    } else if (k == LogicalKeyboardKey.bracketRight) {
      _p.setRate((_p.state.rate + 0.25).clamp(0.25, 4.0).toDouble());
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      _p.setRate((_p.state.rate - 0.25).clamp(0.25, 4.0).toDouble());
    } else {
      return KeyEventResult.ignored;
    }
    _show();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final locked = _locked;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onHover: (_) {
            if (locked) return;
            if (!_visible) {
              _show();
            } else {
              _scheduleHide();
            }
          },
          child: Stack(
            children: [
              // brightness dimmer
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _brightness,
                    builder: (context, b, _) {
                      final op = (1 - b).clamp(0.0, 0.85).toDouble();
                      return ColoredBox(color: Color.fromRGBO(0, 0, 0, op));
                    },
                  ),
                ),
              ),
              // gestures
              Positioned.fill(
                child: locked
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showLockHint,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggle,
                        onDoubleTapDown: (d) => _lastTap = d.localPosition,
                        onDoubleTap: () {
                          if (_desktop) {
                            _toggleFullscreen();
                          } else {
                            final w = context.size?.width ?? 0;
                            _seekBy(_lastTap.dx < w / 2
                                ? const Duration(seconds: -10)
                                : const Duration(seconds: 10));
                          }
                        },
                        onLongPressStart: _desktop ? null : (_) => _boostStart(),
                        onLongPressEnd: _desktop ? null : (_) => _boostEnd(),
                        onLongPressCancel: _desktop ? null : _boostEnd,
                        onHorizontalDragStart: _desktop ? null : _hStart,
                        onHorizontalDragUpdate: _desktop ? null : _hUpdate,
                        onHorizontalDragEnd: _desktop ? null : _hEnd,
                        onHorizontalDragCancel: _desktop ? null : _hEnd,
                        onVerticalDragStart: _desktop ? null : _vStart,
                        onVerticalDragUpdate: _desktop ? null : _vUpdate,
                        onVerticalDragEnd: _desktop ? null : _vEnd,
                        onVerticalDragCancel: _desktop ? null : _vEnd,
                      ),
              ),
              // controls
              if (!locked)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_visible,
                    child: AnimatedOpacity(
                      opacity: _visible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: SafeArea(child: _overlay()),
                    ),
                  ),
                ),
              // unlock button
              if (locked && _lockHint)
                Positioned(
                  left: 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      iconSize: 30,
                      icon: const Icon(Icons.lock),
                      tooltip: 'Unlock',
                      onPressed: _unlock,
                    ),
                  ),
                ),
              // swipe-seek preview
              if (_swipeTarget != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: _PreviewBox(
                        previewer: widget.previewer,
                        label: _swipeLabel(),
                      ),
                    ),
                  ),
                ),
              // volume / brightness indicator
              if (_hudKind != null)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Center(child: _hud())),
                ),
              // 2x indicator
              if (_boost)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(child: _pill('2x  ▶▶')),
                  ),
                ),
              // short message
              if (_toast != null)
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Center(child: _pill(_toast!))),
                ),
              // slider-drag preview
              if (_dragging && !locked) _sliderPreview(screenW),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }

  String _swipeLabel() {
    final t = _swipeTarget ?? Duration.zero;
    final diff = t - _swipeStart;
    final sign = diff.isNegative ? '-' : '+';
    return '${formatDuration(t)}  ($sign${diff.inSeconds.abs()}s)';
  }

  Widget _hud() {
    final isVol = _hudKind == 'volume';
    IconData icon;
    if (isVol) {
      icon = _hudValue <= 0 ? Icons.volume_off : Icons.volume_up;
    } else {
      icon = Icons.brightness_6;
    }
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _hudValue, minHeight: 6),
            ),
          ),
          const SizedBox(width: 10),
          Text('${(_hudValue * 100).round()}',
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sliderPreview(double screenW) {
    final total = _p.state.duration.inMilliseconds.toDouble();
    final frac = total > 0 ? (_dragValue / total).clamp(0.0, 1.0) : 0.0;
    final x = (60 + frac * (screenW - 120)).clamp(96.0, screenW - 96).toDouble();
    return Positioned(
      left: x - 88,
      bottom: 130,
      child: IgnorePointer(
        child: _PreviewBox(
          previewer: widget.previewer,
          label: formatDuration(Duration(milliseconds: _dragValue.round())),
        ),
      ),
    );
  }

  Widget _ib(IconData icon, String tip, VoidCallback? onTap, {Color? color}) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 22, color: color),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _overlay() {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              ),
              Expanded(
                child: Text(
                  widget.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.hasPrev)
                  IconButton(
                    iconSize: 34,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: widget.onPrev,
                  ),
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 6),
                StreamBuilder<bool>(
                  stream: _p.stream.playing,
                  initialData: _p.state.playing,
                  builder: (context, s) {
                    final playing = s.data ?? false;
                    return IconButton(
                      iconSize: 64,
                      icon: Icon(playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill),
                      onPressed: () {
                        _p.playOrPause();
                        _scheduleHide();
                      },
                    );
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                ),
                if (widget.hasNext)
                  IconButton(
                    iconSize: 34,
                    icon: const Icon(Icons.skip_next),
                    onPressed: widget.onNext,
                  ),
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seekBar(),
              _buttonRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: _p.stream.duration,
      initialData: _p.state.duration,
      builder: (context, ds) {
        final total = ds.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _p.stream.position,
          initialData: _p.state.position,
          builder: (context, ps) {
            final pos = ps.data ?? Duration.zero;
            final max = total.inMilliseconds.toDouble();
            final cur = _dragging ? _dragValue : pos.inMilliseconds.toDouble();
            final value = max > 0 ? cur.clamp(0.0, max).toDouble() : 0.0;
            return Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    formatDuration(Duration(milliseconds: value.round())),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: value,
                      min: 0,
                      max: max > 0 ? max : 1,
                      onChangeStart: (v) {
                        _hideTimer?.cancel();
                        widget.previewer
                            .request(Duration(milliseconds: v.round()));
                        setState(() {
                          _dragging = true;
                          _dragValue = v;
                        });
                      },
                      onChanged: (v) {
                        widget.previewer
                            .request(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = v);
                      },
                      onChangeEnd: (v) {
                        _p.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragging = false);
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    formatDuration(total),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buttonRow() {
    final primary = Theme.of(context).colorScheme.primary;
    final abOn = _a != null;
    return Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_desktop)
              StreamBuilder<double>(
                stream: _p.stream.volume,
                initialData: _p.state.volume,
                builder: (context, s) {
                  final vol = (s.data ?? 100).clamp(0.0, 100.0).toDouble();
                  return Row(
                    children: [
                      _ib(vol <= 0 ? Icons.volume_off : Icons.volume_up,
                          'Mute', () => _p.setVolume(vol > 0 ? 0 : 100)),
                      SizedBox(
                        width: 100,
                        child: Slider(
                          value: vol,
                          min: 0,
                          max: 100,
                          onChanged: (v) => _p.setVolume(v),
                        ),
                      ),
                    ],
                  );
                },
              ),
            StreamBuilder<double>(
              stream: _p.stream.rate,
              initialData: _p.state.rate,
              builder: (context, s) {
                final rate = s.data ?? 1.0;
                final label = rate == rate.roundToDouble()
                    ? '${rate.toInt()}x'
                    : '${rate}x';
                return PopupMenuButton<double>(
                  tooltip: 'Speed',
                  onSelected: (v) {
                    _p.setRate(v);
                    _scheduleHide();
                  },
                  itemBuilder: (context) => [
                    for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem<double>(value: r, child: Text('${r}x')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(label),
                  ),
                );
              },
            ),
            _ib(Icons.subtitles_outlined, 'Subtitles and audio', _tracksSheet),
            _ib(Icons.repeat, 'A-B loop', _abPressed,
                color: abOn ? primary : null),
            _ib(Icons.bookmark_add_outlined, 'Add bookmark', _addBookmark),
            _ib(Icons.bookmarks_outlined, 'Bookmarks', _showBookmarks),
            if (Platform.isAndroid)
              _ib(Icons.picture_in_picture_alt_outlined, 'Picture in picture',
                  _pip),
            _ib(Icons.lock_outline, 'Lock screen', _lockOn),
            _ib(Icons.fullscreen, 'Fullscreen', _toggleFullscreen),
          ],
        ),
      ),
    );
  }
}

/// Rounded picture box shown while seeking.
class _PreviewBox extends StatelessWidget {
  final SeekPreviewer previewer;
  final String label;
  const _PreviewBox({required this.previewer, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      height: 99,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70, width: 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<Uint8List?>(
            valueListenable: previewer.image,
            builder: (context, bytes, _) {
              if (bytes == null) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: 352,
                gaplessPlayback: true,
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: Colors.black54,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
