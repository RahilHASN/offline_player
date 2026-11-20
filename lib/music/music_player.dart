import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../services/native_bridge.dart';
import 'track.dart';

/// One music player for the whole app. It keeps playing while you browse.
class MusicPlayer extends ChangeNotifier {
  MusicPlayer._();
  static final MusicPlayer instance = MusicPlayer._();

  Player? _p;
  List<Track> _base = <Track>[];
  List<Track> queue = <Track>[];
  int index = 0;
  Track? current;
  bool playing = false;
  bool shuffle = false;
  int repeat = 0; // 0 off, 1 all, 2 one
  String? error;

  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);

  Player _ensure() {
    final e = _p;
    if (e != null) return e;
    final p = Player();
    _p = p;
    p.stream.playing.listen((v) {
      playing = v;
      if (v) NativeBridge.keepAlive(true);
      notifyListeners();
    });
    p.stream.position.listen((v) => position.value = v);
    p.stream.duration.listen((v) {
      if (v > Duration.zero) duration.value = v;
    });
    p.stream.completed.listen((c) {
      if (c) _onCompleted();
    });
    p.stream.error.listen((e) {
      error = e;
      notifyListeners();
    });
    return p;
  }

  Future<void> playQueue(List<Track> tracks, int i, {bool? shuffle}) async {
    if (tracks.isEmpty || i < 0 || i >= tracks.length) return;
    if (shuffle != null) this.shuffle = shuffle;
    _base = List<Track>.of(tracks);
    if (this.shuffle) {
      final rest = List<Track>.of(tracks)..removeAt(i);
      rest.shuffle();
      queue = <Track>[tracks[i], ...rest];
      index = 0;
    } else {
      queue = List<Track>.of(tracks);
      index = i;
    }
    await _playIndex(index);
  }

  Future<void> _playIndex(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    final t = queue[i];
    current = t;
    error = null;
    position.value = Duration.zero;
    duration.value = Duration(seconds: t.durationSec);
    notifyListeners();
    try {
      await _ensure().open(Media(t.uri));
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> jump(int i) => _playIndex(i);

  void _onCompleted() {
    if (repeat == 2) {
      _playIndex(index);
    } else {
      next(auto: true);
    }
  }

  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    var n = index + 1;
    if (n >= queue.length) {
      if (repeat == 1 || !auto) {
        n = 0;
      } else {
        await _p?.pause();
        return;
      }
    }
    await _playIndex(n);
  }

  Future<void> prev() async {
    if (queue.isEmpty) return;
    if (position.value > const Duration(seconds: 3)) {
      await _p?.seek(Duration.zero);
      return;
    }
    await _playIndex(index <= 0 ? queue.length - 1 : index - 1);
  }

  void playOrPause() => _p?.playOrPause();
  void pause() => _p?.pause();
  void seek(Duration d) => _p?.seek(d);

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = current;
    if (cur != null) {
      if (shuffle) {
        final rest = List<Track>.of(_base)..removeWhere((t) => t.id == cur.id);
        rest.shuffle();
        queue = <Track>[cur, ...rest];
        index = 0;
      } else {
        queue = List<Track>.of(_base);
        index = queue.indexWhere((t) => t.id == cur.id);
        if (index < 0) index = 0;
      }
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = (repeat + 1) % 3;
    notifyListeners();
  }

  void playNext(Track t) {
    if (queue.isEmpty) {
      playQueue(<Track>[t], 0);
      return;
    }
    queue.insert(index + 1, t);
    _base.add(t);
    notifyListeners();
  }

  void addToQueue(Track t) {
    if (queue.isEmpty) {
      playQueue(<Track>[t], 0);
      return;
    }
    queue.add(t);
    _base.add(t);
    notifyListeners();
  }

  Future<void> stop() async {
    await _p?.stop();
    current = null;
    playing = false;
    queue = <Track>[];
    _base = <Track>[];
    NativeBridge.keepAlive(false);
    notifyListeners();
  }
}
