import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only helpers: picture-in-picture and keeping playback alive.
class NativeBridge {
  static const MethodChannel _ch = MethodChannel('offline/native');

  static Future<bool> enterPip() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _ch.invokeMethod<bool>('pip')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// When on, leaving the app (Home button) shrinks it to a floating window.
  static Future<void> setAutoPip(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<bool>('autoPip', <String, Object>{'on': on});
    } catch (_) {}
  }

  static Future<void> keepAlive(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<bool>(on ? 'keepAlive' : 'release');
    } catch (_) {}
  }
}
