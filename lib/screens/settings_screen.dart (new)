import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/thumb_cache.dart';
import '../utils/format.dart';

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

  Future<void> _clear() async {
    await clearThumbCache();
    await _loadSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache cleared. Thumbnails will be made again.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              SwitchListTile(
                title: const Text('Preview sound'),
                subtitle: const Text('Off means previews are muted'),
                value: s.previewAudio,
                onChanged: s.setPreviewAudio,
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Short videos get fewer cuts. Videos under 10 seconds play normally.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Divider(height: 32),
              ListTile(
                title: const Text('Thumbnail cache'),
                subtitle: Text(_bytes == null ? '...' : formatSize(_bytes!)),
                trailing: TextButton(
                  onPressed: _clear,
                  child: const Text('Clear'),
                ),
              ),
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
