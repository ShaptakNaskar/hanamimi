// Not a real test — a tool that renders the launcher icon from
// MascotPainter so the icon and the in-app mascot can never drift.
// Run: flutter test test/tools/generate_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/ui/components/mascot/mascot_painter.dart';

Future<void> _savePng(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('generate launcher icons', () async {
    const size = 1024.0;

    Future<ui.Image> render({required bool withBackground}) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (withBackground) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, size, size),
          Paint()..color = const Color(0xFFF4A7B9),
        );
      }
      final painter = MascotPainter(
        pose: const MascotPose(
          eyes: EyeKind.open,
          brow: BrowKind.none,
          mouth: MouthKind.neutral,
        ),
      );
      // Head fills most of the frame, sitting slightly high so she
      // "looks up" at the viewer (DESIGN.md §2). Painter space is
      // 120×132; the head centers around (60, 62).
      canvas.save();
      canvas.translate(size / 2, size * 0.47);
      final scale = withBackground ? size / 130 : size / 175;
      canvas.scale(scale);
      canvas.translate(-60, -62);
      painter.paint(canvas, const Size(120, 132));
      canvas.restore();
      final picture = recorder.endRecording();
      return picture.toImage(size.toInt(), size.toInt());
    }

    await _savePng(
        await render(withBackground: true), 'assets/icon/icon.png');
    await _savePng(await render(withBackground: false),
        'assets/icon/icon_foreground.png');
  });
}
