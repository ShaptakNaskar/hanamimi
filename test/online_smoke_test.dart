@Tags(['online'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/online/models/resolved_stream.dart';
import 'package:hanamimi/online/saavn_provider.dart';
import 'package:hanamimi/online/youtube_provider.dart';
import 'package:http/http.dart' as http;

/// Live-network smoke test (run explicitly: flutter test -t online).
/// Proves search + stream extraction against today's YouTube.
void main() {
  test('YouTube search and stream resolution', () async {
    final provider = YouTubeProvider();
    final hits = await provider.search('lofi hip hop');
    expect(hits, isNotEmpty);
    expect(hits.first.source, TrackSource.youtube);
    expect(hits.first.sourceId, isNotEmpty);

    final stream =
        await provider.resolveStream(hits.first.sourceId, StreamQuality.high);
    expect(stream, isNotNull);
    expect(stream!.url.toString(), startsWith('https://'));
    expect(stream.expiresAt.isAfter(DateTime.now()), isTrue);
    // ignore: avoid_print
    print('resolved: ${stream.codec} ${stream.bitrateKbps}kbps '
        'expires ${stream.expiresAt}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('JioSaavn search and stream resolution', () async {
    final provider = SaavnProvider();
    final hits = await provider.search('tum hi ho');
    expect(hits, isNotEmpty);
    expect(hits.first.source, TrackSource.saavn);
    expect(hits.first.duration.inSeconds, greaterThan(0));

    final stream =
        await provider.resolveStream(hits.first.sourceId, StreamQuality.high);
    expect(stream, isNotNull);
    expect(stream!.url.toString(), startsWith('https://'));

    // The decrypted, quality-substituted URL must actually serve.
    final head = await http.head(stream.url);
    expect(head.statusCode, 200);
    // ignore: avoid_print
    print('resolved: ${stream.codec} ${stream.bitrateKbps}kbps '
        '→ HTTP ${head.statusCode}, ${head.headers['content-length']} bytes');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('YT Music radio (Tier 1 relatedSongs) returns fresh songs',
      () async {
    final provider = YouTubeProvider();
    final hits = await provider.searchMusic('daft punk get lucky');
    expect(hits, isNotEmpty);
    final seed = hits.first.sourceId;

    final related = await provider.relatedSongs(seed);
    expect(related.length, greaterThanOrEqualTo(5),
        reason: 'radio queue should carry a real set of songs');
    expect(related.map((r) => r.sourceId), isNot(contains(seed)));
    expect(related.first.title, isNotEmpty);
    // ignore: avoid_print
    print('radio: ${related.take(5).map((r) => '${r.title} — ${r.artist}')}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('JioSaavn reco.getreco (Tier 1 similarSongs) returns playable rows',
      () async {
    final provider = SaavnProvider();
    final hits = await provider.search('tum hi ho');
    expect(hits, isNotEmpty);
    final seed = hits.first.sourceId;

    final similar = await provider.similarSongs(seed);
    expect(similar, isNotEmpty,
        reason: 'Saavn recommender should answer for a mainstream seed');
    expect(similar.first.duration.inSeconds, greaterThan(0),
        reason: 'rows come through song.getDetails, so durations exist');
    // ignore: avoid_print
    print('reco: ${similar.take(5).map((r) => '${r.title} — ${r.artist}')}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
