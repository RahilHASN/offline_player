import 'compliance.dart';
import 'provider.dart';
import 'providers/direct_provider.dart';
import 'providers/youtube_provider.dart';
import 'url_guard.dart';

class ProviderRegistry {
  ProviderRegistry._();
  static final ProviderRegistry instance = ProviderRegistry._();

  final List<MediaProvider> providers = <MediaProvider>[
    YouTubeProvider.instance,
    DirectProvider.instance,
  ];

  MediaProvider? byId(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Turns a pasted link into an item. YouTube links go to the official
  /// player; other links must be plain audio or video files.
  Future<MediaItem> resolveUrl(String raw) async {
    final u = UrlGuard.parse(raw);
    final yid = YouTubeProvider.idFromUri(u);
    if (yid != null) return YouTubeProvider.instance.fromId(yid);
    if (Compliance.isYoutubeHost(u.host)) {
      throw 'That link has no video. Paste a link to a single video.';
    }
    return DirectProvider.instance.fromUrl(u);
  }
}
