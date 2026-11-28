import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'bridge/embed_session.dart';
import 'screens/home_screen.dart';
import 'services/app_mode.dart';
import 'services/app_settings.dart';
import 'services/library_store.dart';
import 'services/thumb_cache.dart';
import 'services/trash_service.dart';
import 'theme/app_theme.dart';
import 'widgets/embed_mini_player.dart';

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
  runApp(const StreamBridgeApp());
}

class StreamBridgeApp extends StatelessWidget {
  const StreamBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamBridge',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: rootNavigatorKey,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          const EmbedMiniPlayer(),
        ],
      ),
      home: const HomeScreen(),
    );
  }
}
