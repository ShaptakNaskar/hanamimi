import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';

import 'package:hanamimi/platform/gamepad_service.dart';

/// The ROG Ally / Steam Deck embedded pad is an XInput device on every
/// OS, but each `gamepads` backend surfaces it with a different key
/// naming + value range. These feed synthetic events matching each
/// backend's real convention and assert the mapping fires the right
/// action — the Windows POV-hat + unsigned-axis paths were dead before.
void main() {
  late List<String> log;
  late GamepadService svc;

  setUp(() {
    log = [];
    svc = GamepadService(
      isActive: () => true,
      onDirection: (d) => log.add('dir:${d.name}'),
      onActivate: () => log.add('activate'),
      onBack: () => log.add('back'),
      onPlayPause: () => log.add('playpause'),
      onNext: () => log.add('next'),
      onPrevious: () => log.add('previous'),
    );
  });

  GamepadEvent ev(KeyType type, String key, double value) => GamepadEvent(
        gamepadId: '0',
        timestamp: 0,
        type: type,
        key: key,
        value: value,
      );

  void analog(String key, double value) =>
      svc.debugHandleEvent(ev(KeyType.analog, key, value));
  void button(String key) =>
      svc.debugHandleEvent(ev(KeyType.button, key, 1.0));

  group('Windows (WinMM joyGetPosEx)', () {
    // Regression: the whole Windows path was dead — POV hat and the
    // unsigned 0..65535 axis range were never handled.
    test('D-pad POV hat maps every cardinal', () {
      analog('pov', 0); // up
      analog('pov', 65535); // centre (re-arm)
      analog('pov', 9000); // right
      analog('pov', 65535);
      analog('pov', 18000); // down
      analog('pov', 65535);
      analog('pov', 27000); // left
      expect(log, ['dir:up', 'dir:right', 'dir:down', 'dir:left']);
    });

    test('POV fires on direction change without needing to re-centre', () {
      analog('pov', 0); // up
      analog('pov', 18000); // straight to down
      expect(log, ['dir:up', 'dir:down']);
    });

    test('POV held in one direction does not repeat', () {
      analog('pov', 9000);
      analog('pov', 9000);
      analog('pov', 9000);
      expect(log, ['dir:right']);
    });

    test('left stick uses the unsigned 0..65535 range (centre ~32767)', () {
      // A resting stick sits at ~32767 and must NOT fire (the old bug
      // read centre as fully deflected and latched forever).
      analog('dwXpos', 32767);
      analog('dwYpos', 32767);
      expect(log, isEmpty);

      analog('dwXpos', 65535); // full right
      analog('dwXpos', 32767); // recentre (re-arm)
      analog('dwXpos', 0); // full left
      analog('dwYpos', 0); // full up
      analog('dwYpos', 32767);
      analog('dwYpos', 65535); // full down
      expect(log, ['dir:right', 'dir:left', 'dir:up', 'dir:down']);
    });

    test('face + shoulder + start buttons map', () {
      button('button-0'); // A
      button('button-1'); // B
      button('button-4'); // LB
      button('button-5'); // RB
      button('button-7'); // Start
      expect(log,
          ['activate', 'back', 'previous', 'next', 'playpause']);
    });
  });

  group('Linux joydev (regression — this path already worked)', () {
    test('signed ±32767 left stick', () {
      analog('0', 32767); // right
      analog('0', 0); // recentre
      analog('0', -32767); // left
      expect(log, ['dir:right', 'dir:left']);
    });

    test('hat axes 6/7 are the D-pad', () {
      analog('7', 32767); // down
      analog('7', 0);
      analog('6', -32767); // left
      expect(log, ['dir:down', 'dir:left']);
    });

    test('numeric buttons map', () {
      button('0'); // A
      button('5'); // RB
      expect(log, ['activate', 'next']);
    });
  });

  group('Android/SDL (regression)', () {
    test('±1.0 stick', () {
      analog('leftx', 1.0); // right
      analog('leftx', 0.0);
      analog('leftx', -1.0); // left
      expect(log, ['dir:right', 'dir:left']);
    });

    test('named D-pad buttons', () {
      button('dpad-up');
      button('dpad-right');
      expect(log, ['dir:up', 'dir:right']);
    });
  });

  test('inactive window swallows all input', () {
    final gated = GamepadService(
      isActive: () => false,
      onDirection: (d) => log.add('dir:${d.name}'),
      onActivate: () => log.add('activate'),
      onBack: () {},
      onPlayPause: () {},
      onNext: () {},
      onPrevious: () {},
    );
    gated.debugHandleEvent(ev(KeyType.button, 'button-0', 1.0));
    gated.debugHandleEvent(ev(KeyType.analog, 'pov', 9000));
    expect(log, isEmpty);
  });
}
