import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'audio/queue_manager.dart';
import 'providers/audio_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final audioHandler = await AudioService.init(
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

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
    child: const HanamimiApp(),
  ));
}
