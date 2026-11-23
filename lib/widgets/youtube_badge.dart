import 'package:flutter/material.dart';

/// Small "YouTube" mark shown wherever content comes from YouTube.
class YouTubeBadge extends StatelessWidget {
  final double size;
  const YouTubeBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.32, vertical: size * 0.08),
          decoration: BoxDecoration(
            color: const Color(0xFFFF0000),
            borderRadius: BorderRadius.circular(size * 0.4),
          ),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size),
        ),
        SizedBox(width: size * 0.4),
        Text('YouTube',
            style: TextStyle(fontSize: size * 0.95, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
