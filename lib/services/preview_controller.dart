import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import 'app_settings.dart';

class PreviewState {
  final String? id;
  final int cut;
  final int total;
  final bool ready;
  final VideoController? video;

  const PreviewState({
    this.id,
    this.cut = 0,
    this.total = 0,
    this.ready = false,
    this.video,
  });

  PreviewState copyWith({int? cut, int? total, bool? ready}) {
    return PreviewState(
      id: id,
      cut: cut ?? this.cut,
      total: total ?? this.total,
      ready: ready ?? this.ready,
      video: video,
    );
  }
}

/// Only one preview plays at a time. Each preview uses its own short-lived player.
class PreviewController {
  PreviewController._();
  static final PreviewController instance = PreviewController._();

  final ValueNotifier<PreviewState> state =
      ValueNotifier<PreviewState>(const PreviewState());

  Player? _player;
  Timer? _timer;
  int _token = 0;

  void _set(int token, PreviewState Function(PreviewState) f) {
    if (token != _token) return;
    state.value = f(state.value);
  }

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    final old = _player;
    _player = null;
    if (old != null) {
      old.pause().catchError((_) {});
      Future<void>.delayed(const Duration(milliseconds: 400), () async {
        try {
          await old.dispose();
        } catch (_) {}
      });
    }
  }

  void stop() {
    _token++;
    _teardown();
    state.value = const PreviewState();
  }

  Future<void> start(VideoItem item) async {
    if (item.path.isEmpty) return;
    final token = ++_token;
    _teardown();

    final settings = AppSettings.instance;
    final p = Player();
    final v = VideoController(p);
    _player = p;
    state.value = PreviewState(id: item.id, video: v);

    try {
      await p.setVolume(settings.previewAudio ? 100 : 0);
      await p.open(Media(item.path), play: false);
      if (token != _token) return;
      if (!settings.previewAudio) {
        try {
          await p.setAudioTrack(AudioTrack.no());
        } catch (_) {}
      }

      var dur = p.state.duration;
      if (dur <= Duration.zero) {
        dur = await p.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 6));
      }
      if (token != _token) return;

      final secs = dur.inMilliseconds / 1000.0;

      // Short video: just play it normally, looping.
      if (secs < 10) {
        await p.setPlaylistMode(PlaylistMode.single);
        await p.play();
        _set(token, (s) => s.copyWith(cut: 0, total: 1));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _set(token, (s) => s.copyWith(ready: true));
        return;
      }

      final n = min(settings.cuts, max(2, secs ~/ 5));
      final section = secs / n;
      final clip = min(settings.clipSeconds, section * 0.8);

      await p.play();
      await _cut(token, p, 0, n, section, clip, true);
    } catch (_) {
      if (token == _token) stop();
    }
  }

  Future<void> _cut(
    int token,
    Player p,
    int i,
    int n,
    double section,
    double clip,
    bool first,
  ) async {
    if (token != _token) return;
    final startSec = i * section + (section - clip) / 2;
    try {
      await p.seek(Duration(milliseconds: (startSec * 1000).round()));
    } catch (_) {
      return;
    }
    if (token != _token) return;

    _set(token, (s) => s.copyWith(cut: i, total: n));
    if (first) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _set(token, (s) => s.copyWith(ready: true));
      });
    }

    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: (clip * 1000).round()),
      () => _cut(token, p, (i + 1) % n, n, section, clip, false),
    );
  }
}
