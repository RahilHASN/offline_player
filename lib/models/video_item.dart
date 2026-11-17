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
}
