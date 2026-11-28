import '../../music/track.dart';
import '../../services/net.dart';
import '../compliance.dart';
import '../handoff.dart';
import '../provider.dart';

/// Pasted links to a plain audio or video file you are allowed to play.
class DirectProvider implements MediaProvider {
  DirectProvider._();
  static final DirectProvider instance = DirectProvider._();

  static const _audio = <String>{'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'};
  static const _video = <String>{'mp4', 'm4v', 'webm', 'mkv', 'mov', 'm3u8'};

  @override
  String get id => 'direct';
  @override
  String get name => 'Direct link';
  @override
  ProviderCaps get caps => const ProviderCaps(
        nativeAudio: true,
        nativeVideo: true,
        backgroundAllowed: true,
      );

  @override
  Future<List<MediaItem>> search(String query) async => <MediaItem>[];

  Future<MediaItem> fromUrl(Uri u) async {
    if (Compliance.isYoutubeHost(u.host)) {
      throw 'That link can only be played through its official player.';
    }
    final p = await Net.probe(u);
    final mime = p.mime.toLowerCase();
    final seg = p.url.pathSegments.isNotEmpty ? p.url.pathSegments.last : '';
    final dot = seg.lastIndexOf('.');
    final ext = dot > 0 ? seg.substring(dot + 1).toLowerCase() : '';

    MediaKind? kind;
    if (mime.startsWith('audio/')) {
      kind = MediaKind.audio;
    } else if (mime.startsWith('video/') || mime.contains('mpegurl')) {
      kind = MediaKind.video;
    } else if (_audio.contains(ext)) {
      kind = MediaKind.audio;
    } else if (_video.contains(ext)) {
      kind = MediaKind.video;
    }
    if (kind == null) {
      throw 'That link is not a direct audio or video file.';
    }

    final title = Uri.decodeComponent(dot > 0 ? seg.substring(0, dot) : (seg.isEmpty ? p.url.host : seg));
    final url = p.url.toString();
    final track = kind == MediaKind.audio
        ? Track(
            id: 'd:$url',
            title: title,
            artist: p.url.host,
            album: '',
            uri: url,
            source: TrackSource.web,
          )
        : null;
    return MediaItem(
      id: 'd:$url',
      providerId: 'direct',
      title: title,
      creator: p.url.host,
      kind: kind,
      url: url,
      track: track,
    );
  }

  @override
  List<Handoff> handoffs(MediaItem item) {
    final u = item.url;
    if (u == null) {
      return <Handoff>[
        UnavailableHandoff(providerId: id, reason: 'No address for this item.'),
      ];
    }
    return <Handoff>[
      NativeHandoff(
        providerId: id,
        url: u,
        isVideo: item.kind == MediaKind.video,
        track: item.track,
        title: item.title,
      ),
    ];
  }
}
