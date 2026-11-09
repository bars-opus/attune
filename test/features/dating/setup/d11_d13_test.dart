// Spec 2 W3c (§3.2 D11-D13, §3.4, §3.15, S17): verify shell, preview, ready.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/preview_step.dart';
import 'package:attune/features/dating/setup/ready_step.dart';
import 'package:attune/features/dating/setup/verify_step.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_private_keyboard.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Preview implements DatingPreviewGateway {
  _Preview(this.card);
  DatingCard? card;
  Object? error;
  Completer<DatingCard?>? hold;
  int reads = 0;
  @override
  Future<DatingCard?> preview() async {
    reads++;
    if (error != null) throw error!;
    final h = hold;
    if (h != null) return h.future;
    return card;
  }
}

final _ama = DatingCard.fromJson({
  'display_name': 'Ama',
  'age': 29,
  'region_name_key': 'dating_region_gh_aa',
  'intention': 'marriage',
  'marriage_timeline': 'within_two_years',
  'children_have': false,
  'children_want': 'yes',
  'gender': null,
  'pronouns': null,
  'faith': {'faith': 'christian', 'denomination': 'methodist'},
  'marital': null,
  'prompts': [
    {
      'prompt_id': 'perfect_sunday',
      'answer': 'Church, then jollof with my sisters.',
    },
    {'prompt_id': 'ask_me_about', 'answer': 'My grandmother stories.'},
  ],
  'photos_after_mutual': false,
  'photos': [
    {'id': 'p1', 'position': 1},
    {'id': 'p2', 'position': 2},
  ],
});

typedef _Nav = ({List<String> steps, List<String> me});

DatingStepNav _nav(_Nav n) =>
    DatingStepNav(next: n.steps.add, back: () {}, toMe: () => n.me.add('me'));

/// A Safety PIN store (cheap hashing). pumpFlowScreen empties the keystore
/// mock, so the PIN is set after the screen is pumped.
SafetyPinStore _store() => SafetyPinStore(
  hasher: (p) async => hashPin(p, iterations: 1000),
  verifier: (p, e) async => verifyPinHash(p, e),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('D11 shell: the intro copy, Continue opens the preview (R-26)', (
    t,
  ) async {
    final n = (steps: <String>[], me: <String>[]);
    await pumpFlowScreen(
      t,
      () => DatingVerifyStep(nav: _nav(n)),
      overrides: datingShellOverrides(),
    );
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsOneWidget);
    expect(find.text('Step 10 of 12'), findsOneWidget);
    expect(
      find.textContaining('The video is deleted at once.'),
      findsOneWidget,
    );
    await tapInReach(t, find.text('Continue'));
    expect(n.steps, ['preview']);
  });

  group('D12', () {
    Future<(FakeDatingSetupGateway, FakePushAsker, _Nav, _Preview)> preview(
      WidgetTester t, {
      DatingCard? card,
      bool granted = false,
      bool grantOnAsk = true,
      DatingMyProfile profile = const DatingMyProfile(displayName: 'Ama'),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(profile: profile);
      final asker = FakePushAsker(granted: granted, grantOnAsk: grantOnAsk);
      final n = (steps: <String>[], me: <String>[]);
      final gateway = _Preview(card ?? _ama);
      await pumpFlowScreen(
        t,
        () => DatingPreviewStep(nav: _nav(n)),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(setup),
          datingPreviewGatewayProvider.overrideWithValue(gateway),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(
              photos: [photo(1, 'approved'), photo(2, 'approved')],
            ),
          ),
          pushAskerProvider.overrideWithValue(asker),
        ],
      );
      await t.pumpAndSettle();
      return (setup, asker, n, gateway);
    }

    testWidgets('the card, person first, in the order others read it', (
      t,
    ) async {
      await preview(t);
      expect(find.text('This is what others see'), findsOneWidget);
      expect(find.text('Step 11 of 12'), findsOneWidget);
      final order = [
        'Ama, 29',
        'Looking for marriage, in the next year or two',
        'A perfect Sunday for me looks like…',
        'No children',
        'Methodist',
      ];
      double y(String s) => t.getTopLeft(find.textContaining(s).first).dy;
      for (var i = 1; i < order.length; i++) {
        expect(
          y(order[i - 1]),
          lessThan(y(order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      expect(
        find.text(
          "Never shown: who you'd like to meet, your exact location, your date of birth.",
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'photos after mutual interest: the card says so and shows none',
      (t) async {
        await preview(
          t,
          card: DatingCard.fromJson({
            'display_name': 'Ama',
            'age': 29,
            'photos_after_mutual': true,
            'photos': [],
            'prompts': [],
          }),
        );
        expect(
          find.text("Photos appear after you're both interested."),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp(r'^Photo 1 of')), findsNothing);
      },
    );

    testWidgets('data saver: photos wait for a tap', (t) async {
      await preview(
        t,
        profile: const DatingMyProfile(displayName: 'Ama', dataSaver: true),
      );
      expect(find.text('Show photos (about 1 MB)'), findsOneWidget);
    });

    testWidgets('first name: 1 to 30 characters, saved through its writer', (
      t,
    ) async {
      final (setup, _, _, _) = await preview(t);
      await tapInReach(t, find.text('Edit first name'));
      await t.pumpAndSettle();
      expect(
        find.text('Use your first name or what friends call you.'),
        findsOneWidget,
      );
      // Final fix (M-12): the keyboard learns nothing from the name.
      expectPrivateKeyboard(t, find.byKey(const ValueKey('dating_name_field')));
      await t.enterText(find.byKey(const ValueKey('dating_name_field')), '   ');
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Use 1 to 30 characters.'), findsOneWidget);
      expect(setup.writes, isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('dating_name_field')),
        ' Ama B ',
      );
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$1, 'saveDisplayName');
      expect(setup.lastWrite.$2['name'], 'Ama B');
    });

    testWidgets('edit links reopen the step and come back (R-40)', (t) async {
      final (_, _, n, _) = await preview(t);
      await tapInReach(t, find.text('Edit your answers'));
      expect(n.steps, ['prompts?from=preview']);
    });

    testWidgets('Turn on asks in context, then saves the digest (R-27)', (
      t,
    ) async {
      final (setup, asker, _, _) = await preview(t);
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Tell me when someone messages me',
              ),
            )
            .onChanged,
        isNull,
      );
      await tapInReach(t, find.text('Turn on'));
      await t.pumpAndSettle();
      expect(asker.asked, [PushAskContext.j3]);
      expect(setup.lastWrite.$2['values'], {'digest_push': true});
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Tell me when someone messages me',
              ),
            )
            .onChanged,
        isNotNull,
      );
    });

    testWidgets('a declined ask saves nothing', (t) async {
      final (setup, _, _, _) = await preview(t, grantOnAsk: false);
      await tapInReach(t, find.text('Turn on'));
      await t.pumpAndSettle();
      expect(setup.writes, isEmpty);
    });

    testWidgets('an unreadable preview says so and can be retried', (t) async {
      await t.pumpWidget(const SizedBox());
      final gateway = _Preview(_ama)..error = StateError('preview:unavailable');
      await pumpFlowScreen(
        t,
        () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPreviewGatewayProvider.overrideWithValue(gateway),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
        ],
      );
      await t.pumpAndSettle();
      expect(
        find.text("Your preview can't be shown right now."),
        findsOneWidget,
      );
      gateway.error = null;
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Ama, 29'), findsOneWidget);
    });

    testWidgets('Continue opens D13', (t) async {
      final (_, _, n, _) = await preview(t);
      await tapInReach(t, find.text('Continue'));
      expect(n.steps, ['ready']);
    });
  });

  group('D13', () {
    Future<(FakeDatingSetupGateway, FakeDatingLifecycleGateway, _Nav)> ready(
      WidgetTester t, {
      SafetyPinStore? pins,
      bool online = true,
      DatingLifecycleResult result = const DatingLifecycleResult.done('active'),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(
        profile: const DatingMyProfile(dropTime: '19:00:00'),
      );
      final life = FakeDatingLifecycleGateway()..result = result;
      final home = FakeDatingHomeGateway(
        home: DatingHome(
          state: DatingHomeState.setupInProgress,
          firstDropAt: DateTime.utc(2026, 12, 1, 19),
        ),
      );
      final n = (steps: <String>[], me: <String>[]);
      await pumpFlowScreen(
        t,
        () => DatingReadyStep(nav: _nav(n), pins: pins),
        overrides: [
          ...datingShellOverrides(home: home, life: life, online: online),
          datingSetupGatewayProvider.overrideWithValue(setup),
        ],
      );
      await t.pumpAndSettle();
      return (setup, life, n);
    }

    test('the drop times: 07:00 to 22:00 in 30-minute steps', () {
      expect(datingDropTimes.length, 31);
      expect(datingDropTimes.first, '07:00');
      expect(datingDropTimes.last, '22:00');
      expect(datingDropTimes, contains('19:30'));
    });

    testWidgets('the first drop, the time picker, one item while you wait', (
      t,
    ) async {
      final (setup, _, _) = await ready(t);
      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Step 12 of 12'), findsOneWidget);
      expect(
        find.textContaining('Your first introductions arrive '),
        findsOneWidget,
      );
      expect(find.text('Write in your journal'), findsOneWidget);
      expect(find.textContaining('app icon'), findsNothing);
      await tapInReach(t, find.text('Change time'));
      await t.pumpAndSettle();
      expect(
        find.text('Pick a time when you have a few quiet minutes.'),
        findsOneWidget,
      );
      await tapInReach(t, find.text(datingDropTimeLabel('07:30')));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['values'], {'drop_time': '07:30'});
    });

    testWidgets(
      'shared phone: No shows nothing more; Yes offers the lock and every-open (S17)',
      (t) async {
        final pins = _store();
        await ready(t, pins: pins);
        await pins.setPin('2580');
        await tapInReach(t, find.text('No'));
        await t.pumpAndSettle();
        expect(find.text('Lock Dating with your PIN'), findsNothing);
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        await tapInReach(
          t,
          find.widgetWithText(SwitchListTile, 'Lock Dating with your PIN'),
        );
        await t.pumpAndSettle();
        final container = ProviderScope.containerOf(
          t.element(find.byType(DatingReadyStep)),
        );
        expect(container.read(datingLockProvider).valueOrNull, isTrue);
        await tapInReach(
          t,
          find.widgetWithText(
            SwitchListTile,
            'Ask for my PIN every time Attune opens',
          ),
        );
        await t.pumpAndSettle();
        expect(await pins.everyOpen(), isTrue);
      },
    );

    testWidgets('Done activates, then Me', (t) async {
      final (_, life, n) = await ready(t);
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.calls, ['activate']);
      expect(n.me, ['me']);
    });

    testWidgets(
      'before W4a: activation waits for the check, with a way to it (R-26)',
      (t) async {
        final (_, _, n) = await ready(
          t,
          result: const DatingLifecycleResult.refused(
            DatingLifecycleError.activationGatesNotMet,
          ),
        );
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        expect(n.me, isEmpty);
        expect(
          find.text(
            "We still need to check it's you before introductions start.",
          ),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Verify it's you"));
        expect(n.steps, ['verify?from=ready']);
      },
    );

    testWidgets('offline: Done is off', (t) async {
      final (_, life, _) = await ready(t, online: false);
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.calls, isEmpty);
    });
  });

  testWidgets('guidelines: D12 and D13', (t) async {
    final semantics = t.ensureSemantics();
    await pumpFlowScreen(
      t,
      () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
    await t.pumpAndSettle();
    await expectFlowGuidelines(t);
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => DatingReadyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      ],
    );
    await t.pumpAndSettle();
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  testWidgets('d11_verify goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd11_verify',
      () => DatingVerifyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: datingShellOverrides(),
    );
  });

  testWidgets('d12_preview goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd12_preview',
      () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(displayName: 'Ama'),
          ),
        ),
        datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
  });

  // T11 fix 1 (M-7): the card's photo part, neutral slots for photos still
  // checked (no byte read), scrolled into view.
  testWidgets('d12_card_photos goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd12_card_photos',
      () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(displayName: 'Ama'),
          ),
        ),
        datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(
            photos: [photo(1, 'pending'), photo(2, 'pending')],
          ),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
      before: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('dating_card_dots')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('d13_ready goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd13_ready',
      () => DatingReadyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: DatingHome(
              state: DatingHomeState.setupInProgress,
              firstDropAt: DateTime.utc(2026, 12, 1, 19),
            ),
          ),
        ),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      ],
    );
  });
  // ---- T11 carries (controller A-H).
  group('carries', () {
    Future<
      (
        FakeDatingSetupGateway,
        FakeDatingPhotosGateway,
        _Preview,
        _Nav,
        FakePushAsker,
      )
    >
    open12(
      WidgetTester t, {
      DatingCard? card,
      List<DatingProfilePhoto>? photos,
      FakeDatingSetupGateway? setup,
      FakePushAsker? asker,
      ThemeData? theme,
      double textScale = 1.0,
      bool online = true,
    }) async {
      await t.pumpWidget(const SizedBox());
      final s = setup ?? FakeDatingSetupGateway(profile: _amaProfile);
      final g = FakeDatingPhotosGateway(
        photos: photos ?? [photo(1, 'approved'), photo(2, 'approved')],
      );
      for (final k in ['k1', 'k2', 'k3', 'k4']) {
        g.stored[k] = _png;
      }
      final a = asker ?? FakePushAsker();
      final preview = _Preview(card ?? _ama);
      final n = (steps: <String>[], me: <String>[]);
      Widget screen() => DatingPreviewStep(nav: _nav(n));
      await pumpFlowScreen(
        t,
        () => theme == null ? screen() : Theme(data: theme, child: screen()),
        textScale: textScale,
        overrides: [
          ...datingShellOverrides(online: online),
          datingSetupGatewayProvider.overrideWithValue(s),
          datingPreviewGatewayProvider.overrideWithValue(preview),
          datingPhotosGatewayProvider.overrideWithValue(g),
          pushAskerProvider.overrideWithValue(a),
        ],
      );
      await _settle(t);
      return (s, g, preview, n, a);
    }

    Future<(FakeDatingSetupGateway, _HeldLife, FakeDatingHomeGateway, _Nav)>
    open13(
      WidgetTester t, {
      FakeDatingSetupGateway? setup,
      DatingLifecycleGateway? gateway,
      ThemeData? theme,
      double textScale = 1.0,
      SafetyPinStore? pins,
      bool online = true,
    }) async {
      await t.pumpWidget(const SizedBox());
      final s =
          setup ??
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(dropTime: '19:00:00'),
          );
      final life = _HeldLife();
      final home = FakeDatingHomeGateway(
        home: DatingHome(
          state: DatingHomeState.setupInProgress,
          firstDropAt: DateTime.utc(2026, 12, 1, 19),
        ),
      );
      final n = (steps: <String>[], me: <String>[]);
      Widget screen() => DatingReadyStep(nav: _nav(n), pins: pins);
      await pumpFlowScreen(
        t,
        () => theme == null ? screen() : Theme(data: theme, child: screen()),
        textScale: textScale,
        overrides: [
          ...datingShellOverrides(home: home, life: life, online: online),
          datingSetupGatewayProvider.overrideWithValue(s),
          if (gateway != null)
            datingLifecycleGatewayProvider.overrideWithValue(gateway),
        ],
      );
      await t.pumpAndSettle();
      return (s, life, home, n);
    }

    ProviderContainer c(WidgetTester t) =>
        ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

    testWidgets('A: a named refusal gives the next Done a new key; busy and '
        'failed keep it, so the retry is the same request', (t) async {
      final (_, life, _, _) = await open13(t);
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.activationGatesNotMet,
      );
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.keys, hasLength(2));
      expect(life.keys[1], isNot(life.keys[0]));
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.busy,
      );
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.failed,
      );
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      life.result = const DatingLifecycleResult.done('active');
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.keys, hasLength(5));
      expect(life.keys[2], isNot(life.keys[1]));
      expect(life.keys[3], life.keys[2]);
      expect(life.keys[4], life.keys[2]);
    });

    testWidgets('A: a setup write keeps its key through busy and settles it '
        'once saved', (t) async {
      final (setup, _, _, _, _) = await open12(
        t,
        asker: FakePushAsker(granted: true),
      );
      final messages = find.widgetWithText(
        SwitchListTile,
        'Tell me when someone messages me',
      );
      setup.answer = DatingWrite.busy;
      await tapInReach(t, messages);
      await t.pumpAndSettle();
      await tapInReach(t, messages);
      await t.pumpAndSettle();
      setup.answer = const DatingWrite(ok: true);
      await tapInReach(t, messages);
      await t.pumpAndSettle();
      await tapInReach(t, messages);
      await t.pumpAndSettle();
      final keys = [
        for (final w in setup.calls)
          if (w.$1 == 'saveSettings') w.$2['key'],
      ];
      expect(keys, hasLength(4));
      expect(keys[1], keys[0]);
      expect(keys[2], keys[0]);
      expect(keys[3], isNot(keys[0]));
    });

    testWidgets('B: every activation refusal is the app\'s own copy, and '
        'never moves on', (t) async {
      const generic = 'Something went wrong. Try again.';
      final copy = {
        DatingLifecycleError.pathNotDating:
            'Choose Dating in How you use Attune to carry on.',
        DatingLifecycleError.notPaused: generic,
        DatingLifecycleError.activationRequired:
            'Finish setting up Dating first.',
        DatingLifecycleError.resumeGatesNotMet:
            "Dating can't resume on this account right now.",
        DatingLifecycleError.activationGatesNotMet:
            "We still need to check it's you before introductions start.",
        DatingLifecycleError.enrollmentIncomplete:
            'Finish setting up Dating first.',
        DatingLifecycleError.consentRequired:
            "Agree to Dating's terms again to carry on.",
        DatingLifecycleError.profileIncomplete:
            'Finish setting up Dating first.',
        DatingLifecycleError.reverifyDevice:
            "Confirm it's you on this phone to see Dating.",
        DatingLifecycleError.notEligible:
            "Dating isn't available on this account right now.",
        DatingLifecycleError.rateLimited:
            "You've done this a lot today. Try again tomorrow.",
        DatingLifecycleError.busy:
            'This is taking a little longer than usual. Try again in a moment.',
        DatingLifecycleError.failed: generic,
      };
      expect(copy.keys.toSet(), DatingLifecycleError.values.toSet());
      for (final MapEntry(key: error, value: text) in copy.entries) {
        final (_, life, _, n) = await open13(t);
        life.result = DatingLifecycleResult.refused(error);
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: '$error');
        expect(n.me, isEmpty, reason: '$error');
      }
    });

    testWidgets('B: the server\'s own text never shows, whatever it says', (
      t,
    ) async {
      for (final message in [
        'activation_gates_not_met',
        'Ama Mensah, born 1997-03-02, +233 20 000 0000',
      ]) {
        final rpc = ScriptedRpc([
          (_, __) => PostgrestException(
            message: message,
            code: 'P0001',
            details: 'Ama Mensah 1997-03-02',
            hint: 'Ama',
          ),
        ]);
        await open13(t, gateway: DatingLifecycleRepository(rpc.rpc));
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        expect(rpc.calls.single.$1, 'activate_dating_profile');
        expect(find.textContaining('Ama'), findsNothing, reason: message);
        expect(find.textContaining('1997'), findsNothing, reason: message);
      }
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('C: one Done at a time: a double tap activates once', (
      t,
    ) async {
      final (_, life, _, n) = await open13(t);
      life.hold = Completer<void>();
      await t.tap(find.text('Done'));
      await t.pump();
      await t.tap(find.text('Done'), warnIfMissed: false);
      await t.pump();
      life.hold!.complete();
      await t.pumpAndSettle();
      expect(life.calls, ['activate']);
      expect(n.me, ['me']);
    });

    testWidgets('C: one ask at a time: a double tap on Turn on asks once', (
      t,
    ) async {
      final asker = _HeldAsker();
      final (setup, _, _, _, _) = await open12(t, asker: asker);
      await tapInReach(t, find.text('Turn on'));
      await t.pump();
      await tapInReach(t, find.text('Turn on'));
      await t.pump();
      asker.hold.complete();
      await t.pumpAndSettle();
      expect(asker.asked, [PushAskContext.j3]);
      expect(setup.writes, ['saveSettings']);
    });

    testWidgets('C: a name typed before the saved one arrives is kept, and '
        'Save waits for it', (t) async {
      final held = FakeDatingSetupGateway(profile: _amaProfile)
        ..holdProfile = Completer<DatingMyProfile>();
      await open12(t, setup: held);
      await tapInReach(t, find.text('Edit first name'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_name_field')),
        'Kwame',
      );
      await t.pump();
      expect(
        t
            .widget<FlowSecondaryButton>(
              find.widgetWithText(FlowSecondaryButton, 'Save'),
            )
            .onPressed,
        isNull,
      );
      held.holdProfile!.complete(_amaProfile);
      held.holdProfile = null;
      await _settle(t);
      expect(find.widgetWithText(TextField, 'Kwame'), findsOneWidget);
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(held.lastWrite.$1, 'saveDisplayName');
      expect(held.lastWrite.$2['name'], 'Kwame');
    });

    testWidgets('C: a failed saved-answers read is generic copy with Retry', (
      t,
    ) async {
      final held = FakeDatingSetupGateway(
        profile: const DatingMyProfile(dropTime: '19:00:00'),
      )..holdProfile = Completer<DatingMyProfile>();
      await open13(t, setup: held);
      held.holdProfile!.completeError(StateError('profile:Ama'));
      held.holdProfile = null;
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('Ama'), findsNothing);
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });

    testWidgets('D8: D12 shows nothing of the last account (card, prompts, '
        'photos, typed name) while the next one\'s read is held', (t) async {
      final (setup, photos, preview, _, _) = await open12(t);
      expect(_memoryImages(), findsWidgets);
      await tapInReach(t, find.text('Edit first name'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('dating_name_field')),
        'Ama B',
      );
      await t.pump();
      preview.hold = Completer<DatingCard?>();
      photos.holdList = Completer<DatingPhotoList>();
      setup.holdProfile = Completer<DatingMyProfile>();
      c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(find.textContaining('Ama'), findsNothing);
        expect(find.textContaining('jollof'), findsNothing);
        expect(find.textContaining('grandmother'), findsNothing);
        expect(find.textContaining('Methodist'), findsNothing);
        expect(_memoryImages(), findsNothing);
        expect(find.byKey(const ValueKey('dating_name_field')), findsNothing);
      }
      preview.hold!.complete(
        DatingCard.fromJson({
          'display_name': 'Kofi',
          'age': 31,
          'photos': [],
          'prompts': [],
        }),
      );
      photos.holdList!.complete(const DatingPhotoList());
      setup.holdProfile!.complete(const DatingMyProfile(displayName: 'Kofi'));
      await _settle(t);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(find.textContaining('Ama'), findsNothing);
      expect(_memoryImages(), findsNothing);
      await tapInReach(t, find.text('Edit first name'));
      await t.pump();
      expect(find.widgetWithText(TextField, 'Kofi'), findsOneWidget);
    });

    testWidgets('D8: D13 shows nothing of the last account (first drop, '
        'answer, refusal) while the next one\'s read is held', (t) async {
      final (_, life, home, _) = await open13(t);
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.pathNotDating,
      );
      await tapInReach(t, find.text('Yes'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(
        find.text('Choose Dating in How you use Attune to carry on.'),
        findsOneWidget,
      );
      expect(find.text('Lock Dating with your PIN'), findsOneWidget);
      home.hold = Completer<DatingHome>();
      c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(
          find.textContaining('Your first introductions arrive'),
          findsNothing,
        );
        expect(find.text('Lock Dating with your PIN'), findsNothing);
        expect(
          find.text('Choose Dating in How you use Attune to carry on.'),
          findsNothing,
        );
      }
      home.hold!.complete(const DatingHome(state: DatingHomeState.notStarted));
      await t.pumpAndSettle();
      expect(find.text('Lock Dating with your PIN'), findsNothing);
    });

    testWidgets('D: only an approved photo is read from the server; a pending '
        'one is a neutral slot; rejected, waiting and a hit never show', (
      t,
    ) async {
      final card = DatingCard.fromJson({
        'display_name': 'Ama',
        'age': 29,
        'prompts': [],
        'photos': [
          for (var i = 1; i <= 4; i++) {'id': 'p$i', 'position': i},
        ],
      });
      final (_, photos, _, _, _) = await open12(
        t,
        card: card,
        photos: [
          photo(1, 'approved'),
          photo(2, 'pending'),
          photo(3, 'rejected', reason: 'unsafe'),
          photo(4, 'needs_review', reason: 'needs_review'),
        ],
      );
      expect(photos.byteReads, ['k1']);
      expect(find.bySemanticsLabel('Photo 1 of 2'), findsOneWidget);
      expect(_memoryImages(), findsOneWidget);
      expect(
        PaintingBinding.instance.imageCache.containsKey(MemoryImage(_png)),
        isTrue,
      );
      // The scan of photo 1 matches: it never shows again, and its bytes go.
      photos.photos = [
        photo(1, 'rejected', reason: 'unsafe'),
        photo(2, 'pending'),
      ];
      c(t).invalidate(datingPhotosProvider('ama'));
      await _settle(t);
      expect(find.bySemanticsLabel('Photo 1 of 1'), findsOneWidget);
      expect(_memoryImages(), findsNothing);
      expect(photos.byteReads, ['k1']);
      // Its decoded image is gone from memory too, not just from the card.
      expect(
        PaintingBinding.instance.imageCache.containsKey(MemoryImage(_png)),
        isFalse,
      );
    });

    testWidgets('D: nothing is read before the person\'s list says approved', (
      t,
    ) async {
      await t.pumpWidget(const SizedBox());
      final g =
          FakeDatingPhotosGateway(photos: [photo(1, 'approved')])
            ..stored['k1'] = _png
            ..holdList = Completer<DatingPhotoList>();
      await pumpFlowScreen(
        t,
        () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: _amaProfile),
          ),
          datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
          datingPhotosGatewayProvider.overrideWithValue(g),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
        ],
      );
      await _settle(t);
      expect(find.bySemanticsLabel('Photo 1 of 2'), findsOneWidget);
      expect(g.byteReads, isEmpty);
      expect(_memoryImages(), findsNothing);
      g.holdList!.complete(DatingPhotoList(photos: [photo(1, 'approved')]));
      g.holdList = null;
      await _settle(t);
      expect(g.byteReads, ['k1']);
      expect(find.bySemanticsLabel('Photo 1 of 1'), findsOneWidget);
    });

    testWidgets('D: with data saver on, nothing is read until the tap', (
      t,
    ) async {
      final (_, photos, _, _, _) = await open12(
        t,
        setup: FakeDatingSetupGateway(
          profile: const DatingMyProfile(displayName: 'Ama', dataSaver: true),
        ),
      );
      expect(photos.byteReads, isEmpty);
      await tapInReach(t, find.text('Show photos (about 1 MB)'));
      await _settle(t);
      expect(photos.byteReads, ['k1', 'k2']);
    });

    testWidgets('E (R-38): the card has no "Why you two" and no Interested or '
        'Not for me', (t) async {
      await open12(t);
      for (final text in ['Why you two', 'Interested', 'Not for me']) {
        expect(find.textContaining(text), findsNothing, reason: text);
      }
    });

    test('E (R-40): from= is a token, never a path or typed text', () {
      expect(datingStepFrom('preview'), 'preview');
      expect(datingStepFrom('settings'), 'settings');
      for (final raw in [
        null,
        '',
        '/home',
        '/dating/settings',
        'https://evil.example',
        '//evil.example',
        'Ama',
      ]) {
        expect(datingStepFrom(raw), isNull, reason: raw);
      }
      expect(datingStepLocation('prompts'), '/dating/setup/prompts');
      expect(
        datingStepLocation('prompts?from=preview'),
        '/dating/setup/prompts?from=preview',
      );
      expect(
        datingStepLocation('prompts?from=https://evil.example'),
        '/dating/setup/prompts',
      );
      expect(
        datingStepLocation('prompts?from=preview&name=Ama'),
        '/dating/setup/prompts?from=preview',
      );
      for (final bad in ['../home', 'https://evil.example', '', 'a/b']) {
        expect(datingStepLocation(bad), isNull, reason: bad);
      }
    });

    testWidgets('E (R-40): a from= that isn\'t a token walks forward', (
      t,
    ) async {
      for (final from in ['%2Fhome', 'https%3A%2F%2Fevil.example', 'Ama']) {
        final shell = await pumpDatingShell(
          t,
          overrides: [
            datingPreviewGatewayProvider.overrideWithValue(
              FakeDatingPreviewGateway(),
            ),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        shell.router.push('${DatingPaths.step('verify')}?from=$from');
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(find.text('This is what others see'), findsOneWidget);
        expect(find.textContaining('ME '), findsNothing, reason: from);
      }
    });

    testWidgets('F: Done before W4a says the check is still to come, and the '
        'plain-icon offer stays hidden (R-26, A-11)', (t) async {
      final (_, life, _, _) = await open13(t);
      expect(find.textContaining('plain'), findsNothing);
      expect(find.textContaining('icon'), findsNothing);
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.activationGatesNotMet,
      );
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "We still need to check it's you before introductions start.",
        ),
        findsOneWidget,
      );
      expect(find.byType(FlowErrorLine), findsNothing);
    });

    testWidgets('G: D11-D13 open at their step paths, behind the Dating lock', (
      t,
    ) async {
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('preview'),
        locked: true,
        pinSet: true,
        overrides: [
          datingPreviewGatewayProvider.overrideWithValue(
            FakeDatingPreviewGateway(_ama),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
        ],
      );
      expect(s.location, startsWith('/dating/unlock?from='));
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
      expect(find.text('Ama, 29'), findsNothing);
      s.container.read(datingUnlockedProvider.notifier).unlock();
      for (final (step, screen) in [
        ('verify', DatingVerifyStep),
        ('preview', DatingPreviewStep),
        ('ready', DatingReadyStep),
      ]) {
        s.router.go(DatingPaths.step(step));
        await t.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: step);
        expect(s.location, DatingPaths.step(step));
      }
    });

    testWidgets('H: D11-D13 and the card in the dark theme: tokens only, '
        'contrast holds, the theme\'s own error red', (t) async {
      final semantics = t.ensureSemantics();
      final dark = AppTheme.darkTheme;
      for (final (theme, red) in [
        (dark, dark.colorScheme.error),
        (AppTheme.lightTheme, const Color(0xFFC62828)),
      ]) {
        void surfaces() => expect(
          t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          theme.colorScheme.surface,
        );
        final icon = find.descendant(
          of: find.byType(FlowErrorLine),
          matching: find.byType(Icon),
        );
        // D11.
        await t.pumpWidget(const SizedBox());
        await pumpFlowScreen(
          t,
          () => Theme(
            data: theme,
            child: DatingVerifyStep(
              nav: _nav((steps: <String>[], me: <String>[])),
            ),
          ),
          overrides: datingShellOverrides(),
        );
        await t.pumpAndSettle();
        surfaces();
        await expectFlowGuidelines(t);
        // D12 and the card: a neutral slot in the theme's colours.
        await open12(
          t,
          theme: theme,
          photos: [photo(1, 'pending'), photo(2, 'pending')],
        );
        surfaces();
        final slot = find.descendant(
          of: find.bySemanticsLabel('Photo 1 of 2'),
          matching: find.byType(ColoredBox),
        );
        expect(
          t.widget<ColoredBox>(slot.first).color,
          theme.colorScheme.surfaceContainerHighest,
        );
        await expectFlowGuidelines(t);
        // D13 with a refusal in error red.
        final (_, life, _, _) = await open13(t, theme: theme);
        surfaces();
        life.result = const DatingLifecycleResult.refused(
          DatingLifecycleError.pathNotDating,
        );
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        expect(t.widget<Icon>(icon.first).color, red);
        await expectFlowGuidelines(t);
      }
      expect(dark.colorScheme.error, const Color(0xFFEF5350));
      semantics.dispose();
    });

    testWidgets('H: the time sheet scales its text, and every time is in '
        'reach at 2.0', (t) async {
      final (setup, _, _, _) = await open13(t, textScale: 2.0);
      await tapInReach(t, find.text('Change time'));
      await t.pumpAndSettle();
      final title = find.text('Pick a time when you have a few quiet minutes.');
      expect(MediaQuery.textScalerOf(t.element(title)).scale(10), 20);
      // The last time, scrolled to in the sheet's own list.
      final last = find.text(datingDropTimeLabel('22:00'));
      await t.scrollUntilVisible(
        last,
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tapInReach(t, last);
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['values'], {'drop_time': '22:00'});
    });

    group('H: quick exit', () {
      setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
      setUp(() {
        QuickExitService.clearStories = () async {};
        addTearDown(
          () => QuickExitService.clearStories = clearStoryDeviceCaches,
        );
      });

      testWidgets('from D12 with a name typed: nothing of it stays', (t) async {
        await pumpDatingShell(
          t,
          initial: DatingPaths.step('preview'),
          wrap: (router, child) => QuickExitZone(router: router, child: child),
          overrides: [
            datingPreviewGatewayProvider.overrideWithValue(
              FakeDatingPreviewGateway(_ama),
            ),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(profile: _amaProfile),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        await tapInReach(t, find.text('Edit first name'));
        await t.pump();
        await t.enterText(
          find.byKey(const ValueKey('dating_name_field')),
          'Ama Typed',
        );
        await t.pump();
        for (var i = 0; i < 3; i++) {
          await t.tap(
            find.byKey(const Key('quick_exit_zone')),
            warnIfMissed: false,
          );
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('DECOY'), findsOneWidget);
        expect(find.text('Ama Typed', skipOffstage: false), findsNothing);
        expect(
          find.byType(DatingPreviewStep, skipOffstage: false),
          findsNothing,
        );
      });
    });
    // ---- T11 fix round 1 (review I-1, I-2, M-1..M-9).
    group('fix 1', () {
      testWidgets('I-1: opening D12 reads the card once', (t) async {
        final (_, _, preview, _, _) = await open12(t);
        expect(preview.reads, 1);
      });

      testWidgets('I-1: a changed saved answer reads the card again, once', (
        t,
      ) async {
        final (setup, _, preview, _, _) = await open12(t);
        setup.profile = const DatingMyProfile(
          displayName: 'Ama',
          prompts: [('perfect_sunday', 'A long walk by the sea.')],
        );
        preview.card = DatingCard.fromJson({
          'display_name': 'Ama',
          'age': 29,
          'prompts': [
            {
              'prompt_id': 'perfect_sunday',
              'answer': 'A long walk by the sea.',
            },
          ],
          'photos': [],
        });
        c(t).invalidate(datingMyProfileProvider('ama'));
        await _settle(t);
        expect(find.text('A long walk by the sea.'), findsOneWidget);
        expect(preview.reads, 2);
      });

      testWidgets('I-1: a changed photo reads the card again, once', (t) async {
        final (_, photos, preview, _, _) = await open12(t);
        photos.photos = [...photos.photos, photo(3, 'approved')];
        preview.card = DatingCard.fromJson({
          'display_name': 'Ama',
          'age': 29,
          'prompts': [],
          'photos': [
            for (var i = 1; i <= 3; i++) {'id': 'p$i', 'position': i},
          ],
        });
        c(t).invalidate(datingPhotosProvider('ama'));
        await _settle(t);
        expect(preview.reads, 2);
        expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);
      });

      testWidgets('I-1: the same photo list again reads nothing more (D9\'s '
          'checks)', (t) async {
        final (_, _, preview, _, _) = await open12(t);
        for (var i = 0; i < 3; i++) {
          c(t).invalidate(datingPhotosProvider('ama'));
          await _settle(t);
        }
        expect(preview.reads, 1);
      });

      testWidgets('I-1, D8: the next account reads its own card, once', (
        t,
      ) async {
        final (_, _, preview, _, _) = await open12(t);
        preview.card = DatingCard.fromJson({
          'display_name': 'Kofi',
          'age': 31,
          'prompts': [],
          'photos': [],
        });
        c(t).read(datingTestAccount.notifier).state = 'kofi';
        await _settle(t);
        expect(preview.reads, 2);
        expect(find.text('Kofi, 31'), findsOneWidget);
        expect(find.textContaining('Ama'), findsNothing);
      });

      testWidgets('M-9: a saved name reads the card again once', (t) async {
        final (setup, _, preview, _, _) = await open12(t);
        await tapInReach(t, find.text('Edit first name'));
        await t.pump();
        await t.enterText(
          find.byKey(const ValueKey('dating_name_field')),
          'Ama B',
        );
        await t.pump();
        // The server keeps the new name (the fake's profile is its store).
        setup.guard = (name, args) {
          if (name == 'saveDisplayName') {
            setup.profile = const DatingMyProfile(displayName: 'Ama B');
          }
        };
        await tapInReach(t, find.text('Save'));
        await _settle(t);
        expect(setup.lastWrite.$2['name'], 'Ama B');
        expect(preview.reads, 2);
      });

      testWidgets('I-2: faith, marital and gender each link to their own '
          'step, from the preview', (t) async {
        final card = DatingCard.fromJson({
          'display_name': 'Ama',
          'age': 29,
          'gender': {'identity': 'woman'},
          'faith': {'faith': 'christian', 'denomination': 'methodist'},
          'marital': 'widowed',
          'prompts': [],
          'photos': [],
        });
        final (_, _, _, n, _) = await open12(t, card: card);
        for (final (label, step) in [
          ('Edit what you show about yourself', 'you'),
          ('Edit faith', 'faith'),
          ('Edit marital status', 'looking-for'),
        ]) {
          await tapInReach(t, find.text(label));
          await t.pump();
          expect(n.steps.last, '$step?from=preview', reason: label);
        }
        // Each sits right after its own line.
        double y(String s) => t.getTopLeft(find.text(s)).dy;
        expect(y('Woman'), lessThan(y('Edit what you show about yourself')));
        expect(
          y('Edit what you show about yourself'),
          lessThan(y('Christian · Methodist')),
        );
        expect(y('Christian · Methodist'), lessThan(y('Edit faith')));
        expect(y('Edit faith'), lessThan(y('Widowed')));
        expect(y('Widowed'), lessThan(y('Edit marital status')));
      });

      testWidgets('I-2: a hidden faith can still be turned on from the '
          'preview; no marital link without the line', (t) async {
        final (_, _, _, n, _) = await open12(
          t,
          card: DatingCard.fromJson({
            'display_name': 'Ama',
            'age': 29,
            'prompts': [],
            'photos': [],
          }),
        );
        expect(find.text('Edit marital status'), findsNothing);
        await tapInReach(t, find.text('Edit faith'));
        expect(n.steps, ['faith?from=preview']);
      });

      testWidgets('I-2: Edit faith opens D8 and its Skip comes back to the '
          'preview', (t) async {
        await pumpDatingShell(
          t,
          initial: DatingPaths.step('preview'),
          overrides: [
            datingPreviewGatewayProvider.overrideWithValue(
              FakeDatingPreviewGateway(_ama),
            ),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(profile: _amaProfile),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        await tapInReach(t, find.text('Edit faith'));
        await t.pumpAndSettle();
        expect(find.text('This is what others see'), findsNothing);
        await tapInReach(t, find.text('Skip'));
        await t.pumpAndSettle();
        expect(find.text('This is what others see'), findsOneWidget);
      });

      testWidgets('M-1: one every-open change at a time', (t) async {
        final pins = _HeldPins();
        await open13(t, pins: pins);
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        final every = find.widgetWithText(
          SwitchListTile,
          'Ask for my PIN every time Attune opens',
        );
        await tapInReach(t, every);
        await t.pump();
        await tapInReach(t, every);
        await t.pump();
        pins.hold.complete(true);
        await t.pumpAndSettle();
        expect(pins.sets, [true]);
      });

      testWidgets('M-1: turning every-open off asks for the PIN; dismissed, '
          'it stays on', (t) async {
        final pins = _HeldPins(everyOpenOn: true)..hold.complete(true);
        await open13(t, pins: pins);
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        final every = find.widgetWithText(
          SwitchListTile,
          'Ask for my PIN every time Attune opens',
        );
        expect(t.widget<SwitchListTile>(every).value, isTrue);
        await tapInReach(t, every);
        await t.pumpAndSettle();
        expect(find.text('Enter your Safety PIN'), findsOneWidget);
        await t.tapAt(const Offset(20, 20));
        await t.pumpAndSettle();
        expect(pins.sets, isEmpty);
        expect(t.widget<SwitchListTile>(every).value, isTrue);
      });

      testWidgets('M-1: an account switch mid-change starts no second one', (
        t,
      ) async {
        final pins = _HeldPins();
        await open13(t, pins: pins);
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        await tapInReach(
          t,
          find.widgetWithText(
            SwitchListTile,
            'Ask for my PIN every time Attune opens',
          ),
        );
        await t.pump();
        c(t).read(datingTestAccount.notifier).state = 'kofi';
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        await tapInReach(
          t,
          find.widgetWithText(
            SwitchListTile,
            'Ask for my PIN every time Attune opens',
          ),
        );
        await t.pump();
        pins.hold.complete(true);
        await t.pumpAndSettle();
        expect(pins.sets, [true]);
      });

      // Fix 2 (M-2b): the retry now runs by itself, so this pins the cap: a
      // read that keeps failing is tried once more, then left neutral (no
      // loop, even as the list is checked again).
      testWidgets('M-2: a photo read that keeps failing is tried once more, '
          'then left neutral', (t) async {
        await t.pumpWidget(const SizedBox());
        final g = FakeDatingPhotosGateway(
          photos: [photo(1, 'approved'), photo(2, 'approved')],
        )..bytesError = StateError('storage');
        await pumpFlowScreen(
          t,
          () =>
              DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
          overrides: [
            ...datingShellOverrides(),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(profile: _amaProfile),
            ),
            datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
            datingPhotosGatewayProvider.overrideWithValue(g),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        await _settle(t);
        expect(g.byteReads, ['k1', 'k2', 'k1', 'k2']);
        expect(_memoryImages(), findsNothing);
        expect(find.bySemanticsLabel('Photo 1 of 2'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          c(t).invalidate(datingPhotosProvider('ama'));
          await _settle(t);
        }
        expect(g.byteReads, ['k1', 'k2', 'k1', 'k2']);
        expect(_memoryImages(), findsNothing);
      });

      testWidgets('M-2b: a failed photo read is tried again by itself, with '
          'nothing else changing', (t) async {
        await t.pumpWidget(const SizedBox());
        final g = _FailFirstPhotos(
          photos: [photo(1, 'approved'), photo(2, 'approved')],
        );
        g.stored['k1'] = _png;
        g.stored['k2'] = _png;
        await pumpFlowScreen(
          t,
          () =>
              DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
          overrides: [
            ...datingShellOverrides(),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(profile: _amaProfile),
            ),
            datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
            datingPhotosGatewayProvider.overrideWithValue(g),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        await _settle(t);
        expect(g.byteReads, ['k1', 'k2', 'k1', 'k2']);
        expect(_memoryImages(), findsOneWidget);
      });

      testWidgets('M-3: photos after mutual interest turned on: the bytes go '
          'from memory', (t) async {
        final (_, photos, preview, _, _) = await open12(t);
        expect(
          PaintingBinding.instance.imageCache.containsKey(MemoryImage(_png)),
          isTrue,
        );
        preview.card = DatingCard.fromJson({
          'display_name': 'Ama',
          'age': 29,
          'prompts': [],
          'photos_after_mutual': true,
          'photos': [],
        });
        photos.afterMutual = true;
        c(t).invalidate(datingPhotosProvider('ama'));
        await _settle(t);
        expect(
          find.text("Photos appear after you're both interested."),
          findsOneWidget,
        );
        expect(
          PaintingBinding.instance.imageCache.containsKey(MemoryImage(_png)),
          isFalse,
        );
      });

      testWidgets('M-4: offline, Turn on and Change time are off and read as '
          'off', (t) async {
        await open12(t, online: false);
        expect(_link(t, 'Turn on').onPressed, isNull);
        await open13(t, online: false);
        expect(_link(t, 'Change time').onPressed, isNull);
      });

      testWidgets('M-4: Change time is off while Done is running', (t) async {
        final (_, life, _, _) = await open13(t);
        life.hold = Completer<void>();
        await tapInReach(t, find.text('Done'));
        await t.pump();
        expect(_link(t, 'Change time').onPressed, isNull);
        life.hold!.complete();
        await t.pumpAndSettle();
      });

      testWidgets('M-5: Verify it\'s you from D13 comes back to D13, with no '
          'second D12 or D13', (t) async {
        final shell = await pumpDatingShell(
          t,
          initial: DatingPaths.step('ready'),
          overrides: [
            datingPreviewGatewayProvider.overrideWithValue(
              FakeDatingPreviewGateway(_ama),
            ),
            datingSetupGatewayProvider.overrideWithValue(
              FakeDatingSetupGateway(),
            ),
            datingPhotosGatewayProvider.overrideWithValue(
              FakeDatingPhotosGateway(),
            ),
            pushAskerProvider.overrideWithValue(FakePushAsker()),
          ],
        );
        shell.life.result = const DatingLifecycleResult.refused(
          DatingLifecycleError.activationGatesNotMet,
        );
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        await tapInReach(t, find.text("Verify it's you"));
        await t.pumpAndSettle();
        expect(find.byType(DatingVerifyStep), findsOneWidget);
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(find.byType(DatingReadyStep), findsOneWidget);
        expect(
          find.byType(DatingReadyStep, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(DatingPreviewStep, skipOffstage: false),
          findsNothing,
        );
      });

      testWidgets('M-6: the photos are read as one group, with a page '
          'indicator', (t) async {
        final semantics = t.ensureSemantics();
        await open12(t);
        expect(find.bySemanticsLabel(RegExp(r'^2 photos')), findsOneWidget);
        expect(find.byKey(const ValueKey('dating_card_dots')), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('M-8: a wrapped edit link starts at the start', (t) async {
        await open12(t);
        final text = t.widget<Text>(find.text("Edit what you're looking for"));
        expect(text.textAlign, TextAlign.start);
      });
    });
  });
}

const _amaProfile = DatingMyProfile(displayName: 'Ama');

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

Finder _memoryImages() =>
    find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);

/// The photo reads are real futures: let them land, a frame at a time.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await t.pumpAndSettle();
}

/// Activation, its answer held open on request.
class _HeldLife extends FakeDatingLifecycleGateway {
  Completer<void>? hold;

  @override
  Future<DatingLifecycleResult> activate(String key) async {
    final r = super.activate(key);
    final h = hold;
    if (h != null) await h.future;
    return r;
  }
}

/// The push ask, its answer held open.
class _HeldAsker extends FakePushAsker {
  final hold = Completer<void>();

  @override
  Future<PushAskOutcome> askInContext(PushAskContext context) async {
    asked.add(context);
    await hold.future;
    granted = true;
    return PushAskOutcome.granted;
  }
}

/// A Safety PIN store whose answer to "is there a PIN" is held open.
class _HeldPins extends SafetyPinStore {
  _HeldPins({this.everyOpenOn = false});

  final hold = Completer<bool>();
  final bool everyOpenOn;
  final sets = <bool>[];

  @override
  Future<bool> hasPin() => hold.future;

  @override
  Future<bool> everyOpen() async => everyOpenOn;

  @override
  Future<void> setEveryOpen(bool on) async => sets.add(on);
}

/// A text link, found by its label (enabled or not).
TextButton _link(WidgetTester t, String label) =>
    t.widget<TextButton>(find.widgetWithText(TextButton, label));

/// Photo bytes whose first read of each key fails (T11 fix 2, M-2b).
class _FailFirstPhotos extends FakeDatingPhotosGateway {
  _FailFirstPhotos({super.photos});

  final _failed = <String>{};

  @override
  Future<Uint8List?> bytes(String storageKey) async {
    if (_failed.add(storageKey)) {
      byteReads.add(storageKey);
      throw StateError('storage');
    }
    return super.bytes(storageKey);
  }
}
