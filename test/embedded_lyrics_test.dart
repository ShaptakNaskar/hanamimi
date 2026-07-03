import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/lyrics/embedded_lyrics.dart';

List<int> _syncsafe(int value) => [
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];

List<int> _id3v4Frame(String id, List<int> body) => [
      ...latin1.encode(id),
      ..._syncsafe(body.length),
      0, 0,
      ...body,
    ];

List<int> _id3v4Tag(List<int> frames) => [
      ...latin1.encode('ID3'),
      4, 0, 0,
      ..._syncsafe(frames.length),
      ...frames,
    ];

Future<String> _writeTemp(String name, List<int> bytes) async {
  final file = File(
      '${Directory.systemTemp.path}/hanamimi_test_$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  const lrc = '[00:01.00] hello embedded world';

  test('reads real USLT frames (utf-8)', () async {
    final uslt = [
      3, // utf-8
      ...latin1.encode('eng'),
      0, // empty descriptor + terminator
      ...utf8.encode(lrc),
    ];
    final path = await _writeTemp(
        'uslt.mp3', _id3v4Tag(_id3v4Frame('USLT', uslt)));
    expect(await EmbeddedLyricsReader.read(path), lrc);
  });

  test('reads ffmpeg-style TXXX:USLT frames', () async {
    final txxx = [
      3, // utf-8
      ...utf8.encode('USLT'),
      0,
      ...utf8.encode(lrc),
    ];
    final path = await _writeTemp(
        'txxx.mp3', _id3v4Tag(_id3v4Frame('TXXX', txxx)));
    expect(await EmbeddedLyricsReader.read(path), lrc);
  });

  test('ignores unrelated TXXX frames', () async {
    final txxx = [
      3,
      ...utf8.encode('REPLAYGAIN'),
      0,
      ...utf8.encode('-3.2 dB'),
    ];
    final path = await _writeTemp(
        'txxx_other.mp3', _id3v4Tag(_id3v4Frame('TXXX', txxx)));
    expect(await EmbeddedLyricsReader.read(path), isNull);
  });

  test('reads FLAC LYRICS vorbis comment', () async {
    List<int> le32(int v) =>
        [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
    final comment = utf8.encode('LYRICS=$lrc');
    final vendor = utf8.encode('test');
    final block = [
      ...le32(vendor.length),
      ...vendor,
      ...le32(1),
      ...le32(comment.length),
      ...comment,
    ];
    final bytes = [
      ...latin1.encode('fLaC'),
      0x80 | 4, // last block, type 4 = VORBIS_COMMENT
      (block.length >> 16) & 0xFF,
      (block.length >> 8) & 0xFF,
      block.length & 0xFF,
      ...block,
    ];
    final path = await _writeTemp('lyr.flac', bytes);
    expect(await EmbeddedLyricsReader.read(path), lrc);
  });

  test('returns null for files without lyrics tags', () async {
    final path = await _writeTemp(
        'plain.mp3', _id3v4Tag(_id3v4Frame('TIT2', [3, ...utf8.encode('t')])));
    expect(await EmbeddedLyricsReader.read(path), isNull);
  });
}
