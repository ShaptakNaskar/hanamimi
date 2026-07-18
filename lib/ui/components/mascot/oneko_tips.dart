import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import 'oneko.dart';

/// The tips the sidebar cat mumbles when she wakes up. Facts, hints and
/// a little cheek — every one is true.
const _tips = [
  'did you know? tap the meters under the controls to enter '
      'Visualizer Stare. perfect for people who just wanna… stare.',
  'the 🌙 button tucks the app into Blackout — a bedside clock '
      'with dancing needles. I have a corner seat there.',
  'these meters aren\'t faking it — the song is decoded right here '
      'in your tab, 60 times a second. nothing is ever uploaded.',
  'Adaptive themes repaint the whole app from the album art. '
      'try one in settings, then skip songs.',
  'crossfade lives in settings. Slow Dance even reads where a song\'s '
      'energy dies and times the fade itself.',
  'auto-gain makes quiet lofi fill the meters like loud EDM. '
      'settings → visualizer.',
  'I\'ll chase your mouse if you let me. settings → buddies → '
      '"chases your pointer".',
  'the visualizer never uses a microphone — it reads the music '
      'itself, so it\'s accurate even muted.',
  'heart a song and I\'ll remember it next time you drop the same '
      'folder in. pinky promise.',
  'after midnight the app whispers in lowercase. night mode, '
      'settings.',
  'psst — tapping the mascot in About seven times unlocks developer '
      'mode. you didn\'t hear it from me.',
  'this tab is just the demo. the real Hanamimi lives on GitHub — '
      'phone, desktop, the whole deal. button\'s right below.',
  'media keys on your keyboard work. the browser tells me what '
      'you pressed. spooky.',
];

/// The sidebar's resident cat: asleep on the header, and every few
/// minutes she startles awake, delivers one tip in a speech bubble,
/// then curls back up. Tapping her demands a tip right now.
class OnekoTips extends StatefulWidget {
  const OnekoTips({super.key, required this.theme, this.size = 32});

  final HanamimiTheme theme;
  final double size;

  @override
  State<OnekoTips> createState() => _OnekoTipsState();
}

class _OnekoTipsState extends State<OnekoTips> {
  final _rng = math.Random();
  Timer? _next;
  Timer? _hide;
  String? _tip;
  var _stir = 0;
  var _tipCursor = 0;
  late final List<int> _order = // shuffled once — no repeats until all seen
      List.generate(_tips.length, (i) => i)..shuffle(_rng);

  @override
  void initState() {
    super.initState();
    // First tip comes early (the demo should show itself off), later
    // ones wander in every 2–4 minutes.
    _next = Timer(const Duration(seconds: 25), _speak);
  }

  void _schedule() {
    _next?.cancel();
    _next = Timer(Duration(seconds: 120 + _rng.nextInt(120)), _speak);
  }

  void _speak() {
    if (!mounted) return;
    setState(() {
      _tip = _tips[_order[_tipCursor]];
      _tipCursor = (_tipCursor + 1) % _order.length;
      _stir++; // wakes the sprite: alert → scratch → back to sleep
    });
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() => _tip = null);
      _schedule();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _speak,
          child: StirringOneko(size: widget.size, stir: _stir),
        ),
        // The bubble grows under the cat, inside the sidebar's width.
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _tip == null
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: Space.s2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s3, vertical: Space.s2),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: theme.divider, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _tip!,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      height: 1.35,
                      color: theme.textPrimary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
