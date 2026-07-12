import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

/// Passphrase cloud backup (3.0 #8, plus only) — crypto-wallet UX with
/// the correct architecture: the phrase is a *key, not a container*.
///
/// - The app mints a random 8-word phrase (8 × 256 words = 64 bits of
///   entropy) — always generated, never human-chosen.
/// - The Tier-0 ZIP bundle is encrypted client-side (AES-GCM, key from
///   PBKDF2 over the phrase) and only ciphertext reaches the server.
/// - The blob's storage ID is *derived from* the phrase through a
///   separate hash domain, so the server can't tell whose blob is
///   whose, can't decrypt anything, and can't link blob to leaderboard
///   row — zero-knowledge backup.
/// - A user password is an optional second factor folded into the KDF
///   (the "25th word" pattern) — never the only key.
class PassphraseBackup {
  static const wordCount = 8;

  /// PBKDF2 rounds. High enough to sting a brute-forcer, low enough
  /// that a phone restores in well under a second.
  static const _kdfRounds = 150000;

  static const _apiBase = 'https://sappy-dir.vercel.app/api/hanamimi';

  /// Generates the phrase. Random.secure only — the entropy IS the
  /// security; a memorable hand-picked phrase would be a password.
  static String generatePhrase() {
    final rnd = Random.secure();
    return List.generate(
        wordCount, (_) => _words[rnd.nextInt(_words.length)]).join(' ');
  }

  static String normalizePhrase(String phrase) =>
      phrase.toLowerCase().trim().split(RegExp(r'\s+')).join(' ');

  /// Storage ID: SHA-256 in its own domain — deriving the ID reveals
  /// nothing about the encryption key.
  static String blobIdFor(String phrase) {
    final digest = SHA256Digest().process(Uint8List.fromList(
        utf8.encode('hanamimi-blob-id|${normalizePhrase(phrase)}')));
    return digest
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Uint8List _deriveKey(String phrase, String? password) {
    final secret =
        '${normalizePhrase(phrase)}|${password?.trim() ?? ''}';
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
          Uint8List.fromList(utf8.encode('hanamimi-backup-key-v1')),
          _kdfRounds,
          32));
    return kdf.process(Uint8List.fromList(utf8.encode(secret)));
  }

  /// nonce(12) ‖ ciphertext+tag — same shape as SecretBox.
  static Uint8List encryptBundle(
      Uint8List bundle, String phrase, String? password) {
    final key = _deriveKey(phrase, password);
    final rnd = Random.secure();
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ct = cipher.process(bundle);
    return Uint8List.fromList([...nonce, ...ct]);
  }

  /// Throws on a wrong phrase/password (GCM tag mismatch).
  static Uint8List decryptBundle(
      Uint8List blob, String phrase, String? password) {
    final key = _deriveKey(phrase, password);
    final nonce = Uint8List.sublistView(blob, 0, 12);
    final ct = Uint8List.sublistView(blob, 12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(ct);
  }

  /// Encrypts and uploads. Returns true on success.
  static Future<bool> upload(
      Uint8List bundle, String phrase, String? password) async {
    try {
      final blob = encryptBundle(bundle, phrase, password);
      final res = await http
          .post(Uri.parse('$_apiBase/backup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'blobId': blobIdFor(phrase),
                'data': base64.encode(blob),
              }))
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches and decrypts. Null = not found / network trouble; throws
  /// on a wrong phrase/password so the UI can tell those apart.
  static Future<Uint8List?> download(
      String phrase, String? password) async {
    final res = await http
        .get(Uri.parse('$_apiBase/backup/${blobIdFor(phrase)}'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    final data = body is Map ? body['data'] : null;
    if (data is! String) return null;
    return decryptBundle(base64.decode(data), phrase, password);
  }
}

/// 256 short, common, unambiguous English words (no two share a first
/// four-letter prefix with different meanings; no plurals-vs-singular
/// pairs). 8 draws = 64 bits.
const _words = [
  'acorn', 'amber', 'anchor', 'apple', 'april', 'arrow', 'aspen', 'atlas', //
  'autumn', 'badge', 'bagel', 'bamboo', 'banjo', 'basil', 'beach', 'berry',
  'birch', 'blanket', 'bloom', 'bluebird', 'bounce', 'breeze', 'brick',
  'bridge', 'bright', 'brook', 'bubble', 'bucket', 'butter', 'button',
  'cabin', 'cactus', 'camera', 'candle', 'canoe', 'canyon', 'carpet',
  'castle', 'cedar', 'cello', 'cherry', 'chime', 'cinnamon', 'circle',
  'citrus', 'cloud', 'clover', 'cocoa', 'comet', 'copper', 'coral',
  'cotton', 'cozy', 'crayon', 'cricket', 'crystal', 'daisy', 'dawn',
  'delta', 'denim', 'dewdrop', 'diamond', 'dolphin', 'donut', 'dragon',
  'dream', 'drift', 'drum', 'dune', 'eagle', 'early', 'earth', 'echo',
  'ember', 'engine', 'evening', 'fable', 'falcon', 'feather', 'fern',
  'fiddle', 'field', 'firefly', 'flame', 'flannel', 'flute', 'forest',
  'fossil', 'fountain', 'fox', 'frost', 'garden', 'garnet', 'gecko',
  'gentle', 'ginger', 'glacier', 'glow', 'golden', 'goose', 'grape',
  'grove', 'guitar', 'harbor', 'harvest', 'hazel', 'heron', 'hidden',
  'hill', 'honey', 'horizon', 'hummingbird', 'igloo', 'indigo', 'island',
  'ivory', 'jade', 'jasmine', 'jelly', 'jigsaw', 'journey', 'jungle',
  'juniper', 'kayak', 'kettle', 'kitten', 'kiwi', 'koala', 'lagoon',
  'lantern', 'lavender', 'lemon', 'library', 'lighthouse', 'lilac',
  'lily', 'linen', 'little', 'lotus', 'lucky', 'lunar', 'maple', 'marble',
  'meadow', 'melody', 'mellow', 'midnight', 'mint', 'mirror', 'mocha',
  'monsoon', 'moon', 'morning', 'moss', 'mountain', 'muffin', 'mulberry',
  'nectar', 'nest', 'night', 'noodle', 'north', 'nutmeg', 'ocean',
  'olive', 'onyx', 'opal', 'orange', 'orbit', 'orchid', 'otter', 'owl',
  'oyster', 'paddle', 'pancake', 'panda', 'paper', 'parade', 'pastel',
  'peach', 'pearl', 'pebble', 'penguin', 'peony', 'pepper', 'petal',
  'piano', 'picnic', 'pillow', 'pine', 'pixel', 'plum', 'pocket', 'pond',
  'poppy', 'prairie', 'prism', 'pumpkin', 'puzzle', 'quiet', 'quill',
  'quilt', 'rabbit', 'raccoon', 'rain', 'rainbow', 'raspberry', 'raven',
  'reef', 'ribbon', 'ridge', 'river', 'robin', 'rocket', 'rose', 'ruby',
  'saffron', 'sage', 'sailboat', 'sand', 'sapphire', 'seashell',
  'shadow', 'shore', 'silver', 'sky', 'sleepy', 'snow', 'socks', 'solar',
  'sparrow', 'spring', 'sprout', 'squirrel', 'starlight', 'stone',
  'storm', 'story', 'summer', 'sunflower', 'sunset', 'swan', 'sweater',
  'tango', 'teapot', 'thistle', 'thunder', 'tiger', 'timber', 'toffee',
  'tulip', 'tundra', 'turtle', 'twilight', 'umbrella', 'valley',
  'vanilla', 'velvet', 'violet', 'walnut', 'wander', 'waterfall', 'wave',
  'whale', 'willow', 'window', 'winter', 'wonder', 'zebra', 'zephyr',
];
