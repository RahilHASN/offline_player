enum TrackSource { local, jamendo, web }

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;

  /// File path (local) or stream address (online).
  final String uri;
  final String? art;
  final int durationSec;
  final TrackSource source;
  final String license;
  final int addedMs;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.uri,
    required this.source,
    this.art,
    this.durationSec = 0,
    this.license = '',
    this.addedMs = 0,
  });

  bool get isLocal => source == TrackSource.local;
}
