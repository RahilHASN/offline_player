import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../music/music_player.dart';
import '../music/track.dart';
import 'compliance.dart';
import 'handoff.dart';
import 'native_video_screen.dart';
import 'provider.dart';
import 'registry.dart';
import 'router.dart';
import 'youtube_embed_screen.dart';
import 'youtube_history.dart';

/// One entry point: ask the router, then hand off to the right engine.
class Playback {
  static void _msg(BuildContext context, String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  static Future<void> play(
    BuildContext context,
    MediaItem item, {
    List<MediaItem> queue = const <MediaItem>[],
  }) async {
    final p = ProviderRegistry.instance.byId(item.providerId);
    if (p == null) {
      _msg(context, 'Unknown source.');
      return;
    }
    Handoff h;
    try {
      h = PlaybackRouter.plan(
        item,
        p.handoffs(item),
        ClientProfile.current(),
        const UserPrefs(),
      );
    } on ComplianceError catch (e) {
      _msg(context, '$e');
      return;
    }

    switch (h) {
      case NativeHandoff n:
        if (n.isVideo) {
          MusicPlayer.instance.pause();
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NativeVideoScreen(url: n.url, title: n.title),
          ));
        } else {
          final src = queue.isEmpty ? <MediaItem>[item] : queue;
          final tracks = <Track>[
            for (final q in src)
              if (q.providerId == item.providerId && q.track != null) q.track!,
          ];
          var i = tracks.indexWhere((t) => t.id == item.track?.id);
          if (i < 0) i = 0;
          if (tracks.isEmpty) {
            _msg(context, 'Nothing to play.');
            return;
          }
          await MusicPlayer.instance.playQueue(tracks, i);
        }
      case EmbedHandoff _:
        MusicPlayer.instance.pause();
        final src = queue.isEmpty ? <MediaItem>[item] : queue;
        final q = <MediaItem>[
          for (final m in src)
            if (m.providerId == 'youtube' && m.videoId != null) m,
        ];
        var i = q.indexWhere((m) => m.id == item.id);
        if (i < 0) {
          q.insert(0, item);
          i = 0;
        }
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => YouTubeEmbedScreen(queue: q, index: i),
        ));
      case ExternalLinkHandoff x:
        MusicPlayer.instance.pause();
        YouTubeHistory.instance.add(item);
        final ok = await launchUrl(x.url, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) _msg(context, 'Could not open the link.');
      case UnavailableHandoff u:
        _msg(context, u.reason);
    }
  }
}
