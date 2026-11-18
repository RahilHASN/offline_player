import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../utils/format.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem item;
  const PlayerScreen({super.key, required this.item});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  StreamSubscription<String>? _errSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _errSub = _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _player.open(Media(widget.item.path));
  }

  @override
  void dispose() {
    _errSub?.cancel();
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
  final String title;

  const PlayerControls({
    super.key,
    required this.state,
    required this.player,
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
                ),
              ),
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
            ],
          ),
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
        const Spacer(),
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
                        setState(() {
                          _dragging = true;
                          _dragValue = v;
                        });
                      },
                      onChanged: (v) => setState(() => _dragValue = v),
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
      children: [
        StreamBuilder<bool>(
          stream: _p.stream.playing,
          initialData: _p.state.playing,
          builder: (context, s) {
            final playing = s.data ?? false;
            return IconButton(
              iconSize: 32,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                _p.playOrPause();
                _scheduleHide();
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.replay_10),
          onPressed: () => _seekBy(const Duration(seconds: -10)),
        ),
        IconButton(
          icon: const Icon(Icons.forward_10),
          onPressed: () => _seekBy(const Duration(seconds: 10)),
        ),
        const Spacer(),
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
