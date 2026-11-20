import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/app_mode.dart';
import 'services/app_settings.dart';
import 'services/library_store.dart';
import 'services/thumb_cache.dart';
import 'services/trash_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppMode.instance.load();
  await AppSettings.instance.load();
  await LibraryStore.instance.load();
  await TrashService.instance.load();
  final limit = AppSettings.instance.cacheLimitMb;
  if (limit > 0) {
    trimThumbCache(limit * 1024 * 1024);
  }
  runApp(const OfflinePlayerApp());
}

class OfflinePlayerApp extends StatelessWidget {
  const OfflinePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Player',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
