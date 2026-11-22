// Spec 2 W7b Task 7, fix round 2: the browser tab's sessionStorage, through
// dart:js_interop (the console imports no package beyond Flutter and
// supabase_flutter). Imported only by main_console.dart, the web entry
// point. A browser that refuses sessionStorage gets a store in memory:
// the session then lasts only as long as the page.
//
// Spec 2 W7c Task 9 (the Task 7 re-review's N-3): the probe writes and
// removes as well as reads, and the store is wrapped so that a write the
// browser refuses later (a quota) moves the session to memory instead of
// failing unhandled.
import 'dart:js_interop';

import 'package:attune/console/console_session_storage.dart';

@JS('sessionStorage')
external _Storage get _sessionStorage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// sessionStorage, or memory when the browser refuses it.
ConsoleTabStore browserTabStore() {
  const probe = 'attune-console-probe';
  try {
    final s = _sessionStorage;
    s.getItem(probe);
    s.setItem(probe, '1');
    s.removeItem(probe);
    return ConsoleSafeTabStore(_BrowserTabStore(s));
  } catch (_) {
    return MemoryTabStore();
  }
}

class _BrowserTabStore implements ConsoleTabStore {
  _BrowserTabStore(this._s);

  final _Storage _s;

  @override
  String? read(String key) => _s.getItem(key);

  @override
  void write(String key, String value) => _s.setItem(key, value);

  @override
  void remove(String key) => _s.removeItem(key);
}
