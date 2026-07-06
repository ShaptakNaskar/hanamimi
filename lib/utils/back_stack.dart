/// In-app back handling for UI that isn't a real route — the Library
/// search overlay and the inline folder/playlist detail views. Real
/// routes (bottom sheets, dialogs) already pop normally and never reach
/// this.
///
/// A widget state registers a handler (keyed by itself) in `initState`
/// and unregisters in `dispose`. On a system back press, AppShell asks
/// handlers newest-first; a handler returns true when it consumed the
/// press (closed something), false when it had nothing open.
class BackStack {
  BackStack._();

  static final _handlers = <Object, bool Function()>{};

  static void register(Object key, bool Function() handler) {
    // Re-registering moves the key to the top (newest wins).
    _handlers.remove(key);
    _handlers[key] = handler;
  }

  static void unregister(Object key) => _handlers.remove(key);

  /// True if some in-app view consumed the back press.
  static bool pop() {
    for (final key in _handlers.keys.toList().reversed) {
      final handler = _handlers[key];
      if (handler != null && handler()) return true;
    }
    return false;
  }
}
