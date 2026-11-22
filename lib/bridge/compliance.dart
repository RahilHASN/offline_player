import 'handoff.dart';

class ComplianceError implements Exception {
  final String message;
  const ComplianceError(this.message);
  @override
  String toString() => message;
}

/// Hard rules, checked in code and in tests.
/// YouTube is only ever played by YouTube's own embedded player.
class Compliance {
  static const _youtubeHosts = <String>[
    'googlevideo.com',
    'youtube.com',
    'youtube-nocookie.com',
    'youtu.be',
    'ytimg.com',
  ];

  static const _allowedEmbedParams = <String>{'playsinline', 'rel', 'start', 'hl'};

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isYoutubeHost(String host) {
    final h = host.toLowerCase();
    return _youtubeHosts.any((d) => h == d || h.endsWith('.$d'));
  }

  static bool validVideoId(String s) => _id.hasMatch(s);

  static void assertHandoff(Handoff h) {
    if (h is NativeHandoff) {
      if (h.providerId == 'youtube') {
        throw const ComplianceError('YouTube can only use the official player.');
      }
      final host = Uri.tryParse(h.url)?.host ?? '';
      if (isYoutubeHost(host)) {
        throw const ComplianceError(
            'YouTube media addresses cannot be played by the built-in player.');
      }
    }
    if (h is EmbedHandoff) {
      if (h.providerId != 'youtube') {
        throw const ComplianceError('Embeds are only used for YouTube.');
      }
      if (!validVideoId(h.videoId)) {
        throw const ComplianceError('Invalid YouTube video id.');
      }
      final c = h.constraints;
      if (c.audioOnly || c.backgroundPlayback || !c.playerMustBeVisible) {
        throw const ComplianceError(
            'YouTube playback must stay visible and cannot be audio-only or background.');
      }
      for (final k in h.embedUrl.queryParameters.keys) {
        if (!_allowedEmbedParams.contains(k)) {
          throw ComplianceError('Embed option "$k" is not allowed.');
        }
      }
    }
    if (h is ExternalLinkHandoff && h.url.scheme != 'https') {
      throw const ComplianceError('Only https links can be opened.');
    }
  }
}
