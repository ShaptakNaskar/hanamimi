import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../../audio/audio_handler.dart';
import '../../audio/models/audio_state.dart';
import '../../audio/models/queue_mode.dart';

/// Desktop "now playing" integration (ARCHITECTURE-DESKTOP.md §2):
/// on Linux this exports the MPRIS D-Bus object every desktop
/// environment's media keys, volume applets and lock screens talk to —
/// replacing audio_service's media notification.
///
/// Best-effort: no session bus (odd container, WM without D-Bus) just
/// means no media keys; playback is untouched.
Future<void> initDesktopNowPlaying(HanamimiAudioHandler handler) async {
  if (!Platform.isLinux) return; // Windows SMTC lands separately
  try {
    final client = DBusClient.session();
    final mpris = _MprisMediaPlayer(handler);
    await client.registerObject(mpris);
    await client.requestName(
      'org.mpris.MediaPlayer2.hanamimi',
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    handler.engine.stateStream.listen(mpris.onState);
  } catch (_) {}
}

class _MprisMediaPlayer extends DBusObject {
  _MprisMediaPlayer(this.handler)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final HanamimiAudioHandler handler;
  AudioState _last = const AudioState();

  static const _root = 'org.mpris.MediaPlayer2';
  static const _player = 'org.mpris.MediaPlayer2.Player';

  void onState(AudioState state) {
    final changed = <String, DBusValue>{
      if (_status(state) != _status(_last))
        'PlaybackStatus': DBusString(_status(state)),
      if (state.currentTrack != _last.currentTrack ||
          state.duration != _last.duration)
        'Metadata': _metadata(state),
    };
    _last = state;
    if (changed.isNotEmpty) {
      emitPropertiesChanged(_player, changedProperties: changed);
    }
  }

  static String _status(AudioState s) => switch (s.status) {
        PlaybackStatus.playing => 'Playing',
        PlaybackStatus.paused || PlaybackStatus.loading => 'Paused',
        PlaybackStatus.idle || PlaybackStatus.completed => 'Stopped',
      };

  DBusValue _metadata(AudioState s) {
    final track = s.currentTrack;
    final entries = <DBusValue, DBusValue>{
      const DBusString('mpris:trackid'): DBusVariant(DBusObjectPath(
          track == null ? '/org/hanamimi/notrack' : '/org/hanamimi/track/${track.id}')),
    };
    if (track != null) {
      entries.addAll({
        const DBusString('mpris:length'):
            DBusVariant(DBusInt64(s.duration.inMicroseconds)),
        const DBusString('xesam:title'): DBusVariant(DBusString(track.title)),
        const DBusString('xesam:artist'):
            DBusVariant(DBusArray.string([track.artist])),
        const DBusString('xesam:album'): DBusVariant(DBusString(track.album)),
      });
      final art = track.albumArtPath != null
          ? Uri.file(track.albumArtPath!).toString()
          : track.artUrl;
      if (art != null) {
        entries[const DBusString('mpris:artUrl')] =
            DBusVariant(DBusString(art));
      }
    }
    return DBusDict(DBusSignature('s'), DBusSignature('v'), entries);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    final engine = handler.engine;
    switch ('${call.interface}.${call.name}') {
      case '$_player.PlayPause':
        engine.state.isPlaying ? await engine.pause() : await engine.play();
      case '$_player.Play':
        await engine.play();
      case '$_player.Pause':
        await engine.pause();
      case '$_player.Stop':
        await engine.stop();
      case '$_player.Next':
        await engine.next();
      case '$_player.Previous':
        await engine.previous();
      case '$_player.Seek':
        final offset = call.values.firstOrNull;
        if (offset is DBusInt64) {
          await engine
              .seek(engine.position + Duration(microseconds: offset.value));
        }
      case '$_player.SetPosition':
        final position = call.values.elementAtOrNull(1);
        if (position is DBusInt64) {
          await engine.seek(Duration(microseconds: position.value));
        }
      case '$_root.Raise' || '$_root.Quit':
        break; // window raising is the WM's business; quit via the WM
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final engine = handler.engine;
    final value = switch ('$interface.$name') {
      '$_root.CanQuit' => const DBusBoolean(false),
      '$_root.CanRaise' => const DBusBoolean(false),
      '$_root.HasTrackList' => const DBusBoolean(false),
      '$_root.Identity' => const DBusString('Hanamimi+ 花耳'),
      // Basename of the installed .desktop file (= GTK application id).
      '$_root.DesktopEntry' => const DBusString('com.hanamimi.hanamimi'),
      '$_root.SupportedUriSchemes' => DBusArray.string(const []),
      '$_root.SupportedMimeTypes' => DBusArray.string(const []),
      '$_player.PlaybackStatus' => DBusString(_status(engine.state)),
      '$_player.LoopStatus' => DBusString(switch (engine.state.queueMode) {
          QueueMode.repeatOne => 'Track',
          QueueMode.repeatAll => 'Playlist',
          _ => 'None',
        }),
      '$_player.Shuffle' =>
        DBusBoolean(engine.state.queueMode == QueueMode.shuffle),
      '$_player.Rate' ||
      '$_player.MinimumRate' ||
      '$_player.MaximumRate' =>
        const DBusDouble(1.0),
      '$_player.Volume' => const DBusDouble(1.0),
      '$_player.Metadata' => _metadata(engine.state),
      '$_player.Position' => DBusInt64(engine.position.inMicroseconds),
      '$_player.CanGoNext' ||
      '$_player.CanGoPrevious' ||
      '$_player.CanPlay' ||
      '$_player.CanPause' ||
      '$_player.CanSeek' ||
      '$_player.CanControl' =>
        const DBusBoolean(true),
      _ => null,
    };
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    final engine = handler.engine;
    switch ('$interface.$name') {
      case '$_player.LoopStatus':
        engine.setMode(switch ((value as DBusString).value) {
          'Track' => QueueMode.repeatOne,
          'Playlist' => QueueMode.repeatAll,
          _ => QueueMode.sequential,
        });
      case '$_player.Shuffle':
        engine.setMode((value as DBusBoolean).value
            ? QueueMode.shuffle
            : QueueMode.sequential);
      case '$_player.Volume':
        await engine.setVolume((value as DBusDouble).value.clamp(0.0, 1.0));
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    final names = switch (interface) {
      _root => [
          'CanQuit', 'CanRaise', 'HasTrackList', 'Identity',
          'DesktopEntry', 'SupportedUriSchemes', 'SupportedMimeTypes',
        ],
      _player => [
          'PlaybackStatus', 'LoopStatus', 'Shuffle', 'Rate', 'MinimumRate',
          'MaximumRate', 'Volume', 'Metadata', 'Position', 'CanGoNext',
          'CanGoPrevious', 'CanPlay', 'CanPause', 'CanSeek', 'CanControl',
        ],
      _ => const <String>[],
    };
    final out = <String, DBusValue>{};
    for (final name in names) {
      final res = await getProperty(interface, name);
      if (res is DBusGetPropertyResponse) {
        out[name] = (res.returnValues.first as DBusVariant).value;
      }
    }
    return DBusGetAllPropertiesResponse(out);
  }
}
