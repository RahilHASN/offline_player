import 'dart:convert';
import 'dart:io';

import '../bridge/compliance.dart';
import '../bridge/url_guard.dart';
import 'app_mode.dart';

class ProbeResult {
  final Uri url;
  final String mime;
  final int length;
  const ProbeResult(this.url, this.mime, this.length);
}

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
        final msg = await _errorText(res);
        throw msg ?? 'Server answered ${res.statusCode}';
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

  /// Reads a Google-style {"error":{"message":...}} body. Never includes the URL.
  static Future<String?> _errorText(HttpClientResponse res) async {
    try {
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        final m = (j['error'] as Map)['message'];
        if (m is String && m.isNotEmpty) {
          final t = m.length > 160 ? m.substring(0, 160) : m;
          return '${res.statusCode}: $t';
        }
      }
    } catch (_) {}
    return null;
  }

  /// Checks a pasted link without downloading it. Every redirect is
  /// validated again, so a safe link cannot bounce to an unsafe one.
  static Future<ProbeResult> probe(Uri start) async {
    if (!AppMode.instance.online) throw 'Offline mode';
    var u = start;
    var useGet = false;
    for (var hop = 0; hop < 5; hop++) {
      UrlGuard.parse(u.toString());
      await UrlGuard.assertPublic(u);
      if (Compliance.isYoutubeHost(u.host)) {
        throw 'That media address cannot be played this way.';
      }
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = useGet ? await c.getUrl(u) : await c.headUrl(u);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.userAgentHeader, ua);
        if (useGet) req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final res = await req.close().timeout(const Duration(seconds: 15));
        await res.drain<void>();
        if (res.isRedirect) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          if (loc == null) throw 'Bad redirect.';
          u = u.resolve(loc);
          continue;
        }
        if (!useGet && (res.statusCode == 405 || res.statusCode == 403)) {
          useGet = true;
          continue;
        }
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw 'Server answered ${res.statusCode}';
        }
        return ProbeResult(
          u,
          res.headers.contentType?.mimeType ?? '',
          res.contentLength,
        );
      } finally {
        c.close(force: true);
      }
    }
    throw 'Too many redirects.';
  }
}
