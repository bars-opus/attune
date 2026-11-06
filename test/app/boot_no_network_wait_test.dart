// Spec 1 W10b (§3.14, P-16): boot never waits on the network. With an
// expired stored session and a backend that never replies, the Supabase
// step returns at once and the first frame paints within the 1 s bound;
// and main() awaits only the five local, bounded steps before runApp, so a
// network await added to boot (say, refreshing the session) fails here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/app/boot_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A backend that accepts every request and never answers.
class _SilentBackend extends http.BaseClient {
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request.url);
    return Completer<http.StreamedResponse>().future;
  }
}

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A stored session whose access token expired two hours ago.
String _expiredSession() {
  final exp =
      DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch ~/
      1000;
  final jwt =
      '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': 'u1', 'exp': exp, 'role': 'authenticated'})}.sig';
  return jsonEncode({
    'access_token': jwt,
    'expires_in': 3600,
    'expires_at': exp,
    'refresh_token': 'r1',
    'token_type': 'bearer',
    'user': {
      'id': 'u1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
    },
  });
}

/// The `await` lines of the function that starts at [signature] in [src].
List<String> _awaits(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing $signature');
  final end = src.indexOf('\n}\n', start);
  return src
      .substring(start, end)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.contains('await '))
      .toList();
}

void main() {
  testWidgets(
    'an expired session and a silent backend: first frame within 1 s',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sb-boot-test-auth-token': _expiredSession(),
      });
      // No deep link at launch (the app_links plugin has no host here).
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('com.llfbandit.app_links/events'),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      final backend = _SilentBackend();
      final timeline = BootTimeline()..start();
      await tester.runAsync(() async {
        // The Supabase step of boot, bounded as a whole: a wait on the
        // silent backend fails here after 1 s instead of hanging.
        Future<void> boot() async {
          await Supabase.initialize(
            url: 'https://boot-test.supabase.co',
            publishableKey: 'anon',
            httpClient: backend,
          );
          timeline.mark('supabase');
        }

        await boot().timeout(const Duration(seconds: 1));
        // Let the unawaited session refresh reach the backend.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpWidget(const MaterialApp(home: Text('first frame')));
      final lines = <String>[];
      await timeline.reportFirstFrame(
        firstFrame: Future<void>.value(),
        log: lines.add,
      );

      expect(find.text('first frame'), findsOneWidget);
      expect(
        Supabase.instance.client.auth.currentSession,
        isNotNull,
        reason: 'the stored session is restored locally',
      );
      expect(
        backend.requests,
        isNotEmpty,
        reason: 'the refresh did go to the backend, which never answered',
      );
      final total = int.parse(
        RegExp(r'first frame (\d+) ms').firstMatch(lines.single)!.group(1)!,
      );
      expect(total, lessThan(1000), reason: lines.single);
      await tester.runAsync(() => Supabase.instance.dispose());
    },
  );

  test('main() awaits only the five local, bounded steps before runApp', () {
    final src = File('lib/main.dart').readAsStringSync();
    final main = src.substring(
      src.indexOf('Future<void> main() async {'),
      src.indexOf('  runApp('),
    );
    expect(
      main
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.contains('await '))
          .toList(),
      [
        'await _initializeSupabase();',
        'await chatCache.init().timeout(const Duration(seconds: 8));',
        'final prefs = await SharedPreferences.getInstance();',
        'await AgeGateStore.restoreBlock(prefs).timeout(const Duration(seconds: 1));',
        'final safetyLockSeed = await _safetyLockSeed();',
      ],
    );
    expect(_awaits(src, 'Future<void> _initializeSupabase() async {'), [
      'await Supabase.initialize(',
    ]);
    expect(_awaits(src, 'Future<SafetyLockState?> _safetyLockSeed() async {'), [
      'return await computeLockSeed(',
    ]);
  });
}
