import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/bridge/compliance.dart';
import 'package:offline_player/bridge/handoff.dart';
import 'package:offline_player/bridge/provider.dart';
import 'package:offline_player/bridge/providers/youtube_provider.dart';
import 'package:offline_player/bridge/router.dart';
import 'package:offline_player/bridge/url_guard.dart';

const _id = 'dQw4w9WgXcQ';

MediaItem _item(String provider) => MediaItem(
      id: 'x',
      providerId: provider,
      title: 't',
      creator: 'c',
      kind: MediaKind.video,
    );

void main() {
  group('Compliance', () {
    test('googlevideo addresses cannot be played natively', () {
      final h = NativeHandoff(
        providerId: 'direct',
        url: 'https://rr1---sn-abc.googlevideo.com/videoplayback?x=1',
        isVideo: false,
      );
      expect(() => Compliance.assertHandoff(h), throwsA(isA<ComplianceError>()));
    });

    test('YouTube can never use the native engine', () {
      final h = NativeHandoff(
          providerId: 'youtube', url: 'https://example.com/a.mp3', isVideo: false);
      expect(() => Compliance.assertHandoff(h), throwsA(isA<ComplianceError>()));
    });

    test('embed is visible, not audio-only, not background', () {
      final h = EmbedHandoff(providerId: 'youtube', videoId: _id);
      expect(h.constraints.playerMustBeVisible, isTrue);
      expect(h.constraints.audioOnly, isFalse);
      expect(h.constraints.backgroundPlayback, isFalse);
      Compliance.assertHandoff(h);
    });

    test('bad video id is rejected', () {
      final h = EmbedHandoff(providerId: 'youtube', videoId: 'x"><script>');
      expect(() => Compliance.assertHandoff(h), throwsA(isA<ComplianceError>()));
    });

    test('embed url only has allowed options', () {
      final h = EmbedHandoff(providerId: 'youtube', videoId: _id);
      expect(h.embedUrl.queryParameters.keys.toSet(), {'playsinline', 'rel'});
    });
  });

  group('UrlGuard', () {
    test('accepts a public https link', () {
      expect(UrlGuard.parse('https://example.com/a.mp3').host, 'example.com');
    });
    test('rejects http', () {
      expect(() => UrlGuard.parse('http://example.com/a.mp3'), throwsA(isA<UrlRejected>()));
    });
    test('rejects local and private hosts', () {
      for (final u in [
        'https://localhost/a.mp3',
        'https://192.168.1.5/a.mp3',
        'https://10.0.0.1/a.mp3',
        'https://127.0.0.1/a.mp3',
        'https://169.254.169.254/latest',
        'https://printer.local/a.mp3',
        'https://[::1]/a.mp3',
      ]) {
        expect(() => UrlGuard.parse(u), throwsA(isA<UrlRejected>()), reason: u);
      }
    });
    test('rejects embedded credentials', () {
      expect(() => UrlGuard.parse('https://user:pw@example.com/a.mp3'),
          throwsA(isA<UrlRejected>()));
    });
  });

  group('YouTube links', () {
    test('finds the video id', () {
      for (final u in [
        'https://www.youtube.com/watch?v=$_id',
        'https://youtu.be/$_id',
        'https://www.youtube.com/embed/$_id',
        'https://www.youtube.com/shorts/$_id',
        'https://m.youtube.com/watch?v=$_id&t=5',
      ]) {
        expect(YouTubeProvider.idFromUri(Uri.parse(u)), _id, reason: u);
      }
    });
    test('returns null without an id', () {
      expect(YouTubeProvider.idFromUri(Uri.parse('https://www.youtube.com/')), isNull);
    });
    test('parses durations', () {
      expect(YouTubeProvider.parseDuration('PT1H2M3S'), 3723);
      expect(YouTubeProvider.parseDuration('PT45S'), 45);
    });
  });

  group('PlaybackRouter', () {
    final yt = _item('youtube');
    List<Handoff> ytHandoffs() => YouTubeProvider.instance
        .handoffs(MediaItem(
          id: 'y:$_id',
          providerId: 'youtube',
          title: 't',
          creator: 'c',
          kind: MediaKind.video,
          videoId: _id,
        ));

    test('Android uses the official embed', () {
      final h = PlaybackRouter.plan(yt, ytHandoffs(),
          const ClientProfile(canEmbed: true), const UserPrefs());
      expect(h.engine, Engine.officialEmbed);
    });

    test('Windows falls back to the external link', () {
      final h = PlaybackRouter.plan(yt, ytHandoffs(),
          const ClientProfile(canEmbed: false), const UserPrefs());
      expect(h.engine, Engine.externalLink);
    });

    test('nothing allowed gives unavailable', () {
      final h = PlaybackRouter.plan(
          yt,
          ytHandoffs(),
          const ClientProfile(canEmbed: true),
          const UserPrefs(allowEmbed: false, allowExternal: false));
      expect(h.engine, Engine.unavailable);
    });

    test('native beats embed', () {
      final n = NativeHandoff(
          providerId: 'direct', url: 'https://example.com/a.mp3', isVideo: false);
      final e = EmbedHandoff(providerId: 'youtube', videoId: _id);
      final h = PlaybackRouter.plan(_item('direct'), [e, n],
          const ClientProfile(canEmbed: true), const UserPrefs());
      expect(h.engine, Engine.native);
    });

    test('YouTube never routes natively', () {
      final bad = NativeHandoff(
          providerId: 'youtube', url: 'https://example.com/a.mp3', isVideo: false);
      expect(
          () => PlaybackRouter.plan(yt, [bad],
              const ClientProfile(canEmbed: true), const UserPrefs()),
          throwsA(isA<ComplianceError>()));
    });
  });
}
