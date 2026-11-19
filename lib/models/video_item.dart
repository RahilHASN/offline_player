enum VideoSource { phone, pendrive, pc }

extension VideoSourceLabel on VideoSource {
  String get label {
    switch (this) {
      case VideoSource.phone:
        return 'Phone';
      case VideoSource.pendrive:
        return 'Pendrive';
      case VideoSource.pc:
        return 'PC';
    }
  }
}

class VideoItem {
  final String id;
  final String path;
  final String name;
  final int sizeBytes;
  final Duration? duration;
  final DateTime date;
  final VideoSource source;

  const VideoItem({
    required this.id,
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.duration,
    required this.date,
    required this.source,
  });

  /// Identity for tags, favorites, progress and so on.
  /// Based on size and date, so it survives a rename or move.
  String get key => '$sizeBytes-${date.millisecondsSinceEpoch ~/ 1000}';
}
