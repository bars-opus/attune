// Spec 2 W8a (§3.0 Discretion, §6.7, §7.4, §7.7; F-4): the screen is
// protected while any Dating page is open: setSecure(true) on the
// attune/safety channel when the first one opens, setSecure(false) when
// the last one closes (mock channel; FLAG_SECURE itself is a device
// check). A page pushed over Dating keeps it; a go() from one Dating page
// to another never drops it. On iOS a Dating page blurs while the screen
// is captured (the answer, then captureChanged), and nothing else does.
// No Dating file shows a network image, offers a long press or shares a
// file (no gallery saves).
//
// Task 2 fix round 1: the cover keeps its tree, so a capture starting or
// stopping loses nothing typed (I-1); a failure on a phone is reported,
// never swallowed (I-3); an iPhone is covered until it answers (M-2); a
// late answer changes nothing (M-5); the native text is pinned branch by
// branch (M-4).
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/dating/device/dating_discretion.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingUnlockScreen;
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/safety/presentation/widgets/pin_keypad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

const _channel = MethodChannel('attune/safety');

/// The cover on screen, if any (its tree never changes shape: I-1).
Finder _cover() =>
    find.byKey(const ValueKey('dating_capture_cover'), skipOffstage: false);

/// Whether a Dating page is blurred now: excluded from semantics, blurred
/// past reading and not touchable, all three or none.
bool _blurred(WidgetTester t, [Finder? at]) {
  final cover = at ?? _cover();
  if (cover.evaluate().isEmpty) return false;
  final semantics = t.widget<ExcludeSemantics>(cover);
  final filter = t.widget<ImageFiltered>(
    find.descendant(of: cover, matching: find.byType(ImageFiltered)).first,
  );
  final pointer = t.widget<AbsorbPointer>(
    find.descendant(of: cover, matching: find.byType(AbsorbPointer)).first,
  );
  expect(filter.imageFilter, ImageFilter.blur(sigmaX: 40, sigmaY: 40));
  expect(
    {semantics.excluding, filter.enabled, pointer.absorbing},
    hasLength(1),
    reason: 'semantics, blur and touch go together',
  );
  return filter.enabled;
}

class _Typed extends StatefulWidget {
  const _Typed();
  static int inits = 0;
  @override
  State<_Typed> createState() => _TypedState();
}

class _TypedState extends State<_Typed> {
  @override
  void initState() {
    super.initState();
    _Typed.inits++;
  }

  @override
  Widget build(BuildContext context) => const TextField();
}

class _Toggle extends StatefulWidget {
  const _Toggle({super.key});
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _page = false;
  void set(bool page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) =>
      _page
          ? const DatingPageWatch(child: Text('a Dating page'))
          : const SizedBox();
}

void main() {
  final calls = <Object?>[];
  var captured = false;
  SchedulerPhase? firstPhase;

  setUp(() {
    calls.clear();
    captured = false;
    firstPhase = null;
    DatingDiscretion.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'setSecure') return null;
          firstPhase ??= SchedulerBinding.instance.schedulerPhase;
          calls.add(call.arguments);
          return captured && call.arguments == true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  });

  /// iOS saying the capture changed.
  Future<void> nativeSays(WidgetTester t, bool on) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'attune/safety',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('captureChanged', on),
          ),
          (_) {},
        );
    await t.pump();
  }

  testWidgets('FLAG_SECURE: on with the first Dating page, kept from one '
      'Dating page to the next and under a page pushed over it, off after '
      'the last', (t) async {
    final s = await pumpDatingShell(t);
    expect(calls, isEmpty);
    s.router.push(DatingPaths.settings);
    await t.pumpAndSettle();
    expect(calls, [true]);
    expect(DatingDiscretion.secure, isTrue);
    s.router.push(DatingPaths.neverIntroduce);
    await t.pumpAndSettle();
    s.router.go(DatingPaths.settings);
    await t.pumpAndSettle();
    s.router.push(RouteNames.safetyPin);
    await t.pumpAndSettle();
    expect(find.text('PIN SETUP'), findsOneWidget);
    expect(calls, [true]);
    s.router.pop();
    await t.pumpAndSettle();
    // Back from one Dating page to the one under it keeps it too.
    s.router.push(DatingPaths.neverIntroduce);
    await t.pumpAndSettle();
    s.router.pop();
    await t.pumpAndSettle();
    expect(calls, [true]);
    s.router.go(RouteNames.home);
    await t.pumpAndSettle();
    expect(calls, [true, false]);
    expect(DatingDiscretion.secure, isFalse);
  });

  testWidgets('a deep link straight into Dating asks for protection while '
      'its first frame is being built, before it is shown', (t) async {
    await pumpDatingShell(t, initial: DatingPaths.chats);
    expect(calls, [true]);
    expect(firstPhase, SchedulerPhase.persistentCallbacks);
  });

  testWidgets('iOS: a Dating page blurs while the screen is captured, and '
      'clears when capture ends', (t) async {
    captured = true;
    final s = await pumpDatingShell(t, initial: DatingPaths.settings);
    expect(_blurred(t), isTrue);
    await nativeSays(t, false);
    expect(_blurred(t), isFalse);
    await nativeSays(t, true);
    expect(_blurred(t), isTrue);
    s.router.go(RouteNames.home);
    await t.pumpAndSettle();
    // Off Dating, a late captureChanged blurs nothing.
    await nativeSays(t, true);
    expect(DatingDiscretion.captured.value, isFalse);
    expect(_cover(), findsNothing);
  });

  testWidgets('I-1: a capture starting and stopping keeps what was typed (the '
      'page is never rebuilt from scratch)', (t) async {
    _Typed.inits = 0;
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DatingCaptureCover(child: _Typed())),
      ),
    );
    await t.enterText(find.byType(TextField), 'half a message');
    DatingDiscretion.captured.value = true;
    await t.pump();
    expect(_blurred(t), isTrue);
    DatingDiscretion.captured.value = false;
    await t.pump();
    expect(_blurred(t), isFalse);
    expect(find.text('half a message'), findsOneWidget);
    expect(_Typed.inits, 1);
  });

  const stopLine = 'Stop recording or sharing your screen to enter your PIN.';

  testWidgets('I-4: on an iPhone being recorded or mirrored, the unlock page '
      'never opens the PIN sheet (its keys would show); it says so calmly, '
      'and opens the sheet once the capture ends', (t) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    captured = true;
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      locked: true,
      pinSet: true,
    );
    expect(s.location, startsWith('${DatingPaths.unlock}?from='));
    expect(find.byType(PinKeypad), findsNothing);
    expect(find.text(stopLine), findsOneWidget);
    // The line is painted above the blurred page, so it can be read: no
    // render ancestor of it is the page's blur.
    expect(_blurred(t), isTrue);
    final blur = t.renderObject(
      find.descendant(of: _cover(), matching: find.byType(ImageFiltered)).first,
    );
    final above = <RenderObject>[];
    for (RenderObject? r = t.renderObject(find.text(stopLine)); r != null;) {
      above.add(r);
      r = r.parent;
    }
    expect(above, isNot(contains(blur)));
    // The button asks for nothing while the screen is captured either.
    await nativeSays(t, true);
    expect(find.byType(PinKeypad), findsNothing);
    await nativeSays(t, false);
    // The unlock button's busy spinner turns while the sheet is open: no
    // settle here.
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text(stopLine), findsNothing);
  });

  testWidgets('I-4: a capture that starts while the PIN sheet is open closes '
      'it (nothing entered is kept or checked), and it opens again, empty, '
      'when the capture ends', (t) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      locked: true,
      pinSet: true,
    );
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    for (final d in ['1', '2', '3']) {
      await t.tap(find.text(d));
      await t.pump();
    }
    expect(t.widget<PinKeypad>(find.byType(PinKeypad)).length, 3);
    await nativeSays(t, true);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(PinKeypad), findsNothing);
    expect(find.text(stopLine), findsOneWidget);
    expect(s.location, startsWith('${DatingPaths.unlock}?from='));
    await nativeSays(t, false);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(t.widget<PinKeypad>(find.byType(PinKeypad)).length, 0);
    expect(find.text(stopLine), findsNothing);
  });

  testWidgets('I-4: a capture that ends after the sheet was dismissed opens '
      'nothing (only a sheet the capture closed comes back)', (t) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      locked: true,
      pinSet: true,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(PinKeypad), findsNothing);
    await nativeSays(t, true);
    await nativeSays(t, false);
    await t.pumpAndSettle();
    expect(find.byType(PinKeypad), findsNothing);
  });

  testWidgets('M-10: a capture that starts while the decoy replaces the '
      'unlock page (its PIN sheet open) pops nothing: the decoy stays', (
    t,
  ) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      locked: true,
      pinSet: true,
    );
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    // The unlock page still waiting on Spec 1's confirmSafetyPin (as while
    // it reads the PIN store before pushing its sheet): the sheet taken
    // away without an answer, so the page is still asking.
    final sheet = ModalRoute.of(t.element(find.text('Enter your Safety PIN')))!;
    sheet.navigator!.removeRoute(sheet);
    await t.pump();
    // What quick exit's cover does (the wipe's blanking aside): the decoy
    // route replaces the stack and slides in over the unlock page, which
    // stays mounted under it until the decoy is in.
    s.router.goNamed('neutralScreen');
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byType(DatingUnlockScreen), findsOneWidget);
    await nativeSays(t, true);
    await t.pump(const Duration(milliseconds: 16));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('DECOY'), findsOneWidget);
    expect(s.location, RouteNames.neutralScreen);
  });

  testWidgets('M-11: the first frame of the first Dating page on an iPhone '
      'is already blurred (no answer needed)', (t) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) => Completer<bool>().future);
    await t.pumpWidget(
      const MaterialApp(home: DatingPageWatch(child: Text('secret'))),
    );
    final firstFrameBlurred = _blurred(t);
    await t.pump();
    final secondFrameBlurred = _blurred(t);
    expect(firstFrameBlurred, isTrue);
    expect(secondFrameBlurred, isTrue);
  });

  testWidgets('M-11: on an iPhone that answers "not captured", the first '
      'frame is blurred and the page clears once the answer lands', (t) async {
    DatingDiscretion.debugDevice = TargetPlatform.iOS;
    await t.pumpWidget(
      const MaterialApp(home: DatingPageWatch(child: Text('secret'))),
    );
    expect(_blurred(t), isTrue);
    await t.pumpAndSettle();
    expect(DatingDiscretion.captured.value, isFalse);
    expect(_blurred(t), isFalse);
  });

  group('M-8: the blur never changes while the tree is building or locked', () {
    // A Dating page opened or closed by its own part of the tree (as a
    // route is), next to an open Dating surface elsewhere (a sheet).
    final toggle = GlobalKey<_ToggleState>();
    Widget app() => MaterialApp(
      home: Column(
        children: [
          const DatingCaptureCover(child: Text('elsewhere')),
          _Toggle(key: toggle),
        ],
      ),
    );

    testWidgets('a Dating page opening on an iPhone', (t) async {
      DatingDiscretion.debugDevice = TargetPlatform.iOS;
      captured = true;
      await t.pumpWidget(app());
      toggle.currentState!.set(true);
      await t.pump();
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
      expect(DatingDiscretion.captured.value, isTrue);
      expect(_blurred(t, _cover().first), isTrue);
    });

    testWidgets('the last Dating page closing', (t) async {
      captured = true;
      await t.pumpWidget(app());
      toggle.currentState!.set(true);
      await t.pumpAndSettle();
      expect(DatingDiscretion.captured.value, isTrue);
      toggle.currentState!.set(false);
      await t.pump();
      expect(t.takeException(), isNull);
      await t.pump();
      expect(DatingDiscretion.captured.value, isFalse);
      expect(_blurred(t), isFalse);
    });
  });

  testWidgets('I-2: a report sheet over a Dating page blurs while the screen '
      'is captured, and keeps what was typed', (t) async {
    const typed = 'He threatened me SECRETWORDS';
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(FakeDatingToday()),
        ...datingReportOverrides(FakeDatingReport()),
      ],
    );
    unawaited(
      showDatingReportSheet(
        t.element(find.byType(DatingPageWatch)),
        account: 'ama',
        name: 'Kofi',
        target: const DatingReportMatch('m1'),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_report_details')),
      typed,
    );
    await t.pump();
    // The sheet's own cover (the page's is not above the sheet).
    final sheet = find.ancestor(
      of: find.byType(DatingReportSheet),
      matching: _cover(),
    );
    expect(sheet, findsOneWidget);
    expect(_blurred(t, sheet), isFalse);
    await nativeSays(t, true);
    expect(_blurred(t, sheet), isTrue);
    await nativeSays(t, false);
    expect(_blurred(t, sheet), isFalse);
    expect(find.text(typed), findsOneWidget);
  });

  group('I-3: a failure is reported on a phone, never swallowed', () {
    late List<FlutterErrorDetails> reported;
    late FlutterExceptionHandler? before;

    setUp(() {
      reported = [];
      before = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() {
        FlutterError.onError = before;
        DatingDiscretion.debugDevice = null;
      });
    });

    test('no channel off a phone (a test, a desktop): quiet', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      await DatingDiscretion.setSecure(true);
      expect(reported, isEmpty);
      expect(DatingDiscretion.secure, isTrue);
      expect(DatingDiscretion.captured.value, isFalse);
    });

    for (final device in [TargetPlatform.android, TargetPlatform.iOS]) {
      test('no channel on ${device.name}: reported, and nothing stays '
          'blurred', () async {
        DatingDiscretion.debugDevice = device;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
        await DatingDiscretion.setSecure(true);
        expect(reported, hasLength(1));
        expect(reported.single.exception, isA<MissingPluginException>());
        // M-9: the device log names Attune, never Dating.
        expect(reported.single.library, 'attune');
        // No stack: its frames name the files.
        expect(reported.single.stack, isNull);
        expect(
          reported.single.toString().toLowerCase(),
          isNot(contains('dating')),
        );
        expect(DatingDiscretion.captured.value, isFalse);
      });
    }

    test('the native side failing: reported, wherever it runs', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'broken');
          });
      await DatingDiscretion.setSecure(true);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<PlatformException>());
    });
  });

  group('the answer', () {
    tearDown(() => DatingDiscretion.debugDevice = null);

    test('M-2: an iPhone is covered from the moment it asks, until it '
        'answers that nothing is being captured', () async {
      DatingDiscretion.debugDevice = TargetPlatform.iOS;
      final asked = DatingDiscretion.setSecure(true);
      expect(DatingDiscretion.captured.value, isTrue);
      await asked;
      expect(DatingDiscretion.captured.value, isFalse);
    });

    test('M-2: Android never blurs (FLAG_SECURE blanks the capture)', () async {
      DatingDiscretion.debugDevice = TargetPlatform.android;
      captured = true;
      final asked = DatingDiscretion.setSecure(true);
      expect(DatingDiscretion.captured.value, isFalse);
      await asked;
    });

    test('M-5: leaving clears the blur at once, before any answer', () async {
      captured = true;
      await DatingDiscretion.setSecure(true);
      expect(DatingDiscretion.captured.value, isTrue);
      final left = DatingDiscretion.setSecure(false);
      expect(DatingDiscretion.captured.value, isFalse);
      await left;
    });

    test('M-5: a late answer for an earlier call changes nothing', () async {
      final answer = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.arguments == true) return answer.future;
            return false;
          });
      final opened = DatingDiscretion.setSecure(true);
      await DatingDiscretion.setSecure(false);
      answer.complete(true);
      await opened;
      expect(DatingDiscretion.captured.value, isFalse);
    });
  });

  test(
    'the native side: FLAG_SECURE on attune/safety (Android); the '
    'capture watch with sceneCaptureState and the isCaptured fallback (iOS)',
    () {
      final kt =
          File(
            'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
          ).readAsStringSync();
      expect(kt, contains('"setSecure" ->'));
      expect(
        kt,
        contains('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      expect(
        kt,
        contains('window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      // M-4: true adds the flag, anything else clears it; it answers false.
      expect(
        RegExp(
          r'"setSecure" -> \{\s*'
          r'if \(call\.arguments == true\) \{\s*'
          r'window\.addFlags\(WindowManager\.LayoutParams\.FLAG_SECURE\)\s*'
          r'\} else \{\s*'
          r'window\.clearFlags\(WindowManager\.LayoutParams\.FLAG_SECURE\)\s*'
          r'\}\s*result\.success\(false\)\s*\}',
        ).hasMatch(kt),
        isTrue,
        reason: 'the setSecure branch',
      );
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('name: "attune/safety"'));
      expect(swift, contains('case "setSecure":'));
      expect(swift, contains('sceneCaptureState == .active'));
      expect(swift, contains('UITraitSceneCaptureState.self'));
      expect(swift, contains('screen.isCaptured'));
      expect(swift, contains('UIScreen.capturedDidChangeNotification'));
      expect(swift, contains('invokeMethod("captureChanged"'));
      // M-4: setSecure starts or stops the watch and answers the state now.
      expect(
        RegExp(
          r'case "setSecure":\s*'
          r'let on = \(call\.arguments as\? Bool\) \?\? false\s*'
          r'self\?\.watchCapture\(on\)\s*'
          r'result\(on && \(self\?\.screenIsCaptured\(\) \?\? false\)\)',
        ).hasMatch(swift),
        isTrue,
        reason: 'the setSecure case',
      );
      String between(String from, String to) {
        final a = swift.indexOf(from);
        final b = swift.indexOf(to, a + 1);
        expect(a >= 0 && b > a, isTrue, reason: '$from … $to');
        return swift.substring(a, b);
      }

      final watch = between(
        'private func watchCapture(',
        'private func sendCapture(',
      );
      expect(watch, contains('guard on != captureWatching else { return }'));
      expect(watch, contains('captureWatching = on'));
      final off = between('    if !on {', '      return\n    }');
      expect(
        off,
        contains('NotificationCenter.default.removeObserver(observer)'),
      );
      expect(off, contains('scene.unregisterForTraitChanges(registration)'));
      expect(off, contains('captureRegistration = nil'));
      expect(
        between('private func sendCapture(', 'private func showSwitcherCover('),
        matches(
          RegExp(
            r'\{\s*guard captureWatching else \{ return \}\s*'
            r'safetyChannel\?\.invokeMethod\("captureChanged", '
            r'arguments: screenIsCaptured\(\)\)',
          ),
        ),
      );
    },
  );

  test('no gallery saves: no Dating file shows a network image, offers a '
      'long press, saves to the gallery or shares a file', () {
    final banned = RegExp(
      r'Image\.network|NetworkImage|cached_network_image|onLongPress|'
      r'image_gallery_saver|package:gal/|saveImage|shareXFiles|shareFiles|XFile\(',
    );
    for (final f in Directory(
      'lib/features/dating',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(banned.hasMatch(src), isFalse, reason: f.path);
      // The meeting kit shares its words through the share sheet, never
      // a photo or a file.
      if (src.contains('share_plus')) {
        expect(f.path, endsWith('chat/plan_meet_screen.dart'));
      }
    }
  });
}
