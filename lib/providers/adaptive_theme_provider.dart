import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../theme/hanamimi_theme.dart';
import '../theme/night_shift.dart';
import '../theme/themes.dart';
import 'audio_provider.dart';
import 'night_mode_provider.dart';
import 'theme_provider.dart';

/// The album-art image for a track — a blob URL minted from the file's
/// embedded art, null when it has none. (Web edition: art never leaves
/// the tab.)
ImageProvider? artImageProvider(Track track) {
  final local = track.albumArtPath;
  if (local != null && local.isNotEmpty) return NetworkImage(local);
  return null;
}

bool _isAdaptiveId(String id) =>
    id == neutralAdaptiveLight.id ||
    id == neutralAdaptiveDark.id ||
    id == neutralAdaptiveAmoled.id;

HanamimiTheme _adaptiveVariant(String id) => id == neutralAdaptiveAmoled.id
    ? neutralAdaptiveAmoled
    : id == neutralAdaptiveDark.id
        ? neutralAdaptiveDark
        : neutralAdaptiveLight;

/// Art-derived (Monet) theme for the current track. Runs Flutter's built-in
/// Material You quantizer (`ColorScheme.fromImageProvider`) over the album
/// art and maps the result to a [HanamimiTheme]. The scheme is generated at
/// the selected variant's brightness — Adaptive Light stays light and
/// Adaptive Dark stays dark no matter how bright the cover is. Recomputes
/// only when the art or the variant actually changes (keyed), and falls
/// back to the variant's neutral palette when there's no art or extraction
/// fails — never a jarring default. Only consulted while the selected theme
/// is one of the adaptive ids.
final adaptiveThemeProvider = FutureProvider<HanamimiTheme>((ref) async {
  final id = ref.watch(selectedThemeIdProvider);
  final variant = id == neutralAdaptiveAmoled.id
      ? neutralAdaptiveAmoled
      : id == neutralAdaptiveDark.id
          ? neutralAdaptiveDark
          : neutralAdaptiveLight;
  final track = ref.watch(_artKeyProvider);
  final provider = track?.$2;
  if (provider == null) return variant;
  try {
    final scheme = await ColorScheme.fromImageProvider(
      provider: provider,
      brightness: variant.isDark ? Brightness.dark : Brightness.light,
    );
    return fromArtScheme(scheme, variant);
  } catch (_) {
    return variant;
  }
});

/// The fully-resolved theme (adaptive palette + Night Mode composite) for
/// the crossfade's INCOMING track, computed ahead of the handoff so the
/// UI can recolour in step with the audio wipe instead of snapping when
/// the track finally switches. Null when no crossfade is running. For a
/// static (non-adaptive) theme it just returns that theme, so the driver
/// lerps from a colour to the same colour — a harmless no-op.
final crossfadeIncomingThemeProvider =
    FutureProvider<HanamimiTheme?>((ref) async {
  final incoming = ref.watch(audioStateProvider
      .select((s) => s.value?.crossfadeIncomingTrack));
  if (incoming == null) return null;
  final id = ref.watch(selectedThemeIdProvider);
  HanamimiTheme theme;
  if (_isAdaptiveId(id)) {
    final variant = _adaptiveVariant(id);
    final provider = artImageProvider(incoming);
    if (provider == null) {
      theme = variant;
    } else {
      try {
        final scheme = await ColorScheme.fromImageProvider(
          provider: provider,
          brightness: variant.isDark ? Brightness.dark : Brightness.light,
        );
        theme = fromArtScheme(scheme, variant);
      } catch (_) {
        theme = variant;
      }
    }
  } else {
    theme = themeById(id);
  }
  if (ref.watch(nightModeActiveProvider)) theme = nightShift(theme);
  return theme;
});

/// Collapses the audio state down to just the art identity + its image
/// provider, so the extraction re-runs on a genuine art change and not on
/// every position tick. `$1` is a cache key; `$2` is the provider (null =
/// no art → neutral fallback).
final _artKeyProvider = Provider<(String, ImageProvider)?>((ref) {
  final track = ref.watch(audioStateProvider).value?.currentTrack;
  if (track == null) return null;
  // Embedded album art, minted as a blob URL at import time.
  final local = track.albumArtPath;
  if (local != null && local.isNotEmpty) {
    return ('local:$local', NetworkImage(local));
  }
  return null;
});
