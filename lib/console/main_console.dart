// Spec 2 W7b (§6.4, F-6): the moderation console, a separate web entry
// point (flutter build web -t lib/console/main_console.dart), hosted as a
// private static site behind an access gate. It imports only lib/console
// and the web-safe Supabase client. The project's URL and anon key come
// from --dart-define at build time (no file holds them).
//
// Task 7: a build without them (CI's) says so instead of failing to start.
// No functions region is set (the function's CORS has no x-region).
// Fix round 2: the session lives in the tab's sessionStorage, and a
// session an older build left in the device's localStorage is removed.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/console_session_storage.dart';
import 'package:attune/console/console_tab_store_web.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(
      const MaterialApp(
        title: kConsoleTitle,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text(
              'This build of the console has no server set. Build it with '
              '--dart-define=SUPABASE_URL=… and SUPABASE_ANON_KEY=….',
            ),
          ),
        ),
      ),
    );
    return;
  }
  await consoleForgetDeviceSession(
    SharedPreferencesLocalStorage(persistSessionKey: consoleSessionKey(url)),
  );
  await Supabase.initialize(
    url: url,
    publishableKey: key,
    authOptions: consoleAuthOptions(browserTabStore(), url),
  );
  final client = Supabase.instance.client;
  runApp(
    ConsoleApp(
      api: SupabaseConsoleApi(client),
      auth: SupabaseConsoleAuth(client),
    ),
  );
}
