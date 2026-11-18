import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/video_item.dart';
import 'preview_controller.dart';

class ThumbResult {
  final File file;
  final Duration? duration;
  const ThumbResult(this.file, this.duration);
}

class ThumbHandle {
  final Future<ThumbResult?> future;
  final void Function() cancel;
  const ThumbHandle(this.future, this.cancel);
}

class _Job {
  final VideoItem item;
  final Completer<ThumbResult?> completer = Completer<ThumbResult?>();
  bool cancelled = false;
  _Job(this.item);
}

class _Shot {
  final Uint8List bytes;
  final Duration? duration;
  const _Shot(this.bytes, this.duration);
}

/// Creates thumbnails one at a time and caches them on local storage.
/// Cards on screen go first. Everything else is made quietly in the background.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  Directory? _dir;
  final List<_Job> _queue = <_Job>[];
  final List<VideoItem> _bg = <VideoItem>[];
  final Set<String> _bgIds = <String>{};
  final Map<String, int> _fails = <String, int>{};
  bool _running = false;

  /// Durations discovered while making thumbnails (video id -> duration).
  final Map<String, Duration> durations = <String, Duration>{};

  /// Goes up every time a new thumbnail or duration is ready.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}thumbs');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _dir = d;
    return d;
  }

  String _key(VideoItem v) {
    final s = '${v.id}|${v.sizeBytes}|${v.date.millisecondsSinceEpoch}';
    var h1 = 5381;
    var h2 = 7919;
    for (final c in s.codeUnits) {
      h1 = ((h1 * 33) ^ c) & 0xFFFFFFFF;
      h2 = ((h2 * 131) + c) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }

  Future<ThumbResult?> _cached(VideoItem v) async {
    final dir = await _cacheDir();
    final k = _key(v);
    final img = File('${dir.path}${Platform.pathSeparator}$k.jpg');
    if (!await img.exists()) return null;

    Duration? d;
    final df = File('${dir.path}${Platform.pathSeparator}$k.dur');
    if (await df.exists()) {
      final ms = int.tryParse((await df.readAsString()).trim());
      if (ms != null && ms > 0) d = Duration(milliseconds: ms);
    }
    if (d != null) durations[v.id] = d;
    return ThumbResult(img, d);
  }

  /// Ask for a thumbnail. Call cancel() if the card is no longer visible.
  ThumbHandle request(VideoItem v) {
    final job = _Job(v);
    () async {
      try {
        final hit = await _cached(v);
        if (hit != null) {
          job.completer.complete(hit);
          return;
        }
        if (job.cancelled || (_fails[v.id] ?? 0) >= 3) {
          job.completer.complete(null);
          return;
        }
        _queue.add(job);
        _pump();
      } catch (_) {
        if (!job.completer.isCompleted) job.completer.complete(null);
      }
    }();
    return ThumbHandle(job.completer.future, () => job.cancelled = true);
  }

  /// Make thumbnails and durations for everything, quietly, in the background.
  void prefetch(List<VideoItem> items) {
    for (final v in items) {
      if (v.path.isEmpty && !v.id.startsWith('a:')) continue;
      if (_bgIds.add(v.id)) _bg.add(v);
    }
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty || _bg.isNotEmpty) {
        _Job? job;
        VideoItem item;

        if (_queue.isNotEmpty) {
          // newest request first: it is what the person is looking at now
          job = _queue.removeLast();
          if (job.cancelled) {
            job.completer.complete(null);
            continue;
          }
          item = job.item;
        } else {
          item = _bg.removeAt(0);
          // do not compete with a playing preview
          while (PreviewController.instance.state.value.id != null) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }

        ThumbResult? r;
        try {
          r = await _cached(item);
          r ??= await _generate(item);
        } catch (_) {
          r = null;
        }

        if (r == null) {
          _fails[item.id] = (_fails[item.id] ?? 0) + 1;
        } else {
          version.value++;
        }
        if (job != null && !job.completer.isCompleted) {
          job.completer.complete(r);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<ThumbResult?> _generate(VideoItem v) async {
    Uint8List? bytes;
    Duration? duration = v.duration;

    if (v.id.startsWith('a:')) {
      bytes = await _fromMediaStore(v);
    }
    if ((bytes == null || bytes.isEmpty) && v.path.isNotEmpty) {
      final shot = await _fromMediaKit(v);
      if (shot != null) {
        bytes = shot.bytes;
        duration = shot.duration ?? duration;
      }
    }
    if (bytes == null || bytes.isEmpty) return null;

    final dir = await _cacheDir();
    final k = _key(v);
    final sep = Platform.pathSeparator;
    final tmp = File('${dir.path}$sep$k.tmp');
    final img = File('${dir.path}$sep$k.jpg');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(img.path);

    if (duration != null && duration > Duration.zero) {
      await File('${dir.path}$sep$k.dur')
          .writeAsString('${duration.inMilliseconds}');
      durations[v.id] = duration;
    }
    return ThumbResult(img, duration);
  }

  Future<Uint8List?> _fromMediaStore(VideoItem v) async {
    try {
      final asset = await AssetEntity.fromId(v.id.substring(2));
      if (asset == null) return null;
      return await asset.thumbnailDataWithSize(
        const ThumbnailSize(480, 270),
        quality: 80,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_Shot?> _fromMediaKit(VideoItem v) async {
    final player = Player();
    try {
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
        ),
      );
      await player.setVolume(0);
      await player.open(Media(v.path), play: false);

      var dur = player.state.duration;
      if (dur <= Duration.zero) {
        dur = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }

      final target = Duration(milliseconds: (dur.inMilliseconds * 0.10).round());
      await player.seek(target);

      try {
        await controller.waitUntilFirstFrameRendered
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // try the screenshot anyway
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final bytes = await player.screenshot();
      if (bytes == null || bytes.isEmpty) return null;
      return _Shot(bytes, dur);
    } catch (_) {
      return null;
    } finally {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
