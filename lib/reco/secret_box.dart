import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// At-rest encryption for the YT session cookie (M41). The cookie is a
/// full account credential, so it must not sit in the plaintext DB /
/// SharedPreferences. AES-GCM (pointycastle — already a dependency,
/// pure-Dart so it builds on every platform, unlike the secure-storage
/// native plugins) with a random key kept in a separate file.
///
/// Honest threat model: this stops casual inspection of the app's data
/// (a synced/backed-up DB, a shared machine's file browser) — the key
/// living in a sibling file means grabbing one store isn't enough. It is
/// not hardware-backed like a real OS keystore; for a sideloaded
/// personal + build that trade-off is deliberate (and the desktop cookie
/// already lives in the user's own browser profile anyway).
class SecretBox {
  static const _keyFile = 'yt_session.key';
  static const _dataFile = 'yt_session.enc';

  static Future<Directory> _dir() => getApplicationSupportDirectory();

  static Future<Uint8List> _key() async {
    final f = File('${(await _dir()).path}/$_keyFile');
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      if (bytes.length == 32) return bytes;
    }
    final rnd = Random.secure();
    final key =
        Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    await f.writeAsBytes(key, flush: true);
    return key;
  }

  /// Encrypts and persists [plaintext]. A null/empty value clears it.
  static Future<void> write(String? plaintext) async {
    final data = File('${(await _dir()).path}/$_dataFile');
    if (plaintext == null || plaintext.isEmpty) {
      if (await data.exists()) await data.delete();
      return;
    }
    final key = await _key();
    final rnd = Random.secure();
    final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final ct = cipher.process(
        Uint8List.fromList(utf8.encode(plaintext)));
    // iv ‖ ciphertext(+tag), base64 on disk.
    await data.writeAsString(
        base64.encode(Uint8List.fromList([...iv, ...ct])),
        flush: true);
  }

  /// Decrypts the stored cookie, or null when absent/corrupt.
  static Future<String?> read() async {
    try {
      final data = File('${(await _dir()).path}/$_dataFile');
      if (!await data.exists()) return null;
      final blob = base64.decode(await data.readAsString());
      if (blob.length <= 12) return null;
      final iv = Uint8List.sublistView(blob, 0, 12);
      final ct = Uint8List.sublistView(blob, 12);
      final key = await _key();
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
            false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      return utf8.decode(cipher.process(ct));
    } catch (_) {
      return null; // corrupt / tampered / key rotated → treat as signed out
    }
  }

  static Future<void> clear() => write(null);
}
