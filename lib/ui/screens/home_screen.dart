import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../online/models/online_search_result.dart';
import '../../providers/audio_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/online_provider.dart';
import '../../providers/online_settings_provider.dart';
import '../../providers/reco_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/yt_account_provider.dart';
import '../../reco/yt_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/home/track_shelf.dart';
import '../components/library/art_thumb.dart';
import '../modals/yt_signin_dialog.dart';
import 'online_search_screen.dart';

/// Home — the start page (ARCHITECTURE-RECOMMENDATIONS.md §5). Shelves
/// in trust order: your recents first, then the on-device picks, then
/// (on +) online discovery. Never a merged pool; online never displaces
/// your own music at the top.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Up late ♪';
    if (h < 12) return 'Good morning ♪';
    if (h < 17) return 'Good afternoon ♪';
    return 'Good evening ♪';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final recent = ref.watch(recentTracksProvider).value ?? const [];
    final forYou = ref.watch(forYouProvider).value ?? const [];
    final lanes = ref.watch(discoverLanesProvider).value ?? const [];
    final ytFeed = ref.watch(ytHomeFeedProvider).value ??
        const YtHomeFeed(songs: [], playlists: []);
    final cardDismissed = ref.watch(deepRecsCardDismissedProvider);
    final libraryEmpty =
        (ref.watch(libraryProvider).value ?? const []).isEmpty;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        children: [
          const SizedBox(height: Space.s6),
          Text(greeting(DateTime.now()),
              style: AppText.screenTitle(theme)),
          const SizedBox(height: Space.s6),
          // The online search entry point lives on Home (the start page)
          // so streaming search is one tap from launch — Library search
          // stays local. Only shown when online features are on.
          if (ref.watch(onlineEnabledProvider)) ...[
            const _OnlineSearchBar(),
            const SizedBox(height: Space.s6),
          ],
          if (recent.isEmpty)
            _EmptyHome(theme: theme, libraryEmpty: libraryEmpty)
          else
            TrackShelf(
              title: 'JUMP BACK IN',
              tracks: recent,
              theme: theme,
              onTap: (i) => ref
                  .read(audioHandlerProvider)
                  .playTracks(recent, startIndex: i),
            ),
          if (forYou.isNotEmpty) ...[
            const SizedBox(height: Space.s6),
            TrackShelf(
              title: 'FOR YOU',
              subtitle: 'picked on this device, from your listening',
              tracks: forYou,
              theme: theme,
              // Tap = the pick seeds a whole station, not a bare
              // one-song queue — "For you" is a doorway, not a list.
              onTap: (i) => startRadio(ref, forYou[i]),
            ),
          ],
          // Tier 1 Discover: per-catalog lanes, anonymous per-seed
          // lookups, gone entirely when online is off.
          for (final lane in lanes) ...[
            const SizedBox(height: Space.s6),
            TrackShelf(
              title: lane.title,
              subtitle: 'from ${onlineSourceLabels[lane.source]} · '
                  'anonymous — no account, no profile',
              tracks: [
                for (final item in lane.items) _ephemeral(item),
              ],
              theme: theme,
              onTap: (i) => playDiscoverLane(ref, lane, i),
            ),
          ],
          // Tier 3: the signed-in YT Music personalized feed — Quick
          // Picks songs (once history exists) + playlist/mix cards.
          if (ytFeed.songs.isNotEmpty) ...[
            const SizedBox(height: Space.s6),
            TrackShelf(
              title: 'QUICK PICKS ON YT MUSIC',
              subtitle: 'personalized from your YouTube account',
              tracks: [for (final r in ytFeed.songs) _ephemeral(r)],
              theme: theme,
              onTap: (i) => playYtSongs(ref, ytFeed.songs, i),
            ),
          ],
          if (ytFeed.playlists.isNotEmpty) ...[
            const SizedBox(height: Space.s6),
            _PlaylistShelf(
              title: 'MIXED FOR YOU · YT MUSIC',
              cards: ytFeed.playlists,
              theme: theme,
              onTap: (card) async {
                final ok = await playYtPlaylist(ref, card);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text("Couldn't open ${card.title}",
                        style: const TextStyle(fontFamily: 'Nunito')),
                  ));
                }
              },
            ),
          ],
          // One-time doorway to YT Music sign-in; dismissible forever,
          // and moot once connected.
          if (!cardDismissed &&
              !(ref.watch(ytAccountProvider).value?.connected ?? false)) ...[
            const SizedBox(height: Space.s6),
            _DeepRecsCard(theme: theme),
          ],
          const SizedBox(height: Space.s6),
        ],
      ),
    );
  }
}

/// Horizontal shelf of YT Music playlist / mix cards.
class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({
    required this.title,
    required this.cards,
    required this.theme,
    required this.onTap,
  });

  final String title;
  final List<YtPlaylistCard> cards;
  final HanamimiTheme theme;
  final void Function(YtPlaylistCard) onTap;

  static const _w = 132.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.sectionLabel(theme)),
        const SizedBox(height: Space.s1),
        Text('personalized playlists from your YouTube account',
            style: AppText.caption(theme).copyWith(color: theme.textMuted)),
        const SizedBox(height: Space.s3),
        SizedBox(
          // Extra room + an Expanded caption so a 2-line title never
          // overflows the card box (was spilling ~1px).
          height: _w + 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Clip to the pane (not Clip.none) so cards don't bleed under
            // the Now Playing panel in the three-pane shell.
            clipBehavior: Clip.hardEdge,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.s3),
            itemBuilder: (context, i) {
              final c = cards[i];
              return InkWell(
                onTap: () => onTap(c),
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  width: _w,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArtThumb(
                        title: c.title,
                        artUrl: c.artUrl,
                        size: _w,
                        radius: Radii.md,
                      ),
                      const SizedBox(height: Space.s2),
                      Expanded(
                        child: Text(c.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowSongTitle(theme)
                                .copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tap-to-open entry point for online search (YouTube + JioSaavn).
/// Names the sources so it's clear this is where streaming search lives.
/// Lives on Home now (moved off the You tab) — search is a start-page act.
class _OnlineSearchBar extends ConsumerWidget {
  const _OnlineSearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(OnlineSearchScreen.route()),
      child: Container(
        height: Sizes.inputHeight,
        padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: theme.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: theme.textMuted),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                'Search YouTube & JioSaavn',
                style: AppText.body(theme).copyWith(color: theme.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Display-only Track for a Discover card (no DB row until played —
/// ephemeral-until-touched, same as online search results).
Track _ephemeral(OnlineSearchResult r) => Track(
      id: -1,
      title: r.title,
      artist: r.artist,
      album: r.album,
      duration: r.duration,
      source: r.source,
      sourceId: r.sourceId,
      artUrl: r.artUrl,
    );

/// "Want deeper recommendations?" — the one-time doorway to YT Music
/// sign-in (Tier 3). Never a hidden default: connecting always goes
/// through the consent dialog.
class _DeepRecsCard extends ConsumerWidget {
  const _DeepRecsCard({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('✨ Want deeper recommendations?',
                    style: AppText.rowSongTitle(theme)),
              ),
              InkResponse(
                onTap: () => ref
                    .read(deepRecsCardDismissedProvider.notifier)
                    .dismiss(),
                radius: 16,
                child: Icon(Icons.close, size: 16, color: theme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Everything so far is computed on this device or asked '
            'anonymously. Sign in to YT Music for your own personalized '
            'picks — always your call.',
            style: AppText.caption(theme),
          ),
          const SizedBox(height: Space.s3),
          TextButton(
            onPressed: () => showYtSignInDialog(context),
            child: Text('Sign in to YT Music →',
                style: AppText.caption(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
  }
}

/// Cold start — the page still breathes instead of showing a blank
/// list (the whole point of Home over Songs as the landing tab).
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.theme, required this.libraryEmpty});

  final HanamimiTheme theme;
  final bool libraryEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libraryEmpty ? 'Welcome to Hanamimi 🌸' : 'All quiet 🌸',
              style: AppText.rowSongTitle(theme)),
          const SizedBox(height: Space.s2),
          Text(
            libraryEmpty
                ? 'Your music lives in the Library tab — add folders '
                    'there, or search to stream online. Everything you '
                    'play gathers here.'
                : "Play something and it'll be waiting here next time.",
            style: AppText.caption(theme),
          ),
        ],
      ),
    );
  }
}
