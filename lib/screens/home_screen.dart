import 'package:flutter/material.dart';

import '../music/music_player.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/online_settings.dart';
import 'library_screen.dart';
import 'music_home_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _music(BuildContext c) {
    Navigator.of(c).push(
      MaterialPageRoute<void>(builder: (_) => const MusicHomeScreen()),
    );
  }

  void _videos(BuildContext c) {
    MusicPlayer.instance.pause();
    Navigator.of(c).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = _BigCard(
      title: 'Music',
      subtitle: 'Songs, posters, lyrics and more',
      icon: Icons.music_note_rounded,
      colors: AppColors.music,
      onTap: () => _music(context),
    );
    final video = _BigCard(
      title: 'Videos',
      subtitle: 'Your videos with instant previews',
      icon: Icons.play_circle_rounded,
      colors: AppColors.video,
      onTap: () => _videos(context),
    );
    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight * 1.2;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Offline Player',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const ModeChip(),
                      IconButton(
                        tooltip: 'Online settings',
                        icon: const Icon(Icons.tune),
                        onPressed: () => showOnlineSettings(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('What do you want to enjoy?',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: wide
                        ? Row(children: [
                            Expanded(child: music),
                            const SizedBox(width: 16),
                            Expanded(child: video),
                          ])
                        : Column(children: [
                            Expanded(child: music),
                            const SizedBox(height: 16),
                            Expanded(child: video),
                          ]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BigCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _BigCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Icon(icon, size: 190, color: Colors.white24),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
