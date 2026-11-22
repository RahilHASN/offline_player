import 'dart:io';
import 'dart:typed_data';

class UrlRejected implements Exception {
  final String message;
  const UrlRejected(this.message);
  @override
  String toString() => message;
}

/// Link safety for pasted addresses: https only, public hosts only.
class UrlGuard {
  static const _blockedSuffix = <String>[
    '.local', '.localhost', '.internal', '.lan', '.home', '.corp',
  ];

  static Uri parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s.length > 2048) {
      throw const UrlRejected('Enter a link (up to 2048 characters).');
    }
    final u = Uri.tryParse(s);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      throw const UrlRejected('That is not a valid link.');
    }
    if (u.scheme != 'https') {
      throw const UrlRejected('Only https links are allowed.');
    }
    if (u.userInfo.isNotEmpty) {
      throw const UrlRejected('Links with a username or password are not allowed.');
    }
    final h = u.host.toLowerCase();
    if (h == 'localhost' || _blockedSuffix.any((x) => h.endsWith(x))) {
      throw const UrlRejected('Local addresses are not allowed.');
    }
    final ip = InternetAddress.tryParse(h);
    if (ip != null && isPrivate(ip)) {
      throw const UrlRejected('Private network addresses are not allowed.');
    }
    return u;
  }

  static bool isPrivate(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4) {
      if (b[0] == 0 || b[0] == 10 || b[0] == 127) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
      if (b[0] == 169 && b[1] == 254) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] >= 224) return true;
      return false;
    }
    if (b.length == 16) {
      if (b.every((x) => x == 0)) return true;
      if ((b[0] & 0xFE) == 0xFC) return true;
      final mapped =
          b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xFF && b[11] == 0xFF;
      if (mapped) {
        return isPrivate(
            InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))));
      }
    }
    return false;
  }

  /// Looks the name up and rejects it if any answer is a private address.
  static Future<void> assertPublic(Uri u) async {
    final ip = InternetAddress.tryParse(u.host);
    if (ip != null) {
      if (isPrivate(ip)) {
        throw const UrlRejected('Private network addresses are not allowed.');
      }
      return;
    }
    List<InternetAddress> r;
    try {
      r = await InternetAddress.lookup(u.host).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const UrlRejected('Could not look up that address.');
    }
    if (r.isEmpty || r.any(isPrivate)) {
      throw const UrlRejected('That address points to a private network.');
    }
  }
}
