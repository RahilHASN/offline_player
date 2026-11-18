import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Grabs a still frame at any position, for the seek-bar preview.
/// Uses its own hidden player, started the first time it is needed.
class SeekPreviewer {
  final String path;
  SeekPreviewer(this.path);

  final ValueNotifier<Uint8List?> image = ValueNotifier<Uint8List?>(null);

  Player? _player;
  VideoController? _controller;
  bool _initStarted = false;
  bool _ready = false;
  bool _busy = false;
  bool _disposed = false;
  Duration? _pending;

  Future<void> _init() async {
    _initStarted = true;
    try {
      final p = Player();
      _player = p;
      final c = VideoController(
        p,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
        ),
      );
      _controller = c;
      await p.setVolume(0);
      await p.open(Media(path), play: false);

      var dur = p.state.duration;
      if (dur <= Duration.zero) {
        dur = await p.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }
      try {
        await c.waitUntilFirstFrameRendered
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (_disposed) return;
      _ready = true;
    } catch (_) {}
    _run();
  }

  /// Ask for the frame at [t]. Only the latest request is kept.
  void request(Duration t) {
    if (_disposed) return;
    _pending = t;
    if (!_initStarted) {
      _init();
      return;
    }
    _run();
  }

  Future<void> _run() async {
    if (_busy || !_ready || _disposed) return;
    _busy = true;
    try {
      while (_pending != null && !_disposed) {
        final t = _pending!;
        _pending = null;
        final p = _player;
        if (p == null) break;
        await p.seek(t);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (_disposed) break;
        final bytes = await p.screenshot();
        if (bytes != null && bytes.isNotEmpty && !_disposed) {
          image.value = bytes;
        }
      }
    } catch (_) {}
    _busy = false;
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    final p = _player;
    _player = null;
    if (p != null) {
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        try {
          await p.dispose();
        } catch (_) {}
      });
    }
  }
}
