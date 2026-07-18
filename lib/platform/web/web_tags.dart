import 'dart:convert';
import 'dart:typed_data';

/// What the web tag reader could learn about a file. Anything null falls
/// back to filename parsing at the call site.
class ParsedTags {
  const ParsedTags({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.artBytes,
    this.artMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final Uint8List? artBytes;
  final String? artMime;
}

/// Pure-Dart tag reader for the web edition — the browser has no
/// MediaStore, so titles/artists/art come straight off the bytes:
/// ID3v2 (mp3, and anything else with a bolted-on ID3 header), FLAC
/// (VORBIS_COMMENT + PICTURE), MP4/M4A (ilst atoms), and Ogg
/// Vorbis/Opus comment headers. Defensive throughout: a malformed tag
/// yields nulls, never a throw.
ParsedTags parseTags(Uint8List head, {Uint8List? tail}) {
  try {
    if (head.length >= 3 &&
        head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
      return _parseId3v2(head);
    }
    if (head.length >= 4 &&
        head[0] == 0x66 && head[1] == 0x4C &&
        head[2] == 0x61 && head[3] == 0x43) {
      return _parseFlac(head);
    }
    if (head.length >= 12 &&
        head[4] == 0x66 && head[5] == 0x74 &&
        head[6] == 0x79 && head[7] == 0x70) {
      return _parseMp4(head, tail);
    }
    if (head.length >= 4 &&
        head[0] == 0x4F && head[1] == 0x67 &&
        head[2] == 0x67 && head[3] == 0x53) {
      return _parseOgg(head);
    }
    // No recognized container up front — maybe an ID3v1 footer.
    if (tail != null) {
      final v1 = _parseId3v1(tail);
      if (v1 != null) return v1;
    }
  } catch (_) {
    // Fall through to the empty result.
  }
  return const ParsedTags();
}

// --- ID3v2 -----------------------------------------------------------

ParsedTags _parseId3v2(Uint8List b) {
  final major = b[3];
  final flags = b[5];
  var size = _syncsafe(b, 6);
  var offset = 10;
  if (flags & 0x40 != 0 && major >= 3) {
    // Extended header — skip it.
    final ext = major == 4 ? _syncsafe(b, offset) : _be32(b, offset);
    offset += ext + (major == 4 ? 0 : 4);
  }
  final end = (10 + size).clamp(0, b.length);

  String? title, artist, album;
  int? trackNumber;
  Uint8List? artBytes;
  String? artMime;

  final idLen = major == 2 ? 3 : 4;
  final headerLen = major == 2 ? 6 : 10;

  while (offset + headerLen <= end) {
    final id = String.fromCharCodes(b, offset, offset + idLen);
    if (id.codeUnitAt(0) == 0) break; // padding
    final frameSize = major == 2
        ? (b[offset + 3] << 16) | (b[offset + 4] << 8) | b[offset + 5]
        : major == 3
            ? _be32(b, offset + idLen)
            : _syncsafe(b, offset + idLen);
    final bodyStart = offset + headerLen;
    if (frameSize <= 0 || bodyStart + frameSize > end) break;
    final body = Uint8List.sublistView(b, bodyStart, bodyStart + frameSize);

    switch (id) {
      case 'TIT2' || 'TT2':
        title = _id3Text(body);
      case 'TPE1' || 'TP1':
        artist = _id3Text(body);
      case 'TALB' || 'TAL':
        album = _id3Text(body);
      case 'TRCK' || 'TRK':
        trackNumber =
            int.tryParse(_id3Text(body)?.split('/').first ?? '');
      case 'APIC' || 'PIC':
        final art = _id3Apic(body, major);
        if (art != null && artBytes == null) {
          artMime = art.$1;
          artBytes = art.$2;
        }
    }
    offset = bodyStart + frameSize;
  }
  return ParsedTags(
    title: title,
    artist: artist,
    album: album,
    trackNumber: trackNumber,
    artBytes: artBytes,
    artMime: artMime,
  );
}

String? _id3Text(Uint8List body) {
  if (body.isEmpty) return null;
  final enc = body[0];
  final data = Uint8List.sublistView(body, 1);
  String s;
  switch (enc) {
    case 1: // UTF-16 with BOM
    case 2: // UTF-16BE
      s = _utf16(data, defaultBigEndian: enc == 2);
    case 3:
      s = utf8.decode(data, allowMalformed: true);
    default:
      s = latin1.decode(data);
  }
  s = s.split('\x00').first.trim();
  return s.isEmpty ? null : s;
}

(String, Uint8List)? _id3Apic(Uint8List body, int major) {
  if (body.length < 4) return null;
  final enc = body[0];
  var i = 1;
  String mime;
  if (major == 2) {
    // v2.2 PIC: 3-byte image format instead of a MIME string.
    final fmt = String.fromCharCodes(body, i, i + 3).toLowerCase();
    mime = fmt == 'png' ? 'image/png' : 'image/jpeg';
    i += 3;
  } else {
    final z = body.indexOf(0, i);
    if (z < 0) return null;
    mime = latin1.decode(Uint8List.sublistView(body, i, z));
    i = z + 1;
  }
  i++; // picture type byte
  // Description, terminated per encoding (UTF-16 = double NUL).
  if (enc == 1 || enc == 2) {
    while (i + 1 < body.length && (body[i] != 0 || body[i + 1] != 0)) {
      i += 2;
    }
    i += 2;
  } else {
    while (i < body.length && body[i] != 0) {
      i++;
    }
    i += 1;
  }
  if (i >= body.length) return null;
  return (
    mime.isEmpty ? 'image/jpeg' : mime,
    Uint8List.fromList(Uint8List.sublistView(body, i)),
  );
}

ParsedTags? _parseId3v1(Uint8List tail) {
  if (tail.length < 128) return null;
  final t = Uint8List.sublistView(tail, tail.length - 128);
  if (t[0] != 0x54 || t[1] != 0x41 || t[2] != 0x47) return null; // "TAG"
  String? field(int start, int len) {
    final s = latin1
        .decode(Uint8List.sublistView(t, start, start + len))
        .split('\x00')
        .first
        .trim();
    return s.isEmpty ? null : s;
  }

  return ParsedTags(
    title: field(3, 30),
    artist: field(33, 30),
    album: field(63, 30),
    trackNumber: t[125] == 0 && t[126] != 0 ? t[126] : null,
  );
}

// --- FLAC ------------------------------------------------------------

ParsedTags _parseFlac(Uint8List b) {
  var offset = 4;
  String? title, artist, album;
  int? trackNumber;
  Uint8List? artBytes;
  String? artMime;

  while (offset + 4 <= b.length) {
    final header = b[offset];
    final last = header & 0x80 != 0;
    final type = header & 0x7F;
    final size = (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];
    final bodyStart = offset + 4;
    if (bodyStart + size > b.length) break;
    final body = Uint8List.sublistView(b, bodyStart, bodyStart + size);

    if (type == 4) {
      // VORBIS_COMMENT
      final c = _vorbisComments(body, hasFramingBit: false);
      title ??= c['title'];
      artist ??= c['artist'];
      album ??= c['album'];
      trackNumber ??= int.tryParse(c['tracknumber']?.split('/').first ?? '');
    } else if (type == 6 && artBytes == null) {
      // PICTURE
      final pic = _flacPicture(body);
      if (pic != null) {
        artMime = pic.$1;
        artBytes = pic.$2;
      }
    }
    offset = bodyStart + size;
    if (last) break;
  }
  return ParsedTags(
    title: title,
    artist: artist,
    album: album,
    trackNumber: trackNumber,
    artBytes: artBytes,
    artMime: artMime,
  );
}

(String, Uint8List)? _flacPicture(Uint8List b) {
  if (b.length < 8) return null;
  var i = 4; // picture type
  final mimeLen = _be32(b, i);
  i += 4;
  if (i + mimeLen > b.length) return null;
  final mime = latin1.decode(Uint8List.sublistView(b, i, i + mimeLen));
  i += mimeLen;
  final descLen = _be32(b, i);
  i += 4 + descLen;
  i += 16; // width, height, depth, colors
  if (i + 4 > b.length) return null;
  final dataLen = _be32(b, i);
  i += 4;
  if (i + dataLen > b.length) return null;
  return (mime, Uint8List.fromList(Uint8List.sublistView(b, i, i + dataLen)));
}

// --- Vorbis comments (FLAC block body / Ogg packet payload) ----------

Map<String, String> _vorbisComments(Uint8List b,
    {required bool hasFramingBit}) {
  final out = <String, String>{};
  var i = 0;
  if (i + 4 > b.length) return out;
  final vendorLen = _le32(b, i);
  i += 4 + vendorLen;
  if (i + 4 > b.length) return out;
  final count = _le32(b, i);
  i += 4;
  for (var n = 0; n < count && i + 4 <= b.length; n++) {
    final len = _le32(b, i);
    i += 4;
    if (i + len > b.length) break;
    final entry =
        utf8.decode(Uint8List.sublistView(b, i, i + len), allowMalformed: true);
    i += len;
    final eq = entry.indexOf('=');
    if (eq > 0) {
      out[entry.substring(0, eq).toLowerCase()] = entry.substring(eq + 1);
    }
  }
  return out;
}

// --- Ogg (Vorbis / Opus) ---------------------------------------------

ParsedTags _parseOgg(Uint8List b) {
  // The comment header lives in the second logical packet, near the
  // front. Rather than a full Ogg demux, scan the head bytes for the
  // comment-header magic and parse the comments that follow. Art
  // (METADATA_BLOCK_PICTURE, base64) is skipped — cover art in Ogg is
  // rare and huge; the neutral placeholder covers it.
  const vorbis = [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]; // \x03vorbis
  const opus = [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73]; // OpusTags
  var start = _find(b, vorbis);
  var skip = vorbis.length;
  if (start < 0) {
    start = _find(b, opus);
    skip = opus.length;
  }
  if (start < 0) return const ParsedTags();
  final c = _vorbisComments(
    Uint8List.sublistView(b, start + skip),
    hasFramingBit: true,
  );
  return ParsedTags(
    title: c['title'],
    artist: c['artist'],
    album: c['album'],
    trackNumber: int.tryParse(c['tracknumber']?.split('/').first ?? ''),
  );
}

// --- MP4 / M4A -------------------------------------------------------

ParsedTags _parseMp4(Uint8List head, Uint8List? tail) {
  // moov usually sits at the front for streamable files; some encoders
  // put it at the end — try both windows.
  return _mp4Scan(head) ?? (tail != null ? _mp4Scan(tail) : null) ??
      const ParsedTags();
}

ParsedTags? _mp4Scan(Uint8List b) {
  // Walk for an `ilst` box and read its children. A structural walk of
  // moov→udta→meta→ilst is fragile over a byte window, so find `ilst`
  // directly and bounds-check everything.
  final ilst = _find(b, const [0x69, 0x6C, 0x73, 0x74]); // "ilst"
  if (ilst < 4) return null;
  final size = _be32(b, ilst - 4);
  final end = (ilst - 4 + size).clamp(0, b.length);
  var i = ilst + 4;

  String? title, artist, album;
  int? trackNumber;
  Uint8List? artBytes;
  String? artMime;

  while (i + 8 <= end) {
    final boxSize = _be32(b, i);
    if (boxSize < 8 || i + boxSize > end) break;
    final type = String.fromCharCodes(b, i + 4, i + 8);
    final data = _mp4Data(b, i + 8, i + boxSize);
    if (data != null) {
      final (flags, payload) = data;
      switch (type) {
        case '©nam':
          title = _mp4Text(payload, flags);
        case '©ART' || 'aART':
          artist ??= _mp4Text(payload, flags);
        case '©alb':
          album = _mp4Text(payload, flags);
        case 'trkn':
          if (payload.length >= 4) trackNumber = (payload[2] << 8) | payload[3];
        case 'covr':
          if (artBytes == null) {
            artBytes = Uint8List.fromList(payload);
            artMime = flags == 14 ? 'image/png' : 'image/jpeg';
          }
      }
    }
    i += boxSize;
  }
  return ParsedTags(
    title: title,
    artist: artist,
    album: album,
    trackNumber: trackNumber,
    artBytes: artBytes,
    artMime: artMime,
  );
}

(int, Uint8List)? _mp4Data(Uint8List b, int start, int end) {
  if (start + 16 > end) return null;
  final size = _be32(b, start);
  final type = String.fromCharCodes(b, start + 4, start + 8);
  if (type != 'data' || start + size > end) return null;
  final flags = _be32(b, start + 8) & 0xFFFFFF;
  return (flags, Uint8List.sublistView(b, start + 16, start + size));
}

String? _mp4Text(Uint8List payload, int flags) {
  if (flags != 1) return null;
  final s = utf8.decode(payload, allowMalformed: true).trim();
  return s.isEmpty ? null : s;
}

// --- byte helpers ----------------------------------------------------

int _syncsafe(Uint8List b, int i) =>
    ((b[i] & 0x7F) << 21) |
    ((b[i + 1] & 0x7F) << 14) |
    ((b[i + 2] & 0x7F) << 7) |
    (b[i + 3] & 0x7F);

int _be32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

int _le32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

int _find(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

String _utf16(Uint8List data, {required bool defaultBigEndian}) {
  var big = defaultBigEndian;
  var start = 0;
  if (data.length >= 2) {
    if (data[0] == 0xFF && data[1] == 0xFE) {
      big = false;
      start = 2;
    } else if (data[0] == 0xFE && data[1] == 0xFF) {
      big = true;
      start = 2;
    }
  }
  final codes = <int>[];
  for (var i = start; i + 1 < data.length; i += 2) {
    codes.add(big ? (data[i] << 8) | data[i + 1] : data[i] | (data[i + 1] << 8));
  }
  return String.fromCharCodes(codes);
}
