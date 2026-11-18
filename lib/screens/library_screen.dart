import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/library_controller.dart';
import '../services/preview_controller.dart';
import '../services/thumbnail_service.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final LibraryController _c = LibraryController();
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _c.onResumed();
    } else if (state == AppLifecycleState.paused) {
      PreviewController.instance.stop();
    }
  }

  List<VideoItem> _visible() {
    final s = AppSettings.instance;
    final q = _search.text.trim().toLowerCase();
    final list = _c.items
        .where((v) => q.isEmpty || v.name.toLowerCase().contains(q))
        .toList();

    Duration dur(VideoItem v) =>
        ThumbnailService.instance.durations[v.id] ??
        v.duration ??
        Duration.zero;

    int cmp(VideoItem a, VideoItem b) {
      switch (s.sortKey) {
        case 'date':
          return a.date.compareTo(b.date);
        case 'length':
          return dur(a).compareTo(dur(b));
        case 'size':
          return a.sizeBytes.compareTo(b.sizeBytes);
        default:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    }

    list.sort((a, b) => s.sortAsc ? cmp(a, b) : cmp(b, a));
    return list;
  }

  void _openVideo(VideoItem item) {
    if (item.path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This video has no readable file path.')),
      );
      return;
    }
    PreviewController.instance.stop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen(item: item)),
    );
  }

  void _openSettings() {
    PreviewController.instance.stop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _showSources() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: _c,
        builder: (ctx, _) {
          final titleStyle = Theme.of(ctx).textTheme.titleSmall;
          return AlertDialog(
            title: const Text('Sources'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_c.isAndroid && !_c.allFilesAccess) ...[
                      const Text(
                        'To read pendrives and extra folders, allow '
                        '"All files access" for this app. A settings page '
                        'will open: switch it on, then come back.',
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _c.requestAllFilesAccess,
                        child: const Text('Allow all files access'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_c.canScanFiles) ...[
                      Text('Detected drives', style: titleStyle),
                      if (_c.drives.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _c.isAndroid
                                ? 'No pendrive detected. Plug it in, then tap Rescan. '
                                    'If it still does not show, use "Add folder".'
                                : 'No drives found.',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      for (final d in _c.drives)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              d.removable ? Icons.usb : Icons.storage),
                          title: Text(d.root),
                          subtitle:
                              Text(d.removable ? 'Removable' : 'Fixed drive'),
                          trailing: _c.isAndroid
                              ? const Text('Auto-scanned',
                                  style: TextStyle(fontSize: 12))
                              : (_c.folders.contains(d.root)
                                  ? const Icon(Icons.check)
                                  : TextButton(
                                      onPressed: () => _c.addPath(d.root),
                                      child: const Text('Add'),
                                    )),
                        ),
                      const SizedBox(height: 12),
                      Text('Folders', style: titleStyle),
                      if (_c.folders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No folders added.',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      for (final f in _c.folders)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => _c.removeFolder(f),
                          ),
                        ),
                    ],
                    if (_c.notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _c.notice!,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (_c.canScanFiles)
                TextButton(
                  onPressed: _c.addFolder,
                  child: const Text('Add folder'),
                ),
              TextButton(
                onPressed: _c.loading ? null : _c.refresh,
                child: const Text('Rescan'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sortRow(String label, String key) {
    final s = AppSettings.instance;
    final selected = s.sortKey == key;
    return Row(
      children: [
        Expanded(child: Text(label)),
        if (selected)
          Icon(s.sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, AppSettings.instance]),
      builder: (context, _) {
        final list = _visible();
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search videos',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                : Text('Library (${list.length})'),
            actions: [
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    if (_searching) _search.clear();
                    _searching = !_searching;
                  });
                },
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onSelected: (key) {
                  final s = AppSettings.instance;
                  if (key == s.sortKey) {
                    s.setSort(key, !s.sortAsc);
                  } else {
                    s.setSort(key, key == 'name');
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'name', child: _sortRow('Name', 'name')),
                  PopupMenuItem(value: 'date', child: _sortRow('Date', 'date')),
                  PopupMenuItem(
                      value: 'length', child: _sortRow('Length', 'length')),
                  PopupMenuItem(value: 'size', child: _sortRow('Size', 'size')),
                ],
              ),
              IconButton(
                tooltip: 'Sources',
                icon: const Icon(Icons.usb),
                onPressed: _showSources,
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
              ),
            ],
          ),
          body: _body(list),
        );
      },
    );
  }

  Widget _body(List<VideoItem> list) {
    if (_c.loading && _c.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_c.error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: 'Something went wrong:\n${_c.error}',
        buttonLabel: 'Try again',
        onPressed: _c.refresh,
      );
    }
    if (_c.permissionDenied) {
      return _Message(
        icon: Icons.lock_outline,
        text: 'Allow video access so the app can list your videos.',
        buttonLabel: 'Allow access',
        onPressed: _c.refresh,
        secondaryLabel: 'Open settings',
        onSecondary: PhotoManager.openSetting,
      );
    }
    if (_c.isWindows && _c.folders.isEmpty) {
      return _Message(
        icon: Icons.folder_open,
        text: 'Add a folder or drive to build your library.',
        buttonLabel: 'Add folder',
        onPressed: _c.addFolder,
        secondaryLabel: 'Show drives',
        onSecondary: _showSources,
      );
    }
    if (_c.items.isEmpty) {
      return _Message(
        icon: Icons.video_library_outlined,
        text: 'No videos found.',
        buttonLabel: 'Rescan',
        onPressed: _c.refresh,
      );
    }
    if (list.isEmpty) {
      return const Center(
        child: Text('No matches.', style: TextStyle(color: Colors.white54)),
      );
    }
    return Column(
      children: [
        if (_c.loading) const LinearProgressIndicator(minHeight: 2),
        if (_c.unresolved > 0)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${_c.unresolved} videos have an unknown file path and cannot be played.',
              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _c.refresh,
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final item = list[i];
                return VideoCard(
                  key: ValueKey(item.id),
                  item: item,
                  onOpen: () => _openVideo(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _Message({
    required this.icon,
    required this.text,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white38),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
