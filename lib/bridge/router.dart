import 'dart:io';

import 'compliance.dart';
import 'handoff.dart';
import 'provider.dart';

class ClientProfile {
  final bool canEmbed;
  final bool signedIn;
  const ClientProfile({required this.canEmbed, this.signedIn = false});

  /// The embedded player needs a WebView, which we only ship on Android.
  factory ClientProfile.current() =>
      ClientProfile(canEmbed: Platform.isAndroid);
}

class UserPrefs {
  final bool allowEmbed;
  final bool allowExternal;
  const UserPrefs({this.allowEmbed = true, this.allowExternal = true});
}

/// Picks one handoff. Order: native, official embed, external link.
class PlaybackRouter {
  static int _rank(Handoff h) {
    switch (h.engine) {
      case Engine.native:
        return 0;
      case Engine.officialEmbed:
        return 1;
      case Engine.externalLink:
        return 2;
      case Engine.unavailable:
        return 3;
    }
  }

  static Handoff plan(
    MediaItem item,
    List<Handoff> candidates,
    ClientProfile client,
    UserPrefs prefs,
  ) {
    String? why;
    Handoff? best;
    for (final h in candidates) {
      if (h is UnavailableHandoff) {
        why ??= h.reason;
        continue;
      }
      if (h.constraints.authRequired && !client.signedIn) {
        why ??= 'Sign-in is required to play this.';
        continue;
      }
      if (h is EmbedHandoff && (!client.canEmbed || !prefs.allowEmbed)) {
        continue;
      }
      if (h is ExternalLinkHandoff && !prefs.allowExternal) continue;
      if (best == null || _rank(h) < _rank(best)) best = h;
    }
    if (best == null) {
      return UnavailableHandoff(
        providerId: item.providerId,
        reason: why ?? 'No supported way to play this item here.',
      );
    }
    Compliance.assertHandoff(best);
    return best;
  }
}
