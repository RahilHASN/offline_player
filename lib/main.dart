import 'dart:io' show Platform;

import 'package:flutter/material.dart';

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
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
            ? 'Windows'
            : 'Other';
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Player')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill, size: 96),
            const SizedBox(height: 16),
            const Text(
              'Stage 1 works',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Running on $platform'),
          ],
        ),
      ),
    );
  }
}
