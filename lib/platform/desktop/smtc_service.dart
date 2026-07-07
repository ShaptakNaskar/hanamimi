import 'dart:async';
import 'dart:io';

// The package's PlaybackStatus clashes with the app's own — prefixed.
import 'package:smtc_windows/smtc_windows.dart' as smtc;

import '../../audio/audio_handler.dart';
import '../../audio/models/audio_state.dart';

/// Windows "now playing" integration (ARCHITECTURE-DESKTOP.md §2):
/// System Media Transport Controls — the media flyout next to the
/// volume OSD, lock-screen controls, and global hardware media keys.
/// The Windows counterpart of mpris_service.dart, wired to the same
/// QueueManager state stream.
///
/// Best-effort like MPRIS: if the Rust side fails to init, playback is
/// untouched — only the system integration is missing.
Future<void> initWindowsSmtc(HanamimiAudioHandler handler) async {
  if (!Platform.isWindows) return;
  try {
    await smtc.SMTCWindows.initialize();
    final controls = smtc.SMTCWindows(
      config: const smtc.SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: true,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
      enabled: true,
    );
    final engine = handler.engine;

    controls.buttonPressStream.listen((button) {
      switch (button) {
        case smtc.PressedButton.play:
          engine.play();
        case smtc.PressedButton.pause:
          engine.pause();
        case smtc.PressedButton.next:
          engine.next();
        case smtc.PressedButton.previous:
          engine.previous();
        case smtc.PressedButton.stop:
          engine.stop();
        default:
          break;
      }
    });

    smtc.PlaybackStatus mapStatus(PlaybackStatus status) =>
        switch (status) {
          PlaybackStatus.playing => smtc.PlaybackStatus.playing,
          PlaybackStatus.paused ||
          PlaybackStatus.loading =>
            smtc.PlaybackStatus.paused,
          PlaybackStatus.completed ||
          PlaybackStatus.idle =>
            smtc.PlaybackStatus.stopped,
        };

    var last = const AudioState();
    engine.stateStream.listen((state) {
      if (state.status != last.status) {
        controls.setPlaybackStatus(mapStatus(state.status));
      }

      final track = state.currentTrack;
      if (track != null && track != last.currentTrack) {
        // WinRT thumbnails load from URIs; remote art uses its https
        // URL, local extracted art rides a file: URI (works for
        // unpackaged desktop apps; harmless no-thumb if it doesn't).
        final thumb = track.artUrl ??
            (track.albumArtPath != null
                ? Uri.file(track.albumArtPath!).toString()
                : null);
        controls.updateMetadata(smtc.MusicMetadata(
          title: track.title,
          artist: track.artist,
          album: track.album,
          thumbnail: thumb,
        ));
      }
      if (state.duration != last.duration) {
        controls.updateTimeline(smtc.PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: state.duration.inMilliseconds,
          positionMs: engine.position.inMilliseconds,
        ));
      }
      last = state;
    });

    // The flyout's progress bar doesn't self-advance — feed it about
    // once a second (any finer just burns IPC).
    var lastTickMs = 0;
    engine.positionStream.listen((position) {
      final ms = position.inMilliseconds;
      if ((ms - lastTickMs).abs() < 1000) return;
      lastTickMs = ms;
      controls.updateTimeline(smtc.PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: engine.state.duration.inMilliseconds,
        positionMs: ms,
      ));
    });
  } catch (_) {}
}
