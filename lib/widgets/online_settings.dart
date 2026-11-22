import 'package:flutter/material.dart';

import '../bridge/registry.dart';
import '../services/app_mode.dart';

/// Online / Offline pill. Tap to switch (online build only).
class ModeChip extends StatelessWidget {
  const ModeChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppMode.instance,
      builder: (context, _) {
        final m = AppMode.instance;
        return ActionChip(
          avatar: Icon(m.online ? Icons.cloud_done : Icons.cloud_off, size: 18),
          label: Text(m.online ? 'Online' : 'Offline'),
          onPressed: () {
            if (!AppMode.onlineBuild) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text(
                      'This is the offline-only build. Install the online build to stream music.'),
                ));
              return;
            }
            m.setOnline(!m.online);
          },
        );
      },
    );
  }
}

void showOnlineSettings(BuildContext context) {
  final m = AppMode.instance;
  final jam = TextEditingController(text: m.jamendoId);
  final yt = TextEditingController(text: m.youtubeKey);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: m,
      builder: (ctx, _) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Online settings',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Online mode'),
                subtitle: Text(AppMode.onlineBuild
                    ? 'Off = nothing is ever sent or fetched'
                    : 'This is the offline-only build'),
                value: m.online,
                onChanged: AppMode.onlineBuild ? m.setOnline : null,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: jam,
                decoration: const InputDecoration(
                  labelText: 'Jamendo client ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: yt,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'YouTube Data API key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    m.setJamendoId(jam.text);
                    m.setYoutubeKey(yt.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Jamendo: devportal.jamendo.com, create a non-commercial application, copy its Client ID.\n'
                'YouTube: console.cloud.google.com, enable "YouTube Data API v3", create an API key '
                'and restrict it to that API. The free budget is about 100 searches a day. '
                'The key stays on this device.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text('Sources',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              for (final p in ProviderRegistry.instance.providers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text(p.caps.summary,
                      style: const TextStyle(fontSize: 11)),
                ),
              const Text(
                'Also: LRCLIB (lyrics), MusicBrainz and Cover Art Archive (posters), '
                'Internet Archive (music videos). Nothing is fetched unless Online mode is on.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
