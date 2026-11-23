// Spec 2 W8b (§3.2 D13, §3.12, §6.7, §7.4 icon widget test, §7.7; A-11;
// R-80): the plain app icon for everyone. The channel maps the phone's
// answer and never throws; the page shows the icon on the home screen,
// changes it (offline too), says what iOS and Android do, and says so when
// the phone refuses or can't; Dating settings lists App icon for everyone;
// D13 offers it only in Tier 1/2; quick exit and sign-out never touch it
// (protective, C-2). The native side is pinned by its text (the change
// itself is a device check, §7.7). Settings' own row and neutral page
// (R-80, outside Dating) are in test/features/settings/app_icon_settings_test.dart.
import 'dart:io';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/device/app_icon.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/app_icon_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/ready_step.dart';
import 'package:attune/features/settings/presentation/screens/app_icon_screen.dart'
    show kAttuneLauncherArt;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_app_icon.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

final loc = AppLocalizationsEn();
const _channel = MethodChannel('attune/safety');

void main() {
  group('the channel', () {
    final calls = <MethodCall>[];
    Object? answer;
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (answer is Exception) throw answer!;
            return answer;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );
    });

    test('reads the icon on the home screen', () async {
      const icon = PlatformAppIcon();
      answer = 'plain';
      expect(await icon.current(), AppIconChoice.plain);
      answer = 'default';
      expect(await icon.current(), AppIconChoice.attune);
      answer = 'unsupported';
      expect(await icon.current(), isNull);
      answer = PlatformException(code: 'x');
      expect(await icon.current(), isNull);
      expect(calls.map((c) => c.method).toSet(), {'appIcon'});
    });

    test('changes it, and a refusal or an error is false', () async {
      const icon = PlatformAppIcon();
      answer = true;
      expect(await icon.choose(AppIconChoice.plain), isTrue);
      expect(calls.last.arguments, 'plain');
      expect(await icon.choose(AppIconChoice.attune), isTrue);
      expect(calls.last.arguments, 'default');
      answer = false;
      expect(await icon.choose(AppIconChoice.plain), isFalse);
      answer = PlatformException(code: 'x');
      expect(await icon.choose(AppIconChoice.plain), isFalse);
    });

    test('no channel (a test, an old build): no icon, no change', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      const icon = PlatformAppIcon();
      expect(await icon.current(), isNull);
      expect(await icon.choose(AppIconChoice.plain), isFalse);
    });
  });

  group('the page', () {
    Future<FakeAppIcon> open(
      WidgetTester t, {
      FakeAppIcon? fake,
      bool online = true,
    }) async {
      final icon = fake ?? FakeAppIcon();
      await pumpDatingShell(
        t,
        initial: DatingPaths.appIcon,
        online: online,
        overrides: [appIconControlProvider.overrideWithValue(icon)],
      );
      return icon;
    }

    RadioListTile<AppIconChoice> tile(WidgetTester t, AppIconChoice c) =>
        t.widget(find.byKey(ValueKey('app_icon_${c.name}')));

    testWidgets('the icon now; Plain changes it, offline too; Attune back', (
      t,
    ) async {
      final icon = await open(t, online: false);
      expect(find.byType(DatingAppIconScreen), findsOneWidget);
      // W8a: FLAG_SECURE, the capture cover and blanking, as every page.
      expect(find.byType(DatingPageWatch), findsOneWidget);
      expect(find.text(loc.appIcon_intro), findsOneWidget);
      expect(tile(t, AppIconChoice.attune).groupValue, AppIconChoice.attune);
      await tapInReach(t, find.text(loc.appIcon_plain));
      await t.pumpAndSettle();
      expect(icon.chosen, [AppIconChoice.plain]);
      expect(tile(t, AppIconChoice.plain).groupValue, AppIconChoice.plain);
      await tapInReach(t, find.text(loc.appIcon_attune));
      await t.pumpAndSettle();
      expect(icon.chosen, [AppIconChoice.plain, AppIconChoice.attune]);
      expect(find.text(loc.appIcon_failed), findsNothing);
    });

    testWidgets('behind the Dating lock, as every Dating page', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.appIcon,
        locked: true,
        pinSet: true,
        overrides: [appIconControlProvider.overrideWithValue(FakeAppIcon())],
      );
      expect(find.byType(DatingAppIconScreen), findsNothing);
      expect(find.text(loc.appIcon_intro), findsNothing);
    });

    testWidgets('alone, back is Dating settings', (t) async {
      await open(t);
      await tapInReach(t, find.byKey(const ValueKey('dating_root_back')));
      await t.pumpAndSettle();
      expect(find.byType(DatingAppIconScreen), findsNothing);
      expect(find.text(loc.appIcon_title), findsOneWidget); // the row
    });

    test('fix round 1 (M-1, M-2): the lines say what the phones do', () {
      // iOS changes the icon, then shows a message with one OK: no confirm.
      expect(loc.appIcon_ios, isNot(contains('confirm')));
      expect(loc.appIcon_ios, contains('message'));
      // Final client fix (M-5): shown on iPads too, so no device word.
      expect(loc.appIcon_ios, isNot(contains(RegExp('iPhone|iPad|phone'))));
      // Android may close Attune, and the icon may leave the home screen.
      expect(loc.appIcon_android, contains('may close Attune'));
      expect(loc.appIcon_android, contains('home screen'));
      expect(loc.appIcon_android, contains('app list'));
    });

    testWidgets('Android says the app may close; iOS that it shows a '
        'message', (t) async {
      await open(t);
      expect(find.text(loc.appIcon_android), findsOneWidget);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(t);
        expect(find.text(loc.appIcon_ios), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a refusal says so and keeps the icon as it was', (t) async {
      final icon = await open(t, fake: FakeAppIcon()..refuse = true);
      await tapInReach(t, find.text(loc.appIcon_plain));
      await t.pumpAndSettle();
      expect(find.text(loc.appIcon_failed), findsOneWidget);
      expect(tile(t, AppIconChoice.attune).groupValue, AppIconChoice.attune);
      expect(icon.icon, AppIconChoice.attune);
    });

    testWidgets('final client fix (M-6): "Attune" shows the launcher art '
        'itself, decoded at the size shown', (t) async {
      await open(t);
      expect(find.byIcon(Icons.favorite), findsNothing);
      final image = t.widget<Image>(
        find.byKey(const ValueKey('app_icon_attune_preview')),
      );
      final resized = image.image as ResizeImage;
      expect(
        (resized.imageProvider as AssetImage).assetName,
        kAttuneLauncherArt,
      );
      expect(resized.width, 44);
      expect(image.excludeFromSemantics, isTrue);
      // The art the launcher icons are made from.
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('image_path: "$kAttuneLauncherArt"'),
      );
      expect(File(kAttuneLauncherArt).existsSync(), isTrue);
    });

    testWidgets('round 2 (N-1): art that can\'t be read leaves a 44 x 44 '
        'tile in the app\'s colour, never a gap', (t) async {
      await open(t);
      final preview = find.byKey(const ValueKey('app_icon_attune_preview'));
      final image = t.widget<Image>(preview);
      final context = t.element(preview);
      // The error widget under the loose constraints the row gives it.
      await t.pumpWidget(
        Center(child: image.errorBuilder!(context, Exception('art'), null)),
      );
      final fallback = find.byKey(const ValueKey('app_icon_attune_fallback'));
      expect(t.getSize(fallback), const Size(44, 44));
    });

    testWidgets('a phone that can\'t change it says so, no choices', (t) async {
      await open(t, fake: FakeAppIcon(null));
      expect(find.text(loc.appIcon_unsupported), findsOneWidget);
      expect(find.text(loc.appIcon_plain), findsNothing);
    });

    testWidgets('goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines', (
      t,
    ) async {
      Widget screen() => const DatingAppIconScreen();
      final overrides = [
        ...datingShellOverrides(),
        appIconControlProvider.overrideWithValue(FakeAppIcon()),
      ];
      await expectFlowGoldens(
        t,
        'dating_app_icon',
        screen,
        overrides: overrides,
        // Final client fix (M-6): the launcher art, decoded.
        before: (t) async {
          final preview = find.byKey(const ValueKey('app_icon_attune_preview'));
          await t.runAsync(
            () => precacheImage(
              t.widget<Image>(preview).image,
              t.element(preview),
            ),
          );
          await t.pump();
        },
      );
      await pumpFlowScreen(t, screen, overrides: overrides);
      await expectFlowGuidelines(t);
    });
  });

  testWidgets('Dating settings lists App icon for everyone and opens it', (
    t,
  ) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      overrides: [
        appIconControlProvider.overrideWithValue(
          FakeAppIcon(AppIconChoice.plain),
        ),
      ],
    );
    final row = find.text(loc.appIcon_title);
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    expect(find.text(loc.appIcon_plain), findsOneWidget);
    await tapInReach(t, row);
    await t.pumpAndSettle();
    expect(find.byType(DatingAppIconScreen), findsOneWidget);
  });

  group('D13', () {
    Future<void> ready(WidgetTester t, {required bool offer}) async {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => DatingReadyStep(
          nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: DatingHome(
                state: DatingHomeState.setupInProgress,
                firstDropAt: DateTime.utc(2026, 12, 1, 19),
                offerPlainIcon: offer,
              ),
            ),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(
              profile: const DatingMyProfile(dropTime: '19:00:00'),
            ),
          ),
        ],
      );
      await t.pumpAndSettle();
    }

    testWidgets('the plain-icon offer only in Tier 1/2', (t) async {
      await ready(t, offer: false);
      expect(find.text(loc.dating_readyPlainIcon), findsNothing);
      await ready(t, offer: true);
      expect(find.text(loc.dating_readyPlainIcon), findsOneWidget);
      expect(find.text(loc.dating_readyPlainIconButton), findsOneWidget);
    });

    testWidgets('the offer opens App icon', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('ready'),
        home: FakeDatingHomeGateway(
          home: DatingHome(
            state: DatingHomeState.setupInProgress,
            firstDropAt: DateTime.utc(2026, 12, 1, 19),
            offerPlainIcon: true,
          ),
        ),
        overrides: [
          appIconControlProvider.overrideWithValue(FakeAppIcon()),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(
              profile: const DatingMyProfile(dropTime: '19:00:00'),
            ),
          ),
        ],
      );
      await tapInReach(t, find.text(loc.dating_readyPlainIconButton));
      await t.pumpAndSettle();
      expect(find.byType(DatingAppIconScreen), findsOneWidget);
    });
  });

  testWidgets('the manual: App icon from Settings or Dating settings; the '
      'trip note only on its own page, never on Me', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    String content(String id) =>
        DatingModeDocs()
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == id)
            .content;
    final icon = content('dating_app_icon');
    expect(icon, contains('in Settings or in Dating settings'));
    expect(icon, contains('never change it back'));
    expect(icon, isNot(contains('confirm')));
    expect(icon, contains('shows a message'));
    expect(icon, contains('app list'));
    // Final client fix (M-5): the iPad is named beside the iPhone.
    for (final id in ['dating_app_icon', 'dating_screen']) {
      final text = content(id);
      expect(text, contains('An iPhone or iPad'), reason: id);
      expect(
        text.replaceAll('iPhone or iPad', ''),
        isNot(contains('iPhone')),
        reason: id,
      );
    }
    final away = content('dating_away');
    expect(away, contains('Me shows only a short line and "What this means"'));
    expect(away, contains('are on their own page'));
    expect(away, contains('never comes as a notification'));
  });

  testWidgets('quick exit and sign-out never touch the icon', (t) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.quickExit);
    await registry.run(WipeMoment.signOut);
    expect(calls.where((m) => m.contains('Icon')), isEmpty);
    for (final e in registry.entries) {
      expect(e.keys.where((k) => k.contains('icon')), isEmpty, reason: e.id);
    }
  });

  test('the native side: two launcher aliases, MainActivity found by the '
      'tool but listed by no launcher, the icon methods, iOS\'s alternate '
      'icon', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:name=".IconDefault"'));
    expect(manifest, contains('android:name=".IconPlain"'));
    expect(RegExp('android:enabled="false"').allMatches(manifest).length, 1);
    expect(manifest, contains('<data android:scheme="attune-tool-launch"/>'));
    expect(
      RegExp(r'IconPlain[\s\S]*?</activity-alias>').stringMatch(manifest),
      contains('android.intent.category.LAUNCHER'),
    );
    expect(manifest.toLowerCase(), isNot(contains('dating')));
    // Fix round 1 (I-1): an alias carries none of its target's meta-data, so
    // each names MainActivity's NormalTheme itself (FlutterActivity reads it
    // from the component that started it).
    for (final alias in ['IconDefault', 'IconPlain']) {
      final block = RegExp(
        '\\.$alias"[\\s\\S]*?</activity-alias>',
      ).stringMatch(manifest);
      expect(block, isNotNull, reason: alias);
      expect(
        block,
        contains(
          '<meta-data\n'
          '                android:name="io.flutter.embedding.android.NormalTheme"\n'
          '                android:resource="@style/NormalTheme"',
        ),
        reason: alias,
      );
    }
    // Fix round 1 (M-3): the phone keeps each alias's on/off by its name.
    expect(manifest, contains('Never rename these two'));
    final kt =
        File(
          'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
        ).readAsStringSync();
    expect(kt, contains('"appIcon" ->'));
    expect(kt, contains('"setAppIcon" ->'));
    expect(kt, contains('PackageManager.DONT_KILL_APP'));
    // Fix round 1 (M-3): the new alias is on before the old one goes off
    // (never no launcher entry), and a half-done switch is undone the same
    // way round (never two icons, never none).
    const newOn = 'setAlias(if (plain) plainIcon else defaultIcon, true)';
    const oldOff = 'setAlias(if (plain) defaultIcon else plainIcon, false)';
    const oldOn = 'setAlias(if (plain) defaultIcon else plainIcon, true)';
    const newOff = 'setAlias(if (plain) plainIcon else defaultIcon, false)';
    expect(kt.indexOf(newOn), greaterThan(-1));
    expect(kt.indexOf(oldOff), greaterThan(kt.indexOf(newOn)));
    expect(kt.indexOf(oldOn), greaterThan(kt.indexOf(oldOff)));
    expect(kt.indexOf(newOff), greaterThan(kt.indexOf(oldOn)));
    expect(kt, contains('Never rename'));
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('setAlternateIconName(name)'));
    // Fix round 1 (M-5): the answer goes back on the main thread.
    expect(
      swift,
      contains('DispatchQueue.main.async { result(error == nil) }'),
    );
    expect(swift, contains('"IconPlain"'));
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = IconPlain;'
          .allMatches(pbx)
          .length,
      3,
    );
    expect(
      File(
        'ios/Runner/Assets.xcassets/IconPlain.appiconset/IconPlain-1024.png',
      ).existsSync(),
      isTrue,
    );
  });
}
