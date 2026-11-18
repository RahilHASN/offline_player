import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
  final ScrollController _scroll = ScrollController();

  bool _searching = false;
  String? _dir; // current folder in Folders view (null = top)
  Set<String> _rootKeys = <String>{};

  String _source = 'all'; // all, phone, pendrive, pc
  bool _headerVisible = true;

  bool _selecting = false;
  final Set<String> _sel = <String>{};

  List<VideoItem>? _lastItems;
  Timer? _sortTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.onDriveAdded = _onDriveAdded;
    _c.addListener(_onLibChanged);
    ThumbnailService.instance.version.addListener(_onThumbVersion);
    _c.init();
    _c.startWatching();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThumbnailService.instance.version.removeListener(_onThumbVersion);
    _c.removeListener(_onLibChanged);
    _sortTimer?.cancel();
    _search.dispose();
    _scroll.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _c.onResumed();
      _c.startWatching();
    } else if (state == AppLifecycleState.paused) {
      PreviewController.instance.stop();
      _c.stopWatching();
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- background work ----------

  void _onLibChanged() {
    if (!mounted || _c.loading) return;
    if (!identical(_c.items, _lastItems)) {
      _lastItems = _c.items;
      ThumbnailService.instance.prefetch(_c.items);
    }
    if (_source == 'pendrive') {
      final has = _c.drives.any((d) => d.removable) ||
          _c.items.any((v) => v.source == VideoSource.pendrive);
      if (!has) setState(() => _source = 'all');
    }
  }

  /// When sorting by length, re-sort now and then as durations arrive.
  void _onThumbVersion() {
    if (AppSettings.instance.sortKey != 'length') return;
    if (_sortTimer?.isActive ?? false) return;
    _sortTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() {});
    });
  }

  void _apply(String source, bool folders) {
    AppSettings.instance.setViewFolders(folders);
    setState(() {
      _source = source;
      _dir = null;
    });
  }

  void _onDriveAdded(List<String> roots) {
    if (!mounted) return;
    PreviewController.instance.stop();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.usb),
              title: const Text('USB drive detected'),
              subtitle: Text(roots.join('\n')),
            ),
            ListTile(
              leading: const Icon(Icons.usb),
              title: const Text('All files in USB storage'),
              onTap: () {
                Navigator.pop(ctx);
                _apply('pendrive', false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('All files in Phone storage'),
              onTap: () {
                Navigator.pop(ctx);
                _apply('phone', false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Browse USB folders'),
              onTap: () {
                Navigator.pop(ctx);
                _apply('pendrive', true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: const Text('Show everything'),
              onTap: () {
                Navigator.pop(ctx);
                _apply('all', false);
              },
            ),
          ],
        ),
      ),
    );
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
      if (_source != 'all' && v.source.name != _source) return false;
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

  /// The videos shown on screen right now (used by Select all).
  List<VideoItem> _currentVideos() {
    final list = _visible();
    if (!AppSettings.instance.viewFolders || _dir == null) return list;
    return FolderTree.level(list, _dir, _c.browseRoots, _c.labelFor).videos;
  }

  String? _up(String dir) {
    if (_rootKeys.contains(dir)) return null;
    final p = FolderTree.parentOf(dir);
    return p.isEmpty ? null : p;
  }

  // ---------- selection ----------

  List<VideoItem> get _selectedItems =>
      _c.items.where((v) => _sel.contains(v.id)).toList();

  void _toggleSel(VideoItem v) {
    setState(() {
      if (!_sel.add(v.id)) _sel.remove(v.id);
    });
  }

  void _startSelect([VideoItem? first]) {
    PreviewController.instance.stop();
    setState(() {
      _selecting = true;
      if (first != null) _sel.add(first.id);
    });
  }

  void _endSelect() {
    setState(() {
      _selecting = false;
      _sel.clear();
    });
  }

  void _selectAll() {
    final ids = _currentVideos().map((v) => v.id).toSet();
    setState(() {
      if (ids.isNotEmpty && _sel.containsAll(ids)) {
        _sel.removeAll(ids);
      } else {
        _sel.addAll(ids);
      }
    });
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
    if (a == VideoAction.select) {
      _startSelect(v);
      return;
    }
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
        await _transfer(<VideoItem>[v], move: true);
        break;
      case VideoAction.copyTo:
        await _transfer(<VideoItem>[v], move: false);
        break;
      case VideoAction.delete:
        await _deleteItems(<VideoItem>[v]);
        break;
      case VideoAction.select:
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

  /// Move or copy one or many videos: pick the destination folder, then do it.
  Future<void> _transfer(List<VideoItem> all, {required bool move}) async {
    final items = all.where((v) => v.path.isNotEmpty).toList();
    if (items.isEmpty) return;
    if (_c.isAndroid && !_c.allFilesAccess) {
      _snack('Allow "All files access" first (menu > Sources).');
      return;
    }
    PreviewController.instance.stop();
    final dest = await FilePicker.platform.getDirectoryPath(
      dialogTitle: move ? 'Move to...' : 'Copy to...',
    );
    if (dest == null) return;
    if (_c.isAndroid && !dest.startsWith('/')) {
      _snack('Could not read that folder as a path. Choose another folder.');
      return;
    }
    _snack('${move ? 'Moving' : 'Copying'} ${items.length}...');
    var ok = 0;
    var failed = 0;
    for (final v in items) {
      try {
        final np = await FileOps.paste(v.path, dest, move: move);
        if (move) LibraryStore.instance.renamePath(v.path, np);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    final word = move ? 'Moved' : 'Copied';
    _snack(failed == 0 ? '$word $ok.' : '$word $ok, failed $failed.');
    if (_selecting) _endSelect();
    await _c.refresh();
  }

  Future<void> _deleteItems(List<VideoItem> all) async {
    final items = all.where((v) => v.path.isNotEmpty).toList();
    if (items.isEmpty) return;
    if (_c.isAndroid && !_c.allFilesAccess) {
      _snack('Allow "All files access" first (menu > Sources).');
      return;
    }
    PreviewController.instance.stop();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(items.length == 1
            ? 'Delete this video?'
            : 'Delete ${items.length} videos?'),
        content: Text(
          items.length == 1
              ? '${items.first.name}\n\nThis cannot be undone.'
              : 'They will be deleted from the device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    var done = 0;
    var failed = 0;
    for (final v in items) {
      try {
        await File(v.path).delete();
        done++;
      } catch (_) {
        failed++;
      }
    }
    _snack(failed == 0 ? 'Deleted $done.' : 'Deleted $done, failed $failed.');
    if (_selecting) _endSelect();
    await _c.refresh();
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
        final list = _visible();
        if (s.viewFolders) {
          _rootKeys = FolderTree.rootKeys(list, _c.browseRoots);
        }
        final inSub = s.viewFolders && _dir != null;
        final land = MediaQuery.orientationOf(context) == Orientation.landscape;
        final showHeader = _headerVisible || _searching || _selecting;

        return PopScope(
          canPop: !inSub && !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selecting) {
              _endSelect();
            } else if (inSub) {
              setState(() => _dir = _up(_dir!));
            }
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      ClipRect(
                        child: AnimatedAlign(
                          alignment: Alignment.topCenter,
                          heightFactor: showHeader ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _selecting
                                  ? _selectionBar(land)
                                  : _topBar(list.length, inSub, land),
                              if (_searching && !_selecting) _tagStrip(),
                              if (!_selecting) _sourceRow(land),
                            ],
                          ),
                        ),
                      ),
                      _filterBar(),
                      Expanded(child: _body(list)),
                    ],
                  ),
                  Positioned.fill(child: _largePreview()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback? onTap, {Color? color}) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 22, color: color),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _topBar(int count, bool inSub, bool land) {
    final store = LibraryStore.instance;
    final h = land ? 40.0 : 52.0;
    final title = inSub ? _c.labelFor(_dir!) : 'Library ($count)';

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            if (inSub)
              _btn(Icons.arrow_back, 'Back',
                  () => setState(() => _dir = _up(_dir!)))
            else
              const SizedBox(width: 12),
            Expanded(
              child: _searching
                  ? TextField(
                      controller: _search,
                      autofocus: true,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Search videos or tags',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
            ),
            _btn(
              _searching ? Icons.close : Icons.search,
              _searching ? 'Close search' : 'Search and tags',
              () {
                setState(() {
                  if (_searching) _search.clear();
                  _searching = !_searching;
                });
              },
            ),
            _btn(
              store.favoritesOnly ? Icons.favorite : Icons.favorite_border,
              'Favorites only',
              () => store.setFavoritesOnly(!store.favoritesOnly),
              color: store.favoritesOnly ? Colors.redAccent : null,
            ),
            _btn(Icons.tune, 'View options', _showViewOptions),
            PopupMenuButton<String>(
              iconSize: 22,
              padding: const EdgeInsets.all(9),
              onSelected: (v) {
                if (v == 'select') _startSelect();
                if (v == 'sources') _showSources();
                if (v == 'settings') _openSettings();
                if (v == 'rescan') _c.refresh();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'select', child: Text('Select')),
                PopupMenuItem(value: 'sources', child: Text('Sources')),
                PopupMenuItem(value: 'rescan', child: Text('Rescan')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(bool land) {
    final h = land ? 40.0 : 52.0;
    final chosen = _selectedItems;
    return Material(
      color: const Color(0xFF23233A),
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            _btn(Icons.close, 'Cancel', _endSelect),
            Expanded(
              child: Text(
                '${_sel.length} selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            _btn(Icons.select_all, 'Select all', _selectAll),
            _btn(Icons.copy, 'Copy to...',
                chosen.isEmpty ? null : () => _transfer(chosen, move: false)),
            _btn(Icons.drive_file_move, 'Move to...',
                chosen.isEmpty ? null : () => _transfer(chosen, move: true)),
            _btn(Icons.delete_outline, 'Delete',
                chosen.isEmpty ? null : () => _deleteItems(chosen)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// All / Phone / USB chips and the folder-view switch.
  Widget _sourceRow(bool land) {
    final s = AppSettings.instance;
    final hasUsb = _c.drives.any((d) => d.removable) ||
        _c.items.any((v) => v.source == VideoSource.pendrive);

    final entries = <String, String>{
      'all': 'All',
      if (_c.isAndroid) 'phone': 'Phone',
      if (_c.isWindows) 'pc': 'PC',
      if (hasUsb) 'pendrive': 'USB',
    };

    int countOf(String key) => key == 'all'
        ? _c.items.length
        : _c.items.where((v) => v.source.name == key).length;

    return SizedBox(
      height: land ? 38 : 46,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final e in entries.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${e.value} (${countOf(e.key)})',
                          style: const TextStyle(fontSize: 12)),
                      selected: _source == e.key,
                      onSelected: (_) => setState(() {
                        _source = e.key;
                        _dir = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          _btn(
            s.viewFolders ? Icons.grid_view : Icons.folder_open,
            s.viewFolders ? 'Show all files' : 'Show folders',
            () {
              s.setViewFolders(!s.viewFolders);
              setState(() => _dir = null);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
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

              return NotificationListener<UserScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis != Axis.vertical) return false;
                  if (n.direction == ScrollDirection.reverse &&
                      _headerVisible &&
                      n.metrics.pixels > 80) {
                    setState(() => _headerVisible = false);
                  } else if (n.direction == ScrollDirection.forward &&
                      !_headerVisible) {
                    setState(() => _headerVisible = true);
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: _c.refresh,
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thickness: const WidgetStatePropertyAll<double>(14),
                      radius: const Radius.circular(7),
                      thumbColor:
                          const WidgetStatePropertyAll<Color>(Colors.white54),
                      minThumbLength: 56,
                    ),
                    child: Scrollbar(
                      controller: _scroll,
                      interactive: true,
                      thumbVisibility: true,
                      child: CustomScrollView(
                        controller: _scroll,
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
                            padding:
                                const EdgeInsets.fromLTRB(pad, pad, 22, pad),
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
                                    selecting: _selecting,
                                    selected: _sel.contains(item.id),
                                    onToggleSelect: () => _toggleSel(item),
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
                    ),
                  ),
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
