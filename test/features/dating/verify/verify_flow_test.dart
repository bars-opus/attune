// Spec 2 W4a (§3.3.2, §3.3.3, §3.15 D11, §7.4; D8; R-10): D11's flow. The
// intro and its consent; the video check and every outcome; the ID route;
// the human route (camera only, temp files deleted); where a resumed or a
// waiting session opens; nothing of one account shown to the next; large
// text, the dark theme, goldens, guidelines; quick exit leaves nothing.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart'
    show OnboardingHeld;
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';

class _Prep extends DatingImagePreparer {
  _Prep(this.dir);
  final Directory dir;
  final made = <File>[];
  @override
  Future<PreparedDatingImage> prepare(String localPath) async {
    final f = File('${dir.path}/p_${made.length}.jpg')
      ..writeAsBytesSync(List.filled(300, 1));
    made.add(f);
    return PreparedDatingImage(file: f, mimeType: 'image/jpeg', byteSize: 300);
  }
}

/// Task 4 (carry A): answers as they come off the wire, so a server's or
/// a vendor's text next to the code can be checked never to show.
class _Wire extends FakeDatingVerificationGateway {
  final wire = <String, Map<String, Object?>>{};

  @override
  Future<DatingVerifyAnswer> act(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final raw = wire[action];
    if (raw == null) return super.act(action, body);
    actions.add((action, body));
    onAct?.call(action);
    return DatingVerifyAnswer.fromJson(raw);
  }
}

/// Task 4 (carry C): records what each answer settles.
class _Keys extends DatingActionKeys {
  final log = <String>[];

  @override
  void settle(String action, {DatingLifecycleError? error, String? reason}) {
    log.add('$action:${reason ?? 'ok'}');
    super.settle(action, error: error, reason: reason);
  }
}

class _Run {
  _Run(this.gateway, this.capture, this.done, this.photos, this.dir);
  final FakeDatingVerificationGateway gateway;
  final FakeCaptureLauncher capture;
  final List<String> done;
  final List<String> photos;
  final Directory dir;
}

/// Fix round 1 (I-4): the ID passed (age only, §3.3.1); identity is
/// still the video face match or a person.
const _agePassed = DatingVerification(available: true, age: DatingCheck.pass);

const _docs = [
  DatingIdDocument(code: 'passport', nameKey: 'dating_id_passport'),
];

const _verified = DatingVerification(
  available: true,
  age: DatingCheck.pass,
  identity: DatingCheck.pass,
);

Future<_Run> _open(
  WidgetTester t, {
  DatingVerification? state,
  bool online = true,
  ThemeData? theme,
  double textScale = 1.0,
  DatingCaptureResult capture = const DatingCaptureResult(
    DatingCaptureKind.done,
  ),
  Future<String?> Function()? camera,
  DatingActionKeys Function()? newKeys,
  FakeDatingVerificationGateway? gateway,
  List<Override> more = const [],
}) async {
  await t.pumpWidget(const SizedBox());
  final dir = Directory.systemTemp.createTempSync('d11');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  gateway ??=
      state == null
          ? FakeDatingVerificationGateway()
          : FakeDatingVerificationGateway(state: state);
  final launcher = FakeCaptureLauncher(result: capture);
  final done = <String>[];
  final photos = <String>[];
  Widget screen() => DatingVerifyFlow(
    step: 'verify',
    onBack: () => done.add('<back>'),
    onDone: () => done.add('done'),
    onChangePhotos: () => photos.add('photos'),
    onHeld: () => done.add('<held>'),
    onFixBirthDate: () => done.add('<dob>'),
    newKeys: newKeys,
  );
  await pumpFlowScreen(
    t,
    () => theme == null ? screen() : Theme(data: theme, child: screen()),
    textScale: textScale,
    overrides: [
      ...datingShellOverrides(online: online, verification: gateway),
      datingCaptureLauncherProvider.overrideWithValue(launcher),
      datingImagePreparerProvider.overrideWithValue(_Prep(dir)),
      datingReviewCameraProvider.overrideWithValue(
        camera ??
            () async =>
                (File('${dir.path}/cam.jpg')
                  ..writeAsBytesSync(List.filled(10, 2))).path,
      ),
      ...more,
    ],
  );
  await t.pumpAndSettle();
  return _Run(gateway, launcher, done, photos, dir);
}

Future<void> _consentAndStart(WidgetTester t) async {
  await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
  await t.pump();
  await tapInReach(t, find.text('Start video check'));
  await t.pumpAndSettle();
}

/// Real file I/O (the human route) finishes outside the test clock.
Future<void> _settleIo(WidgetTester t, bool Function() until) async {
  final limit = DateTime.now().add(const Duration(seconds: 30));
  while (!until()) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
    if (DateTime.now().isAfter(limit)) fail('_settleIo: never settled');
  }
  await t.pumpAndSettle();
}

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  group('the intro', () {
    testWidgets('§3.3.2 copy; Start and the other way wait for the consent', (
      t,
    ) async {
      final r = await _open(t);
      for (final text in [
        "Verify it's you",
        'Step 10 of 12',
        "A short video selfie checks that you're a real person, that your "
            "photos are you, and that you're over 18. The video is deleted "
            'at once. We keep only whether it passed.',
        'Face a window or a lamp, not away from it.',
        'Take off sunglasses. Glasses are fine without glare.',
        'Hold the phone at eye level.',
        "This check flashes colours on your screen. If flashing lights "
            "affect you, choose 'Check another way'.",
        'I agree that Attune and its verification partner can use my face '
            'to check my age and match my photos. Nothing is kept after the '
            'check.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tapInReach(t, find.text('Start video check'));
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(r.gateway.actions, isEmpty, reason: 'nothing without consent');
      expect(r.gateway.consents, isEmpty);
    });

    testWidgets('offline: both wait, and the step says why', (t) async {
      final r = await _open(t, online: false);
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.actions, isEmpty);
      expect(find.text('Connect to save this answer.'), findsOneWidget);
    });

    testWidgets('unavailable (the flag off, or no read): a calm line and '
        'Try again', (t) async {
      final r = await _open(t, state: DatingVerification.unavailable);
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsOneWidget,
      );
      r.gateway.state = const DatingVerification(available: true);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsNothing,
      );
    });
  });

  group('the video check', () {
    testWidgets('both pass: the consent once, start, the capture, complete; '
        '"You\'re verified." and Continue moves on', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) {
        if (a == 'complete') r.gateway.state = _verified;
      };
      await _consentAndStart(t);
      expect(r.gateway.consents.length, 1);
      expect(r.gateway.actionNames, ['start', 'complete']);
      expect(r.gateway.actions.last.$2, {'session_id': datingTestSession});
      expect(r.capture.calls, ['liveness:fake:ref-1']);
      expect(find.text("You're verified."), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      expect(r.done, ['done']);
    });

    testWidgets('a scenario picked on the practice capture re-arms the '
        'session first', (t) async {
      final r = await _open(
        t,
        capture: const DatingCaptureResult(
          DatingCaptureKind.done,
          scenario: 'under_25',
        ),
      );
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.needsId),
      ];
      await _consentAndStart(t);
      expect(r.gateway.actionNames, ['start', 'start', 'complete']);
      expect(r.gateway.actions[1].$2, {'scenario': 'under_25'});
      expect(
        find.text(
          "We couldn't confirm your age from the video. That's common for "
          "people under 25. Let's check with your ID instead.",
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      expect(find.text('Which ID do you have?'), findsWidgets);
      expect(find.text('Ghana Card'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
    });

    testWidgets('failed once: try again with the tips; twice: another way', (
      t,
    ) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.retry),
        datingOutcome(DatingVerifyOutcome.anotherWay),
      ];
      await _consentAndStart(t);
      expect(find.text("That didn't work. Let's try again."), findsOneWidget);
      expect(find.text('Hold the phone at eye level.'), findsOneWidget);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(
        find.text('Still not working? You can check another way.'),
        findsOneWidget,
      );
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(find.text('Ask a person to review it'), findsOneWidget);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
    });

    testWidgets('a photo that doesn\'t match: named, and Change that photo '
        'opens D9', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
      ];
      await _consentAndStart(t);
      expect(
        find.text(
          "Photo 2 doesn't look like the video. Change that photo, or ask a "
          'person to review it.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Change that photo'));
      expect(r.photos, ['photos']);
    });

    testWidgets('far below 18: support copy only (Spec 1\'s hold)', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.farBelow),
      ];
      await _consentAndStart(t);
      expect(
        find.text(
          'We need to check a few things on your account. Contact support if '
          'you have questions.',
        ),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Start video check'), findsNothing);
    });

    testWidgets('R-13: a failed or an uncertain estimate goes to the ID '
        'check, never an ending', (t) async {
      for (final (outcome, text) in [
        (
          DatingVerifyOutcome.needsId,
          "We couldn't confirm your age from the video. That's common for "
              "people under 25. Let's check with your ID instead.",
        ),
        (
          DatingVerifyOutcome.ageUncertain,
          "The video couldn't confirm your age this time. Let's check with "
              'your ID instead.',
        ),
      ]) {
        final r = await _open(t);
        r.gateway.answers['start'] = [datingStarted()];
        r.gateway.answers['complete'] = [datingOutcome(outcome)];
        await _consentAndStart(t);
        expect(find.text(text), findsOneWidget, reason: '$outcome');
        expect(find.text('Contact support'), findsNothing, reason: '$outcome');
        await tapInReach(t, find.text('Check with my ID'));
        await t.pumpAndSettle();
        expect(find.text('Ghana Card'), findsOneWidget, reason: '$outcome');
      }
    });

    testWidgets('the vendor can\'t answer: "That didn\'t go through. Try '
        'again." and nothing moves; a server\'s text never shows', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [
        datingRefused(DatingVerifyRefusal.vendorUnavailable),
      ];
      await _consentAndStart(t);
      expect(find.text("That didn't go through. Try again."), findsOneWidget);
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      r.gateway.answers['start'] = [DatingVerifyAnswer.failed];
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('R-10: no capture for this vendor: unavailable; cancelled: '
        'nothing completes', (t) async {
      final r = await _open(t, capture: DatingCaptureResult.unavailable);
      r.gateway.answers['start'] = [datingStarted(vendor: 'aws_rekognition')];
      await _consentAndStart(t);
      expect(
        find.text('Checking isn\'t available right now. Try again later.'),
        findsOneWidget,
      );
      r.capture.result = DatingCaptureResult.cancelled;
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.actionNames, ['start', 'start']);
    });

    testWidgets('the consent: a failed record keeps its key, the retry '
        'sends the same one; a reverify answer is calm', (t) async {
      final r = await _open(t);
      r.gateway.consentAnswer = const DatingWrite(ok: false, reason: 'failed');
      await _consentAndStart(t);
      expect(r.gateway.actions, isEmpty);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.consents.toSet().length, 1, reason: 'same key');
      r.gateway.consentAnswer = const DatingWrite(
        ok: false,
        reason: 'reverify_device',
      );
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(
        find.text("Confirm it's you on this phone to see Dating."),
        findsOneWidget,
      );
    });
  });

  group('where the flow opens', () {
    testWidgets('a session left open: "Let\'s pick up where you left off."', (
      t,
    ) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'started',
            open: true,
          ),
        ),
      );
      expect(find.text("Let's pick up where you left off."), findsOneWidget);
    });

    testWidgets('a person checking; an ID being checked; a date of birth '
        'that differs; an age not confirmed', (t) async {
      final cases = {
        const DatingVerifySession(
              id: datingTestSession,
              step: 'human',
              state: 'awaiting_review',
              open: true,
            ):
            "A person is checking. This usually takes less than a day. We'll "
            'show the result here.',
        const DatingVerifySession(
              id: datingTestSession,
              step: 'id',
              state: 'awaiting_review',
              outcome: DatingVerifyOutcome.idPending,
              open: true,
            ):
            'Thanks. Most checks finish in a few minutes. Some need a person, '
            'which takes up to 24 hours.',
        const DatingVerifySession(
              id: datingTestSession,
              step: 'id',
              state: 'awaiting_review',
              outcome: DatingVerifyOutcome.dobMismatch,
              open: true,
            ):
            "The date of birth on your ID doesn't match the one you gave us. "
            'A person will check this within 24 hours.',
      };
      for (final MapEntry(key: session, value: text) in cases.entries) {
        await _open(
          t,
          state: DatingVerification(available: true, session: session),
        );
        expect(find.text(text), findsOneWidget, reason: text);
        expect(find.text('Start video check'), findsNothing);
      }
      await _open(
        t,
        state: const DatingVerification(available: true, age: DatingCheck.fail),
      );
      expect(
        find.text(
          "We couldn't confirm your age, so Dating isn't available on this "
          'account. If you think this is wrong, contact support.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('R-13: a video check that ended on the estimate reopens on '
        'the ID offer', (t) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'passed',
            outcome: DatingVerifyOutcome.ageUncertain,
          ),
        ),
      );
      expect(
        find.text(
          "The video couldn't confirm your age this time. Let's check with "
          'your ID instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(find.text('Start video check'), findsNothing);
    });

    testWidgets('a pending ID check is read again on Check again', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.idPending,
            open: true,
          ),
        ),
      );
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) => r.gateway.state = _verified;
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      // (A record holding a map compares by identity: one field at a time.)
      expect(r.gateway.actions.single.$1, 'complete_id');
      expect(r.gateway.actions.single.$2, {'session_id': datingTestSession});
      expect(find.text("You're verified."), findsOneWidget);
    });
  });

  group('the ID route', () {
    testWidgets('pick a document, the capture, then the outcome', (t) async {
      final r = await _open(t);
      r.gateway.answers['start_id'] = [datingStarted()];
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.dobMismatch),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.first.$1, 'start_id');
      expect(r.gateway.actions.first.$2, {'document': 'passport'});
      expect(r.capture.calls, ['id:fake:ref-1']);
      expect(
        find.text(
          "The date of birth on your ID doesn't match the one you gave us. A "
          'person will check this within 24 hours.',
        ),
        findsOneWidget,
      );
      // R-12: once the date is corrected, Check again compares it again.
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      // Fix round 1 (I-4): the ID confirms the age only; identity is still
      // to do, so the flow says so and offers the video or a person.
      r.gateway.onAct = (a) {
        if (a == 'complete_id') r.gateway.state = _agePassed;
      };
      r.gateway.state = const DatingVerification(available: true);
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.last.$1, 'complete_id');
      expect(r.gateway.actions.last.$2, {
        'session_id': datingTestSession,
      }, reason: 'the ID check this screen started');
      expect(find.text("You're verified."), findsNothing);
      expect(
        find.text(
          "Your age is confirmed. Now we check it's you: a short video, or a "
          'person can look at two quick photos.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.text('Ask a person to review it'), findsOneWidget);
    });
  });

  group('R-13: the only endings', () {
    testWidgets('a failed ID check is final: support copy, nothing to try '
        'again', (t) async {
      final r = await _open(t);
      r.gateway.answers['start_id'] = [datingStarted()];
      r.gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.ageNotConfirmed),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "We couldn't confirm your age, so Dating isn't available on this "
          'account. If you think this is wrong, contact support.',
        ),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
      for (final none in [
        'Try again',
        'Start video check',
        'Check with my ID',
        'Check another way',
      ]) {
        expect(find.text(none), findsNothing, reason: none);
      }
    });
  });

  group('the human route (§3.3.3)', () {
    testWidgets('two gestures, two camera photos (temp files deleted), sent '
        'for review', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['$datingTestSession/1.jpg', '$datingTestSession/2.jpg'],
        ),
      ];
      r.gateway.answers['submit_human'] = [
        datingOutcome(DatingVerifyOutcome.humanPending),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(find.text('Take two quick photos'), findsWidgets);
      expect(find.text('1. Touch your left ear'), findsOneWidget);
      expect(find.text('2. Give a thumbs up'), findsOneWidget);
      await tapInReach(t, find.text('Send for review'));
      await t.pump();
      expect(r.gateway.actionNames, [
        'human_start',
      ], reason: 'two photos first');
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      await tapInReach(t, find.text('Take photo 2'));
      await _settleIo(t, () => r.gateway.uploads.length == 2);
      expect(r.gateway.uploads, [
        '$datingTestSession/1.jpg',
        '$datingTestSession/2.jpg',
      ]);
      expect(r.dir.listSync(), isEmpty, reason: 'every temp file deleted');
      await tapInReach(t, find.text('Send for review'));
      await t.pumpAndSettle();
      expect(r.gateway.actions.last.$1, 'submit_human');
      expect(r.gateway.actions.last.$2, {'session_id': datingTestSession});
      expect(
        find.text(
          "A person is checking. This usually takes less than a day. We'll "
          'show the result here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a photo that did not land says so; a cancelled camera '
        'says nothing', (t) async {
      String? next;
      final r = await _open(t, camera: () async => next);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Take photo 1'));
      await t.pumpAndSettle();
      expect(_shows("That photo didn't go through. Take it again."), isFalse);
      next = (File('${r.dir.path}/cam.jpg')..writeAsBytesSync([1, 2, 3])).path;
      r.gateway.uploadOk = false;
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      expect(
        find.text("That photo didn't go through. Take it again."),
        findsOneWidget,
      );
      expect(find.text('Take photo 1'), findsOneWidget);
    });
  });

  testWidgets('D8: another account sees nothing of the last one while its '
      'read is held', (t) async {
    final r = await _open(t);
    r.gateway.answers['start'] = [datingStarted()];
    r.gateway.answers['complete'] = [
      datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
    ];
    await _consentAndStart(t);
    expect(find.textContaining('Photo 2'), findsOneWidget);
    r.gateway.hold = Completer<DatingVerification>();
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    c.read(datingTestAccount.notifier).state = 'kofi';
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 40));
      expect(find.textContaining('Photo 2'), findsNothing);
      expect(find.text('Change that photo'), findsNothing);
    }
    r.gateway.hold!.complete(const DatingVerification(available: true));
    await t.pumpAndSettle();
    expect(find.text('Start video check'), findsOneWidget);
    final consent = t.widget<CheckboxListTile>(
      find.byKey(const ValueKey('dating_verify_consent')),
    );
    expect(consent.value, isFalse, reason: 'the consent is per account');
  });

  testWidgets('large text at 2.0: every stage in reach, nothing clipped', (
    t,
  ) async {
    final r = await _open(t, textScale: 2.0);
    r.gateway.answers['start'] = [datingStarted()];
    r.gateway.answers['complete'] = [
      datingOutcome(DatingVerifyOutcome.anotherWay),
    ];
    await _consentAndStart(t);
    expect(t.takeException(), isNull);
    await tapInReach(t, find.text('Ask a person to review it'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // Fix round 1 (M-11): every outcome stage, its primary in reach.
    DatingVerification at(
      String step,
      DatingVerifyOutcome o, {
      bool open = true,
    }) => DatingVerification(
      available: true,
      session: DatingVerifySession(
        id: datingTestSession,
        step: step,
        state: open ? 'awaiting_review' : 'failed',
        outcome: o,
        open: open,
      ),
    );
    for (final (state, primary) in [
      (at('id', DatingVerifyOutcome.dobMismatch), 'Check again'),
      (at('id', DatingVerifyOutcome.idPending), 'Check again'),
      (
        at('liveness', DatingVerifyOutcome.photoMismatch, open: false),
        'Change that photo',
      ),
      (
        at('liveness', DatingVerifyOutcome.ageUncertain, open: false),
        'Check with my ID',
      ),
      (
        const DatingVerification(
          available: true,
          age: DatingCheck.fail,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.farBelow,
          ),
        ),
        'Contact support',
      ),
      (
        const DatingVerification(available: true, age: DatingCheck.fail),
        'Contact support',
      ),
      (_agePassed, 'Start video check'),
    ]) {
      await _open(t, textScale: 2.0, state: state);
      expect(t.takeException(), isNull, reason: primary);
      await bringIntoReach(t, find.text(primary));
      expect(wouldHit(t, find.text(primary)), isTrue, reason: primary);
    }
    // The vendor hasn't finished the video.
    final p = await _open(t, textScale: 2.0);
    p.gateway.answers['start'] = [datingStarted()];
    p.gateway.answers['complete'] = [
      datingOutcome(DatingVerifyOutcome.pending),
    ];
    await _consentAndStart(t);
    expect(t.takeException(), isNull);
    await bringIntoReach(t, find.text('Check again'));
    expect(wouldHit(t, find.text('Check again')), isTrue);
  });

  // Task 4 deviation (carry A): a failed answer is calm now; the one error
  // line in D11 is the final ending (R-13), so that is where the theme's
  // error red is checked, and a failed answer is checked to be calm.
  testWidgets('the dark theme: tokens only, contrast holds, the theme\'s '
      'error red', (t) async {
    final semantics = t.ensureSemantics();
    final dark = AppTheme.darkTheme;
    for (final (theme, red) in [
      (dark, dark.colorScheme.error),
      (AppTheme.lightTheme, const Color(0xFFC62828)),
    ]) {
      final r = await _open(t, theme: theme);
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        theme.colorScheme.surface,
      );
      await expectFlowGuidelines(t);
      r.gateway.answers['start'] = [DatingVerifyAnswer.failed];
      await _consentAndStart(t);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      await expectFlowGuidelines(t);
      await _open(
        t,
        theme: theme,
        state: const DatingVerification(available: true, age: DatingCheck.fail),
      );
      final icon = find.descendant(
        of: find.byType(FlowErrorLine),
        matching: find.byType(Icon),
      );
      expect(t.widget<Icon>(icon).color, red);
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  testWidgets('reduce motion: the verified check appears at once', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await _open(t, state: _verified);
    final tween = t.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('dating_verified_check')),
    );
    expect(tween.duration, Duration.zero);
    t.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await _open(t, state: _verified);
    expect(
      t
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('dating_verified_check')),
          )
          .duration,
      kDatingVerifiedFade,
    );
  });

  for (final (name, state) in [
    (
      'd11_waiting',
      const DatingVerification(
        available: true,
        session: DatingVerifySession(
          id: datingTestSession,
          step: 'human',
          state: 'awaiting_review',
          open: true,
        ),
      ),
    ),
    ('d11_verified', _verified),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => DatingVerifyFlow(
          step: 'verify',
          onBack: () {},
          onDone: () {},
          onChangePhotos: () {},
        ),
        overrides: datingShellOverrides(
          verification: FakeDatingVerificationGateway(state: state),
        ),
        before: (t) => t.pumpAndSettle(),
      );
    });
  }

  group('quick exit', () {
    setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    testWidgets('from D11 mid-check: the decoy, and nothing of the check '
        'left', (t) async {
      final gateway = FakeDatingVerificationGateway();
      gateway.answers['start'] = [datingStarted()];
      gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
      ];
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('verify'),
        locked: true,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
          datingCaptureLauncherProvider.overrideWithValue(
            FakeCaptureLauncher(),
          ),
        ],
      );
      await _consentAndStart(t);
      expect(find.textContaining('Photo 2'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.byType(DatingVerifyFlow, skipOffstage: false), findsNothing);
      expect(find.textContaining('Photo 2', skipOffstage: false), findsNothing);
      expect(s.lock.on, isTrue);
    });
  });

  // Task 4: what the brief couldn't know (the coordinator's A-H, against
  // Tasks 1-3 as their fix rounds left them).
  group('Task 4 carries', () {
    AppLocalizations l10n(WidgetTester t) =>
        AppLocalizations.of(t.element(find.byType(DatingVerifyFlow)))!;

    testWidgets('A: every refusal is its own calm line, never error red, '
        'never the server\'s text', (t) async {
      for (final r in DatingVerifyRefusal.values) {
        final gateway =
            _Wire()
              ..wire['start'] = {
                'ok': false,
                'reason': r == DatingVerifyRefusal.failed ? 'teapot' : r.wire,
                'message': 'SERVER SAYS NO',
              };
        await _open(t, gateway: gateway);
        final loc = l10n(t);
        final text = datingVerifyRefusalText(loc, r);
        // With Task 3's parity test (every server code has its own name),
        // nothing the server sends reaches the generic line.
        expect(
          text == loc.dating_errorGeneric,
          r == DatingVerifyRefusal.failed,
          reason: '$r',
        );
        await _consentAndStart(t);
        expect(find.textContaining('SERVER'), findsNothing, reason: '$r');
        final reread =
            DatingVerifyAnswer(ok: false, refusal: r).readStatusAgain ||
            r == DatingVerifyRefusal.alreadyVerified ||
            r == DatingVerifyRefusal.awaitingReview ||
            r == DatingVerifyRefusal.ageNotConfirmed;
        expect(gateway.reads, reread ? 2 : 1, reason: '$r');
        if (r == DatingVerifyRefusal.ageNotConfirmed) {
          // R-13: the one ending, with support copy and nothing to retry.
          expect(find.text(loc.dating_verifyAgeNotConfirmed), findsOneWidget);
          expect(find.text('Contact support'), findsOneWidget);
          expect(find.text('Start video check'), findsNothing);
          continue;
        }
        expect(find.text(text), findsOneWidget, reason: '$r');
        expect(find.byType(FlowErrorLine), findsNothing, reason: '$r calm');
        expect(find.text('Start video check'), findsOneWidget, reason: '$r');
      }
    });

    testWidgets('A: every outcome is its own copy; only the final ending is '
        'an error line, with support copy', (t) async {
      for (final o in DatingVerifyOutcome.values) {
        final gateway =
            _Wire()
              ..answers['start'] = [datingStarted()]
              ..wire['complete'] = {
                'ok': true,
                'outcome': o == DatingVerifyOutcome.unknown ? 'teapot' : o.wire,
                'position': 2,
                'message': 'VENDOR SAYS',
              };
        if (o == DatingVerifyOutcome.verified) {
          gateway.onAct = (a) {
            if (a == 'complete') gateway.state = _verified;
          };
        }
        await _open(t, gateway: gateway);
        final loc = l10n(t);
        await _consentAndStart(t);
        expect(find.textContaining('VENDOR'), findsNothing, reason: '$o');
        final expected = switch (o) {
          DatingVerifyOutcome.verified => loc.dating_verifyVerified,
          DatingVerifyOutcome.retry ||
          DatingVerifyOutcome.identityFailed => loc.dating_verifyRetry,
          DatingVerifyOutcome.anotherWay => loc.dating_verifyStillNotWorking,
          DatingVerifyOutcome.needsId => loc.dating_verifyUnder25,
          DatingVerifyOutcome.ageUncertain => loc.dating_verifyUncertain,
          DatingVerifyOutcome.photoMismatch => loc.dating_verifyPhotoMismatch(
            2,
          ),
          DatingVerifyOutcome.farBelow => loc.dating_verifyFarBelow,
          DatingVerifyOutcome.idPending => loc.dating_verifyIdThanks,
          DatingVerifyOutcome.dobMismatch => loc.dating_verifyDobMismatch,
          DatingVerifyOutcome.ageNotConfirmed =>
            loc.dating_verifyAgeNotConfirmed,
          DatingVerifyOutcome.humanPending => loc.dating_verifyWaiting,
          DatingVerifyOutcome.askForId => loc.dating_verifyAskedForId,
          DatingVerifyOutcome.pending => loc.dating_verifyStillChecking,
          // An outcome this build doesn't know: the status decides.
          DatingVerifyOutcome.unknown => loc.dating_verifyStart,
        };
        expect(find.text(expected), findsOneWidget, reason: '$o');
        expect(
          find.byType(FlowErrorLine),
          o == DatingVerifyOutcome.ageNotConfirmed
              ? findsOneWidget
              : findsNothing,
          reason: '$o',
        );
        expect(
          find.text('Contact support'),
          o == DatingVerifyOutcome.ageNotConfirmed ||
                  o == DatingVerifyOutcome.farBelow
              ? findsOneWidget
              : findsNothing,
          reason: '$o',
        );
        if (o != DatingVerifyOutcome.verified) {
          expect(find.text("You're verified."), findsNothing, reason: '$o');
        }
      }
    });

    testWidgets('A: the human route\'s photo that didn\'t land is calm', (
      t,
    ) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      r.gateway.uploadOk = false;
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      expect(
        find.text("That photo didn't go through. Take it again."),
        findsOneWidget,
      );
      expect(find.byType(FlowErrorLine), findsNothing);
    });

    testWidgets('B: an answer that may not have arrived reads the status '
        'first: a slow far-below result shows Spec 1\'s hold copy, never '
        '"failed"', (t) async {
      for (final lost in [
        datingRefused(DatingVerifyRefusal.busy), // also a client timeout
        DatingVerifyAnswer.failed,
        datingRefused(DatingVerifyRefusal.sessionUnavailable),
      ]) {
        final r = await _open(t);
        r.gateway.answers['start'] = [datingStarted()];
        r.gateway.answers['complete'] = [lost];
        r.gateway.onAct = (a) {
          if (a != 'complete') return;
          r.gateway.state = const DatingVerification(
            available: true,
            age: DatingCheck.fail,
            session: DatingVerifySession(
              id: datingTestSession,
              step: 'liveness',
              state: 'failed',
              outcome: DatingVerifyOutcome.farBelow,
            ),
          );
        };
        await _consentAndStart(t);
        final loc = l10n(t);
        expect(find.text(loc.dating_verifyFarBelow), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
        for (final none in [
          loc.dating_busy,
          loc.dating_errorGeneric,
          loc.dating_verifyNetwork,
          loc.dating_verifyAgeNotConfirmed,
          'Start video check',
        ]) {
          expect(find.text(none), findsNothing, reason: '$lost: $none');
        }
        expect(r.gateway.reads, 2);
      }
    });

    testWidgets('B: a slow photo mismatch, a slow review submit and a slow '
        'ID pass each show their real outcome', (t) async {
      // The video check: closed with photo 3 named while the app waited.
      var r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [DatingVerifyAnswer.failed];
      r.gateway.onAct = (a) {
        if (a != 'complete') return;
        r.gateway.state = const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.photoMismatch,
            position: 3,
          ),
        );
      };
      await _consentAndStart(t);
      expect(find.textContaining('Photo 3'), findsOneWidget);
      // The human route: submitted after all.
      r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      r.gateway.answers['submit_human'] = [
        datingRefused(DatingVerifyRefusal.busy),
      ];
      r.gateway.onAct = (a) {
        if (a != 'submit_human') return;
        r.gateway.state = const DatingVerification(
          available: true,
          identity: DatingCheck.review,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'human',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.humanPending,
            open: true,
          ),
        );
      };
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      await tapInReach(t, find.text('Take photo 2'));
      await _settleIo(t, () => r.gateway.uploads.length == 2);
      await tapInReach(t, find.text('Send for review'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "A person is checking. This usually takes less than a day. We'll "
          'show the result here.',
        ),
        findsOneWidget,
      );
      // Check again on an ID check that passed while the call was lost.
      r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.idPending,
            open: true,
          ),
        ),
      );
      r.gateway.answers['complete_id'] = [
        datingRefused(DatingVerifyRefusal.sessionUnavailable),
      ];
      r.gateway.onAct = (a) => r.gateway.state = _verified;
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(find.text("You're verified."), findsOneWidget);
    });

    testWidgets('B: nothing moved: the calm line, and an earlier session\'s '
        'outcome is never taken for this one', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          idDocuments: [
            DatingIdDocument(code: 'passport', nameKey: 'dating_id_passport'),
          ],
        ),
      );
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [datingRefused(DatingVerifyRefusal.busy)];
      // The status shows last week's closed session (another id).
      r.gateway.onAct = (a) {
        if (a != 'complete') return;
        r.gateway.state = const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: 'an-older-session',
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.photoMismatch,
            position: 1,
          ),
        );
      };
      await _consentAndStart(t);
      final loc = l10n(t);
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(find.textContaining('Photo 1'), findsNothing);
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing);
      expect(r.gateway.reads, 2);
    });

    testWidgets('C: the consent and every action\'s answer settle their key; '
        'a final consent refusal gives the next a new key', (t) async {
      final keys = _Keys();
      final r = await _open(t, newKeys: () => keys);
      r.gateway.answers['start'] = [
        datingRefused(DatingVerifyRefusal.busy),
        datingStarted(),
      ];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 1),
      ];
      await _consentAndStart(t);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(keys.log, ['consent:ok', 'start:busy', 'start:ok', 'complete:ok']);
      final again = await _open(t);
      again.gateway.consentAnswer = const DatingWrite(
        ok: false,
        reason: 'reverify_device',
      );
      await _consentAndStart(t);
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(again.gateway.consents.length, 2);
      expect(again.gateway.consents.toSet().length, 2, reason: 'settled');
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
    });

    testWidgets('D (R-35): a person\'s failed review offers the video again', (
      t,
    ) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          identity: DatingCheck.fail,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'human',
            state: 'failed',
            outcome: DatingVerifyOutcome.identityFailed,
          ),
        ),
      );
      expect(find.text("That didn't work. Let's try again."), findsOneWidget);
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.text('Contact support'), findsNothing);
    });

    testWidgets('D: a review that asked for an ID opens the ID route', (
      t,
    ) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          idDocuments: [
            DatingIdDocument(code: 'passport', nameKey: 'dating_id_passport'),
          ],
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'human',
            state: 'failed',
            outcome: DatingVerifyOutcome.askForId,
          ),
        ),
      );
      expect(
        find.text('A person asked to see your ID. Check with your ID next.'),
        findsOneWidget,
      );
      expect(find.text('Passport'), findsOneWidget);
    });

    testWidgets('E (R-8): far below 18 read from the status is Spec 1\'s '
        'hold copy, and leaving goes to the hold screen', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          age: DatingCheck.fail,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.farBelow,
          ),
        ),
      );
      expect(
        find.text(
          'We need to check a few things on your account. Contact support if '
          'you have questions.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.byType(BackButtonIcon));
      expect(r.done, ['<held>']);
    });

    testWidgets('E (R-8): by default, the gate\'s one H1 path: D11 leaves '
        'the stack, nothing is stacked on the hold', (t) async {
      final gateway = FakeDatingVerificationGateway();
      gateway.answers['start'] = [datingStarted()];
      gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.farBelow),
      ];
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('verify'),
        extraRoutes: [
          GoRoute(
            path: RouteNames.onboarding,
            builder:
                (_, st) =>
                    Scaffold(body: Text('H1 ${st.extra is OnboardingHeld}')),
          ),
        ],
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
          datingCaptureLauncherProvider.overrideWithValue(
            FakeCaptureLauncher(),
          ),
        ],
      );
      await _consentAndStart(t);
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('H1 true'), findsOneWidget);
      expect(s.location, RouteNames.onboarding);
      expect(find.byType(DatingVerifyFlow, skipOffstage: false), findsNothing);
    });

    testWidgets('E (R-12): a date of birth that differs: Spec 1\'s '
        'correction, then Check again on the same session; no date is ever '
        'sent or shown', (t) async {
      final gateway = FakeDatingVerificationGateway(
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.dobMismatch,
            open: true,
          ),
        ),
      );
      gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      // Fix round 1 (I-4): the ID confirms the age only.
      gateway.onAct = (a) => gateway.state = _agePassed;
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('verify'),
        extraRoutes: [
          GoRoute(
            path: RouteNames.birthDateSettings,
            builder: (_, __) => const Scaffold(body: Text('DOB SETTINGS')),
          ),
        ],
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      await tapInReach(t, find.text('Change my date of birth'));
      await t.pumpAndSettle();
      expect(find.text('DOB SETTINGS'), findsOneWidget);
      s.router.pop();
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(gateway.actions.single.$1, 'complete_id');
      expect(gateway.actions.single.$2, {'session_id': datingTestSession});
      expect(find.text("You're verified."), findsNothing);
      expect(find.textContaining('Your age is confirmed.'), findsOneWidget);
    });

    testWidgets('F: a review or ID check waiting for a person reads as '
        'waiting on the flow too (never the intro)', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            outcome: DatingVerifyOutcome.idPending,
            open: true,
          ),
        ),
      );
      expect(find.text('Start video check'), findsNothing);
      expect(r.gateway.actions, isEmpty);
    });

    testWidgets('G (carry 4): the manual says what W4a built', (t) async {
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final passage = DatingModeDocs()
          .getSections(context)
          .expand((s) => s.contents)
          .singleWhere((c) => c.id == 'dating_setup_verify');
      expect(
        passage.content,
        'Before your first introduction, a short video selfie checks that '
        "you're a real person and that your photos are you, and it can "
        "confirm you're over 18. The video is deleted straight away, and "
        'Attune keeps only whether the check passed. The video check '
        'flashes colours on your screen; if flashing lights affect you, you '
        'can check another way. If the video can\'t '
        'confirm your age, you check with your ID instead. If you check '
        'with your ID first, a short video or two quick photos then check '
        'that your photos are you. If the date of '
        "birth on your ID doesn't match the one you gave us, you can correct "
        'your date of birth and check again. If the ID check fails, Dating '
        "isn't available on your account; if you think that's wrong, "
        'contact support. If the video check doesn\'t '
        'work for you, a person can look at two quick photos to check it\'s '
        "you. That checks it's you, not your age.",
      );
    });

    testWidgets('H: a double tap starts one session', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.needsId),
      ];
      r.gateway.actHold = Completer<void>();
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Start video check'));
      await t.tap(find.text('Start video check'), warnIfMissed: false);
      await t.pump();
      await t.tap(find.text('Start video check'), warnIfMissed: false);
      await t.pump();
      r.gateway.actHold!.complete();
      r.gateway.actHold = null;
      await t.pumpAndSettle();
      expect(r.gateway.consents.length, 1);
      expect(r.gateway.actionNames, ['start', 'complete']);
      expect(r.capture.calls.length, 1);
    });

    testWidgets('H (D8): an answer that lands after the account changed '
        'shows nothing and goes no further', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.photoMismatch, position: 2),
      ];
      r.gateway.actHold = Completer<void>();
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Start video check'));
      await t.pump();
      final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
      c.read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      r.gateway.actHold!.complete();
      r.gateway.actHold = null;
      await t.pumpAndSettle();
      expect(r.gateway.actionNames, ['start'], reason: 'no complete');
      expect(r.capture.calls, isEmpty, reason: 'no capture for the last one');
      expect(find.textContaining('Photo 2'), findsNothing);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('dating_verify_consent')),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('H (D8): the human route\'s progress is not the next '
        'account\'s', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      expect(find.text('Done'), findsOneWidget);
      final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
      c.read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
      expect(find.text('Take two quick photos'), findsNothing);
      expect(find.text('Start video check'), findsOneWidget);
    });

    testWidgets('H: no text field anywhere in D11 (no keyboard learning to '
        'turn off)', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      expect(find.byType(EditableText), findsNothing);
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      // Fix round 1 (M-3): Back retraces the flow's own stages first.
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(r.done, isEmpty);
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
      expect(r.done, isEmpty);
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(r.done, ['<back>']);
    });

    group('quick exit (H)', () {
      // Registered once per isolate: the brief's group above already has
      // when the whole file runs.
      setUpAll(() {
        try {
          registerDatingDeviceWipes(DeviceWipeRegistry.instance);
        } on AssertionError catch (_) {}
      });
      setUp(() {
        QuickExitService.clearStories = () async {};
        addTearDown(
          () => QuickExitService.clearStories = clearStoryDeviceCaches,
        );
      });

      testWidgets('with the capture open: the decoy, the capture gone, '
          'nothing completes; the capture lets large text through', (t) async {
        final gateway = FakeDatingVerificationGateway();
        gateway.answers['start'] = [datingStarted()];
        gateway.answers['complete'] = [
          datingOutcome(DatingVerifyOutcome.verified),
        ];
        await pumpDatingShell(
          t,
          initial: DatingPaths.step('verify'),
          locked: true,
          wrap: (router, child) => QuickExitZone(router: router, child: child),
          overrides: [
            datingVerificationGatewayProvider.overrideWithValue(gateway),
          ],
        );
        await tapInReach(
          t,
          find.byKey(const ValueKey('dating_verify_consent')),
        );
        await t.pump();
        await tapInReach(t, find.text('Start video check'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        expect(find.byType(DatingPracticeCaptureScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DatingPracticeCaptureScreen),
            matching: find.byType(AllowLargeText),
          ),
          findsOneWidget,
        );
        for (var i = 0; i < 3; i++) {
          await t.tap(
            find.byKey(const Key('quick_exit_zone')),
            warnIfMissed: false,
          );
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('DECOY'), findsOneWidget);
        expect(
          find.byType(DatingPracticeCaptureScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(DatingVerifyFlow, skipOffstage: false),
          findsNothing,
        );
        expect(gateway.actionNames, ['start']);
      });
    });
  });

  // Task 4 fix round 1 (task-4-review.md I-1..I-4, M-2..M-6).
  group('fix round 1', () {
    DatingVerification closed(
      String step,
      DatingVerifyOutcome o, {
      DatingCheck age = DatingCheck.none,
    }) => DatingVerification(
      available: true,
      age: age,
      idDocuments: _docs,
      session: DatingVerifySession(
        id: datingTestSession,
        step: step,
        state: 'failed',
        outcome: o,
        position: 2,
      ),
    );

    testWidgets('I-1: after a photo mismatch, Try again leads back to the '
        'video, also after D9', (t) async {
      final r = await _open(
        t,
        state: closed('liveness', DatingVerifyOutcome.photoMismatch),
      );
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.needsId),
      ];
      await tapInReach(t, find.text('Change that photo'));
      expect(r.photos, ['photos']);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      await _consentAndStart(t);
      expect(r.gateway.actionNames, ['start', 'complete']);
    });

    testWidgets('I-2: a reopen path never records a consent the box didn\'t '
        'give; the server\'s standing consent decides', (t) async {
      for (final (state, button, action) in [
        (
          closed('liveness', DatingVerifyOutcome.needsId),
          'Check with my ID',
          'start_id',
        ),
        (
          closed('liveness', DatingVerifyOutcome.ageUncertain),
          'Check with my ID',
          'start_id',
        ),
        (closed('human', DatingVerifyOutcome.askForId), null, 'start_id'),
        (
          closed('liveness', DatingVerifyOutcome.photoMismatch),
          'Ask a person to review it',
          'human_start',
        ),
      ]) {
        final r = await _open(t, state: state);
        r.gateway.answers['start_id'] = [datingStarted()];
        r.gateway.answers['complete_id'] = [
          datingOutcome(DatingVerifyOutcome.idPending),
        ];
        if (button != null) {
          await tapInReach(t, find.text(button));
          await t.pumpAndSettle();
        }
        if (action == 'start_id') {
          await tapInReach(t, find.text('Passport'));
          await t.pump();
          await tapInReach(t, find.text('Continue'));
          await t.pumpAndSettle();
        }
        expect(r.gateway.consents, isEmpty, reason: '$action via $button');
        expect(r.gateway.actionNames.first, action, reason: '$button');
      }
    });

    testWidgets('I-2: consent_required leads to the intro, the box shown '
        'unticked', (t) async {
      final r = await _open(
        t,
        state: closed('liveness', DatingVerifyOutcome.needsId),
      );
      r.gateway.answers['start_id'] = [
        datingRefused(DatingVerifyRefusal.consentRequired),
      ];
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text('Tick the box to agree to the check, then start again.'),
        findsOneWidget,
      );
      expect(find.text('Start video check'), findsOneWidget);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('dating_verify_consent')),
            )
            .value,
        isFalse,
      );
      expect(r.gateway.consents, isEmpty);
      // Ticked now: the next start records it.
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.needsId),
      ];
      await _consentAndStart(t);
      expect(r.gateway.consents.length, 1);
    });

    testWidgets('I-3: on the far-below screen a system back goes to Spec 1\'s '
        'hold screen, never back down the stack', (t) async {
      final gateway = FakeDatingVerificationGateway(
        state: closed(
          'liveness',
          DatingVerifyOutcome.farBelow,
          age: DatingCheck.fail,
        ),
      );
      final s = await pumpDatingShell(
        t,
        initial: RouteNames.home,
        extraRoutes: [
          GoRoute(
            path: RouteNames.onboarding,
            builder:
                (_, st) =>
                    Scaffold(body: Text('H1 ${st.extra is OnboardingHeld}')),
          ),
        ],
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      unawaited(s.router.push(DatingPaths.step('verify')));
      await t.pumpAndSettle();
      expect(find.textContaining('We need to check a few things'), findsOne);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('H1 true'), findsOneWidget);
      expect(find.textContaining('ME'), findsNothing);
      expect(find.byType(DatingVerifyFlow, skipOffstage: false), findsNothing);
    });

    testWidgets('I-4: the ID passed, identity still to do: the age is '
        'confirmed, then the video or a person', (t) async {
      final r = await _open(t, state: _agePassed);
      expect(
        find.text(
          "Your age is confirmed. Now we check it's you: a short video, or a "
          'person can look at two quick photos.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'This check flashes colours on your screen. If flashing lights '
          'affect you, ask a person to review it instead.',
        ),
        findsOneWidget,
      );
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) {
        if (a == 'complete') r.gateway.state = _verified;
      };
      await tapInReach(t, find.text('Start video check'));
      await t.pumpAndSettle();
      expect(r.gateway.consents, isEmpty, reason: 'no box ticked here');
      expect(r.gateway.actionNames, ['start', 'complete']);
      expect(find.text("You're verified."), findsOneWidget);
    });

    testWidgets('I-4: a person instead of the flashing video', (t) async {
      final r = await _open(t, state: _agePassed);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(find.text('Take two quick photos'), findsWidgets);
    });

    testWidgets('I-4: a photo that doesn\'t match still comes first', (
      t,
    ) async {
      await _open(
        t,
        state: closed(
          'liveness',
          DatingVerifyOutcome.photoMismatch,
          age: DatingCheck.pass,
        ),
      );
      expect(find.textContaining('Photo 2'), findsOneWidget);
      expect(find.textContaining('Your age is confirmed.'), findsNothing);
    });

    testWidgets('M-2: a pending video result can go back to the intro', (
      t,
    ) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.pending),
      ];
      await _consentAndStart(t);
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
    });

    testWidgets('M-3: Back from the photos page returns to the other ways', (
      t,
    ) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(r.done, isEmpty);
    });

    testWidgets('M-4: a gesture this build doesn\'t know is never shown as '
        'another one', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'touch_your_nose'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(find.text('Take photo 1'), findsNothing);
      expect(find.text('2. Give a thumbs up'), findsNothing);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('M-5: the check switched off with an older session: the '
        'intro says why', (t) async {
      await _open(
        t,
        state: const DatingVerification(
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'expired',
          ),
        ),
      );
      expect(
        find.text("Checking isn't available right now. Try again later."),
        findsOneWidget,
      );
    });

    testWidgets('M-6: a country with no ID listed: a calm line, not an '
        'empty choice', (t) async {
      await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.needsId,
          ),
        ),
      );
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      expect(
        find.text("Checking isn't available right now. Try again later."),
        findsOneWidget,
      );
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('M-8, M-9: the other ways and the photos page say what each '
        'checks', (t) async {
      final r = await _open(t);
      r.gateway.answers['human_start'] = [
        const DatingVerifyAnswer(
          ok: true,
          sessionId: datingTestSession,
          gestures: ['left_ear', 'thumbs_up'],
          paths: ['a/1.jpg', 'a/2.jpg'],
        ),
      ];
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'You can check with your ID. Or a person can look at two quick '
          "photos to check it's you (this doesn't confirm your age).",
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Take each photo with your camera. A person checks the photos are '
          'you, and the photos are deleted after the check.',
        ),
        findsOneWidget,
      );
    });
  });

  group('final fix wave', () {
    const stillChecking = "We're still checking. Check again in a moment.";
    const human = DatingVerifyAnswer(
      ok: true,
      sessionId: datingTestSession,
      gestures: ['left_ear', 'thumbs_up'],
      paths: ['a/1.jpg', 'a/2.jpg'],
    );

    Future<void> toId(WidgetTester t) async {
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Check with my ID'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Passport'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
    }

    Future<void> toHuman(WidgetTester t) async {
      await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
      await t.pump();
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
    }

    testWidgets('M-1: an ID pass whose status can\'t be read is never "You\'re '
        'verified." (the ID proves age only): still checking, and Check '
        'again reads it', (t) async {
      final gateway = _Unreadable();
      final r = await _open(t, gateway: gateway);
      gateway.answers['start_id'] = [datingStarted()];
      gateway.answers['complete_id'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      gateway.onAct = (a) {
        if (a == 'complete_id') gateway.unreadable = true;
      };
      await toId(t);
      expect(gateway.actionNames, ['start_id', 'complete_id']);
      expect(find.text("You're verified."), findsNothing);
      expect(find.byKey(const ValueKey('dating_verified_check')), findsNothing);
      expect(find.text(stillChecking), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      expect(r.done, isEmpty);
      // Still unreadable: the calm line, nothing moves on.
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(find.text(stillChecking), findsOneWidget);
      expect(find.text("You're verified."), findsNothing);
      // Readable again: what the status says (the age only, so far).
      gateway
        ..unreadable = false
        ..state = _agePassed;
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(find.textContaining('Your age is confirmed.'), findsOneWidget);
      expect(find.text("You're verified."), findsNothing);
      expect(gateway.actionNames, ['start_id', 'complete_id']);
    });

    testWidgets('M-1: a video pass whose status can\'t be read is still '
        'checking too; the next account never sees it (D8)', (t) async {
      final gateway = _Unreadable();
      await _open(t, gateway: gateway);
      gateway.answers['start'] = [datingStarted()];
      gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      gateway.onAct = (a) {
        if (a == 'complete') gateway.unreadable = true;
      };
      await _consentAndStart(t);
      expect(find.text("You're verified."), findsNothing);
      expect(find.text(stillChecking), findsOneWidget);
      gateway
        ..unreadable = false
        ..hold = Completer<DatingVerification>();
      final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
      c.read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(find.text(stillChecking), findsNothing);
        expect(find.text('Check again'), findsNothing);
      }
      gateway.hold!.complete(const DatingVerification(available: true));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.text(stillChecking), findsNothing);
    });

    testWidgets('M-1: a pass whose status reads verified still shows "You\'re '
        'verified."', (t) async {
      final r = await _open(t);
      r.gateway.answers['start'] = [datingStarted()];
      r.gateway.answers['complete'] = [
        datingOutcome(DatingVerifyOutcome.verified),
      ];
      r.gateway.onAct = (a) {
        if (a == 'complete') r.gateway.state = _verified;
      };
      await _consentAndStart(t);
      expect(find.text("You're verified."), findsOneWidget);
      expect(find.text(stillChecking), findsNothing);
    });

    for (final (name, blocked, line) in [
      (
        'denied',
        false,
        'Attune needs your camera for these photos. Tap Take photo and '
            "choose Allow, or allow the camera in your phone's Settings.",
      ),
      (
        'permanently denied',
        true,
        "Attune can't use your camera right now. To take these photos, "
            "allow the camera for Attune in your phone's Settings.",
      ),
    ]) {
      testWidgets('M-4: a camera $name: how to allow it, Open Settings and '
          'the other ways; never "That photo didn\'t go through"', (t) async {
        final access = _Access(isBlocked: blocked);
        final r = await _open(
          t,
          camera:
              () async =>
                  throw PlatformException(
                    code: 'camera_access_denied',
                    message: 'The user did not allow camera access. +233',
                  ),
          more: [datingCameraAccessProvider.overrideWithValue(access)],
        );
        r.gateway.answers['human_start'] = [human];
        await toHuman(t);
        for (var i = 0; i < 2; i++) {
          await tapInReach(t, find.text('Take photo 1'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text(line), findsOneWidget, reason: 'tap $i');
          expect(
            _shows("That photo didn't go through. Take it again."),
            isFalse,
            reason: 'tap $i',
          );
        }
        expect(find.textContaining('+233'), findsNothing);
        expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
        expect(r.gateway.uploads, isEmpty);
        expect(r.dir.listSync(), isEmpty, reason: 'nothing on disk');
        await tapInReach(t, find.text('Open Settings'));
        await t.pump();
        expect(access.opened, 1);
        // The other ways: where they were offered (ID, or a person).
        await tapInReach(t, find.text('Check another way'));
        await t.pumpAndSettle();
        expect(find.text('Check with my ID'), findsOneWidget);
        expect(r.done, isEmpty, reason: 'still on D11');
        expect(_shows(line), isFalse);
      });
    }

    testWidgets('M-4: any other camera failure is still "That photo didn\'t '
        'go through"; allowed again, the line goes', (t) async {
      Object? fail = PlatformException(code: 'no_available_camera');
      final access = _Access(isBlocked: false);
      late final _Run r;
      r = await _open(
        t,
        camera: () async {
          final f = fail;
          if (f != null) throw f;
          return (File('${r.dir.path}/cam.jpg')
            ..writeAsBytesSync([1, 2, 3])).path;
        },
        more: [datingCameraAccessProvider.overrideWithValue(access)],
      );
      r.gateway.answers['human_start'] = [human];
      await toHuman(t);
      await tapInReach(t, find.text('Take photo 1'));
      await t.pumpAndSettle();
      expect(
        find.text("That photo didn't go through. Take it again."),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsNothing);
      fail = PlatformException(code: 'camera_access_denied');
      await tapInReach(t, find.text('Take photo 1'));
      await t.pumpAndSettle();
      expect(find.text('Open Settings'), findsOneWidget);
      fail = null;
      await tapInReach(t, find.text('Take photo 1'));
      await _settleIo(t, () => r.gateway.uploads.length == 1);
      expect(find.text('Open Settings'), findsNothing);
      expect(r.dir.listSync(), isEmpty);
    });

    testWidgets('M-3: system back retraces the stages, then leaves D11; the '
        'app bar back does the same', (t) async {
      final gateway = FakeDatingVerificationGateway();
      gateway.answers['human_start'] = [human];
      final s = await pumpDatingShell(
        t,
        overrides: [
          datingVerificationGatewayProvider.overrideWithValue(gateway),
          datingCaptureLauncherProvider.overrideWithValue(
            FakeCaptureLauncher(),
          ),
        ],
      );
      unawaited(s.router.push(DatingPaths.step('verify')));
      await t.pumpAndSettle();
      await toHuman(t);
      expect(find.text('Take two quick photos'), findsWidgets);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Check with my ID'), findsOneWidget);
      expect(find.byType(DatingVerifyFlow), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.byType(DatingVerifyFlow), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(DatingVerifyFlow), findsNothing);
      expect(find.textContaining('ME'), findsOneWidget);
    });

    testWidgets('M-6: an outcome and a refusal under it are separate live '
        'regions, never one inside another', (t) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'id',
            state: 'awaiting_review',
            open: true,
          ),
        ),
      );
      r.gateway.answers['complete_id'] = [
        datingRefused(DatingVerifyRefusal.rateLimited),
      ];
      await tapInReach(t, find.text('Check again'));
      await t.pumpAndSettle();
      expect(
        find.text("You've started a lot of checks. Try again later."),
        findsOneWidget,
      );
      expect(_nestedLiveRegions(t), isEmpty);
      // The outcome itself is still read out.
      expect(
        find.ancestor(
          of: find.textContaining('Most checks finish in a few minutes'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('M-7: a person\'s review left half done reopens on the other '
        'ways, "Let\'s pick up where you left off.", the same session', (
      t,
    ) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          idDocuments: _docs,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'human',
            state: 'started',
            open: true,
          ),
        ),
      );
      r.gateway.answers['human_start'] = [human];
      expect(find.text("Let's pick up where you left off."), findsOneWidget);
      expect(find.text('Ask a person to review it'), findsOneWidget);
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(r.gateway.consents, isEmpty, reason: 'no box ticked here');
      expect(r.gateway.actionNames, ['human_start']);
      expect(find.text('Take two quick photos'), findsWidgets);
      // Back reaches the intro, which names no video to pick up.
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      await tapInReach(t, find.byType(BackButtonIcon));
      await t.pumpAndSettle();
      expect(find.text('Start video check'), findsOneWidget);
      expect(find.text("Let's pick up where you left off."), findsNothing);
      expect(r.done, isEmpty);
    });

    testWidgets('M-3: the far-below screen keeps its own rule: a system '
        'back goes to Spec 1\'s hold only, never back through the flow', (
      t,
    ) async {
      final r = await _open(
        t,
        state: const DatingVerification(
          available: true,
          age: DatingCheck.fail,
          session: DatingVerifySession(
            id: datingTestSession,
            step: 'liveness',
            state: 'failed',
            outcome: DatingVerifyOutcome.farBelow,
          ),
        ),
      );
      expect(find.textContaining('We need to check a few things'), findsOne);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(r.done, ['<held>']);
    });

    testWidgets('the new lines at large text 2.0 and in the dark theme: in '
        'reach, calm, the guidelines hold', (t) async {
      final semantics = t.ensureSemantics();
      // The guidelines at 1.0 (as D11's dark-theme test); reach at 2.0.
      for (final (theme, textScale) in [
        (AppTheme.lightTheme, 2.0),
        (AppTheme.darkTheme, 2.0),
        (AppTheme.lightTheme, 1.0),
        (AppTheme.darkTheme, 1.0),
      ]) {
        Future<void> guidelines() async {
          if (textScale == 1.0) await expectFlowGuidelines(t);
        }

        // M-1: still checking.
        final gateway = _Unreadable();
        await _open(t, gateway: gateway, theme: theme, textScale: textScale);
        gateway.answers['start'] = [datingStarted()];
        gateway.answers['complete'] = [
          datingOutcome(DatingVerifyOutcome.verified),
        ];
        gateway.onAct = (a) {
          if (a == 'complete') gateway.unreadable = true;
        };
        await bringIntoReach(
          t,
          find.byKey(const ValueKey('dating_verify_consent')),
        );
        await _consentAndStart(t);
        expect(t.takeException(), isNull);
        expect(find.text(stillChecking), findsOneWidget);
        await bringIntoReach(t, find.text('Check again'));
        expect(wouldHit(t, find.text('Check again')), isTrue);
        expect(find.byType(FlowErrorLine), findsNothing);
        await guidelines();
        // M-4: the camera refused.
        final r = await _open(
          t,
          theme: theme,
          textScale: textScale,
          camera:
              () async => throw PlatformException(code: 'camera_access_denied'),
          more: [
            datingCameraAccessProvider.overrideWithValue(
              _Access(isBlocked: true),
            ),
          ],
        );
        r.gateway.answers['human_start'] = [human];
        await toHuman(t);
        await tapInReach(t, find.text('Take photo 1'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        for (final target in ['Open Settings', 'Check another way']) {
          await bringIntoReach(t, find.text(target));
          expect(wouldHit(t, find.text(target)), isTrue, reason: target);
        }
        final line = t.widget<Text>(
          find.textContaining("Attune can't use your camera"),
        );
        expect(line.style?.color, isNot(theme.colorScheme.error));
        expect(find.byType(FlowErrorLine), findsNothing);
        await guidelines();
      }
      semantics.dispose();
    });

    testWidgets('server M-4: a check open on another phone is its own calm '
        'line, never "Something went wrong."', (t) async {
      final r = await _open(t);
      for (final action in ['start', 'start_id', 'human_start']) {
        r.gateway.answers[action] = [
          DatingVerifyAnswer.fromJson({
            'ok': false,
            'reason': 'session_elsewhere',
            'message': 'SERVER SAYS NO',
          }),
        ];
      }
      await _consentAndStart(t);
      const elsewhere =
          "A check is already open on another phone. Finish it there, or try "
          'again later.';
      expect(find.text(elsewhere), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(find.textContaining('SERVER'), findsNothing);
      expect(find.byType(FlowErrorLine), findsNothing, reason: 'calm');
      expect(r.gateway.reads, 1, reason: 'nothing moved: no read again');
      expect(find.text('Start video check'), findsOneWidget);
      // The other ways say the same.
      await tapInReach(t, find.text('Check another way'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ask a person to review it'));
      await t.pumpAndSettle();
      expect(find.text(elsewhere), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing);
    });

    testWidgets('M-9: the manual says an ID-first check still needs the '
        'video or a person', (t) async {
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final verify = DatingModeDocs()
          .getSections(context)
          .expand((s) => s.contents)
          .singleWhere((c) => c.id == 'dating_setup_verify');
      expect(
        verify.content,
        contains(
          'If you check with your ID first, a short video or two quick '
          'photos then check that your photos are you.',
        ),
      );
    });
  });
}

/// Final fix (M-1): a status that can't be read while [unreadable].
class _Unreadable extends FakeDatingVerificationGateway {
  bool unreadable = false;

  @override
  Future<DatingVerification> status() async {
    if (unreadable) {
      reads++;
      throw StateError('offline');
    }
    return super.status();
  }
}

/// Final fix (M-4): the camera's permission, as the phone answers it.
class _Access extends DatingCameraAccess {
  _Access({required this.isBlocked});

  final bool isBlocked;
  int opened = 0;

  @override
  Future<bool> blocked() async => isBlocked;

  @override
  Future<void> openSettings() async => opened++;
}

/// Final fix (M-6): every live region that holds another one.
List<String> _nestedLiveRegions(WidgetTester t) {
  bool live(Widget w) => w is Semantics && w.properties.liveRegion == true;
  final out = <String>[];
  for (final outer in find.byWidgetPredicate(live).evaluate()) {
    final inner = find.descendant(
      of: find.byElementPredicate((e) => e == outer),
      matching: find.byWidgetPredicate(live),
    );
    for (final e in inner.evaluate()) {
      out.add('${outer.widget} > ${e.widget}');
    }
  }
  return out;
}
