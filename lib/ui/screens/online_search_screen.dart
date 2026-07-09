import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../online/models/online_search_result.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/online_provider.dart';
import '../../providers/online_settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/track_row.dart';
import '../components/shared/pill_tab_bar.dart';
import '../modals/playlist_picker_sheet.dart';

/// The definitive online search (YouTube + JioSaavn), opened from the You
/// page. Local search stays in Library; this is the one place that
/// reaches out to the providers. A full screen so the results have room
/// and typing isn't cramped by a settings list underneath.
class OnlineSearchScreen extends ConsumerStatefulWidget {
  const OnlineSearchScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const OnlineSearchScreen());

  @override
  ConsumerState<OnlineSearchScreen> createState() =>
      _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends ConsumerState<OnlineSearchScreen> {
  int _source = 0; // index into registeredOnlineSources
  String _query = '';
  String _debouncedQuery = '';
  Timer? _debounce;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    // Debounced so typing doesn't fire a provider request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _debouncedQuery = q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final sources = registeredOnlineSources;

    // Online disabled (or no providers): nothing to search here.
    if (!ref.watch(onlineEnabledProvider) || sources.isEmpty) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.surface,
          title: Text('Search online', style: AppText.rowSongTitle(theme)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.s6),
            child: Text(
              'Turn on online features in You → Online to search '
              'YouTube and JioSaavn.',
              textAlign: TextAlign.center,
              style: AppText.caption(theme),
            ),
          ),
        ),
      );
    }

    final source = sources[_source.clamp(0, sources.length - 1)];

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.s3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: Row(
                children: [
                  InkResponse(
                    onTap: () => Navigator.of(context).pop(),
                    radius: 20,
                    child: Icon(Icons.arrow_back,
                        size: 24, color: theme.textMuted),
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: SizedBox(
                      height: Sizes.inputHeight,
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _onChanged,
                        style: AppText.body(theme),
                        decoration: InputDecoration(
                          hintText:
                              'Search ${onlineSourceLabels[source]}…',
                          hintStyle: AppText.body(theme)
                              .copyWith(color: theme.textMuted),
                          prefixIcon: Icon(Icons.search,
                              size: 20, color: theme.textMuted),
                          suffixIcon: _query.isEmpty
                              ? null
                              : InkResponse(
                                  onTap: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                  child: Icon(Icons.close,
                                      size: 18, color: theme.textMuted),
                                ),
                          filled: true,
                          fillColor: theme.surface,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.s4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: PillTabBar(
                tabs: [for (final s in sources) onlineSourceLabels[s]!],
                activeIndex: _source,
                onChanged: (i) => setState(() => _source = i),
                theme: theme,
              ),
            ),
            const SizedBox(height: Space.s2),
            Expanded(
              child: _Results(
                key: ValueKey(source.name),
                source: source,
                query: _debouncedQuery,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({super.key, required this.source, required this.query});

  final TrackSource source;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final label = onlineSourceLabels[source]!;
    if (query.trim().length < 2) {
      return _message('Type to search $label', theme);
    }

    final results =
        ref.watch(onlineSearchProvider((source: source, query: query)));
    return results.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: theme.primary)),
      error: (_, __) => _message('$label is unavailable right now', theme),
      data: (hits) {
        if (hits.isEmpty) return _message('Nothing matches "$query"', theme);
        final playing = ref.watch(audioStateProvider).value?.currentTrack;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.s4, vertical: Space.s2),
          itemCount: hits.length,
          itemExtent: Sizes.trackRowHeight,
          itemBuilder: (context, i) {
            final hit = hits[i];
            return TrackRow(
              // Display-only stand-in; the real row is created on tap.
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
              onTap: () => _play(ref, hit),
              onAddToQueue: () => _queue(context, ref, hit),
              onAddToPlaylist: () => _playlist(context, ref, theme, hit),
            );
          },
        );
      },
    );
  }

  Future<void> _play(WidgetRef ref, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    await ref.read(audioHandlerProvider).playTracks([track]);
  }

  Future<void> _queue(
      BuildContext context, WidgetRef ref, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    await ref.read(audioHandlerProvider).engine.addToQueue(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        content: const Text('Added to queue',
            style: TextStyle(fontFamily: 'Nunito')),
      ));
    }
  }

  Future<void> _playlist(BuildContext context, WidgetRef ref,
      HanamimiTheme theme, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    if (context.mounted) showPlaylistPicker(context, ref, theme, track.id);
  }

  Widget _message(String text, HanamimiTheme theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s6),
          child: Text(text,
              textAlign: TextAlign.center, style: AppText.caption(theme)),
        ),
      );
}
