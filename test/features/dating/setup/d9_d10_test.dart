// Spec 2 W3c (§3.2 D9-D10, §3.15, C-5): photos and prompts.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/photos_step.dart';
import 'package:attune/features/dating/setup/prompts_step.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_private_keyboard.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Prep extends DatingImagePreparer {
  _Prep(this.dir);
  final Directory dir;
  final made = <File>[];
  int sweeps = 0;
  @override
  Future<int> sweepLeftovers({Directory? dir, DateTime? before}) async {
    sweeps++;
    return 0;
  }

  @override
  Future<PreparedDatingImage> prepare(String localPath) async {
    final f = File('${dir.path}/p_${made.length}.jpg')
      ..writeAsBytesSync(List.filled(300, 1));
    made.add(f);
    return PreparedDatingImage(file: f, mimeType: 'image/jpeg', byteSize: 300);
  }
}

Future<(FakeDatingPhotosGateway, List<String>, _Prep, Directory)> _photos(
  WidgetTester t, {
  List photos = const [],
  bool online = true,
  DateTime? afterMutualFrom,
}) async {
  DatingPhotosStep.debugAddsInFlight = 0;
  await t.pumpWidget(const SizedBox());
  final dir = Directory.systemTemp.createTempSync('d9');
  addTearDown(() => dir.deleteSync(recursive: true));
  final picked = File('${dir.path}/picked.jpg')
    ..writeAsBytesSync(List.filled(10, 2));
  final gateway = FakeDatingPhotosGateway(
    photos: [...photos],
    afterMutualFrom: afterMutualFrom ?? DateTime.utc(2026, 1, 1),
  );
  final prep = _Prep(dir);
  final steps = <String>[];
  await pumpFlowScreen(
    t,
    () => DatingPhotosStep(
      nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
    ),
    overrides: [
      ...datingShellOverrides(online: online),
      datingPhotosGatewayProvider.overrideWithValue(gateway),
      datingImagePreparerProvider.overrideWithValue(prep),
      datingPhotoPickerProvider.overrideWithValue(() async => picked.path),
      datingPhotoCropperProvider.overrideWithValue((path) async => path),
    ],
  );
  await t.pumpAndSettle();
  return (gateway, steps, prep, dir);
}

/// The add path reads and deletes real files: let that I/O finish (the test
/// clock doesn't run it), a frame at a time, until [until] holds (by
/// default: no add is running), never for a fixed time (T10 hardening:
/// under a loaded machine 10 x 10 ms was not always enough). Then a few
/// frames for what the add's end asked for (the list, its post-frame).
Future<void> _settleIo(WidgetTester t, {bool Function()? until}) async {
  final done = until ?? () => DatingPhotosStep.debugAddsInFlight <= 0;
  final limit = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
    if (done()) break;
    if (DateTime.now().isAfter(limit)) {
      fail('_settleIo: the step never settled');
    }
  }
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

/// [text] is on screen now.
bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  group('D9', () {
    testWidgets('six slots, each read as "Photo n of 6, state"', (t) async {
      final semantics = t.ensureSemantics();
      await _photos(t, photos: [photo(1, 'approved'), photo(2, 'pending')]);
      expect(find.text('Add your photos'), findsOneWidget);
      expect(find.text('Step 8 of 12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 2 of 6, Checking…')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 3 of 6, Add photo')),
        findsOneWidget,
      );
      expect(find.text('Each photo uses about 300 KB.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('add: prepared, uploaded, and every temp file deleted (C-5)', (
      t,
    ) async {
      final (gateway, _, prep, dir) = await _photos(t);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(gateway.calls.where((c) => c.$1 == 'add').single.$2, (
        1,
        300,
        'image/jpeg',
      ));
      expect(prep.made.single.existsSync(), isFalse);
      expect(File('${dir.path}/picked.jpg').existsSync(), isFalse);
      for (final f in dir.listSync()) {
        expect(f.path.toLowerCase(), isNot(contains('dating')));
      }
    });

    testWidgets(
      'each rejection names its slot and its reason; a child photo offers Crop',
      (t) async {
        await _photos(
          t,
          photos: [
            photo(1, 'rejected', reason: 'face_unclear'),
            photo(2, 'rejected', reason: 'too_small'),
            photo(3, 'rejected', reason: 'contains_child'),
            photo(4, 'rejected', reason: 'unsafe'),
            photo(5, 'needs_review', reason: 'needs_review'),
          ],
        );
        expect(
          find.text("Photo 1: we couldn't see your face clearly."),
          findsOneWidget,
        );
        expect(find.text('Photo 2 is too small.'), findsOneWidget);
        expect(
          find.text(
            "Photo 3: photos with children can't be used on Dating. Crop to just you?",
          ),
          findsOneWidget,
        );
        expect(find.text('Crop'), findsOneWidget);
        expect(find.text("Photo 4 can't be used."), findsOneWidget);
        expect(
          find.text(
            'Needs a person to check it. That usually takes less than a day.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Continue needs two photos that aren\'t rejected', (t) async {
      final (_, steps, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'rejected', reason: 'unsafe')],
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(steps, isEmpty);
      final (_, steps2, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'pending')],
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(steps2, ['prompts']);
    });

    testWidgets('Move later: the new order is sent', (t) async {
      final (gateway, _, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
      );
      await tapInReach(t, find.byTooltip('Move later').first);
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder').single.$2, [
        'p2',
        'p1',
      ]);
    });

    testWidgets('drag by the thumbnail: the new order is sent', (t) async {
      final (gateway, _, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
      );
      await bringIntoReach(t, find.byKey(const ValueKey('drag_p1')));
      await t.drag(find.byKey(const ValueKey('drag_p1')), const Offset(0, 400));
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder').single.$2, [
        'p2',
        'p1',
      ]);
    });

    testWidgets(
      'before account day 30 the photos-after toggle is off and says when',
      (t) async {
        await _photos(
          t,
          afterMutualFrom: DateTime.now().toUtc().add(const Duration(days: 9)),
        );
        final toggle = t.widget<SwitchListTile>(
          find.widgetWithText(
            SwitchListTile,
            "Show my photos only after we're both interested",
          ),
        );
        expect(toggle.onChanged, isNull);
        expect(find.textContaining('Available from '), findsOneWidget);
      },
    );

    testWidgets('offline: adding is off and says so', (t) async {
      final (gateway, _, _, _) = await _photos(t, online: false);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(
        find.text("You're offline. Add photos when you're connected."),
        findsOneWidget,
      );
    });

    testWidgets('a failed upload names the slot', (t) async {
      final (gateway, _, _, _) = await _photos(t);
      gateway.addAnswer = DatingWrite.failed;
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
    });

    // Final fix (M-13): a prepared photo a crash left behind is swept as
    // soon as D9 opens.
    testWidgets('opening D9 sweeps leftover prepared photos', (t) async {
      final (_, _, prep, _) = await _photos(t);
      expect(prep.sweeps, 1);
    });

    // Final fix (M-16): the delete is at once (no undo), so Remove asks
    // first; Keep it keeps the photo and sends nothing.
    testWidgets('Remove asks first: Keep it keeps, Remove deletes', (t) async {
      final (gateway, _, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
      );
      await tapInReach(t, find.byTooltip('Remove').first);
      await t.pumpAndSettle();
      expect(find.text('Remove photo 1?'), findsOneWidget);
      expect(
        find.text(
          "It's deleted at once. A photo you add later is checked again "
          'before anyone sees it.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Keep it'));
      await t.pumpAndSettle();
      expect(find.text('Remove photo 1?'), findsNothing);
      expect(gateway.calls.where((c) => c.$1 == 'remove'), isEmpty);
      await tapInReach(t, find.byTooltip('Remove').at(1));
      await _confirmRemove(t);
      expect(gateway.calls.where((c) => c.$1 == 'remove').single.$2, 'p2');
    });
  });

  group('D10', () {
    Future<(FakeDatingSetupGateway, List<String>)> prompts(
      WidgetTester t, {
      DatingMyProfile profile = const DatingMyProfile(),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(profile: profile);
      final steps = <String>[];
      await pumpFlowScreen(
        t,
        () => DatingPromptsStep(
          nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(setup),
        ],
      );
      await t.pumpAndSettle();
      return (setup, steps);
    }

    testWidgets('two answers of 10 to 200 characters, sent in order', (
      t,
    ) async {
      final (setup, steps) = await prompts(t);
      expect(find.text('Answer 2 of these. Short is fine.'), findsOneWidget);
      await tapInReach(t, find.text('A perfect Sunday for me looks like…'));
      await t.pump();
      await tapInReach(t, find.text('Ask me about…'));
      await t.pumpAndSettle();
      // Final fix (M-12): nor from a prompt's answer.
      for (final id in ['perfect_sunday', 'ask_me_about']) {
        expectPrivateKeyboard(t, find.byKey(ValueKey('dating_prompt_$id')));
      }
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
        'A long walk, then lunch.',
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'short',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.writes, isEmpty);
      expect(find.text('At least 10 characters.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'My grandmother.',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['items'], [
        ('perfect_sunday', 'A long walk, then lunch.'),
        ('ask_me_about', 'My grandmother.'),
      ]);
      expect(steps, ['verify']);
    });

    testWidgets('the contact and kindness filters land on their prompt', (
      t,
    ) async {
      final (setup, _) = await prompts(
        t,
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      );
      setup.answer = const DatingWrite(
        ok: false,
        reason: 'contact_details',
        position: 2,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "Contact details can't go on your profile. You can swap them in a chat when you're both ready.",
        ),
        findsOneWidget,
      );
      setup.answer = const DatingWrite(
        ok: false,
        reason: 'unkind',
        position: 1,
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
        'A long walk, then a lunch.',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text("Please rephrase this so it's kind to everyone."),
        findsOneWidget,
      );
    });

    testWidgets('at most three prompts', (t) async {
      await prompts(t);
      for (final p in [
        'A perfect Sunday for me looks like…',
        'I feel most at home when…',
        "My friends would say I'm…",
        'Ask me about…',
      ]) {
        await tapInReach(t, find.text(p));
        await t.pumpAndSettle();
      }
      expect(find.byType(TextField), findsNWidgets(3));
    });
  });

  testWidgets('guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await _photos(
      t,
      photos: [
        photo(1, 'approved'),
        photo(3, 'rejected', reason: 'contains_child'),
      ],
    );
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, photos) in [
    ('d9_photos_empty', const <dynamic>[]),
    (
      'd9_photos_states',
      [
        photo(1, 'approved'),
        photo(2, 'pending'),
        photo(3, 'rejected', reason: 'contains_child'),
        photo(4, 'needs_review', reason: 'needs_review'),
      ],
    ),
  ]) {
    testWidgets('$name goldens', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [...photos],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await expectFlowGoldens(
        t,
        name,
        () => DatingPhotosStep(
          nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(),
          datingPhotosGatewayProvider.overrideWithValue(gateway),
        ],
      );
    });
  }

  testWidgets('d10_prompts goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd10_prompts',
      () => DatingPromptsStep(
        nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
      ),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(
              prompts: [('perfect_sunday', 'A long walk, then lunch.')],
            ),
          ),
        ),
      ],
    );
  });

  // ---- T10 carries (A-I): the current photo RPCs, no server bytes before a
  // clear scan, the preparer as it is, keys settled, no server text, the
  // step frame, quick exit, routing, theme and large text, the filters.
  group('D9 carries', () {
    testWidgets('B: a pending photo shows the local preview; nothing is '
        'fetched before the scan is clear', (t) async {
      final r = await _open9(t);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(_previews(t), hasLength(1));
      expect(_previews(t).single.bytes, List.filled(300, 1));
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Checking…')),
        findsOneWidget,
      );
      expect(r.gateway.byteReads, isEmpty);
      // Still pending at the next check: still the local file, still no read.
      await _recheck(t);
      expect(_previews(t), hasLength(1));
      expect(r.gateway.byteReads, isEmpty);
    });

    testWidgets('B: only an approved (scanned clear) photo is read from the '
        'server', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [
          photo(1, 'approved'),
          photo(2, 'pending'),
          photo(3, 'rejected', reason: 'unsafe'),
          photo(4, 'needs_review', reason: 'needs_review'),
          photo(5, 'rejected', reason: 'face_unclear'),
          photo(6, 'rejected', reason: 'contains_child'),
        ],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..stored['k1'] = _png;
      await _open9(t, gateway: gateway);
      await _settleIo(t);
      expect(gateway.byteReads, ['k1']);
      expect(_previews(t), hasLength(1));
      expect(_previews(t).single.bytes, _png);
    });

    testWidgets('B: a hit never shows: the local preview goes, the slot is '
        'neutral and never says why', (t) async {
      final r = await _open9(t);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(_previews(t), hasLength(1));
      // The scan matched: the server answers rejected / unsafe.
      r.gateway.photos = [
        DatingProfilePhoto(
          id: 'new-1',
          position: 1,
          moderationState: 'rejected',
          rejectionReason: 'unsafe',
          storageKey: 'k-1',
          createdAt: DateTime.utc(2026, 11, 7),
        ),
      ];
      await _recheck(t);
      expect(_previews(t), isEmpty);
      expect(find.text("Photo 1 can't be used."), findsOneWidget);
      expect(find.textContaining('CSAM'), findsNothing);
      expect(find.textContaining('child'), findsNothing);
      expect(r.gateway.byteReads, isEmpty);
    });

    testWidgets('A, E: a denied storage read is calm: no error, no text', (
      t,
    ) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved'), photo(2, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..bytesError = StateError(_leaky);
      await _open9(t, gateway: gateway);
      await _settleIo(t);
      expect(gateway.byteReads, ['k1', 'k2']);
      expect(_previews(t), isEmpty);
      expect(find.byType(FlowErrorLine), findsNothing);
      expect(find.textContaining('+233'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
    });

    testWidgets('E: a failed list read is generic copy with Retry, never the '
        'error', (t) async {
      final gateway = FakeDatingPhotosGateway(
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..listError = StateError(_leaky);
      await _open9(t, gateway: gateway);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      gateway
        ..listError = null
        ..photos = [photo(1, 'approved')];
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
    });

    testWidgets('A, E: busy is said calmly, a failed write generically, and '
        'never the server text', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved'), photo(2, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..writeAnswer = DatingWrite.busy;
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.byTooltip('Remove').first);
      await _confirmRemove(t);
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FlowErrorLine), findsNothing);
      gateway.writeAnswer = const DatingWrite(ok: false, reason: _leaky);
      await tapInReach(t, find.byTooltip('Move later').first);
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
    });

    testWidgets('A: an add refused by name says so, as well as the slot', (
      t,
    ) async {
      final r = await _open9(t);
      r.gateway.addAnswer = const DatingWrite(
        ok: false,
        reason: 'rate_limited',
      );
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
      expect(
        find.text("You've done this a lot today. Try again tomorrow."),
        findsOneWidget,
      );
      expect(r.dir.listSync(), isEmpty);
    });

    testWidgets('C: a photo the preparer refuses is the slot\'s failure, and '
        'the picked file still goes', (t) async {
      final r = await _open9(t, refuse: true);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t);
      expect(r.gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
      expect(r.dir.listSync(), isEmpty);
    });

    testWidgets('C: the picked and prepared files are gone before the upload '
        'ends', (t) async {
      final r = await _open9(t);
      r.gateway.holdAdd = Completer<void>();
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(
        t,
        until: () => _shows('Uploading photo 1…') && r.dir.listSync().isEmpty,
      );
      expect(find.text('Uploading photo 1…'), findsOneWidget);
      expect(r.gateway.calls.where((c) => c.$1 == 'add'), hasLength(1));
      expect(r.dir.listSync(), isEmpty);
      r.gateway.holdAdd!.complete();
      await _settleIo(t);
      expect(find.text('Uploading photo 1…'), findsNothing);
    });

    testWidgets('D: every keyed write settles its key; busy and failed keep '
        'it', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved'), photo(2, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..writeAnswer = DatingWrite.busy;
      await _open9(t, gateway: gateway);
      Future<String> later() async {
        await tapInReach(t, find.byTooltip('Move later').first);
        await t.pumpAndSettle();
        return gateway.keys.last.$2;
      }

      final busy = await later();
      expect(await later(), busy);
      gateway.writeAnswer = DatingWrite.failed;
      expect(await later(), busy);
      gateway.writeAnswer = const DatingWrite(ok: true);
      expect(await later(), busy);
      // Settled: the same move again is a new request.
      expect(await later(), isNot(busy));
      // The photos-after toggle, the same way.
      gateway.writeAnswer = DatingWrite.busy;
      final toggle = find.widgetWithText(
        SwitchListTile,
        "Show my photos only after we're both interested",
      );
      await tapInReach(t, toggle);
      await t.pumpAndSettle();
      final held = gateway.keys.last.$2;
      await tapInReach(t, toggle);
      await t.pumpAndSettle();
      expect(gateway.keys.last.$2, held);
      gateway.writeAnswer = const DatingWrite(ok: true);
      await tapInReach(t, toggle);
      await t.pumpAndSettle();
      expect(gateway.keys.last.$2, held);
    });

    testWidgets('F: a double tap opens one picker and adds once', (t) async {
      final pick = Completer<void>();
      final r = await _open9(t, holdPicker: pick);
      final add = find.widgetWithText(TextButton, 'Add photo').first;
      await tapInReach(t, add);
      await t.tap(add);
      await t.pump();
      await t.tap(add, warnIfMissed: false);
      pick.complete();
      await _settleIo(t);
      expect(r.picks, 1);
      expect(r.gateway.calls.where((c) => c.$1 == 'add'), hasLength(1));
    });

    testWidgets('F: a double tap on a move sends one reorder', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved'), photo(2, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..holdWrite = Completer<void>();
      await _open9(t, gateway: gateway);
      final later = find.byTooltip('Move later').first;
      await tapInReach(t, later);
      await t.tap(later);
      await t.pump();
      await t.tap(later, warnIfMissed: false);
      gateway.holdWrite!.complete();
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder'), hasLength(1));
    });

    testWidgets('D8: the next account sees nothing of the picked photo, even '
        'while its read is held', (t) async {
      final r = await _open9(t);
      r.gateway.holdAdd = Completer<void>();
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t, until: () => _shows('Uploading photo 1…'));
      expect(_previews(t), hasLength(1));
      expect(find.text('Uploading photo 1…'), findsOneWidget);
      r.gateway.holdList = Completer<DatingPhotoList>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(_previews(t), isEmpty);
        expect(find.text('Uploading photo 1…'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Add photo'), findsNWidgets(6));
      }
      // The first account's upload ends: nothing of it lands here.
      r.gateway.holdAdd!.complete();
      await _settleIo(t);
      expect(_previews(t), isEmpty);
      expect(find.text("Photo 1 didn't upload. Try again."), findsNothing);
      r.gateway.holdList!.complete(const DatingPhotoList());
      await _settleIo(t);
      expect(_previews(t), isEmpty);
      expect(find.widgetWithText(TextButton, 'Add photo'), findsNWidgets(6));
    });

    testWidgets('D8: a photo picked by one account is never uploaded for the '
        'next', (t) async {
      final prep = Completer<void>();
      final r = await _open9(t, holdPrepare: prep);
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t, until: () => _shows('Preparing photo 1…'));
      expect(find.text('Preparing photo 1…'), findsOneWidget);
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      expect(find.text('Preparing photo 1…'), findsNothing);
      prep.complete();
      await _settleIo(t);
      expect(r.gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(r.dir.listSync(), isEmpty);
      expect(_previews(t), isEmpty);
    });

    testWidgets('H: Move earlier / Move later are semantic actions on the '
        'slot, and only where the photo can move', (t) async {
      final semantics = t.ensureSemantics();
      final gateway = FakeDatingPhotosGateway(
        photos: [
          photo(1, 'approved'),
          photo(2, 'approved'),
          photo(3, 'pending'),
        ],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      int id(String label) => CustomSemanticsAction.getIdentifier(
        CustomSemanticsAction(label: label),
      );
      List<int> actions(String slot) =>
          t
              .getSemantics(find.bySemanticsLabel(RegExp('^$slot')))
              .getSemanticsData()
              .customSemanticsActionIds ??
          const [];
      expect(actions('Photo 1 of 6, Ready'), [id('Move later')]);
      expect(
        actions('Photo 2 of 6, Ready'),
        containsAll([id('Move earlier'), id('Move later')]),
      );
      expect(actions('Photo 3 of 6, Checking…'), [id('Move earlier')]);
      final node = t.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Photo 2 of 6, Ready')),
      );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id('Move later'),
      );
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder').single.$2, [
        'p1',
        'p3',
        'p2',
      ]);
      semantics.dispose();
    });

    testWidgets('H: the caption sheet scales its text and saves trimmed', (
      t,
    ) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.byTooltip('Add a caption (only you see it)'));
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.widgetWithText(TextField, 'Caption'),
          matching: find.byType(AllowLargeText),
        ),
        findsOneWidget,
      );
      // Final fix (M-12): the keyboard learns nothing from a caption.
      expectPrivateKeyboard(t, find.widgetWithText(TextField, 'Caption'));
      await t.enterText(find.widgetWithText(TextField, 'Caption'), ' Beach ');
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'caption').single.$2, (
        'p1',
        'Beach',
      ));
    });
  });

  group('D10 carries', () {
    testWidgets('F: a prompt touched before the saved ones arrive is kept; '
        'every other saved one still fills, and Continue waits', (t) async {
      final setup = _HeldPrompts()..holdProfile = Completer<DatingMyProfile>();
      await _open10(t, setup);
      await tapInReach(t, find.text('I feel most at home when…'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_feel_at_home')),
        'Cooking for friends.',
      );
      await t.pump();
      await tapInReach(t, find.text('A perfect Sunday for me looks like…'));
      await t.pump();
      expect(
        t.widget<FlowPrimaryButton>(find.byType(FlowPrimaryButton)).onPressed,
        isNull,
      );
      setup.holdProfile!.complete(
        const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(_typed(t, 'feel_at_home'), 'Cooking for friends.');
      // Ticked early, never typed in: the saved answer fills it.
      expect(_typed(t, 'perfect_sunday'), 'A long walk, then lunch.');
      // Never touched: the saved prompt is chosen and filled too.
      expect(_typed(t, 'ask_me_about'), 'My grandmother stories.');
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['items'], [
        ('feel_at_home', 'Cooking for friends.'),
        ('perfect_sunday', 'A long walk, then lunch.'),
        ('ask_me_about', 'My grandmother stories.'),
      ]);
    });

    testWidgets('F: a saved prompt the person typed in or took back early '
        'stays as they left it; one never touched is seeded whole', (t) async {
      final setup = _HeldPrompts()..holdProfile = Completer<DatingMyProfile>();
      await _open10(t, setup);
      await tapInReach(t, find.text('Ask me about…'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'My grandmother.',
      );
      await t.pump();
      // Ticked and taken back before the saved answers arrive.
      final sunday = find.widgetWithText(
        CheckboxListTile,
        'A perfect Sunday for me looks like…',
      );
      await tapInReach(t, sunday);
      await t.pump();
      await tapInReach(t, sunday);
      await t.pump();
      setup.holdProfile!.complete(
        const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
            ('feel_at_home', 'Cooking for friends.'),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(_typed(t, 'ask_me_about'), 'My grandmother.');
      expect(_typed(t, 'feel_at_home'), 'Cooking for friends.');
      expect(
        find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
        findsNothing,
      );
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('F: a double tap sends one write', (t) async {
      final setup = _HeldPrompts(
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      )..hold = Completer<void>();
      final steps = await _open10(t, setup);
      final go = find.byType(FlowPrimaryButton);
      await tapInReach(t, go);
      await t.tap(go);
      await t.pump();
      await t.tap(go, warnIfMissed: false);
      setup.hold!.complete();
      await t.pumpAndSettle();
      expect(setup.writes.where((w) => w == 'savePrompts'), hasLength(1));
      expect(steps, ['verify']);
    });

    testWidgets('D: a busy save keeps its key; an ok one settles it', (
      t,
    ) async {
      final setup = _HeldPrompts(
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      )..answer = DatingWrite.busy;
      await _open10(t, setup);
      Future<String> save() async {
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        return setup.lastWrite.$2['key']! as String;
      }

      final busy = await save();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(await save(), busy);
      setup.answer = const DatingWrite(ok: true);
      expect(await save(), busy);
      expect(await save(), isNot(busy));
    });

    testWidgets('D8: the next account sees none of the typed text, even while '
        'its read is held', (t) async {
      final setup = _HeldPrompts();
      await _open10(t, setup);
      await tapInReach(t, find.text('Ask me about…'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'My grandmother.',
      );
      await t.pump();
      setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(find.text('My grandmother.'), findsNothing);
        expect(find.byType(TextField), findsNothing);
      }
      setup.holdProfile!.complete(const DatingMyProfile());
      await t.pumpAndSettle();
      expect(find.text('My grandmother.'), findsNothing);
      await tapInReach(t, find.text('Ask me about…'));
      await t.pump();
      expect(_typed(t, 'ask_me_about'), '');
    });

    testWidgets('E: a failed profile read is generic copy with Retry', (
      t,
    ) async {
      final setup = _HeldPrompts()..profileError = StateError(_leaky);
      await _open10(t, setup);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
      setup.profileError = null;
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });

    testWidgets('I: an answer the server refuses lands on its prompt', (
      t,
    ) async {
      final setup = _HeldPrompts(
          profile: const DatingMyProfile(
            prompts: [
              ('perfect_sunday', 'A long walk, then lunch.'),
              ('ask_me_about', 'My grandmother stories.'),
            ],
          ),
        )
        ..answer = const DatingWrite(
          ok: false,
          reason: 'contact_details',
          position: 1,
        );
      await _open10(t, setup);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      final line = find.text(
        "Contact details can't go on your profile. You can swap them in a chat when you're both ready.",
      );
      expect(line, findsOneWidget);
      // Under the first prompt's field, above the second's.
      expect(
        t.getTopLeft(line).dy,
        lessThan(
          t
              .getTopLeft(
                find.byKey(const ValueKey('dating_prompt_ask_me_about')),
              )
              .dy,
        ),
      );
      expect(
        t.getTopLeft(line).dy,
        greaterThan(
          t
              .getTopLeft(
                find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
              )
              .dy,
        ),
      );
    });
  });

  group('G: quick exit', () {
    setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    Future<void> quickExit(WidgetTester t) async {
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
    }

    testWidgets('from D9 mid-upload: the preview and the temp files go', (
      t,
    ) async {
      DatingPhotosStep.debugAddsInFlight = 0;
      final dir = Directory.systemTemp.createTempSync('d9');
      addTearDown(() => dir.deleteSync(recursive: true));
      final picked = File('${dir.path}/picked.jpg')
        ..writeAsBytesSync(List.filled(10, 2));
      final gateway = FakeDatingPhotosGateway(
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..holdAdd = Completer<void>();
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('photos'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingPhotosGatewayProvider.overrideWithValue(gateway),
          datingImagePreparerProvider.overrideWithValue(_Prep(dir)),
          datingPhotoPickerProvider.overrideWithValue(() async => picked.path),
          datingPhotoCropperProvider.overrideWithValue((path) async => path),
        ],
      );
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t, until: () => _shows('Uploading photo 1…'));
      expect(_previews(t), hasLength(1));
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.byType(DatingPhotosStep, skipOffstage: false), findsNothing);
      expect(_previews(t), isEmpty);
      expect(dir.listSync(), isEmpty);
      gateway.holdAdd!.complete();
      await _settleIo(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(dir.listSync(), isEmpty);
    });

    testWidgets('from D9 while a photo is prepared: the picked file goes at '
        'once', (t) async {
      DatingPhotosStep.debugAddsInFlight = 0;
      final dir = Directory.systemTemp.createTempSync('d9');
      addTearDown(() => dir.deleteSync(recursive: true));
      final picked = File('${dir.path}/picked.jpg')
        ..writeAsBytesSync(List.filled(10, 2));
      final hold = Completer<void>();
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('photos'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
          ),
          datingImagePreparerProvider.overrideWithValue(
            _Prep9(dir, hold: hold),
          ),
          datingPhotoPickerProvider.overrideWithValue(() async => picked.path),
          datingPhotoCropperProvider.overrideWithValue((path) async => path),
        ],
      );
      await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
      await _settleIo(t, until: () => _shows('Preparing photo 1…'));
      expect(find.text('Preparing photo 1…'), findsOneWidget);
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(picked.existsSync(), isFalse);
      hold.complete();
      await _settleIo(t);
      expect(dir.listSync(), isEmpty);
    });

    testWidgets('from D10 with an answer typed: nothing of it stays', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('prompts'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
        ],
      );
      await tapInReach(t, find.text('Ask me about…'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'My grandmother.',
      );
      await t.pump();
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.text('My grandmother.', skipOffstage: false), findsNothing);
      expect(find.byType(DatingPromptsStep, skipOffstage: false), findsNothing);
    });
  });

  testWidgets('H: D9 and D10 open at their step paths, behind the Dating '
      'lock', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('photos'),
      locked: true,
      pinSet: true,
      overrides: [
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
        ),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      ],
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Add your photos'), findsNothing);
    s.container.read(datingUnlockedProvider.notifier).unlock();
    for (final (step, screen) in [
      ('photos', DatingPhotosStep),
      ('prompts', DatingPromptsStep),
    ]) {
      s.router.go(DatingPaths.step(step));
      await t.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: step);
      expect(s.location, DatingPaths.step(step));
    }
  });

  testWidgets('H: D9 and D10 in the dark theme: tokens only, contrast holds, '
      'the theme\'s own error red', (t) async {
    final semantics = t.ensureSemantics();
    final dark = AppTheme.darkTheme;
    for (final (theme, red) in [
      (dark, dark.colorScheme.error),
      (AppTheme.lightTheme, const Color(0xFFC62828)),
    ]) {
      await _open9(
        t,
        theme: theme,
        gateway: FakeDatingPhotosGateway(
          photos: [
            photo(1, 'approved'),
            photo(2, 'pending'),
            photo(3, 'rejected', reason: 'contains_child'),
            photo(4, 'needs_review', reason: 'needs_review'),
          ],
          afterMutualFrom: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        theme.colorScheme.surface,
      );
      final icon = find.descendant(
        of: find.byType(FlowErrorLine),
        matching: find.byType(Icon),
      );
      expect(t.widget<Icon>(icon.first).color, red);
      await expectFlowGuidelines(t);
      final setup = _HeldPrompts(
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      )..answer = const DatingWrite(ok: false, reason: 'unkind', position: 2);
      await _open10(t, setup, theme: theme);
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        theme.colorScheme.surface,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(t.widget<Icon>(icon.first).color, red);
      await expectFlowGuidelines(t);
    }
    expect(dark.colorScheme.error, const Color(0xFFEF5350));
    semantics.dispose();
  });

  // ---- T10 fix round 1 (review I-1..I-3, M-1..M-8).
  group('fix 1: D9', () {
    FakeDatingPhotosGateway two() => FakeDatingPhotosGateway(
      photos: [photo(1, 'approved'), photo(2, 'approved')],
      afterMutualFrom: DateTime.utc(2026, 1, 1),
    );

    testWidgets('I-1: a failed refresh keeps the photos on screen, with the '
        'error row', (t) async {
      final semantics = t.ensureSemantics();
      final gateway = two();
      await _open9(t, gateway: gateway);
      gateway.listError = StateError(_leaky);
      await _recheck(t);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 2 of 6, Ready')),
        findsOneWidget,
      );
      // Slots 1 and 2 hold photos: no Add photo there to replace them with.
      expect(_adds, findsNWidgets(4));
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Add photo')),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('I-1: until the list has loaded once, Add is off', (t) async {
      final gateway = FakeDatingPhotosGateway(
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..listError = StateError(_leaky);
      final r = await _open9(t, gateway: gateway);
      expect(_adds, findsNWidgets(6));
      for (final add in _adds.evaluate()) {
        expect((add.widget as TextButton).onPressed, isNull);
      }
      await tapInReach(t, _adds.first);
      await _settleIo(t);
      expect(r.picks, 0);
      gateway.listError = null;
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(_enabled(t, _adds.first), isTrue);
    });

    testWidgets('I-1, D8: the next account never sees the last one\'s '
        'photos, while its read is held or after it fails', (t) async {
      final semantics = t.ensureSemantics();
      final gateway = two();
      await _open9(t, gateway: gateway);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
      gateway.holdList = Completer<DatingPhotoList>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      expect(find.bySemanticsLabel(RegExp(r'Ready')), findsNothing);
      gateway
        ..holdList!.completeError(StateError(_leaky))
        ..holdList = null;
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Ready')), findsNothing);
      expect(_adds, findsNWidgets(6));
      expect(_enabled(t, _adds.first), isFalse);
      semantics.dispose();
    });

    testWidgets('I-3: a picker that is refused or fails is the slot\'s calm '
        'line, never its error', (t) async {
      final r = await _open9(
        t,
        pickError: PlatformException(
          code: 'photo_access_denied',
          message: 'The user did not allow photo access. +233 24 555 0101',
        ),
      );
      await tapInReach(t, _adds.first);
      await _settleIo(t);
      expect(t.takeException(), isNull);
      expect(
        find.text(
          "Photo 1: your photos couldn't be opened. Check that Attune can use "
          'them in Settings, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('+233'), findsNothing);
      expect(r.gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(r.dir.listSync(), isEmpty);
    });

    testWidgets('I-3: a cropper that throws is the slot\'s calm line; the '
        'picked file still goes', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(3, 'rejected', reason: 'contains_child')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      final r = await _open9(
        t,
        gateway: gateway,
        cropError: PlatformException(code: 'crop', message: 'boom +233'),
      );
      await tapInReach(t, find.widgetWithText(TextButton, 'Crop'));
      await _settleIo(t);
      expect(t.takeException(), isNull);
      expect(
        find.text("Photo 3 couldn't be cropped. Try again."),
        findsOneWidget,
      );
      expect(find.textContaining('+233'), findsNothing);
      expect(gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(r.dir.listSync(), isEmpty);
    });

    testWidgets('M-1: a pending photo is checked again every 4 s', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'pending')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      int lists() => gateway.calls.where((c) => c.$1 == 'list').length;
      final first = lists();
      await t.pump(const Duration(seconds: 3));
      expect(lists(), first);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(lists(), first + 1);
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(lists(), first + 2);
    });

    testWidgets('M-1: every 4 s for a minute, then every 20 s, then it '
        'stops at 10 minutes', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'pending')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      int lists() => gateway.calls.where((c) => c.$1 == 'list').length;
      final first = lists();
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(seconds: 4));
        await t.pump();
      }
      expect(lists(), first + 15);
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(lists(), first + 15);
      await t.pump(const Duration(seconds: 16));
      await t.pump();
      expect(lists(), first + 16);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(seconds: 20));
        await t.pump();
      }
      final capped = lists();
      expect(capped, first + 42);
      await t.pump(const Duration(minutes: 5));
      await t.pump();
      expect(lists(), capped);
    });

    testWidgets('M-1: a failed check or an offline one uses none of the '
        'budget; reconnecting checks at once', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'pending')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      final online = StreamController<bool>();
      addTearDown(online.close);
      online.add(true);
      await _open9(t, gateway: gateway, online: online.stream);
      int lists() => gateway.calls.where((c) => c.$1 == 'list').length;
      gateway.listError = StateError(_leaky);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(seconds: 4));
        await t.pump();
      }
      gateway.listError = null;
      online.add(false);
      await t.pump();
      final before = lists();
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(seconds: 4));
        await t.pump();
      }
      expect(lists(), before);
      online.add(true);
      await t.pump();
      await t.pump();
      expect(lists(), before + 1);
      // The budget is still whole: 4 s checks go on.
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(lists(), before + 2);
    });

    testWidgets('M-1: coming back to the app checks again', (t) async {
      final gateway = two();
      await _open9(t, gateway: gateway);
      int lists() => gateway.calls.where((c) => c.$1 == 'list').length;
      final before = lists();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(lists(), before);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump();
      expect(lists(), before + 1);
    });

    testWidgets('M-2: an add whose answer was lost but whose photo landed '
        'is that photo, not "didn\'t upload"', (t) async {
      final r = await _open9(t);
      r.gateway
        ..addAnswer = DatingWrite.failed
        ..insertAnyway = true;
      await tapInReach(t, _adds.first);
      await _settleIo(t);
      // The next list (the add asks for it once it ends) settles it.
      await _settleIo(t);
      expect(r.gateway.calls.where((c) => c.$1 == 'list'), hasLength(2));
      expect(find.text("Photo 1 didn't upload. Try again."), findsNothing);
      expect(find.text('Checking…'), findsOneWidget);
      expect(_previews(t), hasLength(1));
    });

    testWidgets('M-2: a failed add shows no preview, and its line goes with '
        'the photo it stood over', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'rejected', reason: 'face_unclear')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..addAnswer = DatingWrite.failed;
      await _open9(t, gateway: gateway);
      // Hardening: the list the add asks for is held, so this is the
      // moment before it lands, when a failed add's bytes could show.
      gateway.holdList = Completer<DatingPhotoList>();
      await tapInReach(t, find.widgetWithText(TextButton, 'Replace'));
      await _settleIo(t);
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
      expect(_previews(t), isEmpty);
      final held = gateway.holdList!;
      gateway.holdList = null;
      held.complete(
        DatingPhotoList(
          photos: gateway.photos,
          afterMutualFrom: gateway.afterMutualFrom,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
      expect(_previews(t), isEmpty);
      await tapInReach(t, find.byTooltip('Remove'));
      await _confirmRemove(t);
      expect(find.text("Photo 1 didn't upload. Try again."), findsNothing);
      expect(_adds, findsNWidgets(6));
    });

    testWidgets('M-2 (review survivor): a replaced slot\'s new photo keeps '
        'its local preview', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'rejected', reason: 'face_unclear')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.widgetWithText(TextButton, 'Replace'));
      await _settleIo(t);
      expect(gateway.photos.single.id, 'new-1');
      await _recheck(t);
      expect(find.text('Checking…'), findsOneWidget);
      expect(_previews(t), hasLength(1));
    });

    testWidgets('M-3: offline, every photo action is off and reads as off', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
        online: false,
      );
      for (final tip in ['Move later', 'Move earlier', 'Remove']) {
        for (final b in find.byTooltip(tip).evaluate()) {
          final button = b.findAncestorWidgetOfExactType<IconButton>();
          expect(button?.onPressed, isNull, reason: tip);
        }
      }
      expect(_enabled(t, _adds.first), isFalse);
      expect(
        t
            .getSemantics(_adds.first)
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isEnabled),
        isFalse,
      );
      for (final d in find.byType(ReorderableDragStartListener).evaluate()) {
        expect((d.widget as ReorderableDragStartListener).enabled, isFalse);
      }
      semantics.dispose();
    });

    testWidgets('M-4: a write that fails is said on its own photo', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [
          photo(1, 'approved'),
          photo(2, 'approved'),
          photo(3, 'approved'),
        ],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      )..writeAnswer = DatingWrite.failed;
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.byTooltip('Remove').at(1));
      await _confirmRemove(t);
      final line = find.text('Something went wrong. Try again.');
      expect(line, findsOneWidget);
      double y(Finder f) => t.getTopLeft(f).dy;
      final ready = find.text('Ready');
      expect(y(line), greaterThan(y(ready.at(1))));
      expect(y(line), lessThan(y(ready.at(2))));
    });

    testWidgets('M-7: thumbnails decode at the slot\'s size', (t) async {
      final gateway = two()..stored['k1'] = _png;
      await _open9(t, gateway: gateway);
      await _settleIo(t);
      final image = t.widget<Image>(find.byType(Image)).image;
      expect(image, isA<ResizeImage>());
      expect((image as ResizeImage).width, 64);
    });

    testWidgets('M-8: a caption is shown to the person, and read with its '
        'slot', (t) async {
      final semantics = t.ensureSemantics();
      final gateway = FakeDatingPhotosGateway(
        photos: [
          DatingProfilePhoto(
            id: 'p1',
            position: 1,
            moderationState: 'approved',
            caption: 'At the beach',
            storageKey: 'k1',
            createdAt: DateTime.utc(2026, 11, 1),
          ),
        ],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      expect(find.text('At the beach'), findsOneWidget);
      final node = t.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
      );
      expect(node.getSemanticsData().value, 'At the beach');
      semantics.dispose();
    });

    testWidgets('I-2: a caption the server would refuse is said in the sheet '
        'and never sent', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.byTooltip('Add a caption (only you see it)'));
      await t.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Caption');
      await t.enterText(field, 'Cooking 👩🏾‍🍳');
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "Some emoji and symbols can't be used here. Try taking them out.",
        ),
        findsOneWidget,
      );
      expect(gateway.calls.where((c) => c.$1 == 'caption'), isEmpty);
      await t.enterText(field, 'Cooking 🍳');
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'caption').single.$2, (
        'p1',
        'Cooking 🍳',
      ));
    });
  });

  group('fix 1: D10', () {
    const saved = DatingMyProfile(
      prompts: [
        ('perfect_sunday', 'A long walk, then lunch.'),
        ('ask_me_about', 'My grandmother stories.'),
      ],
    );

    Future<void> answer(WidgetTester t, String id, String text) async {
      await t.enterText(find.byKey(ValueKey('dating_prompt_$id')), text);
      await t.pump();
    }

    Finder under(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('dating_prompt_${id}_block')),
      matching: find.text(text),
    );

    const invisible =
        "Some emoji and symbols can't be used here. Try taking them out.";

    testWidgets('I-2: a joined emoji is said under its answer, never sent', (
      t,
    ) async {
      final setup = _HeldPrompts(profile: saved);
      await _open10(t, setup);
      await answer(t, 'ask_me_about', 'Ask me about my cooking 👩🏾‍🍳');
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(under('ask_me_about', invisible), findsOneWidget);
      expect(under('perfect_sunday', invisible), findsNothing);
      expect(setup.writes, isEmpty);
    });

    for (final (name, char) in [
      ('zero-width space', '\u200b'),
      ('a direction mark', '\u202a'),
      ('a word joiner', '\u2060'),
      ('a byte-order mark', '\ufeff'),
      ('a right-to-left mark', '\u200f'),
    ]) {
      testWidgets('I-2: $name is said and never sent', (t) async {
        final setup = _HeldPrompts(profile: saved);
        await _open10(t, setup);
        await answer(t, 'perfect_sunday', 'A long${char}walk, then lunch.');
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(under('perfect_sunday', invisible), findsOneWidget);
        expect(setup.writes, isEmpty);
      });
    }

    testWidgets('I-2: an answer with no letter or number is said', (t) async {
      final setup = _HeldPrompts(profile: saved);
      await _open10(t, setup);
      await answer(t, 'ask_me_about', '!!! ??? ... 🙂🙂');
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        under('ask_me_about', 'Add a few words, not just emoji or symbols.'),
        findsOneWidget,
      );
      expect(setup.writes, isEmpty);
    });

    testWidgets('I-2, M-5: too short after the spaces go is said under its '
        'own prompt', (t) async {
      final setup = _HeldPrompts(profile: saved);
      await _open10(t, setup);
      await answer(t, 'ask_me_about', '   Hi there      ');
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(under('ask_me_about', 'At least 10 characters.'), findsOneWidget);
      expect(under('perfect_sunday', 'At least 10 characters.'), findsNothing);
      expect(setup.writes, isEmpty);
    });

    testWidgets('I-2: plain emoji are fine and sent', (t) async {
      final setup = _HeldPrompts(profile: saved);
      await _open10(t, setup);
      await answer(t, 'ask_me_about', 'Coffee and long walks 🙂☕');
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.writes, ['savePrompts']);
    });

    testWidgets('I-2: an answer the server still refuses as invalid is the '
        'generic line under it', (t) async {
      final setup = _HeldPrompts(profile: saved)
        ..answer = const DatingWrite(
          ok: false,
          reason: 'invalid',
          field: 'answer',
          position: 2,
        );
      await _open10(t, setup);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.writes, ['savePrompts']);
      expect(
        under('ask_me_about', 'Something went wrong. Try again.'),
        findsOneWidget,
      );
      expect(under('ask_me_about', invisible), findsNothing);
    });

    testWidgets('M-5: at most 200 characters, counted as the server counts', (
      t,
    ) async {
      final setup = _HeldPrompts(profile: saved);
      await _open10(t, setup);
      // 150 letters each with a combining accent: 150 shown, 300 counted.
      await answer(t, 'ask_me_about', 'e\u0301' * 150);
      expect(_typed(t, 'ask_me_about').runes.length, 200);
      expect(find.text('200 of 200 characters'), findsOneWidget);
    });

    testWidgets('M-6: a refusal stays on its prompt when the ticks change', (
      t,
    ) async {
      final setup = _HeldPrompts(
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('feel_at_home', 'Cooking for my friends.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      )..answer = const DatingWrite(ok: false, reason: 'unkind', position: 3);
      await _open10(t, setup);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      const kind = "Please rephrase this so it's kind to everyone.";
      expect(under('ask_me_about', kind), findsOneWidget);
      await tapInReach(
        t,
        find.widgetWithText(CheckboxListTile, 'I feel most at home when…'),
      );
      await t.pumpAndSettle();
      expect(under('ask_me_about', kind), findsOneWidget);
      expect(find.text(kind), findsOneWidget);
    });
  });

  test(
    'I-3: the picker asks for no full metadata (no library permission)',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(datingPhotoPickerProvider)(), isNull);
      expect(calls.single.method, 'pickImage');
      expect((calls.single.arguments as Map)['requestFullMetadata'], isFalse);
    },
  );

  // ---- T10 fix round 2 (re-review 1): the letter-or-digit rule as the
  // server's pg_c_utf8 [[:alnum:]] (Unicode Alphabetic, ASCII 0-9 only;
  // each case read on attune_spec3a), and the caption counter.
  group('fix 2', () {
    const saved = DatingMyProfile(
      prompts: [
        ('perfect_sunday', 'A long walk, then lunch.'),
        ('ask_me_about', 'My grandmother stories.'),
      ],
    );
    const needsWords = 'Add a few words, not just emoji or symbols.';

    for (final (name, text, sent) in [
      ('circled digits', '\u2460' * 10, false),
      ('Arabic-Indic digits', '\u0663' * 10, false),
      ('superscripts and fractions', '\u00b2\u00bd' * 5, false),
      ('circled letters', '\u24b6' * 10, true),
      ('a Devanagari vowel sign', '\u093f' * 10, true),
    ]) {
      testWidgets('N-2: $name ${sent ? 'are sent' : 'are refused'}, as the '
          'server reads them', (t) async {
        final setup = _HeldPrompts(profile: saved);
        await _open10(t, setup);
        await t.enterText(
          find.byKey(const ValueKey('dating_prompt_ask_me_about')),
          text,
        );
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        if (sent) {
          expect(setup.writes, ['savePrompts']);
          expect(find.text(needsWords), findsNothing);
        } else {
          expect(setup.writes, isEmpty);
          expect(find.text(needsWords), findsOneWidget);
        }
      });
    }

    testWidgets('N-1: the caption counter follows the typing', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [photo(1, 'approved')],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await _open9(t, gateway: gateway);
      await tapInReach(t, find.byTooltip('Add a caption (only you see it)'));
      await t.pumpAndSettle();
      expect(find.text('0 of 100 characters'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Caption'), 'Beach');
      await t.pump();
      expect(find.text('5 of 100 characters'), findsOneWidget);
    });
  });

  // ---- T10 hardening: a refusal said on a slot stays through the next
  // list; it goes only when that slot's photo changes.
  testWidgets('hardening: a named add refusal stays after the next list, '
      'and goes once the slot holds a photo', (t) async {
    final r = await _open9(t);
    r.gateway.addAnswer = const DatingWrite(ok: false, reason: 'rate_limited');
    await tapInReach(t, find.widgetWithText(TextButton, 'Add photo').first);
    await _settleIo(t);
    const line = "You've done this a lot today. Try again tomorrow.";
    expect(find.text(line), findsOneWidget);
    await _recheck(t);
    expect(find.text(line), findsOneWidget);
    r.gateway.photos = [photo(1, 'pending')];
    await _recheck(t);
    expect(find.text(line), findsNothing);
  });
}

/// Server text that must never reach the screen (it names a phone number).
const _leaky = 'photos: +233 24 555 0101 refused';

/// A real 2 x 2 PNG: the bytes an approved photo's read answers.
final _png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

/// The next check of the list (what the step's 4 s poll does; a timer made
/// while [_settleIo] runs real I/O is not on the test clock).
Future<void> _recheck(WidgetTester t) async {
  _c(t).invalidate(datingPhotosProvider('ama'));
  await _settleIo(t);
}

/// Every photo on screen, local or read (the step's thumbnails).
List<MemoryImage> _previews(WidgetTester t) => [
  for (final w in t.widgetList<Image>(find.byType(Image, skipOffstage: false)))
    if (_memory(w.image) case final m?) m,
];

MemoryImage? _memory(ImageProvider image) => switch (image) {
  MemoryImage() => image,
  ResizeImage(imageProvider: final MemoryImage inner) => inner,
  _ => null,
};

/// The slot's Add photo buttons (a disabled one is a real disabled button).
Finder get _adds => find.widgetWithText(TextButton, 'Add photo');

bool _enabled(WidgetTester t, Finder button) =>
    t.widget<TextButton>(button).onPressed != null;

String _typed(WidgetTester t, String id) =>
    t
        .widget<TextField>(find.byKey(ValueKey('dating_prompt_$id')))
        .controller!
        .text;

class _Prep9 extends _Prep {
  _Prep9(super.dir, {this.hold, this.refuse = false});
  final Completer<void>? hold;
  final bool refuse;
  @override
  Future<PreparedDatingImage> prepare(String localPath) async {
    final h = hold;
    if (h != null) await h.future;
    if (refuse) throw const DatingImageRejected('media_decode_failed');
    return super.prepare(localPath);
  }
}

/// Final fix (M-16): Remove asks first; this says yes.
Future<void> _confirmRemove(WidgetTester t) async {
  await t.pumpAndSettle();
  await tapInReach(t, find.widgetWithText(TextButton, 'Remove'));
  await t.pumpAndSettle();
}

class _Run9 {
  _Run9(this.gateway, this.dir, this.steps, this.pickCount);
  final FakeDatingPhotosGateway gateway;
  final Directory dir;
  final List<String> steps;
  final int Function() pickCount;
  int get picks => pickCount();
}

/// D9 alone, with the seams the carries need (the brief's [_photos] kept).
Future<_Run9> _open9(
  WidgetTester t, {
  FakeDatingPhotosGateway? gateway,
  Completer<void>? holdPicker,
  Completer<void>? holdPrepare,
  bool refuse = false,
  ThemeData? theme,
  Object? pickError,
  Object? cropError,
  Stream<bool>? online,
}) async {
  DatingPhotosStep.debugAddsInFlight = 0;
  await t.pumpWidget(const SizedBox());
  final dir = Directory.systemTemp.createTempSync('d9');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final g =
      gateway ??
      FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1));
  final steps = <String>[];
  var picks = 0;
  Future<String?> pick() async {
    picks++;
    final h = holdPicker;
    if (h != null) await h.future;
    // A picker that fails hands back no file.
    final error = pickError;
    if (error != null) throw error;
    final picked = File('${dir.path}/picked_$picks.jpg')
      ..writeAsBytesSync(List.filled(10, 2));
    return picked.path;
  }

  Future<String?> crop(String path) async {
    final error = cropError;
    if (error != null) throw error;
    return path;
  }

  Widget screen() => DatingPhotosStep(
    nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
  );
  await pumpFlowScreen(
    t,
    () => theme == null ? screen() : Theme(data: theme, child: screen()),
    overrides: [
      ...datingShellOverrides(),
      datingPhotosGatewayProvider.overrideWithValue(g),
      datingImagePreparerProvider.overrideWithValue(
        _Prep9(dir, hold: holdPrepare, refuse: refuse),
      ),
      datingPhotoPickerProvider.overrideWithValue(pick),
      datingPhotoCropperProvider.overrideWithValue(crop),
      if (online != null) datingOnlineProvider.overrideWith((ref) => online),
    ],
  );
  await t.pumpAndSettle();
  return _Run9(g, dir, steps, () => picks);
}

/// The setup fake with a prompts write that waits for [hold] and a profile
/// read that can fail.
class _HeldPrompts extends FakeDatingSetupGateway {
  _HeldPrompts({super.profile});
  Completer<void>? hold;
  Object? profileError;

  @override
  Future<DatingMyProfile> myProfile() async {
    final error = profileError;
    if (error != null) throw error;
    return super.myProfile();
  }

  @override
  Future<DatingWrite> savePrompts(
    String key,
    List<(String, String)> items,
  ) async {
    final h = hold;
    if (h != null) await h.future;
    return super.savePrompts(key, items);
  }
}

Future<List<String>> _open10(
  WidgetTester t,
  FakeDatingSetupGateway setup, {
  ThemeData? theme,
}) async {
  await t.pumpWidget(const SizedBox());
  final steps = <String>[];
  Widget screen() => DatingPromptsStep(
    nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
  );
  await pumpFlowScreen(
    t,
    () => theme == null ? screen() : Theme(data: theme, child: screen()),
    overrides: [
      ...datingShellOverrides(),
      datingSetupGatewayProvider.overrideWithValue(setup),
    ],
  );
  await t.pump();
  return steps;
}
