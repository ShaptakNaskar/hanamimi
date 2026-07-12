import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/dev_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/mascot/hanamimi_widget.dart';

/// The proper "About Hanamimi" card: mascot, edition + version, a short
/// blurb, and links out to the site and the source. The hidden developer
/// unlock (7 taps) now lives on the mascot inside here, so the menu row
/// can just open this.
Future<void> showAboutHanamimi(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AboutDialog(),
  );
}

class _AboutDialog extends ConsumerWidget {
  const _AboutDialog();

  static const _site = 'https://sappy-dir.vercel.app/';
  static const _github = 'https://github.com/ShaptakNaskar/hanamimi';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    // "Hanamimi+ 花耳 · 2.3.2" → name = before " · ", version = after.
    final label = ref.watch(appVersionLabelProvider).value ?? 'Hanamimi 花耳';
    final parts = label.split(' · ');
    final name = parts.first;
    final version = parts.length > 1 ? 'v${parts[1]}' : '';

    return Dialog(
      backgroundColor: theme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.s6, Space.s6, Space.s6, Space.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              // Tap the mascot 7× to unlock developer options — the same
              // easter egg that used to hide on the About menu row.
              HanamimiMascot(
                state: MascotState.playing,
                size: 104,
                fullBody: true,
                onTap: () {
                  final unlocked = ref
                      .read(devModeProvider.notifier)
                      .registerAboutTap();
                  if (unlocked) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.md)),
                      content: const Text('🛠️ Developer mode unlocked',
                          style: TextStyle(fontFamily: 'Nunito')),
                    ));
                  }
                },
              ),
              const SizedBox(height: Space.s3),
              Text(name,
                  style: AppText.screenTitle(theme),
                  textAlign: TextAlign.center),
              if (version.isNotEmpty) ...[
                const SizedBox(height: Space.s1),
                Text(version,
                    style: AppText.caption(theme)
                        .copyWith(color: theme.textMuted)),
              ],
              const SizedBox(height: Space.s4),
              Text(
                'A cozy little music player — your own library and the '
                'whole online world, wrapped in kawaii. No ads, no '
                'tracking, just your songs and a friendly companion.',
                style: AppText.caption(theme),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.s4),
              Text('Made with love by Sappy 🌸',
                  style: AppText.rowSongTitle(theme)
                      .copyWith(color: theme.primary),
                  textAlign: TextAlign.center),
              const SizedBox(height: Space.s6),
              Row(
                children: [
                  Expanded(
                    child: _LinkButton(
                      icon: Icons.public,
                      label: 'Website',
                      onTap: () => _open(_site),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: _LinkButton(
                      icon: Icons.code,
                      label: 'GitHub',
                      onTap: () => _open(_github),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s3),
              SizedBox(
                width: double.infinity,
                child: _LinkButton(
                  icon: Icons.description_outlined,
                  label: 'Open-source licenses',
                  onTap: () => _showLicenseDialog(context, theme),
                ),
              ),
              const SizedBox(height: Space.s2),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close',
                    style: AppText.button(theme)
                        .copyWith(color: theme.textMuted)),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// GPLv3 notice for the plus build. Hanamimi+ links yt-dlp (via
/// youtubedl-android) for YouTube resolution, so this build is licensed
/// under GPLv3 — surfacing the notice here honors that at distribution.
void _showLicenseDialog(BuildContext context, HanamimiTheme theme) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      title: Text('Open-source licenses', style: AppText.rowSongTitle(theme)),
      content: SingleChildScrollView(
        child: Text(
          'Hanamimi+ bundles yt-dlp through youtubedl-android '
          '(io.github.junkfood02.youtubedl-android), which is licensed under '
          'the GNU General Public License v3.\n\n'
          'Because this build links that library, Hanamimi+ as a whole is '
          'distributed under GPLv3. The corresponding source is available at '
          'github.com/ShaptakNaskar/hanamimi (plus branch).\n\n'
          'yt-dlp and youtubedl-android are © their respective authors.\n\n'
          'The pointer-chasing cat — mouse on desktop, your taps on a phone '
          '— is oneko, ported from oneko.js by adryd '
          '(adryd325/oneko.js), which revives the classic X11 "neko". Its '
          'sprite sheet ships with the app. The idea to bring it into an app '
          'comes from the Vencord oneko plugin by V '
          '(vencord.dev/plugins/oneko), which is likewise GPLv3.',
          style: AppText.caption(theme),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.primary)),
        ),
      ],
    ),
  );
}

class _LinkButton extends ConsumerWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.primary,
        side: BorderSide(color: theme.divider),
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(
              fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
    );
  }
}
