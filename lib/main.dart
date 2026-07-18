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

  // audio_service's web backend wires the browser Media Session API —
  // hardware media keys and the tab's "now playing" chip drive the same
  // handler the Android notification does.
  final audioHandler = await AudioService.init(
    builder: () => HanamimiAudioHandler(QueueManager()),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hanamimi.app.channel.audio',
      androidNotificationChannelName: 'Hanamimi playback',
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
