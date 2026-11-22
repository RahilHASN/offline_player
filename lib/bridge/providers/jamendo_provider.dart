import '../../music/online_sources.dart';
import '../../music/track.dart';
import '../handoff.dart';
import '../provider.dart';

class JamendoProvider implements MediaProvider {
  @override
  String get id => 'jamendo';
  @override
  String get name => 'Jamendo (Creative Commons music)';
  @override
  ProviderCaps get caps => const ProviderCaps(
        search: true,
        nativeAudio: true,
        backgroundAllowed: true,
        needsKey: true,
      );

  static MediaItem fromTrack(Track t) => MediaItem(
        id: t.id,
        providerId: 'jamendo',
        title: t.title,
        creator: t.artist,
        thumb: t.art,
        durationSec: t.durationSec,
        kind: MediaKind.audio,
        url: t.uri,
        track: t,
      );

  @override
  Future<List<MediaItem>> search(String query) async {
    final r = await OnlineSources.jamendo(
        search: query, order: 'relevance', limit: 30);
    return r.map(fromTrack).toList();
  }

  @override
  List<Handoff> handoffs(MediaItem item) {
    final u = item.url;
    if (u == null) {
      return <Handoff>[
        UnavailableHandoff(providerId: id, reason: 'No stream for this track.'),
      ];
    }
    return <Handoff>[
      NativeHandoff(
          providerId: id,
          url: u,
          isVideo: false,
          track: item.track,
          title: item.title),
    ];
  }
}
