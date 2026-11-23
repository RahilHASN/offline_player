import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/bridge/providers/youtube_provider.dart';

void main() {
  test('splits Artist - Song and drops (Official Video)', () {
    final (song, artist) = YouTubeProvider.split(
        'Daft Punk - One More Time (Official Video)', 'DaftPunkVEVO');
    expect(song, 'One More Time');
    expect(artist, 'Daft Punk');
  });

  test('uses the channel as artist and removes - Topic', () {
    final (song, artist) =
        YouTubeProvider.split('Blinding Lights', 'The Weeknd - Topic');
    expect(song, 'Blinding Lights');
    expect(artist, 'The Weeknd');
  });
}
