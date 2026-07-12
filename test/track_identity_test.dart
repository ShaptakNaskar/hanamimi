import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/reco/taste_fingerprint.dart';
import 'package:hanamimi/utils/track_identity.dart';

void main() {
  group('normalization (3.0 #7 — shared by history + MinHash)', () {
    test('strips featuring credits in every spelling', () {
      expect(normalizeTitle('Song (feat. Someone)'), 'song');
      expect(normalizeTitle('Song ft. Someone'), 'song');
      expect(normalizeTitle('Song featuring Someone'), 'song');
      expect(normalizeArtist('YOASOBI feat. Ado'), 'yoasobi');
    });

    test('case and whitespace collapse', () {
      expect(normalizeTitle('  Racing   Into The Night '),
          'racing into the night');
    });

    test('identity key ties title, artist and duration bucket', () {
      final a = identityKey(
          title: 'Idol',
          artist: 'YOASOBI',
          duration: const Duration(seconds: 213));
      final b = identityKey(
          title: 'IDOL (feat. nobody)',
          artist: 'yoasobi',
          duration: const Duration(seconds: 215));
      expect(a, b); // same 10s bucket, same normalized names

      final c = identityKey(
          title: 'Idol',
          artist: 'YOASOBI',
          duration: const Duration(seconds: 300));
      expect(a, isNot(c)); // radio edit vs album cut
    });
  });

  group('taste fingerprint (3.0 #5)', () {
    Map<String, int> artists(int n) =>
        {for (var i = 0; i < n; i++) 'artist $i': 1000 - i};

    test('below the minimum artist count there is no signature', () {
      expect(buildTasteSignature(artists(tasteMinArtists - 1)), isNull);
      expect(buildTasteSignature(artists(tasteMinArtists)), isNotNull);
    });

    test('deterministic across calls (device-independent contract)', () {
      expect(buildTasteSignature(artists(30)),
          buildTasteSignature(artists(30)));
    });

    test('signature has the wire shape the backend validates', () {
      final sig = buildTasteSignature(artists(30))!;
      expect(sig.length, tasteSignatureSize);
      expect(sig.every((v) => v >= 0 && v <= 0xFFFFFFFF), isTrue);
    });

    test('identical taste = 100% match, disjoint taste ≈ 0%', () {
      final a = buildTasteSignature(artists(30))!;
      final b = buildTasteSignature(artists(30))!;
      final disjoint = buildTasteSignature(
          {for (var i = 0; i < 30; i++) 'other $i': 500})!;

      int matches(List<int> x, List<int> y) => [
            for (var i = 0; i < x.length; i++)
              if (x[i] == y[i]) 1
          ].length;

      expect(matches(a, b), tasteSignatureSize);
      expect(matches(a, disjoint), lessThan(tasteSignatureSize ~/ 4));
    });

    test('feat. credits merge into the lead artist before hashing', () {
      final plain = buildTasteSignature(
          {for (var i = 0; i < 15; i++) 'artist $i': 100});
      final feats = buildTasteSignature({
        for (var i = 0; i < 15; i++) 'Artist $i feat. Guest': 100,
      });
      expect(plain, feats);
    });
  });
}
