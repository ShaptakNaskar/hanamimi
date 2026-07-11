import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/models/queue_mode.dart';
import '../../library/models/playlist.dart';
import '../../library/models/track.dart';
import '../../online/models/online_search_result.dart';
import '../../providers/audio_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/reco_provider.dart';
import '../../providers/theme_provider.dart';
import '../../reco/yt_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/art_thumb.dart';
import '../components/library/playlist_hero_header.dart';
import '../components/library/track_row.dart';
import '../modals/download_quality_sheet.dart';
import '../modals/playlist_picker_sheet.dart';

/// Opens a YT Music home-feed playlist / mix card as a browsable list —
/// the songs, not an instant play (Requests: "clicking a recommended
/// playlist should open it, not just play"). From here you can play the
/// whole thing, save it as an offline playlist, or download every song.
///
/// Rendered *inside* the Home pane (not a pushed route), the same way the
/// offline playlist detail lives inside the Library pane — so on desktop
/// it stays in the middle pane with the sidebar and Now Playing panel,
/// instead of a full-window overlay. [onClose] backs out to Home.
class OnlinePlaylistView extends ConsumerStatefulWidget {
  const OnlinePlaylistView({
    super.key,
    required this.card,
    required this.onClose,
  });

  final YtPlaylistCard card;
  final VoidCallback onClose;

  @override
  ConsumerState<OnlinePlaylistView> createState() =>
      _OnlinePlaylistViewState();
}

class _OnlinePlaylistViewState extends ConsumerState<OnlinePlaylistView> {
  bool _working = false;

  /// Materializes the whole playlist into real library rows, in order —
  /// so playback and downloads act on the same tracks the list shows.
  Future<List<Track>> _materialize(List<OnlineSearchResult> results) async {
    final notifier = ref.read(libraryProvider.notifier);
    return [
      for (final r in results) await notifier.ensureOnlineTrack(r),
    ];
  }

  Future<void> _playFrom(List<OnlineSearchResult> results, int index) async {
    if (_working) return;
    setState(() => _working = true);
    final tracks = await _materialize(results);
    if (!mounted) return;
    setState(() => _working = false);
    await ref
        .read(audioHandlerProvider)
        .playTracks(tracks, startIndex: index, mode: QueueMode.sequential);
  }

  /// Saves the playlist into the user's own library as a new offline
  /// playlist (same machinery as importing a link).
  Future<void> _saveToLibrary(List<OnlineSearchResult> results) async {
    if (_working) return;
    setState(() => _working = true);
    final color = playlistCoverColors[
        widget.card.title.hashCode.abs() % playlistCoverColors.length];
    await ref
        .read(playlistsProvider.notifier)
        .importPlaylist(widget.card.title, color.toARGB32(), results);
    if (!mounted) return;
    setState(() => _working = false);
    _snack('Saved "${widget.card.title}" to your playlists 🌸');
  }

  Future<void> _downloadAll(List<OnlineSearchResult> results) async {
    final quality = await resolveDownloadQuality(context, ref);
    if (quality == null || !mounted) return; // cancelled
    setState(() => _working = true);
    final tracks = await _materialize(results);
    if (!mounted) return;
    setState(() => _working = false);
    final pending = [
      for (final t in tracks)
        if (!t.isPlayableOffline) t,
    ];
    for (final t in pending) {
      ref.read(downloadManagerProvider.notifier).enqueue(t, quality);
    }
    _snack(pending.isEmpty
        ? 'Already saved offline 🐰'
        : 'Downloading ${pending.length} song${pending.length == 1 ? '' : 's'} — see the Downloads tab 🐰');
  }

  Future<void> _addOne(OnlineSearchResult hit) async {
    final theme = ref.read(currentThemeProvider);
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    if (mounted) showPlaylistPicker(context, ref, theme, track.id);
  }

  Future<void> _queueOne(OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    await ref.read(audioHandlerProvider).engine.addToQueue(track);
    _snack('Added to queue');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final async = ref.watch(ytPlaylistTracksProvider(widget.card.playlistId));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Space.s2, Space.s2, Space.s4, 0),
            child: Row(
              children: [
                InkResponse(
                  onTap: widget.onClose,
                  radius: 20,
                  child: SizedBox(
                    width: Sizes.minTouchTarget,
                    height: Sizes.minTouchTarget,
                    child: Icon(Icons.chevron_left,
                        size: 26, color: theme.textPrimary),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text('YouTube Music',
                      style: AppText.caption(theme),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (_working)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.primary),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => Center(
                  child: CircularProgressIndicator(color: theme.primary)),
              error: (_, __) =>
                  _message("Couldn't open this playlist — try again", theme),
              data: (results) => results.isEmpty
                  ? _message('This playlist came back empty', theme)
                  : _list(theme, results),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(HanamimiTheme theme, List<OnlineSearchResult> results) {
    final playing = ref.watch(audioStateProvider).value?.currentTrack;
    return ListView.builder(
      // Same horizontal inset as the offline playlist detail so the rows
      // line up with the rest of the app instead of hugging the pane edge.
      padding: const EdgeInsets.fromLTRB(
          Space.s4, Space.s2, Space.s4, Space.s6),
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _header(theme, results);
        final hit = results[i - 1];
        return SizedBox(
          height: Sizes.trackRowHeight,
          child: TrackRow(
            track: Track(
              id: -1,
              title: hit.title,
              artist: hit.artist,
              album: hit.album,
              duration: hit.duration,
              source: hit.source,
              sourceId: hit.sourceId,
              artUrl: hit.artUrl,
            ),
            theme: theme,
            isPlaying: playing?.source == hit.source &&
                playing?.sourceId == hit.sourceId,
            onTap: () => _playFrom(results, i - 1),
            onAddToQueue: () => _queueOne(hit),
            onAddToPlaylist: () => _addOne(hit),
          ),
        );
      },
    );
  }

  Widget _header(HanamimiTheme theme, List<OnlineSearchResult> results) {
    // Horizontal inset comes from the ListView padding now; just the
    // gap below the header before the first row.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: PlaylistHeroHeader(
        theme: theme,
        cover: ArtThumb(
          title: widget.card.title,
          artUrl: widget.card.artUrl,
          size: 180,
          radius: Radii.md,
        ),
        title: widget.card.title,
        meta:
            '${results.length} song${results.length == 1 ? '' : 's'} · YouTube Music',
        leading: [
          HeroAction(
            theme: theme,
            icon: Icons.library_add_outlined,
            onTap: () => _saveToLibrary(results),
          ),
        ],
        trailing: [
          HeroAction(
            theme: theme,
            icon: Icons.download_for_offline_outlined,
            onTap: () => _downloadAll(results),
          ),
        ],
        onPlay: () => _playFrom(results, 0),
      ),
    );
  }

  Widget _message(String text, HanamimiTheme theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s6),
          child: Text(text,
              textAlign: TextAlign.center, style: AppText.caption(theme)),
        ),
      );
}
