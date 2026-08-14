import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The visual animation cadence used by the desktop app.
///
/// Desktop monitors commonly run at 120–180 Hz. A normal Flutter [Ticker]
/// follows that refresh rate, which made every always-on visual animation
/// raster and submit the whole window up to 180 times a second. Hanamimi's
/// visualizer source is 60 fps, so the extra frames spend CPU without adding
/// information.
const desktopVisualFrameInterval = Duration(microseconds: 16667);

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// A ticker for visual-only animation.
///
/// On Android it is a regular vsync [Ticker], preserving native 90/120 Hz
/// motion. On desktop every instance shares one exact 60 Hz timer. Sharing is
/// important: band sampling, meters, album art, mascots and playing indicators
/// all update in the same event-loop turn, so Flutter coalesces them into one
/// frame rather than rendering several slightly offset 60 Hz streams.
///
/// Set [nativeVsyncOnMobile] to false for data sources that are intrinsically
/// 60 fps (the FFT frame store). They remain fixed at 60 Hz on every platform.
class AppFrameTicker {
  AppFrameTicker(this._onTick, {this.nativeVsyncOnMobile = true}) {
    if (!_isDesktop && nativeVsyncOnMobile) {
      _native = Ticker(_onTick, debugLabel: 'AppFrameTicker');
    }
  }

  final TickerCallback _onTick;
  final bool nativeVsyncOnMobile;
  Ticker? _native;
  Timer? _timer;
  Duration _desktopEpoch = Duration.zero;
  bool _active = false;
  bool _disposed = false;

  bool get isActive => _active;

  void start() {
    assert(!_disposed, 'Cannot start a disposed AppFrameTicker.');
    if (_disposed || _active) return;
    _active = true;

    final native = _native;
    if (native != null) {
      native.start();
    } else if (_isDesktop) {
      _desktopVisualClock.add(this);
    } else {
      // Fixed-rate mobile data ticker (used by the 60 fps FFT sampler).
      _timer = Timer.periodic(
        desktopVisualFrameInterval,
        (timer) => _onTick(
          Duration(
            microseconds:
                desktopVisualFrameInterval.inMicroseconds * timer.tick,
          ),
        ),
      );
    }
  }

  void stop() {
    if (!_active) return;
    _active = false;
    _native?.stop();
    if (_isDesktop) _desktopVisualClock.remove(this);
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _native?.dispose();
    _native = null;
    _disposed = true;
  }

  void _desktopTick(Duration clockElapsed) {
    if (_active) _onTick(clockElapsed - _desktopEpoch);
  }
}

final _desktopVisualClock = _DesktopVisualClock();

/// Number of animations currently attached to the shared desktop clock.
///
/// Exposed only so regression tests can prove that paused/hidden visuals stop
/// requesting timer-driven frames, just as they previously checked Flutter's
/// transient vsync callback count.
@visibleForTesting
int get debugActiveDesktopVisualTickers =>
    _desktopVisualClock._listeners.length;

class _DesktopVisualClock {
  final _listeners = <AppFrameTicker>{};
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  void add(AppFrameTicker ticker) {
    if (_listeners.isEmpty) {
      _elapsed = Duration.zero;
      _timer = Timer.periodic(desktopVisualFrameInterval, _tick);
    }
    ticker._desktopEpoch = _elapsed;
    _listeners.add(ticker);
  }

  void remove(AppFrameTicker ticker) {
    _listeners.remove(ticker);
    if (_listeners.isNotEmpty) return;
    _timer?.cancel();
    _timer = null;
    _elapsed = Duration.zero;
  }

  void _tick(Timer timer) {
    _elapsed = Duration(
      microseconds: desktopVisualFrameInterval.inMicroseconds * timer.tick,
    );
    // A callback may stop/dispose itself, so iterate over a snapshot.
    for (final ticker in List<AppFrameTicker>.of(_listeners)) {
      ticker._desktopTick(_elapsed);
    }
  }
}
