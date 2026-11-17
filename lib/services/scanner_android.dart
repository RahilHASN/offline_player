
import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/video_item.dart';

class AndroidScanResult {
  final List<VideoItem> items;
  final int unresolved;
  final bool permissionDenied;
  const AndroidScanResult(this.items, this.unresolved, this.permissionDenied);
}

class AndroidScanner {
  static const _root = '/storage/emulated/0/';

  static Future<AndroidScanResult> scan() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.video,
          mediaLocation: false,
        ),
      ),
    );
    if (!state.hasAccess) {
      return AndroidScanResult(<VideoItem>[], 0, true);
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        videoOption: FilterOption(needTitle: true),
      ),
    );
    if (paths.isEmpty) {
      return AndroidScanResult(<VideoItem>[], 0, false);
    }

    final all = paths.first;
    const pageSize = 200;
    var page = 0;
    var unresolved = 0;
    final items = <VideoItem>[];

    while (true) {
      final batch = await all.getAssetListPaged(page: page, size: pageSize);
      if (batch.isEmpty) break;

      for (final a in batch) {
        final title = a.title ?? await a.titleAsync;
        var rel = a.relativePath ?? '';
        if (rel.isNotEmpty && !rel.endsWith('/')) rel = '$rel/';

        var path = '$_root$rel$title';
        var size = 0;
        try {
          final st = File(path).statSync();
          if (st.type == FileSystemEntityType.notFound) {
            path = '';
            unresolved++;
          } else {
            size = st.size;
          }
        } catch (_) {
          path = '';
          unresolved++;
        }

        Duration? duration = a.videoDuration;
        if (duration == Duration.zero) duration = null;

        items.add(VideoItem(
          id: 'a:${a.id}',
          path: path,
          name: title,
          sizeBytes: size,
          duration: duration,
          date: a.createDateTime,
          source: VideoSource.phone,
        ));
      }

      if (batch.length < pageSize) break;
      page++;
    }

    return AndroidScanResult(items, unresolved, false);
  }
}
