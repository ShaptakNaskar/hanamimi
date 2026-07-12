import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/theme_tokens.dart';

/// Toast that always renders on top — including above modal bottom
/// sheets. SnackBars live in the Scaffold UNDER a modal route, so
/// messages fired from a sheet ("local files can't travel") were hidden
/// behind it (user-reported). This inserts into the root overlay, which
/// stacks above every route.
void showAppToast(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: Space.s6,
      right: Space.s6,
      bottom: Space.s6 + MediaQuery.viewInsetsOf(context).bottom,
      child: IgnorePointer(
        child: _ToastCard(message: message),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 3200), () {
    if (entry.mounted) entry.remove();
  });
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({required this.message});

  final String message;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200))
    ..forward();
  Timer? _out;

  @override
  void initState() {
    super.initState();
    _out = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) _c.reverse();
    });
  }

  @override
  void dispose() {
    _out?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.s4, vertical: Space.s3),
            decoration: BoxDecoration(
              color: const Color(0xE6202024),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
