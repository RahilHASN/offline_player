import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/file_ops.dart';
import '../services/folder_tree.dart';
import '../services/library_controller.dart';
import '../services/library_store.dart';
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
  String? _dir; // current folder in Folders view (null = top)
  Set<String> _rootKeys = <String>{};

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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- data ----------

  String get _tagQuery =>
      _search.text.trim().replaceAll(RegExp(r'^#+'), '').trim();

  List<VideoItem> _visible() {
    final s = AppSettings.instance;
    final store = LibraryStore.instance;
    final raw = _search.text.trim().toLowerCase();
    final tagOnly = raw.startsWith('#');
    final tq = _tagQuery.toLowerCase();

    final list = _c.items.where((v) {
      if (tq.isNotEmpty) {
        final tagHit =
            store.tagsFor(v.path).any((t) => t.toLowerCase().contains(tq));
        final nameHit = !tagOnly && v.name.toLowerCase().contains(tq);
        if (!tagHit && !nameHit) return false;
      }
      if (store.filtering && !store.matches(v.path)) return false;
      return true;
    }).toList();

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

  String? _up(String dir) {
    if (_rootKeys.contains(dir)) return null;
    final p = FolderTree.parentOf(dir);
    return p.isEmpty ? null : p;
  }

  // ---------- actions ----------

  void _openVideo(VideoItem item) {
    if (item.path.isEmpty) {
      _snack('This video has no readable file path.');
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

  Future<void> _onAction(VideoItem v, VideoAction a) async {
    if (v.path.isEmpty) {
      _snack('This video has no readable file path.');
      return;
    }
    switch (a) {
      case VideoAction.play:
        _openVideo(v);
        break;
      case VideoAction.favorite:
        LibraryStore.instance.toggleFav(v.path);
        break;
      case VideoAction.tags:
        _editTags(v);
        break;
      case VideoAction.rename:
        await _rename(v);
        break;
      case VideoAction.moveTo:
        await _transfer(v, move: true);
        break;
      case VideoAction.copyTo:
        await _transfer(v, move: false);
        break;
    }
  }

  Future<void> _rename(VideoItem v) async {
    final ctrl = TextEditingController(text: v.name);
    final dot = v.name.lastIndexOf('.');
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : v.name.length,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == v.name) return;
    try {
      final np = await FileOps.rename(v.path, newName);
      LibraryStore.instance.renamePath(v.path, np);
      await _c.refresh();
    } catch (e) {
      _snack('Could not rename: $e');
    }
  }

  /// Move or copy: pick the destination folder, then do it.
  Future<void> _transfer(VideoItem v, {required bool move}) async {
    if (_c.isAndroid && !_c.allFilesAccess) {
      _snack('Allow "All files access" first (menu > Sources).');
      return;
    }
    final dest = await FilePicker.platform.getDirectoryPath(
      dialogTitle: move ? 'Move to...' : 'Copy to...',
    );
    if (dest == null) return;
    if (_c.isAndroid && !dest.startsWith('/')) {
      _snack('Could not read that folder as a path. Choose another folder.');
      return;
    }
    _snack(move ? 'Moving...' : 'Copying...');
    try {
      final np = await FileOps.paste(v.path, dest, move: move);
      if (move) LibraryStore.instance.renamePath(v.path, np);
      _snack(move ? 'Moved.' : 'Copied.');
      await _c.refresh();
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  /// Tags for one video: search, create, tick. Every tap is saved at once.
  void _editTags(VideoItem v) {
    final store = LibraryStore.instance;
    final ctrl = TextEditingController();

    void create() {
      final n = store.createTag(ctrl.text);
      if (n != null) {
        store.setTags(v.path, <String>{...store.tagsFor(v.path), n});
        ctrl.clear();
      }
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([store, ctrl]),
        builder: (ctx, _) {
          final q = ctrl.text.trim().replaceAll(RegExp(r'^#+'), '').trim();
          final cur = store.tagsFor(v.path);
          final shown = store.tags
              .where((t) =>
                  q.isEmpty || t.toLowerCase().contains(q.toLowerCase()))
              .toList();
          final exists =
              store.tags.any((t) => t.toLowerCase() == q.toLowerCase());
          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search or create a tag',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => create(),
                ),
                if (q.isNotEmpty && !exists)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text('Create "$q" and add it to this video'),
                    onTap: create,
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (store.tags.isEmpty && q.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No tags yet. Type a name above to create one.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      for (final t in shown)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: cur.contains(t),
                          title: Text(t),
                          onChanged: (b) {
                            final next = <String>{...store.tagsFor(v.path)};
                            if (b == true) {
                              next.add(t);
                            } else {
                              next.remove(t);
                            }
                            store.setTags(v.path, next);
                          },
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteTag(String t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Delete tag "$t"?'),
        content: const Text('It will be removed from all videos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) LibraryStore.instance.deleteTag(t);
  }

  void _showViewOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (ctx, _) {
          final s = AppSettings.instance;
          const heading = TextStyle(fontSize: 13, color: Colors.white54);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Show', style: heading),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('All files'),
                        icon: Icon(Icons.grid_view),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Folders'),
                        icon: Icon(Icons.folder),
                      ),
                    ],
                    selected: {s.viewFolders},
                    onSelectionChanged: (v) {
                      s.setViewFolders(v.first);
                      setState(() => _dir = null);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Columns', style: heading),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Auto')),
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {s.columns},
                    onSelectionChanged: (v) => s.setColumns(v.first),
                  ),
                  const SizedBox(height: 16),
                  const Text('Sort by', style: heading),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in const {
                        'name': 'Name',
                        'date': 'Date',
                        'length': 'Length',
                        'size': 'Size',
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: s.sortKey == e.key,
                          onSelected: (_) => s.setSort(
                            e.key,
                            s.sortKey == e.key ? s.sortAsc : e.key == 'name',
                          ),
                        ),
                      ActionChip(
                        avatar: Icon(
                          s.sortAsc
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16,
                        ),
                        label: Text(s.sortAsc ? 'Ascending' : 'Descending'),
                        onPressed: () => s.setSort(s.sortKey, !s.sortAsc),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Large preview window'),
                    subtitle: const Text(
                        'Show the preview in a big window instead of on the card'),
                    value: s.largePreview,
                    onChanged: s.setLargePreview,
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
                          leading:
                              Icon(d.removable ? Icons.usb : Icons.storage),
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

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _c,
        AppSettings.instance,
        LibraryStore.instance,
      ]),
      builder: (context, _) {
        final s = AppSettings.instance;
        final store = LibraryStore.instance;
        final list = _visible();
        if (s.viewFolders) {
          _rootKeys = FolderTree.rootKeys(list, _c.browseRoots);
        }
        final inSub = s.viewFolders && _dir != null;

        return PopScope(
          canPop: !inSub,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && inSub) {
              setState(() => _dir = _up(_dir!));
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: inSub
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _dir = _up(_dir!)),
                    )
                  : null,
              title: _searching
                  ? TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search videos or tags',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : Text(
                      inSub
                          ? _c.labelFor(_dir!)
                          : 'Library (${list.length})',
                      overflow: TextOverflow.ellipsis,
                    ),
              actions: [
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search and tags',
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      if (_searching) _search.clear();
                      _searching = !_searching;
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Favorites only',
                  icon: Icon(
                    store.favoritesOnly
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: store.favoritesOnly ? Colors.redAccent : null,
                  ),
                  onPressed: () =>
                      store.setFavoritesOnly(!store.favoritesOnly),
                ),
                IconButton(
                  tooltip: 'View options',
                  icon: const Icon(Icons.tune),
                  onPressed: _showViewOptions,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'sources') _showSources();
                    if (v == 'settings') _openSettings();
                    if (v == 'rescan') _c.refresh();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'sources', child: Text('Sources')),
                    PopupMenuItem(value: 'rescan', child: Text('Rescan')),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
              ],
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    if (_searching) _tagStrip(),
                    _filterBar(),
                    Expanded(child: _body(list)),
                  ],
                ),
                Positioned.fill(child: _largePreview()),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tags under the search bar: pick to filter, create when nothing matches.
  Widget _tagStrip() {
    final store = LibraryStore.instance;
    final q = _tagQuery;
    final ql = q.toLowerCase();
    final exists = store.tags.any((t) => t.toLowerCase() == ql);
    final shown = store.tags
        .where((t) => ql.isEmpty || t.toLowerCase().contains(ql))
        .toList();

    final chips = <Widget>[];

    if (q.isNotEmpty && !exists) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: Text('Create tag "$q"'),
          onPressed: () {
            final n = store.createTag(q);
            if (n != null) {
              setState(() => _search.clear());
              _snack('Tag "$n" created. Add it to videos from the ⋮ menu.');
            }
          },
        ),
      ));
    }

    if (store.selected.length > 1) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          avatar: const Icon(Icons.filter_alt, size: 16),
          label: Text(store.matchAll ? 'Match: all' : 'Match: any'),
          onPressed: () => store.setMatchAll(!store.matchAll),
        ),
      ));
    }

    for (final t in shown) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onLongPress: () => _confirmDeleteTag(t),
          child: FilterChip(
            label: Text('$t (${store.countFor(t)})'),
            selected: store.selected.contains(t),
            onSelected: (_) => store.toggleSelected(t),
          ),
        ),
      ));
    }

    if (chips.isEmpty) {
      chips.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Type a name to create a tag.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ));
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: chips,
      ),
    );
  }

  Widget _filterBar() {
    final store = LibraryStore.instance;
    if (!store.filtering) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          if (store.favoritesOnly)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                avatar: const Icon(Icons.favorite,
                    size: 16, color: Colors.redAccent),
                label: const Text('Favorites'),
                onDeleted: () => store.setFavoritesOnly(false),
              ),
            ),
          for (final t in store.selected)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                label: Text('#$t'),
                onDeleted: () => store.toggleSelected(t),
              ),
            ),
          TextButton(
            onPressed: store.clearFilters,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _largePreview() {
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
                        padding: const EdgeInsets.fromLTRB(12, 8, 52, 8),
                        color: Colors.black45,
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 6,
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

    final s = AppSettings.instance;
    FolderLevel? level;
    var videos = list;
    if (s.viewFolders) {
      level = FolderTree.level(list, _dir, _c.browseRoots, _c.labelFor);
      videos = level.videos;
    }

    return Column(
      children: [
        if (_c.loading) const LinearProgressIndicator(minHeight: 2),
        if (_c.unresolved > 0 && !s.viewFolders)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${_c.unresolved} videos have an unknown file path and cannot be played.',
              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final n = s.columns == 0
                  ? max(2, (w / 240).floor())
                  : s.columns;
              const pad = 8.0;
              const gap = 8.0;
              final cellW = (w - pad * 2 - gap * (n - 1)) / n;
              final extent = cellW * 9 / 16 + 76;
              final folders = level?.folders ?? const <FolderEntry>[];

              if (level != null && folders.isEmpty && videos.isEmpty) {
                return const Center(
                  child: Text('This folder has no videos.',
                      style: TextStyle(color: Colors.white54)),
                );
              }

              return RefreshIndicator(
                onRefresh: _c.refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (folders.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final f = folders[i];
                            return ListTile(
                              leading: const Icon(Icons.folder,
                                  color: Colors.amber),
                              title: Text(f.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${f.count} video${f.count == 1 ? '' : 's'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => setState(() => _dir = f.path),
                            );
                          },
                          childCount: folders.length,
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.all(pad),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: n,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          mainAxisExtent: extent,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final item = videos[i];
                            return VideoCard(
                              key: ValueKey(item.id),
                              item: item,
                              onOpen: () => _openVideo(item),
                              onAction: (a) => _onAction(item, a),
                            );
                          },
                          childCount: videos.length,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
