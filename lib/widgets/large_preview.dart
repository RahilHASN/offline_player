import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/app_settings.dart';
import '../services/preview_controller.dart';
import 'video_card.dart';

/// The big preview window shown over the library.
class LargePreview extends StatelessWidget {
  const LargePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PreviewState>(
      valueListenable: PreviewController.instance.state,
      builder: (context, s, _) {
        if (!AppSettings.instance.largePreview || s.video == null) {
          return const SizedBox.shrink();
        }
        final size = MediaQuery.sizeOf(context);
        final maxW = min(size.width * 0.94, 780.0);
        final maxH = size.height * 0.72;
        var pw = maxW;
        var ph = pw / s.aspect;
        if (ph > maxH) {
          ph = maxH;
          pw = ph * s.aspect;
        }
        return IgnorePointer(
          child: Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: SizedBox(
              width: pw,
              height: ph,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!s.ready)
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: s.ready ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Video(
                        controller: s.video!,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                        fill: Colors.black,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 46, 5),
                        color: Colors.black45,
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 4,
                      child: PreviewRing(state: s),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PreviewBar(state: s),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
