import '../music/track.dart';

/// Which engine plays an item.
enum Engine { native, officialEmbed, externalLink, unavailable }

/// What an engine allows. The router and the compliance check read these.
class Constraints {
  final bool audioOnly;
  final bool backgroundPlayback;
  final bool playerMustBeVisible;
  final bool adsControlledByProvider;
  final bool requiresAttribution;
  final bool authRequired;

  const Constraints({
    this.audioOnly = false,
    this.backgroundPlayback = false,
    this.playerMustBeVisible = false,
    this.adsControlledByProvider = false,
    this.requiresAttribution = false,
    this.authRequired = false,
  });

  static const nativeAudio = Constraints(audioOnly: true, backgroundPlayback: true);
  static const nativeVideo = Constraints(playerMustBeVisible: true);
  static const youtubeEmbed = Constraints(
    playerMustBeVisible: true,
    adsControlledByProvider: true,
    requiresAttribution: true,
  );
  static const external = Constraints(requiresAttribution: true);
  static const none = Constraints();
}

/// A standard answer to "how do we play this?".
sealed class Handoff {
  final String providerId;
  final Constraints constraints;
  const Handoff(this.providerId, this.constraints);
  Engine get engine;
}

/// Our own player (media_kit): local files, Jamendo, direct links.
class NativeHandoff extends Handoff {
  final String url;
  final bool isVideo;
  final Track? track;
  final String title;

  NativeHandoff({
    required String providerId,
    required this.url,
    required this.isVideo,
    this.track,
    this.title = '',
  }) : super(providerId,
            isVideo ? Constraints.nativeVideo : Constraints.nativeAudio);

  @override
  Engine get engine => Engine.native;
}

/// YouTube's official embedded player. Never a stream address.
class EmbedHandoff extends Handoff {
  final String videoId;

  EmbedHandoff({required String providerId, required this.videoId})
      : super(providerId, Constraints.youtubeEmbed);

  static const embedParams = <String, String>{'playsinline': '1', 'rel': '0'};

  Uri get embedUrl =>
      Uri.https('www.youtube.com', '/embed/$videoId', embedParams);

  @override
  Engine get engine => Engine.officialEmbed;
}

/// Open the provider's own website or app.
class ExternalLinkHandoff extends Handoff {
  final Uri url;
  final String reason;

  ExternalLinkHandoff({
    required String providerId,
    required this.url,
    this.reason = '',
  }) : super(providerId, Constraints.external);

  @override
  Engine get engine => Engine.externalLink;
}

class UnavailableHandoff extends Handoff {
  final String reason;

  UnavailableHandoff({required String providerId, required this.reason})
      : super(providerId, Constraints.none);

  @override
  Engine get engine => Engine.unavailable;
}
