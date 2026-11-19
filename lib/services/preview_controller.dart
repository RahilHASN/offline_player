import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import 'app_settings.dart';
import 'smart_cuts.dart';

class PreviewState {
  final String? id;
  final String name;
  final int cut;
  final int total;
  final bool ready;
  final VideoController? video;
  final double aspect; // width / height
  final int clipMs; // length of the current cut
  final int seq; // changes every cut, restarts the progress animation

  const PreviewState({
    this.id,
    this.name = '',
    this.cut = 0,
    this.total = 0,
    this.ready = false,
    this.video,
    this.aspect = 16 / 9,
    this.clipMs = 1500,
    this.seq = 0,
  });

  PreviewState copyWith({
    int? cut,
    int? total,
    bool? ready,
    double? aspect,
    int? clipMs,
    int? seq,
  }) {
    return PreviewState(
      id: id,
      name: name,
      cut: cut ?? this.cut,
      total: total ?? this.total,
      ready: ready ?? this.ready,
      video: video,
      aspect: aspect ?? this.aspect,
      clipMs: clipMs ?? this.clipMs,
      seq: seq ?? this.seq,
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
    SmartCuts.instance.paused = false;
    state.value = const PreviewState();
  }

  /// Reads the video's shape (width / height). Falls back to 16:9.
  Future<double> _readAspect(Player p) async {
    try {
      for (var i = 0; i < 20; i++) {
        final w = p.state.width;
        final h = p.state.height;
        if (w != null && h != null && w > 0 && h > 0) {
          return (w / h).clamp(0.4, 2.5).toDouble();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}
    return 16 / 9;
  }

  Future<void> start(VideoItem item) async {
    if (item.path.isEmpty) return;
    final token = ++_token;
    _teardown();
    SmartCuts.instance.paused = true;

    final settings = AppSettings.instance;
    final p = Player();
    final v = VideoController(p);
    _player = p;
    state.value = PreviewState(id: item.id, name: item.name, video: v);

    try {
      await SmartCuts.instance.load();
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
        final a = await _readAspect(p);
        if (token != _token) return;
        final ms = max(1000, dur.inMilliseconds);
        _set(token,
            (s) => s.copyWith(cut: 0, total: 1, aspect: a, clipMs: ms, seq: 1));
        _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
          _set(token, (s) => s.copyWith(seq: s.seq + 1));
        });
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _set(token, (s) => s.copyWith(ready: true));
        return;
      }

      final n = min(settings.cuts, max(2, secs ~/ 5));
      final section = secs / n;
      final clip = min(settings.clipSeconds, section * 0.8);

      List<double>? smart;
      if (settings.smartCuts) {
        smart = SmartCuts.instance.cutsFor(item, n);
        if (smart == null) SmartCuts.instance.enqueue(item, n, secs);
      }
      final starts = <double>[
        for (var i = 0; i < n; i++)
          smart != null
              ? (smart[i] - clip / 2).clamp(0.0, max(0.0, secs - clip)).toDouble()
              : i * section + (section - clip) / 2,
      ];

      await p.play();
      final a = await _readAspect(p);
      if (token != _token) return;
      _set(token, (s) => s.copyWith(aspect: a));
      await _cut(token, p, 0, n, starts, clip, true);
    } catch (_) {
      if (token == _token) stop();
    }
  }

  Future<void> _cut(
    int token,
    Player p,
    int i,
    int n,
    List<double> starts,
    double clip,
    bool first,
  ) async {
    if (token != _token) return;
    try {
      await p.seek(Duration(milliseconds: (starts[i] * 1000).round()));
    } catch (_) {
      return;
    }
    if (token != _token) return;

    final clipMs = max(200, (clip * 1000).round());
    _set(
      token,
      (s) => s.copyWith(cut: i, total: n, clipMs: clipMs, seq: s.seq + 1),
    );
    if (first) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _set(token, (s) => s.copyWith(ready: true));
      });
    }

    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: clipMs),
      () => _cut(token, p, (i + 1) % n, n, starts, clip, false),
    );
  }
}
