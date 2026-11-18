import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'services/app_settings.dart';
import 'services/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppSettings.instance.load();
  await LibraryStore.instance.load();
  runApp(const OfflinePlayerApp());
}

class OfflinePlayerApp extends StatelessWidget {
  const OfflinePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
      ),
      home: LibraryScreen(),
    );
  }
}
