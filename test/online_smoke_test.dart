@Tags(['online'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/online/models/resolved_stream.dart';
import 'package:hanamimi/online/youtube_provider.dart';

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
}
