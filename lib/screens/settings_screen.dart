import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/backup_service.dart';
import '../services/library_store.dart';
import '../services/thumb_cache.dart';
import '../utils/format.dart';
import '../widgets/library_sheets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final b = await thumbCacheBytes();
    if (mounted) setState(() => _bytes = b);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _clear() async {
    await clearThumbCache();
    await _loadSize();
    _snack('Cache cleared. Thumbnails will be made again.');
  }

  Future<void> _export() async {
    try {
      final ok = await BackupService.export();
      _snack(ok ? 'Backup saved.' : 'Backup cancelled.');
    } catch (e) {
      _snack('Backup failed: $e');
    }
  }

  Future<void> _restore() async {
    try {
      final ok = await BackupService.restore();
      _snack(ok ? 'Backup restored.' : 'Restore cancelled.');
    } catch (e) {
      _snack('Restore failed: $e');
    }
  }

  Future<void> _changePin() async {
    if (!await ensureVaultUnlocked(context)) return;
    if (!mounted) return;
    final pin = await askPin(context, 'New vault PIN', confirm: true);
    if (pin == null) return;
    LibraryStore.instance.setPin(pin);
    _snack('PIN changed.');
  }

  Future<void> _removeVault() async {
    if (!LibraryStore.instance.hasPin) {
      _snack('There is no vault PIN yet.');
      return;
    }
    if (!await ensureVaultUnlocked(context)) return;
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove PIN and unhide all?'),
        content: const Text(
            'Every video in the vault becomes visible again and the PIN is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      LibraryStore.instance.clearVault();
      _snack('Vault removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        const head = TextStyle(
            fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w600);
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('PREVIEW', style: head),
              ),
              SwitchListTile(
                title: const Text('Preview sound'),
                subtitle: const Text('Off means previews are muted'),
                value: s.previewAudio,
                onChanged: s.setPreviewAudio,
              ),
              SwitchListTile(
                title: const Text('Smart cuts'),
                subtitle: const Text(
                  'After a video has been previewed once, the app studies it '
                  'in the background and later previews pick the busiest '
                  'moments instead of cutting evenly.',
                ),
                value: s.smartCuts,
                onChanged: s.setSmartCuts,
              ),
              ListTile(
                title: Text('Cuts per preview: ${s.cuts}'),
                subtitle: Slider(
                  value: s.cuts.toDouble(),
                  min: 2,
                  max: 12,
                  divisions: 10,
                  label: '${s.cuts}',
                  onChanged: (v) => s.setCuts(v.round()),
                ),
              ),
              ListTile(
                title: Text(
                    'Length of each cut: ${s.clipSeconds.toStringAsFixed(1)} s'),
                subtitle: Slider(
                  value: s.clipSeconds,
                  min: 1.0,
                  max: 3.0,
                  divisions: 4,
                  label: '${s.clipSeconds.toStringAsFixed(1)} s',
                  onChanged: s.setClipSeconds,
                ),
              ),
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text('PLAYBACK', style: head),
              ),
              SwitchListTile(
                title: const Text('Play next video automatically'),
                value: s.autoNext,
                onChanged: s.setAutoNext,
              ),
              SwitchListTile(
                title: const Text('Resume where I stopped'),
                value: s.autoResume,
                onChanged: s.setAutoResume,
              ),
              SwitchListTile(
                title: const Text('Keep playing in the background'),
                subtitle: const Text(
                    'Android only. Shows a small notification while a video is open.'),
                value: s.backgroundPlay,
                onChanged: s.setBackgroundPlay,
              ),
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text('STORAGE', style: head),
              ),
              ListTile(
                title: const Text('Thumbnail cache'),
                subtitle: Text(_bytes == null ? '...' : formatSize(_bytes!)),
                trailing: TextButton(
                  onPressed: _clear,
                  child: const Text('Clear'),
                ),
              ),
              ListTile(
                title: const Text('Thumbnail cache limit'),
                subtitle: const Text('The oldest thumbnails go first'),
                trailing: DropdownButton<int>(
                  value: const [100, 300, 1000, 0].contains(s.cacheLimitMb)
                      ? s.cacheLimitMb
                      : 300,
                  items: const [
                    DropdownMenuItem(value: 100, child: Text('100 MB')),
                    DropdownMenuItem(value: 300, child: Text('300 MB')),
                    DropdownMenuItem(value: 1000, child: Text('1 GB')),
                    DropdownMenuItem(value: 0, child: Text('No limit')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    s.setCacheLimitMb(v);
                    if (v > 0) {
                      trimThumbCache(v * 1024 * 1024).then((_) => _loadSize());
                    }
                  },
                ),
              ),
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text('VAULT', style: head),
              ),
              ListTile(
                title: const Text('Change vault PIN'),
                onTap: _changePin,
              ),
              ListTile(
                title: const Text('Remove PIN and unhide all'),
                onTap: _removeVault,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'The vault hides videos inside this app only. The files are '
                  'not encrypted, and other apps can still see them. If you '
                  'forget the PIN, clearing the app data is the only way back.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text('BACKUP', style: head),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Back up tags, favorites and settings'),
                subtitle: const Text(
                    'Also saves playlists, bookmarks, watch progress and the vault list'),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Restore from a backup file'),
                onTap: _restore,
              ),
              const Divider(height: 32),
              const ListTile(
                title: Text('Offline'),
                subtitle: Text(
                  'This app has no internet permission and sends nothing anywhere.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
