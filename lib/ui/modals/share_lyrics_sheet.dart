import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show getSaveLocation;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../library/models/track.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/mascot/hanamimi_widget.dart';
import '../components/shared/app_toast.dart';

const _maxLines = 6;

/// Spotify-style lyrics card: pick up to [_maxLines] lines, preview the
/// kawaii card (mascot peeking over the top-right corner), share as an
/// image.
void showShareLyricsSheet(
  BuildContext context,
  Track track,
  List<String> lines,
  HanamimiTheme theme,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _ShareLyricsBody(track: track, lines: lines, theme: theme),
    ),
  );
}

class _ShareLyricsBody extends StatefulWidget {
  const _ShareLyricsBody({
    required this.track,
    required this.lines,
    required this.theme,
  });

  final Track track;
  final List<String> lines;
  final HanamimiTheme theme;

  @override
  State<_ShareLyricsBody> createState() => _ShareLyricsBodyState();
}

class _ShareLyricsBodyState extends State<_ShareLyricsBody> {
  final _cardKey = GlobalKey();
  final _selected = <int>{};
  bool _sharing = false;

  List<String> get _selectedLines =>
      [for (final i in _selected.toList()..sort()) widget.lines[i]];

  void _toggle(int i) {
    setState(() {
      if (_selected.contains(i)) {
        _selected.remove(i);
      } else if (_selected.length < _maxLines) {
        _selected.add(i);
      }
    });
  }

  Future<void> _share() async {
    if (_selected.isEmpty || _sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${(await getTemporaryDirectory()).path}/hanamimi_lyrics.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      if (Platform.isAndroid) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: '${widget.track.title} — ${widget.track.artist}',
        ));
      } else {
        // No share sheet on desktop — save the card where the user says.
        final location = await getSaveLocation(
          suggestedName:
              'hanamimi ${widget.track.title} lyrics.png'.replaceAll('/', '·'),
        );
        if (location != null) {
          await file.copy(location.path);
          if (mounted) {
            // Root-overlay toast — SnackBars hide behind the sheet.
            showAppToast(context, 'Lyrics card saved 🌸');
          }
        }
      }
    } catch (_) {
      // Sharing is best-effort; the sheet just stays open.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: Space.s3),
          Text('Share lyrics',
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.textPrimary)),
          Text(
            _selected.length == _maxLines
                ? 'Max lines selected'
                : 'Pick up to $_maxLines lines',
            style: AppText.caption(theme),
          ),
          const SizedBox(height: Space.s2),
          // Live card preview — this exact widget is what gets captured.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s6),
            child: RepaintBoundary(
              key: _cardKey,
              // The mascot overhangs the card top; toImage crops to the
              // boundary's bounds, so give her headroom inside it.
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: _LyricsCard(
                  track: widget.track,
                  lines: _selectedLines.isEmpty
                      ? const ['Pick some lines below…']
                      : _selectedLines,
                  theme: theme,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s2),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4, vertical: Space.s2),
              itemCount: widget.lines.length,
              itemBuilder: (context, i) {
                final on = _selected.contains(i);
                return Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: Material(
                    color: on ? theme.primary.withValues(alpha: 0.18) : theme.surface,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: InkWell(
                      onTap: () => _toggle(i),
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.s4, vertical: Space.s3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(
                              color: on ? theme.primary : theme.divider,
                              width: on ? 1.2 : 0.5),
                        ),
                        child: Text(
                          widget.lines[i],
                          style: AppText.body(theme).copyWith(
                            fontWeight:
                                on ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: SizedBox(
              width: double.infinity,
              height: Sizes.inputHeight,
              child: FilledButton(
                onPressed: _selected.isEmpty || _sharing ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.pill)),
                ),
                child: _sharing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : const Text('Share',
                        style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shareable card: theme-tinted, art + title header, big bold lines,
/// mascot peeking over the top-right corner, Hanamimi sign-off.
class _LyricsCard extends StatelessWidget {
  const _LyricsCard({
    required this.track,
    required this.lines,
    required this.theme,
  });

  final Track track;
  final List<String> lines;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final artPath = track.albumArtPath;
    final hasArt = artPath != null && File(artPath).existsSync();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.s6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.primary.withValues(alpha: 0.22),
                theme.secondary.withValues(alpha: 0.22),
              ],
            ),
            color: theme.background,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: theme.primary.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasArt
                        ? Image.file(File(artPath),
                            width: 36, height: 36, fit: BoxFit.cover)
                        : Container(
                            width: 36,
                            height: 36,
                            color: theme.primary,
                            child: const Icon(Icons.music_note,
                                size: 20, color: Colors.white)),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            style: AppText.rowSongTitle(theme),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(track.artist,
                            style: AppText.caption(theme),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // Room for the mascot hanging over the corner.
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: Space.s4),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 19,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: theme.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(height: Space.s2),
              Text('🌸 Hanamimi 花耳',
                  style: AppText.caption(theme)
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        // The mascot peeks over the top-right corner, like she's reading
        // along.
        const Positioned(
          top: -26,
          right: Space.s3,
          child: IgnorePointer(
            child: HanamimiMascot(state: MascotState.playing, size: 44),
          ),
        ),
      ],
    );
  }
}
