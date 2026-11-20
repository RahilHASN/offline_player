import 'dart:convert';
import 'dart:io';

import 'app_mode.dart';

/// The only place in the app that talks to the internet.
class Net {
  static const ua = 'OfflinePlayer/1.0 (personal non-commercial app)';

  /// Returns decoded JSON, or null when the server says 404.
  static Future<dynamic> json(Uri u) async {
    if (!AppMode.instance.online) throw 'Offline mode';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(u);
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw 'Server answered ${res.statusCode}';
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }
}
