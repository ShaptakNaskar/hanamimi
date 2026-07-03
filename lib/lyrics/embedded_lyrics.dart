import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Extracts lyrics embedded in the audio file itself:
/// - MP3: ID3v2.3/2.4 USLT frames (very often LRC-formatted inside)
/// - FLAC: Vorbis comment LYRICS= / UNSYNCEDLYRICS=
/// Returns the raw lyric text, or null. Never throws — a malformed tag
/// just means "no embedded lyrics".
abstract final class EmbeddedLyricsReader {
  static Future<String?> read(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final ext = filePath.toLowerCase();
      if (ext.endsWith('.mp3')) return _readId3(file);
      if (ext.endsWith('.flac')) return _readFlac(file);
      // Other containers (m4a/ogg/opus) are rare enough locally to
      // leave to LRCLIB.
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- ID3v2 ---

  static Future<String?> _readId3(File file) async {
    final raf = await file.open();
    try {
      final header = await raf.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
        return null; // no "ID3"
      }
      final version = header[3]; // 3 = v2.3, 4 = v2.4
      if (version < 3 || version > 4) return null;
      final tagSize = _syncsafe(header.sublist(6, 10));
      final tag = await raf.read(tagSize);

      var offset = 0;
      while (offset + 10 <= tag.length) {
        final id = latin1.decode(tag.sublist(offset, offset + 4));
        if (id == '\x00\x00\x00\x00') break; // padding
        final rawSize = tag.sublist(offset + 4, offset + 8);
        final frameSize = version == 4
            ? _syncsafe(rawSize)
            : (rawSize[0] << 24) |
                (rawSize[1] << 16) |
                (rawSize[2] << 8) |
                rawSize[3];
        if (frameSize <= 0 || offset + 10 + frameSize > tag.length) break;
        if (id == 'USLT') {
          final body = tag.sublist(offset + 10, offset + 10 + frameSize);
          final text = _decodeUslt(body);
          if (text != null && text.trim().isNotEmpty) return text;
        }
        // ffmpeg and some taggers store lyrics as TXXX:USLT / TXXX:LYRICS.
        if (id == 'TXXX') {
          final body = tag.sublist(offset + 10, offset + 10 + frameSize);
          final text = _decodeTxxxLyrics(body);
          if (text != null && text.trim().isNotEmpty) return text;
        }
        offset += 10 + frameSize;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  /// USLT: encoding(1) + language(3) + descriptor(term) + lyrics.
  static String? _decodeUslt(Uint8List body) {
    if (body.length < 5) return null;
    final encoding = body[0];
    final content = body.sublist(4);
    switch (encoding) {
      case 0: // latin-1, descriptor terminated by single 0x00
        final split = content.indexOf(0);
        if (split == -1) return null;
        return latin1.decode(content.sublist(split + 1));
      case 3: // utf-8, single 0x00 terminator
        final split = content.indexOf(0);
        if (split == -1) return null;
        return utf8.decode(content.sublist(split + 1), allowMalformed: true);
      case 1: // utf-16 with BOM, double 0x00 terminator
      case 2: // utf-16 BE
        final split = _findUtf16Terminator(content);
        if (split == -1) return null;
        return _decodeUtf16(content.sublist(split + 2), bigEndianDefault: encoding == 2);
      default:
        return null;
    }
  }

  /// TXXX: encoding(1) + description(term) + value. Only returns the
  /// value when the description names a lyrics field.
  static String? _decodeTxxxLyrics(Uint8List body) {
    if (body.length < 2) return null;
    final encoding = body[0];
    final content = body.sublist(1);

    String description;
    String value;
    if (encoding == 0 || encoding == 3) {
      final split = content.indexOf(0);
      if (split == -1) return null;
      final decode = encoding == 0
          ? latin1.decode
          : (List<int> b) => utf8.decode(b, allowMalformed: true);
      description = decode(content.sublist(0, split));
      value = decode(content.sublist(split + 1));
    } else {
      final split = _findUtf16Terminator(content);
      if (split == -1) return null;
      description = _decodeUtf16(content.sublist(0, split),
          bigEndianDefault: encoding == 2);
      value = _decodeUtf16(content.sublist(split + 2),
          bigEndianDefault: encoding == 2);
    }

    const lyricKeys = {'USLT', 'LYRICS', 'UNSYNCEDLYRICS', 'SYNCEDLYRICS'};
    return lyricKeys.contains(description.toUpperCase().trim())
        ? value
        : null;
  }

  static int _findUtf16Terminator(Uint8List bytes) {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool bigEndianDefault}) {
    var bigEndian = bigEndianDefault;
    var start = 0;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        bigEndian = false;
        start = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        bigEndian = true;
        start = 2;
      }
    }
    final codes = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      codes.add(bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i]);
    }
    return String.fromCharCodes(codes);
  }

  static int _syncsafe(List<int> b) =>
      ((b[0] & 0x7F) << 21) |
      ((b[1] & 0x7F) << 14) |
      ((b[2] & 0x7F) << 7) |
      (b[3] & 0x7F);

  // --- FLAC ---

  static Future<String?> _readFlac(File file) async {
    final raf = await file.open();
    try {
      final magic = await raf.read(4);
      if (latin1.decode(magic) != 'fLaC') return null;

      while (true) {
        final blockHeader = await raf.read(4);
        if (blockHeader.length < 4) return null;
        final isLast = blockHeader[0] & 0x80 != 0;
        final type = blockHeader[0] & 0x7F;
        final length = (blockHeader[1] << 16) |
            (blockHeader[2] << 8) |
            blockHeader[3];
        if (type == 4) {
          // VORBIS_COMMENT
          final block = await raf.read(length);
          return _lyricsFromVorbisComment(block);
        }
        if (isLast) return null;
        await raf.setPosition(await raf.position() + length);
      }
    } finally {
      await raf.close();
    }
  }

  static String? _lyricsFromVorbisComment(Uint8List block) {
    var offset = 0;
    int readLe32() {
      final v = block[offset] |
          (block[offset + 1] << 8) |
          (block[offset + 2] << 16) |
          (block[offset + 3] << 24);
      offset += 4;
      return v;
    }

    if (block.length < 8) return null;
    final vendorLength = readLe32();
    offset += vendorLength;
    if (offset + 4 > block.length) return null;
    final count = readLe32();
    for (var i = 0; i < count; i++) {
      if (offset + 4 > block.length) return null;
      final length = readLe32();
      if (offset + length > block.length) return null;
      final comment =
          utf8.decode(block.sublist(offset, offset + length), allowMalformed: true);
      offset += length;
      final eq = comment.indexOf('=');
      if (eq == -1) continue;
      final key = comment.substring(0, eq).toUpperCase();
      if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS' || key == 'SYNCEDLYRICS') {
        final value = comment.substring(eq + 1);
        if (value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }
}
