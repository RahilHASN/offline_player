import 'package:flutter/material.dart';

import '../music/lyrics_service.dart';
import '../music/music_player.dart';
import '../music/track.dart';
import '../services/app_mode.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final MusicPlayer mp = MusicPlayer.instance;
  bool _lyricsOn = false;
  bool _loading = false;
  Lyrics? _lyrics;
  String? _lyricsFor;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _lyricsFor = mp.current?.id;
    mp.addListener(_onPlayer);
  }

  @override
  void dispose() {
    mp.removeListener(_onPlayer);
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted) return;
    final t = mp.current;
    if (t == null) {
      Navigator.of(context).maybePop();
      return;
    }
    if (t.id != _lyricsFor) {
      _lyricsFor = t.id;
      _lyrics = null;
      _loading = false;
      if (_lyricsOn) _fetch(t);
    }
    setState(() {});
  }

  Future<void> _fetch(Track t) async {
    setState(() => _loading = true);
    final r = await LyricsService.instance.forTrack(t);
    if (!mounted || _lyricsFor != t.id) return;
    setState(() {
      _lyrics = r;
      _loading = false;
    });
  }

  void _toggleLyrics() {
    setState(() => _lyricsOn = !_lyricsOn);
    final t = mp.current;
    if (_lyricsOn && t != null && _lyrics == null && !_loading) _fetch(t);
  }

  void _queue() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: mp,
        builder: (ctx, _) => ListView.builder(
          itemCount: mp.queue.length,
          itemBuilder: (ctx, i) {
            final t = mp.queue[i];
            final cur = i == mp.index;
            return ListTile(
              dense: true,
              leading: Icon(cur ? Icons.equalizer : Icons.music_note,
                  color: cur ? Theme.of(ctx).colorScheme.primary : null),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle:
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                mp.jump(i);
                Navigator.pop(ctx);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = mp.current;
    if (t == null) return const Scaffold();
    final g = gradientFor('${t.artist}${t.title}');
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [g[0], AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight * 1.1;
              if (wide) {
                return Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(child: _artOrLyrics(t)),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _top(),
                              _info(t),
                              _seek(),
                              _controls(),
                              _extras(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _top(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Center(child: _artOrLyrics(t)),
                    ),
                  ),
                  _info(t),
                  _seek(),
                  _controls(),
                  _extras(),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _top() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          iconSize: 32,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Expanded(
          child: Text('Now playing',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          icon: const Icon(Icons.queue_music),
          onPressed: _queue,
        ),
      ],
    );
  }

  Widget _artOrLyrics(Track t) {
    if (_lyricsOn) return _lyricsBox(t);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14)),
          ],
        ),
        child: Poster(track: t),
      ),
    );
  }

  Widget _lyricsBox(Track t) {
    Widget child;
    if (_loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_lyrics == null) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            AppMode.instance.online
                ? 'No lyrics found for this song.'
                : 'No lyrics on this device. Put a .lrc file with the same '
                    'name next to the song, or switch to Online mode.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    } else {
      child = _LyricsView(
        key: ValueKey(t.id),
        lyrics: _lyrics!,
        position: mp.position,
        onSeek: mp.seek,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _info(Track t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
          if (t.source == TrackSource.jamendo)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Creative Commons · via Jamendo',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          if (mp.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Playback problem: ${mp.error}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.orangeAccent)),
            ),
        ],
      ),
    );
  }

  Widget _seek() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ValueListenableBuilder<Duration>(
        valueListenable: mp.duration,
        builder: (context, dur, _) => ValueListenableBuilder<Duration>(
          valueListenable: mp.position,
          builder: (context, pos, _) {
            final max = dur.inMilliseconds.toDouble();
            final cur = _drag ?? pos.inMilliseconds.toDouble();
            final v = max > 0 ? cur.clamp(0.0, max).toDouble() : 0.0;
            return Column(
              children: [
                Slider(
                  value: v,
                  min: 0,
                  max: max > 0 ? max : 1,
                  onChangeStart: (x) => setState(() => _drag = x),
                  onChanged: (x) => setState(() => _drag = x),
                  onChangeEnd: (x) {
                    mp.seek(Duration(milliseconds: x.round()));
                    setState(() => _drag = null);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(Duration(milliseconds: v.round())),
                          style: const TextStyle(fontSize: 12)),
                      Text(formatDuration(dur),
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _controls() {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shuffle),
          color: mp.shuffle ? primary : Colors.white70,
          onPressed: mp.toggleShuffle,
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 40,
          onPressed: mp.prev,
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: IconButton(
            icon: Icon(mp.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded),
            iconSize: 44,
            color: Colors.black,
            onPressed: mp.playOrPause,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 40,
          onPressed: mp.next,
        ),
        IconButton(
          icon: Icon(mp.repeat == 2 ? Icons.repeat_one : Icons.repeat),
          color: mp.repeat == 0 ? Colors.white70 : primary,
          onPressed: mp.cycleRepeat,
        ),
      ],
    );
  }

  Widget _extras() {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: _toggleLyrics,
          icon: Icon(Icons.lyrics_outlined,
              color: _lyricsOn ? primary : Colors.white70),
          label: Text('Lyrics',
              style: TextStyle(color: _lyricsOn ? primary : Colors.white70)),
        ),
      ],
    );
  }
}

class _LyricsView extends StatefulWidget {
  final Lyrics lyrics;
  final ValueNotifier<Duration> position;
  final void Function(Duration) onSeek;
  const _LyricsView({
    super.key,
    required this.lyrics,
    required this.position,
    required this.onSeek,
  });

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  static const double _h = 56;
  final ScrollController _c = ScrollController();
  int _last = -1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int _indexAt(int ms) {
    var r = -1;
    final l = widget.lyrics.lines;
    for (var i = 0; i < l.length; i++) {
      if (l[i].ms <= ms) {
        r = i;
      } else {
        break;
      }
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.synced;
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.position,
      builder: (context, pos, _) {
        final idx = synced ? _indexAt(pos.inMilliseconds + 250) : -1;
        if (synced && idx != _last) {
          _last = idx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_c.hasClients || idx < 0) return;
            final vp = _c.position.viewportDimension;
            final target = (24 + idx * _h - vp / 2 + _h / 2)
                .clamp(0.0, _c.position.maxScrollExtent)
                .toDouble();
            _c.animateTo(
              target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          });
        }
        return ListView.builder(
          controller: _c,
          itemExtent: _h,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final line = lines[i];
            final active = i == idx;
            return InkWell(
              onTap: synced
                  ? () => widget.onSeek(Duration(milliseconds: line.ms))
                  : null,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: active ? 22 : 18,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: (active || !synced) ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
