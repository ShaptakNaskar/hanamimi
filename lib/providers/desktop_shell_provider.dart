import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the desktop sidebar asked the middle pane to open
/// (Spotify-style three-pane shell, M31). A nonce makes every click a
/// fresh request so re-opening the same playlist after browsing away
/// still navigates.
enum DesktopCollectionType { liked, playlist, folder }

class DesktopCollectionRequest {
  const DesktopCollectionRequest._(
      this.type, this.playlistId, this.folderPath, this.nonce);

  final DesktopCollectionType type;
  final int? playlistId;
  final String? folderPath;
  final int nonce;
}

class DesktopCollectionNotifier extends Notifier<DesktopCollectionRequest?> {
  var _nonce = 0;

  @override
  DesktopCollectionRequest? build() => null;

  void openLiked() => state = DesktopCollectionRequest._(
      DesktopCollectionType.liked, null, null, ++_nonce);

  void openPlaylist(int id) => state = DesktopCollectionRequest._(
      DesktopCollectionType.playlist, id, null, ++_nonce);

  void openFolder(String path) => state = DesktopCollectionRequest._(
      DesktopCollectionType.folder, null, path, ++_nonce);

  /// Back to whatever tab the user drives manually.
  void clear() => state = null;
}

final desktopCollectionProvider =
    NotifierProvider<DesktopCollectionNotifier, DesktopCollectionRequest?>(
        DesktopCollectionNotifier.new);

/// Whether the desktop middle pane is showing lyrics (Spotify-style —
/// the Now Playing panel's "Lyrics" chevron swaps the middle pane
/// instead of raising a bottom sheet in a desktop window).
class DesktopLyricsNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void close() => state = false;
}

final desktopLyricsOpenProvider =
    NotifierProvider<DesktopLyricsNotifier, bool>(DesktopLyricsNotifier.new);
