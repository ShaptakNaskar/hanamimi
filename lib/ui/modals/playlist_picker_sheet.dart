import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_provider.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/playlist_card.dart';
import '../components/shared/app_toast.dart';

/// "Add to playlist" bottom sheet — shared by library track rows and
/// Now Playing. Extracted from library_screen so any surface with a
/// track id can offer it.
Future<void> showPlaylistPicker(BuildContext context, WidgetRef ref,
    HanamimiTheme theme, int trackId) async {
  // ref.read gives AsyncLoading if the Playlists tab was never opened
  // this session — await the future so existing playlists always show.
  final playlists = await ref.read(playlistsProvider.future);
  if (!context.mounted) return;
  if (playlists.isEmpty) {
    _toast(context, 'No playlists yet — make one first!');
    return;
  }
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to playlist',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s3),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: playlists.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: Space.s3),
                itemBuilder: (context, i) => PlaylistCard(
                  playlist: playlists[i],
                  theme: theme,
                  onTap: () {
                    ref
                        .read(playlistsProvider.notifier)
                        .addTrack(playlists[i].id, trackId);
                    Navigator.pop(sheetContext);
                    _toast(context, 'Added to ${playlists[i].name}');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Root-overlay toast — SnackBars hide behind modal sheets.
void _toast(BuildContext context, String message) =>
    showAppToast(context, message);
