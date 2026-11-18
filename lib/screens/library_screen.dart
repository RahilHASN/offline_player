import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/seek_previewer.dart';
import '../utils/format.dart';

/// Software brightness: 1.0 = normal, lower = darker.
final ValueNotifier<double> _brightness = ValueNotifier<double>(1.0);

class PlayerScreen extends StatefulWidget {
  final VideoItem item;
  const PlayerScreen({super.key, required this.item});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  late final SeekPreviewer _previewer = SeekPreviewer(widget.item.path);
  StreamSubscription<String>? _errSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _brightness.value = 1.0;
    _errSub = _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _player.open(Media(widget.item.path));
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _previewer.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                title: widget.item.name,
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
    );
  }
}

class PlayerControls extends StatefulWidget {
  final VideoState state;
  final Player player;
  final SeekPreviewer previewer;
  final String title;

  const PlayerControls({
    super.key,
    required this.state,
    required this.player,
    required this.previewer,
    required this.title,
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

  Player get _p => widget.player;
  bool get _desktop => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _focus.dispose();
    super.dispose();
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
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
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onHover: (_) {
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
                child: GestureDetector(
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
              // slider-drag preview
              if (_dragging) _sliderPreview(screenW),
            ],
          ),
        ),
      ),
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
                  widget.title,
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
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 12),
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
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
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
                        widget.previewer.request(
                            Duration(milliseconds: v.round()));
                        setState(() {
                          _dragging = true;
                          _dragValue = v;
                        });
                      },
                      onChanged: (v) {
                        widget.previewer.request(
                            Duration(milliseconds: v.round()));
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_desktop)
          StreamBuilder<double>(
            stream: _p.stream.volume,
            initialData: _p.state.volume,
            builder: (context, s) {
              final vol = (s.data ?? 100).clamp(0.0, 100.0).toDouble();
              return Row(
                children: [
                  IconButton(
                    icon: Icon(vol <= 0 ? Icons.volume_off : Icons.volume_up),
                    onPressed: () => _p.setVolume(vol > 0 ? 0 : 100),
                  ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.fullscreen),
          onPressed: _toggleFullscreen,
        ),
      ],
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
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
