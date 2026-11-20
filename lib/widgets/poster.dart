import 'package:flutter/material.dart';

import '../music/art_service.dart';
import '../music/track.dart';
import '../services/app_mode.dart';

/// A colour pair made from a text, so every song gets its own look.
List<Color> gradientFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  final hue = (h % 360).toDouble();
  return <Color>[
    HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor(),
    HSLColor.fromAHSL(1, (hue + 50) % 360, 0.60, 0.16).toColor(),
  ];
}

/// Cover picture that fills its parent. Falls back to a coloured poster.
class Poster extends StatelessWidget {
  final Track track;
  const Poster({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ArtService.instance.version,
      builder: (context, _, __) {
        ArtService.instance.want(track);
        final url =
            AppMode.instance.online ? ArtService.instance.artFor(track) : null;
        final g = gradientFor('${track.artist}${track.title}');
        final letter =
            track.title.isEmpty ? '♪' : track.title.characters.first.toUpperCase();
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: g,
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w800,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
          ],
        );
      },
    );
  }
}
