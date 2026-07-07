import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'audio/queue_manager.dart';
import 'library/models/track.dart';
import 'online/music_provider.dart';
import 'online/saavn_provider.dart';
import 'online/youtube_provider.dart';
import 'platform/desktop/desktop_bootstrap.dart';
import 'platform/desktop/mpris_service.dart';
import 'providers/audio_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Online catalogs (plus build). StreamResolver and the search scopes
  // read this registry.
  musicProviderRegistry[TrackSource.youtube] = YouTubeProvider();
  musicProviderRegistry[TrackSource.saavn] = SaavnProvider();

  final HanamimiAudioHandler audioHandler;
  if (Platform.isAndroid) {
    audioHandler = await AudioService.init(
      builder: () => HanamimiAudioHandler(QueueManager()),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.hanamimi.app.channel.audio',
        androidNotificationChannelName: 'Hanamimi playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // Status-bar icons render alpha-only; the launcher mascot became a
        // featureless blob there. This is a purpose-drawn silhouette.
        androidNotificationIcon: 'drawable/ic_stat_hanamimi',
      ),
    );
  } else {
    // Desktop (M31): no audio_service — the handler is constructed
    // directly (BaseAudioHandler is plain Dart) and MPRIS/SMTC stand in
    // for the media notification and hardware keys.
    await initDesktop(args, prefs);
    audioHandler = HanamimiAudioHandler(QueueManager());
    initDesktopNowPlaying(audioHandler);
  }

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
    child: const HanamimiApp(),
  ));
}
