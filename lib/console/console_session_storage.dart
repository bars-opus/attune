// Spec 2 W7b Task 7, fix round 2: the console's Supabase session lives in
// the tab's own store (sessionStorage on the web, console_tab_store_web),
// never the device's localStorage, so closing the tab signs the moderator
// out and an aal2 session never outlives it. The 30-minute idle sign-out
// still applies within the tab.
import 'package:supabase_flutter/supabase_flutter.dart';

/// A tab's key-value store (sessionStorage on the web; memory in tests).
abstract class ConsoleTabStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// A store that lives as long as this object (tests, and the fallback
/// when the browser refuses sessionStorage).
class MemoryTabStore implements ConsoleTabStore {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;

  @override
  void remove(String key) => values.remove(key);
}

/// Spec 2 W7c Task 9 (the Task 7 re-review's N-3): a tab store that never
/// throws. Once the browser refuses a read or a write (a quota, a sandbox),
/// the session lives in memory for the rest of the page, and whatever the
/// refusing store still held under that key is removed (best effort), so a
/// stale session is never read back. Supabase's persistSession then never
/// rejects unhandled.
class ConsoleSafeTabStore implements ConsoleTabStore {
  ConsoleSafeTabStore(this._store);

  final ConsoleTabStore _store;
  MemoryTabStore? _memory;

  MemoryTabStore _fallBack(String key) {
    try {
      _store.remove(key);
    } catch (_) {}
    return _memory ??= MemoryTabStore();
  }

  @override
  String? read(String key) {
    if (_memory case final m?) return m.read(key);
    try {
      return _store.read(key);
    } catch (_) {
      return _fallBack(key).read(key);
    }
  }

  @override
  void write(String key, String value) {
    if (_memory case final m?) return m.write(key, value);
    try {
      _store.write(key, value);
    } catch (_) {
      _fallBack(key).write(key, value);
    }
  }

  @override
  void remove(String key) {
    _memory?.remove(key);
    try {
      _store.remove(key);
    } catch (_) {}
  }
}

/// The Supabase client's session key for a project URL (its own default).
String consoleSessionKey(String url) =>
    'sb-${Uri.parse(url).host.split('.').first}-auth-token';

/// The session, kept in the tab's store only.
class ConsoleSessionStorage extends LocalStorage {
  const ConsoleSessionStorage(this.store, {required this.key});

  final ConsoleTabStore store;
  final String key;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => store.read(key) != null;

  @override
  Future<String?> accessToken() async => store.read(key);

  @override
  Future<void> removePersistedSession() async => store.remove(key);

  @override
  Future<void> persistSession(String persistSessionString) async =>
      store.write(key, persistSessionString);
}

/// The console's auth options: the tab's store; no session read from a
/// link (the console signs in by phone code and TOTP only).
FlutterAuthClientOptions consoleAuthOptions(
  ConsoleTabStore store,
  String url,
) => FlutterAuthClientOptions(
  localStorage: ConsoleSessionStorage(store, key: consoleSessionKey(url)),
  detectSessionInUri: false,
);

/// Removes a session an older console build kept on the device.
Future<void> consoleForgetDeviceSession(LocalStorage device) async {
  try {
    await device.initialize();
    await device.removePersistedSession();
  } catch (_) {}
}
