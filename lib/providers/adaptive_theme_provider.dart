import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/hanamimi_theme.dart';
import '../theme/themes.dart';
import 'audio_provider.dart';

/// Art-derived (Monet) theme for the current track. Runs Flutter's built-in
/// Material You quantizer (`ColorScheme.fromImageProvider`) over the album
/// art and maps the result to a [HanamimiTheme]. Recomputes only when the
/// track's art actually changes (keyed), and falls back to a neutral
/// grey-pink when there's no art or extraction fails — never a jarring
/// default. Only consulted while the selected theme is "adaptive".
final adaptiveThemeProvider = FutureProvider<HanamimiTheme>((ref) async {
  final track = ref.watch(_artKeyProvider);
  final provider = track?.$2;
  if (provider == null) return neutralAdaptive;
  try {
    final scheme = await ColorScheme.fromImageProvider(provider: provider);
    return fromArtScheme(scheme);
  } catch (_) {
    return neutralAdaptive;
  }
});

/// Collapses the audio state down to just the art identity + its image
/// provider, so the extraction re-runs on a genuine art change and not on
/// every position tick. `$1` is a cache key; `$2` is the provider (null =
/// no art → neutral fallback).
final _artKeyProvider = Provider<(String, ImageProvider)?>((ref) {
  final track = ref.watch(audioStateProvider).value?.currentTrack;
  if (track == null) return null;
  // Prefer the locally cached/embedded art; fall back to the remote URL.
  final local = track.albumArtPath;
  if (local != null && local.isNotEmpty) {
    return ('local:$local', FileImage(File(local)));
  }
  final url = track.artUrl;
  if (url != null && url.isNotEmpty) {
    return ('net:$url', NetworkImage(url));
  }
  return null;
});
