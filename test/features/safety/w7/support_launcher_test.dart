// Spec 1 W7a, ruling PF-H3: the support screen's launcher opens a confirmed
// tel:, sms: or https: link with launchUrl directly and never asks
// canLaunchUrl first (it answers false for tel: and sms: on real phones,
// where neither manifest declares them), and says so when nothing opened.
import 'dart:io';

import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeLauncher extends UrlLauncherPlatform {
  _FakeLauncher({this.result = true, this.error});

  final bool result;
  final Object? error;
  final canLaunchCalls = <String>[];
  final launched = <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    if (error case final e?) throw e;
    return result;
  }
}

Future<void> _open(
  WidgetTester tester,
  String url, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => TextButton(
                  onPressed:
                      () => ref.read(supportLauncherProvider)(context, url),
                  child: const Text('go'),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  if (settle) await tester.pumpAndSettle();
}

const _cannotOpen =
    "That didn't open here. Try it from another phone or computer.";

void main() {
  late UrlLauncherPlatform original;
  setUp(() => original = UrlLauncherPlatform.instance);
  tearDown(() => UrlLauncherPlatform.instance = original);

  testWidgets('a call goes straight to launchUrl, never canLaunchUrl', (
    tester,
  ) async {
    final fake = _FakeLauncher();
    UrlLauncherPlatform.instance = fake;
    await _open(tester, 'tel:999');
    expect(fake.canLaunchCalls, isEmpty);
    expect(fake.launched, [
      ('tel:999', PreferredLaunchMode.externalApplication),
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a text and a website do too', (tester) async {
    final fake = _FakeLauncher();
    UrlLauncherPlatform.instance = fake;
    await _open(tester, 'sms:116123');
    await _open(tester, 'https://dv.example.org/help');
    expect(fake.canLaunchCalls, isEmpty);
    expect(fake.launched, [
      ('sms:116123', PreferredLaunchMode.externalApplication),
      ('https://dv.example.org/help', PreferredLaunchMode.externalApplication),
    ]);
  });

  testWidgets('nothing opened: a SnackBar says so, unanimated and announced', (
    tester,
  ) async {
    UrlLauncherPlatform.instance = _FakeLauncher(result: false);
    await _open(tester, 'tel:999', settle: false);
    // One frame: already fully in (never animated, §2.2).
    await tester.pump();
    await tester.pump();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.animation?.value, 1.0);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains(_cannotOpen),
    );
    expect(find.text(_cannotOpen), findsOneWidget);
  });

  testWidgets('the platform throws: the same SnackBar, no crash', (
    tester,
  ) async {
    UrlLauncherPlatform.instance = _FakeLauncher(
      error: PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    await _open(tester, 'tel:999');
    expect(tester.takeException(), isNull);
    expect(find.text(_cannotOpen), findsOneWidget);
  });

  test('the launcher never goes through canLaunchUrl or UrlLauncherUtils', () {
    final source =
        File(
          'lib/features/safety/presentation/providers/support_resources_providers.dart',
        ).readAsStringSync();
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code, isNot(contains('canLaunchUrl')));
    expect(code, isNot(contains('UrlLauncherUtils')));
    expect(code, contains('LaunchMode.externalApplication'));
  });
}
