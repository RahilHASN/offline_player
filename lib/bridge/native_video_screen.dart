import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays an authorised direct video link with the built-in player.
class NativeVideoScreen extends StatefulWidget {
  final String url;
  final String title;
  const NativeVideoScreen({super.key, required this.url, required this.title});

  @override
  State<NativeVideoScreen> createState() => _NativeVideoScreenState();
}

class _NativeVideoScreenState extends State<NativeVideoScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(child: Video(controller: _controller)),
    );
  }
}
