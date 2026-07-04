import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/playlist.dart';
import '../../online/import/import_models.dart';
import '../../online/import/playlist_importer.dart';
import '../../online/models/online_search_result.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';

/// Import a YouTube / Spotify playlist by URL. Paste → fetch+match with
/// progress → auto-add confident matches, review only the misses → commit
/// as a new Hanamimi playlist (M30).
Future<void> showImportPlaylistSheet(BuildContext context,
    {String? initialUrl}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _ImportSheet(initialUrl: initialUrl),
    ),
  );
}

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({this.initialUrl});
  final String? initialUrl;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _controller = TextEditingController();
  ImportProgress _progress = const ImportProgress(phase: ImportPhase.idle);
  ImportResult? _result;

  /// Manual picks for review misses: source-track index → chosen result.
  final _picked = <int, OnlineSearchResult>{};
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _controller.text = widget.initialUrl!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    if (detectImportSource(url) == ImportSource.unknown) {
      _snack('Paste a YouTube or Spotify playlist link');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _result = null;
      _picked.clear();
      _progress = const ImportProgress(phase: ImportPhase.fetching);
    });
    final importer = PlaylistImporter();
    final sub = importer.progress(url).listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    final result = await importer.run(url);
    await sub.cancel();
    if (!mounted) return;
    if (result == null || result.matches.isEmpty) {
      setState(() =>
          _progress = const ImportProgress(phase: ImportPhase.failed));
      return;
    }
    setState(() {
      _result = result;
      _progress = ImportProgress(
        phase: ImportPhase.done,
        total: result.matches.length,
        matched: result.confident.length,
      );
    });
  }

  Future<void> _commit() async {
    final result = _result;
    if (result == null || _committing) return;
    setState(() => _committing = true);

    // Auto-accepted matches + any manual picks from the review list.
    final chosen = <OnlineSearchResult>[];
    for (var i = 0; i < result.matches.length; i++) {
      final m = result.matches[i];
      if (m.matched) {
        chosen.add(m.result!);
      } else if (_picked[i] != null) {
        chosen.add(_picked[i]!);
      }
    }
    if (chosen.isEmpty) {
      setState(() => _committing = false);
      _snack('Nothing to import');
      return;
    }

    final color = playlistCoverColors[
        result.playlistName.hashCode.abs() % playlistCoverColors.length];
    await ref
        .read(playlistsProvider.notifier)
        .importPlaylist(result.playlistName, color.toARGB32(), chosen);
    if (!mounted) return;
    Navigator.of(context).pop();
    _snack('Imported "${result.playlistName}" · ${chosen.length} songs');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Space.s4,
          right: Space.s4,
          top: Space.s4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Space.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import playlist',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s1),
            Text('Paste a YouTube or Spotify playlist link',
                style: AppText.caption(theme)),
            const SizedBox(height: Space.s3),
            _urlField(theme),
            const SizedBox(height: Space.s3),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _urlField(HanamimiTheme theme) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: AppText.body(theme),
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'https://…',
                hintStyle:
                    AppText.body(theme).copyWith(color: theme.textMuted),
                filled: true,
                fillColor: theme.background,
                isDense: true,
                prefixIcon: IconButton(
                  icon: Icon(Icons.paste, size: 18, color: theme.textMuted),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _controller.text = data!.text!.trim();
                    }
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.s2),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.primary),
            onPressed: _busy ? null : _start,
            child: const Text('Import',
                style: TextStyle(fontFamily: 'Nunito')),
          ),
        ],
      );

  bool get _busy =>
      _progress.phase == ImportPhase.fetching ||
      _progress.phase == ImportPhase.matching ||
      _committing;

  Widget _body(HanamimiTheme theme) {
    switch (_progress.phase) {
      case ImportPhase.idle:
        return _hint(theme);
      case ImportPhase.fetching:
      case ImportPhase.matching:
        return _progressView(theme);
      case ImportPhase.failed:
        return Center(
          child: Text("Couldn't read that playlist — is it public?",
              style: AppText.body(theme), textAlign: TextAlign.center),
        );
      case ImportPhase.done:
        return _review(theme);
    }
  }

  Widget _hint(HanamimiTheme theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 44, color: theme.textMuted),
            const SizedBox(height: Space.s3),
            Text('YouTube playlists import directly.',
                style: AppText.caption(theme)),
            Text('Spotify tracks are matched to YouTube & JioSaavn.',
                style: AppText.caption(theme)),
          ],
        ),
      );

  Widget _progressView(HanamimiTheme theme) {
    final p = _progress;
    final label = p.phase == ImportPhase.fetching
        ? (p.fetched > 0 ? 'Reading playlist… ${p.fetched}' : 'Reading playlist…')
        : 'Matching ${p.fetched}/${p.total} · ${p.matched} found';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: p.phase == ImportPhase.matching && p.total > 0
                    ? p.fetched / p.total
                    : null,
                minHeight: 6,
                color: theme.primary,
                backgroundColor: theme.divider.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Text(label, style: AppText.caption(theme)),
        ],
      ),
    );
  }

  Widget _review(HanamimiTheme theme) {
    final result = _result!;
    final misses = <int>[
      for (var i = 0; i < result.matches.length; i++)
        if (!result.matches[i].matched) i,
    ];
    final autoCount = result.confident.length;
    final willImport = autoCount + _picked.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.playlistName,
            style: AppText.rowSongTitle(theme).copyWith(color: theme.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(
          '$autoCount matched automatically'
          '${misses.isEmpty ? '' : ' · ${misses.length} need a look'}',
          style: AppText.caption(theme),
        ),
        const SizedBox(height: Space.s2),
        Expanded(
          child: misses.isEmpty
              ? Center(
                  child: Text('All ${result.matches.length} tracks matched 🎉',
                      style: AppText.body(theme)))
              : ListView(
                  children: [
                    Text('COULDN\'T AUTO-MATCH',
                        style: AppText.sectionLabel(theme)),
                    const SizedBox(height: Space.s2),
                    for (final i in misses)
                      _MissRow(
                        match: result.matches[i],
                        picked: _picked[i],
                        theme: theme,
                        onPick: (r) => setState(() {
                          if (_picked[i]?.sourceId == r.sourceId) {
                            _picked.remove(i); // toggle off
                          } else {
                            _picked[i] = r;
                          }
                        }),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: Space.s2),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.primary),
            onPressed: _committing || willImport == 0 ? null : _commit,
            child: _committing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('Import $willImport song${willImport == 1 ? '' : 's'}',
                    style: const TextStyle(fontFamily: 'Nunito')),
          ),
        ),
      ],
    );
  }
}

/// One unmatched track with tappable candidate chips.
class _MissRow extends StatelessWidget {
  const _MissRow({
    required this.match,
    required this.picked,
    required this.theme,
    required this.onPick,
  });

  final ImportMatch match;
  final OnlineSearchResult? picked;
  final HanamimiTheme theme;
  final ValueChanged<OnlineSearchResult> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${match.source.title} · ${match.source.artist}',
              style: AppText.rowSongTitle(theme),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.s1),
          if (match.candidates.isEmpty)
            Text('No candidates found', style: AppText.caption(theme))
          else
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                for (final c in match.candidates)
                  _CandidateChip(
                    result: c,
                    selected: picked?.sourceId == c.sourceId,
                    theme: theme,
                    onTap: () => onPick(c),
                  ),
              ],
            ),
          Divider(height: Space.s4, color: theme.divider),
        ],
      ),
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.result,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final OnlineSearchResult result;
  final bool selected;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = '${result.source.name == 'saavn' ? 'Saavn' : 'YT'} · '
        '${result.title}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding:
            const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s1),
        decoration: BoxDecoration(
          color: selected
              ? theme.primary.withValues(alpha: 0.18)
              : theme.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
              color: selected ? theme.primary : theme.divider,
              width: selected ? 1.4 : 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: Space.s1),
                child: Icon(Icons.check, size: 14, color: theme.primary),
              ),
            Flexible(
              child: Text(label,
                  style: AppText.caption(theme).copyWith(
                      color: selected ? theme.primary : theme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
