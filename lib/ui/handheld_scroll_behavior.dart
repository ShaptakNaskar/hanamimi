import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lets every scrollable be dragged by touch, stylus and trackpad — not
/// just mouse-wheel/scrollbar. Flutter's desktop default only accepts
/// mouse + trackpad, so on a **Steam Deck / ROG Ally** touchscreen the
/// lists felt dead (you couldn't flick them). This adds the finger.
///
/// Keeps the platform's normal scrollbar and overscroll so it still
/// reads as a desktop app on a real desktop.
class HandheldScrollBehavior extends MaterialScrollBehavior {
  const HandheldScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.mouse,
      };
}
