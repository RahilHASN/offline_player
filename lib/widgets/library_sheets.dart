import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/app_settings.dart';
import '../services/library_controller.dart';
import '../services/library_store.dart';
import '../utils/format.dart';

// ---------- generic "search, create, tick" sheet ----------

void _checkListSheet(
  BuildContext context, {
  required String heading,
  required String hint,
  required String emptyText,
  required Listenable listenable,
  required List<String> Function() names,
  required bool Function(String) isOn,
  required void Function(String, bool) toggle,
  required String? Function(String) create,
}) {
  final ctrl = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([listenable, ctrl]),
      builder: (ctx, _) {
        final q = ctrl.text.trim().replaceAll(RegExp(r'^#+'), '').trim();
        final all = names();
        final shown = all
            .where((t) => q.isEmpty || t.toLowerCase().contains(q.toLowerCase()))
            .toList();
        final exists = all.any((t) => t.toLowerCase() == q.toLowerCase());
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) {
                  if (create(ctrl.text) != null) ctrl.clear();
                },
              ),
              if (q.isNotEmpty && !exists)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text('Create "$q" and add it to this video'),
                  onTap: () {
                    if (create(ctrl.text) != null) ctrl.clear();
                  },
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (all.isEmpty && q.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(emptyText,
                            style: const TextStyle(color: Colors.white54)),
                      ),
                    for (final t in shown)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: isOn(t),
                        title: Text(t),
                        onChanged: (b) => toggle(t, b == true),
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

void showTagsSheet(BuildContext context, VideoItem v) {
  final store = LibraryStore.instance;
  _checkListSheet(
    context,
    heading: v.name,
    hint: 'Search or create a tag',
    emptyText: 'No tags yet. Type a name above to create one.',
    listenable: store,
    names: () => store.tags,
    isOn: (t) => store.tagsFor(v.key).contains(t),
    toggle: (t, on) {
      final next = <String>{...store.tagsFor(v.key)};
      if (on) {
        next.add(t);
      } else {
        next.remove(t);
      }
      store.setTags(v.key, next);
    },
    create: (text) {
      final n = store.createTag(text);
      if (n != null) {
        store.setTags(v.key, <String>{...store.tagsFor(v.key), n});
      }
      return n;
    },
  );
}

void showPlaylistsSheet(BuildContext context, VideoItem v) {
  final store = LibraryStore.instance;
  _checkListSheet(
    context,
    heading: 'Playlists for ${v.name}',
    hint: 'Search or create a playlist',
    emptyText: 'No playlists yet. Type a name above to create one.',
    listenable: store,
    names: () => store.playlistNames,
    isOn: (t) => store.inPlaylist(t, v.key),
    toggle: (t, on) => store.togglePlaylist(t, v.key, on),
    create: (text) {
      final n = store.createPlaylist(text);
      if (n != null) store.togglePlaylist(n, v.key, true);
      return n;
    },
  );
}

/// Pick a playlist to show. Returns its name, '' for "show all", null if closed.
Future<String?> showPlaylistList(BuildContext context) {
  final store = LibraryStore.instance;
  final ctrl = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([store, ctrl]),
      builder: (ctx, _) {
        final names = store.playlistNames;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playlists',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.grid_view),
                title: const Text('Show all videos'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (names.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No playlists yet. Create one below, then add '
                          'videos from the card menu.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    for (final n in names)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.queue_music),
                        title: Text(n),
                        subtitle:
                            Text('${store.playlistKeys(n).length} videos'),
                        onTap: () => Navigator.pop(ctx, n),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete playlist',
                          onPressed: () => store.deletePlaylist(n),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration:
                          const InputDecoration(hintText: 'New playlist'),
                      onSubmitted: (_) {
                        store.createPlaylist(ctrl.text);
                        ctrl.clear();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      store.createPlaylist(ctrl.text);
                      ctrl.clear();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

void showBookmarksSheet(
  BuildContext context,
  VideoItem v,
  void Function(int ms) onPlayAt,
) {
  final store = LibraryStore.instance;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final list = store.bookmarksFor(v.key);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Bookmarks: ${v.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'No bookmarks yet. Tap the bookmark button in the player '
                    'to save a moment.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ms in list)
                      ListTile(
                        leading: const Icon(Icons.bookmark),
                        title:
                            Text(formatDuration(Duration(milliseconds: ms))),
                        onTap: () {
                          Navigator.pop(ctx);
                          onPlayAt(ms);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => store.removeBookmark(v.key, ms),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ---------- vault PIN ----------

Future<String?> askPin(
  BuildContext context,
  String title, {
  bool confirm = false,
}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(labelText: 'PIN', errorText: err),
            ),
            if (confirm)
              TextField(
                controller: b,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'Repeat PIN'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = a.text.trim();
              if (p.length < 4) {
                setS(() => err = 'Use 4 to 8 digits');
                return;
              }
              if (confirm && p != b.text.trim()) {
                setS(() => err = 'PINs do not match');
                return;
              }
              Navigator.pop(ctx, p);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/// Makes sure the vault is open: asks for a PIN (or creates one the first time).
Future<bool> ensureVaultUnlocked(BuildContext context) async {
  final store = LibraryStore.instance;
  if (store.vaultUnlocked) return true;
  if (!store.hasPin) {
    final pin = await askPin(context, 'Create a vault PIN', confirm: true);
    if (pin == null) return false;
    store.setPin(pin);
    store.unlockVault();
    return true;
  }
  final pin = await askPin(context, 'Enter vault PIN');
  if (pin == null) return false;
  if (store.checkPin(pin)) {
    store.unlockVault();
    return true;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Wrong PIN')));
  }
  return false;
}

// ---------- view options ----------

void showViewOptions(BuildContext context, {required VoidCallback onFoldersChanged}) {
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
                    onFoldersChanged();
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
                        s.sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
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

// ---------- sources ----------

void showSourcesDialog(BuildContext context, LibraryController c) {
  showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
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
                  if (c.isAndroid && !c.allFilesAccess) ...[
                    const Text(
                      'To read pendrives and extra folders, allow '
                      '"All files access" for this app. A settings page '
                      'will open: switch it on, then come back.',
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: c.requestAllFilesAccess,
                      child: const Text('Allow all files access'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (c.canScanFiles) ...[
                    Text('Detected drives', style: titleStyle),
                    if (c.drives.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          c.isAndroid
                              ? 'No pendrive detected. Plug it in, then tap Rescan. '
                                  'If it still does not show, use "Add folder".'
                              : 'No drives found.',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    for (final d in c.drives)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(d.removable ? Icons.usb : Icons.storage),
                        title: Text(d.root),
                        subtitle:
                            Text(d.removable ? 'Removable' : 'Fixed drive'),
                        trailing: c.isAndroid
                            ? const Text('Auto-scanned',
                                style: TextStyle(fontSize: 12))
                            : (c.folders.contains(d.root)
                                ? const Icon(Icons.check)
                                : TextButton(
                                    onPressed: () => c.addPath(d.root),
                                    child: const Text('Add'),
                                  )),
                      ),
                    const SizedBox(height: 12),
                    Text('Folders', style: titleStyle),
                    if (c.folders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No folders added.',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    for (final f in c.folders)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(f, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => c.removeFolder(f),
                        ),
                      ),
                  ],
                  if (c.notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        c.notice!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (c.canScanFiles)
              TextButton(
                onPressed: c.addFolder,
                child: const Text('Add folder'),
              ),
            TextButton(
              onPressed: c.loading ? null : c.refresh,
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
