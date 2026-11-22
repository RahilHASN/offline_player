import '../music/track.dart';
import 'handoff.dart';

enum MediaKind { audio, video }

/// One search result or resolved link, whatever its source.
class MediaItem {
  final String id;
  final String providerId;
  final String title;
  final String creator;
  final String? thumb;
  final int durationSec;
  final MediaKind kind;

  /// Playable address for native items.
  final String? url;

  /// YouTube video id for embed items.
  final String? videoId;

  /// Ready-made track for native audio.
  final Track? track;

  const MediaItem({
    required this.id,
    required this.providerId,
    required this.title,
    required this.creator,
    required this.kind,
    this.thumb,
    this.durationSec = 0,
    this.url,
    this.videoId,
    this.track,
  });
}

class ProviderCaps {
  final bool search;
  final bool nativeAudio;
  final bool nativeVideo;
  final bool officialEmbed;
  final bool backgroundAllowed;
  final bool needsKey;
  final bool needsSignIn;

  const ProviderCaps({
    this.search = false,
    this.nativeAudio = false,
    this.nativeVideo = false,
    this.officialEmbed = false,
    this.backgroundAllowed = false,
    this.needsKey = false,
    this.needsSignIn = false,
  });

  String get summary {
    final parts = <String>[];
    if (officialEmbed) {
      parts.add("Official YouTube player only (stays visible, no background or audio-only)");
    }
    if (nativeAudio || nativeVideo) {
      parts.add(backgroundAllowed ? 'Plays in the app, background OK' : 'Plays in the app');
    }
    if (needsKey) parts.add('needs a key');
    return parts.join(' · ');
  }
}

abstract class MediaProvider {
  String get id;
  String get name;
  ProviderCaps get caps;

  Future<List<MediaItem>> search(String query);

  /// Every way this provider allows the item to be played.
  List<Handoff> handoffs(MediaItem item);
}
