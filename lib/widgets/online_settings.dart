import 'package:flutter/material.dart';

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
  final ctrl = TextEditingController(text: m.jamendoId);
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
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Jamendo client ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    m.setJamendoId(ctrl.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Get a free ID: open devportal.jamendo.com, sign up, create an '
                'application (non-commercial) and copy its Client ID.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sources: Jamendo (Creative Commons music), LRCLIB (lyrics), '
                'MusicBrainz and Cover Art Archive (posters), Internet Archive '
                '(music videos). Nothing is fetched unless Online mode is on.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
