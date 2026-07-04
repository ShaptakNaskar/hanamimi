import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/models/resolved_stream.dart';
import '../../providers/download_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';

/// Resolves the quality for a download. Uses the remembered choice when
/// one is set; otherwise shows the picker (with a "remember" toggle
/// that persists the choice for next time). Null = user dismissed.
Future<StreamQuality?> resolveDownloadQuality(
    BuildContext context, WidgetRef ref) async {
  final remembered = ref.read(downloadQualityProvider);
  if (remembered != null) return remembered;
  return showModalBottomSheet<StreamQuality>(
    context: context,
    builder: (_) => const _QualitySheet(),
  );
}

class _QualitySheet extends ConsumerStatefulWidget {
  const _QualitySheet();

  @override
  ConsumerState<_QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends ConsumerState<_QualitySheet> {
  bool _remember = false;

  void _pick(StreamQuality q) {
    if (_remember) {
      ref.read(downloadQualityProvider.notifier).set(q);
    }
    Navigator.of(context).pop(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download quality',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s3),
            _QualityOption(
              title: 'High',
              subtitle: 'Best available — 320 kbps on JioSaavn, '
                  'best audio on YouTube',
              icon: Icons.high_quality_outlined,
              onTap: () => _pick(StreamQuality.high),
              theme: theme,
            ),
            _QualityOption(
              title: 'Low',
              subtitle: 'Smaller files (~96 kbps), easier on storage',
              icon: Icons.data_saver_on_outlined,
              onTap: () => _pick(StreamQuality.low),
              theme: theme,
            ),
            const SizedBox(height: Space.s2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
              title: Text('Remember my choice',
                  style: AppText.rowSongTitle(theme)),
              subtitle: Text('Change it any time in You → Online',
                  style: AppText.caption(theme)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.theme,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 22, color: theme.primary),
      title: Text(title, style: AppText.rowSongTitle(theme)),
      subtitle: Text(subtitle, style: AppText.caption(theme)),
      onTap: onTap,
    );
  }
}
