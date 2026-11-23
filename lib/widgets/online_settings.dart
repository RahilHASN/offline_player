import 'package:flutter/material.dart';

import '../bridge/providers/youtube_provider.dart';
import '../bridge/registry.dart';
import '../services/app_mode.dart';
import 'youtube_badge.dart';

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
                      'This is the offline-only build. Install the online build to use YouTube.'),
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
              Row(
                children: const [
                  Text('Online settings',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Spacer(),
                  YouTubeBadge(),
                ],
              ),
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
                    m.setYoutubeKey(yt.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
              FutureBuilder<void>(
                future: YouTubeQuota.instance.load(),
                builder: (_, __) {
                  final q = YouTubeQuota.instance;
                  final left = (YouTubeQuota.budget - q.used) ~/ 101;
                  return Text(
                    'Used today: ${q.used} / ${YouTubeQuota.budget} units (about $left searches left)',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Get a key: console.cloud.google.com, enable "YouTube Data API v3", '
                'create an API key and restrict it to that API. The free budget is '
                'about 100 searches a day. The key stays on this device.',
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
                'Also: LRCLIB (lyrics) and MusicBrainz with Cover Art Archive (posters) '
                'for songs on your device. Nothing is fetched unless Online mode is on.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
