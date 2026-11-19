import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';

class _Task {
  final VideoItem item;
  final int n;
  final double durSec;
  _Task(this.item, this.n, this.durSec);
}

/// Studies a video in the background and remembers its busiest moments,
/// so the preview can pick them instead of cutting evenly.
class SmartCuts {
  SmartCuts._();
  static final SmartCuts instance = SmartCuts._();

  final Map<String, List<double>> _cache = <String, List<double>>{};
  final List<_Task> _queue = <_Task>[];
  final Set<String> _queued = <String>{};
  bool _loaded = false;
  bool _running = false;

  /// Set while a preview is playing, so analysis does not compete with it.
  bool paused = false;

  String _k(VideoItem v, int n) => '${v.key}|$n';

  Future<File> _file() async {
    final b = await getApplicationSupportDirectory();
    return File('${b.path}${Platform.pathSeparator}smartcuts.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      m.forEach((k, v) {
        if (v is List) {
          _cache[k] = v.whereType<num>().map((e) => e.toDouble()).toList();
        }
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_cache), flush: true);
    } catch (_) {}
  }

  List<double>? cutsFor(VideoItem v, int n) {
    final c = _cache[_k(v, n)];
    return (c != null && c.length == n) ? c : null;
  }

  void enqueue(VideoItem v, int n, double durSec) {
    final k = _k(v, n);
    if (_cache.containsKey(k) || !_queued.add(k)) return;
    _queue.add(_Task(v, n, durSec));
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        while (paused) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final t = _queue.removeAt(0);
        final r = await _analyze(t);
        final k = _k(t.item, t.n);
        if (r == null) {
          // interrupted by a preview: try again later
          _queue.add(t);
        } else {
          if (r.length == t.n) {
            _cache[k] = r;
            await _save();
          }
          _queued.remove(k);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<Uint8List?> _tiny(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 14,
      );
      final fr = await codec.getNextFrame();
      final bd = await fr.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      fr.image.dispose();
      codec.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Returns the chosen centres in seconds, an empty list on failure,
  /// or null when interrupted.
  Future<List<double>?> _analyze(_Task t) async {
    const per = 4;
    final n = t.n;
    final k = n * per;
    final player = Player();
    try {
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
        ),
      );
      await player.setVolume(0);
      await player.open(Media(t.item.path), play: false);
      if (player.state.duration <= Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }
      try {
        await controller.waitUntilFirstFrameRendered
            .timeout(const Duration(seconds: 8));
      } catch (_) {}

      final lumas = <List<double>?>[];
      final means = <double>[];
      final devs = <double>[];

      for (var i = 0; i < k; i++) {
        if (paused) return null;
        final at = (i + 0.5) / k * t.durSec;
        await player.seek(Duration(milliseconds: (at * 1000).round()));
        await Future<void>.delayed(const Duration(milliseconds: 260));
        final shot = await player.screenshot();
        final px = (shot == null || shot.isEmpty) ? null : await _tiny(shot);
        if (px == null || px.length < 4) {
          lumas.add(null);
          means.add(0);
          devs.add(0);
          continue;
        }
        final l = <double>[];
        for (var j = 0; j + 3 < px.length; j += 4) {
          l.add(0.299 * px[j] + 0.587 * px[j + 1] + 0.114 * px[j + 2]);
        }
        var sum = 0.0;
        for (final x in l) {
          sum += x;
        }
        final mean = sum / l.length;
        var sq = 0.0;
        for (final x in l) {
          sq += (x - mean) * (x - mean);
        }
        lumas.add(l);
        means.add(mean);
        devs.add(sqrt(sq / l.length));
      }

      double score(int i) {
        final l = lumas[i];
        if (l == null || means[i] < 14) return -1;
        List<double>? o;
        if (i > 0) o = lumas[i - 1];
        if (o == null && i + 1 < k) o = lumas[i + 1];
        var diff = 0.0;
        if (o != null) {
          var s = 0.0;
          for (var j = 0; j < l.length && j < o.length; j++) {
            s += (l[j] - o[j]).abs();
          }
          diff = s / l.length;
        }
        return diff + devs[i] * 0.5;
      }

      final out = <double>[];
      for (var s = 0; s < n; s++) {
        var best = s * per;
        var bs = -2.0;
        for (var j = 0; j < per; j++) {
          final idx = s * per + j;
          final sc = score(idx);
          if (sc > bs) {
            bs = sc;
            best = idx;
          }
        }
        out.add((best + 0.5) / k * t.durSec);
      }
      return out;
    } catch (_) {
      return <double>[];
    } finally {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
