import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

void main() {
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
      ),
      home: const LibraryScreen(),
    );
  }
}
