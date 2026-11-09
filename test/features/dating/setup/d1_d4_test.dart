// Spec 2 W3b (§3.2 D1-D4, §3.0, §3.15): the first four setup screens.
import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart'
    show FlowPrimaryButton, FlowSecondaryButton;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/how_step.dart';
import 'package:attune/features/dating/setup/looking_for_step.dart';
import 'package:attune/features/dating/setup/privacy_step.dart';
import 'package:attune/features/dating/setup/where_step.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Run {
  _Run(this.setup, this.home, this.spec1, this.steps, this.harness);
  final FakeDatingSetupGateway setup;
  final FakeDatingHomeGateway home;
  final FakeHomeStateGateway spec1;
  final List<String> steps;
  final FlowHarness harness;
}

Future<_Run> _open(
  WidgetTester t,
  Widget Function(DatingStepNav nav) screen, {
  DatingMyProfile profile = const DatingMyProfile(),
  DatingHome home = const DatingHome(state: DatingHomeState.notStarted),
  bool online = true,
  ({String? sim, String? region}) device = (sim: null, region: null),
  FakeDatingSetupGateway? gateway,
  bool reduceMotion = false,
  ThemeData? theme,
}) async {
  await t.pumpWidget(const SizedBox());
  final setup = gateway ?? FakeDatingSetupGateway(profile: profile);
  final homeGateway = FakeDatingHomeGateway(home: home);
  final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
  final steps = <String>[];
  final nav = DatingStepNav(
    next: steps.add,
    back: () => steps.add('<back>'),
    toMe: () => steps.add('<me>'),
  );
  final h = await pumpFlowScreen(
    t,
    () => theme == null ? screen(nav) : Theme(data: theme, child: screen(nav)),
    reduceMotion: reduceMotion,
    overrides: [
      ...datingShellOverrides(home: homeGateway, online: online),
      datingSetupGatewayProvider.overrideWithValue(setup),
      deviceCountryProvider.overrideWith((ref) async => device),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(spec1)),
    ],
  );
  await t.pumpAndSettle();
  return _Run(setup, homeGateway, spec1, steps, h);
}

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

/// Server text that must never reach the screen (T5 carry B): it names a
/// phone number, as a raised message can echo what was typed.
const _leaky = 'profile: +233 24 555 0101 refused';

/// The setup fake, with a write that waits for [hold] and reads or writes
/// that throw (T6 carries A and B).
class _TestSetup extends FakeDatingSetupGateway {
  Completer<void>? hold;
  Object? profileError;
  Object? listsError;
  Object? writeError;

  @override
  Future<DatingMyProfile> myProfile() async {
    final error = profileError;
    if (error != null) throw error;
    return super.myProfile();
  }

  @override
  Future<DatingSetupLists> lists() async {
    final error = listsError;
    if (error != null) throw error;
    return super.lists();
  }

  @override
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  }) async {
    final held = hold;
    if (held != null) await held.future;
    final error = writeError;
    if (error != null) {
      calls.add(('saveIntention', {'key': key}));
      throw error;
    }
    return super.saveIntention(
      key,
      intention: intention,
      timeline: timeline,
      timelineVisible: timelineVisible,
      marital: marital,
      maritalVisible: maritalVisible,
    );
  }
}

bool? _radio(WidgetTester t, String text) =>
    t
        .widget<RadioListTile<String>>(
          find.widgetWithText(RadioListTile<String>, text),
        )
        .checked;

FlowPrimaryButton _primary(WidgetTester t) =>
    t.widget<FlowPrimaryButton>(find.byType(FlowPrimaryButton));

Future<void> _pickVolta(WidgetTester t) async {
  await tapInReach(t, find.text('Region'));
  await t.pumpAndSettle();
  await tapInReach(t, find.text('Volta').last);
  await t.pumpAndSettle();
}

/// [ghanaLists] once Volta has opened.
final _voltaOpen = DatingSetupLists(
  countries: [
    for (final c in ghanaLists.countries)
      DatingCountryLists(
        code: c.code,
        sameGender: c.sameGender,
        faiths: c.faiths,
        regions: [
          for (final r in c.regions)
            DatingRegion(
              code: r.code,
              nameKey: r.nameKey,
              open: r.open || r.code == 'TV',
              sides: r.sides,
            ),
        ],
      ),
  ],
  phoneCountry: ghanaLists.phoneCountry,
  defaultAges: ghanaLists.defaultAges,
);

Future<void> _answerD2(WidgetTester t) async {
  await tapInReach(t, find.text('Not sure yet'));
  await t.pump();
  await tapInReach(t, find.textContaining("I'm not married in any form"));
  await t.pump();
}

void main() {
  group('D1', () {
    testWidgets('eight lines, the open list built and the first drop dated', (
      t,
    ) async {
      await _open(
        t,
        (nav) => DatingHowStep(nav: nav),
        home: DatingHome(
          state: DatingHomeState.notStarted,
          firstDropAt: DateTime.utc(2026, 11, 12, 19),
        ),
      );
      expect(find.text('How Dating works'), findsOneWidget);
      expect(
        find.text('Up to 3 introductions a day, at a time you choose.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your first introductions can arrive from '),
        findsOneWidget,
      );
      expect(
        find.text(
          'Dating is open in the United Kingdom and Ghana (Greater Accra and Ashanti).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Setting up uses about 15 MB of data, mostly for the video check.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Set up Dating, Set up later', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Set up Dating'));
      await t.pump();
      await tapInReach(t, find.text('Set up later'));
      expect(r.steps, ['looking-for', '<me>']);
    });

    testWidgets('Not ready? switches in one tap, with Undo', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Not ready? Use Attune just for me'));
      await t.pumpAndSettle();
      expect(r.spec1.count('set_my_path'), 1);
      expect(find.text("You're on 'Just for me'."), findsOneWidget);
      // Fix 1 (M-8): the W10 tap helper.
      await tapInReach(t, find.text('Undo'));
      await t.pumpAndSettle();
      expect(r.spec1.count('set_my_path'), 2);
      // Fix 1 (M-1): undone, D1 stays.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(r.steps, isEmpty);
    });

    testWidgets('Not ready? without Undo: Me once the snackbar closes, and '
        'D1 takes no other tap meanwhile (fix 1, M-1)', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Not ready? Use Attune just for me'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Set up Dating'));
      await t.pump();
      // (The snackbar can cover "Not ready?" at large text: read it.)
      expect(
        t
            .widget<FlowSecondaryButton>(find.byType(FlowSecondaryButton))
            .onPressed,
        isNull,
      );
      expect(r.steps, isEmpty);
      expect(r.spec1.count('set_my_path'), 1);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(r.steps, ['<me>']);
    });

    testWidgets('with a screen reader, Undo stays up for 20 s (fix 1, M-1)', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Not ready? Use Attune just for me'));
      await t.pumpAndSettle();
      expect(
        t.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 20),
      );
    });

    testWidgets('the snackbar never outlives D1 (fix 1, M-1)', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Not ready? Use Attune just for me'));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      r.harness.router.go('/elsewhere');
      await t.pumpAndSettle();
      expect(find.byType(DatingHowStep), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('each item is read with its number (fix 1, M-5)', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingHowStep(nav: nav));
      expect(
        t
            .getSemantics(
              find.text('Up to 3 introductions a day, at a time you choose.'),
            )
            .label,
        startsWith('1.'),
      );
      semantics.dispose();
    });

    testWidgets('a closed country: §3.10 instead', (t) async {
      await _open(
        t,
        (nav) => DatingHowStep(nav: nav),
        home: const DatingHome(
          state: DatingHomeState.countryClosed,
          country: 'NG',
          notice: DatingNotice(available: true),
        ),
      );
      // Fix 1 (M-6): §3.10's own page (never animated), not D1's.
      expect(find.text('at /dating/not-open?country=NG'), findsOneWidget);
      expect(find.text('How Dating works'), findsNothing);
    });
  });

  group('D2', () {
    testWidgets(
      'Continue waits for an intention; the attestation is required',
      (t) async {
        final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
        expect(find.text('Step 1 of 12'), findsOneWidget);
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, isEmpty);
        await tapInReach(t, find.text('A committed relationship'));
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(
          find.text("Please confirm you're free to start a relationship."),
          findsOneWidget,
        );
        expect(r.setup.writes, isEmpty);
        await tapInReach(t, find.textContaining("I'm not married in any form"));
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(r.setup.lastWrite.$2['intention'], 'committed');
        expect(r.setup.lastWrite.$2['timeline'], isNull);
        expect(r.steps, ['where']);
      },
    );

    testWidgets('Marriage opens the timeline; a double tap is one key', (
      t,
    ) async {
      // T6 deviation (carry A): the second tap lands while the first save
      // is still in flight; a tap after a final answer is a new request.
      final held = _TestSetup()..hold = Completer<void>();
      final r = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        gateway: held,
      );
      await tapInReach(t, find.text('Marriage'));
      await t.pumpAndSettle();
      expect(find.text('When would you like to marry?'), findsOneWidget);
      await tapInReach(t, find.text('In a few years'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      final go = find.byType(FlowPrimaryButton);
      await tapInReach(t, go);
      await t.tap(go);
      await t.pump();
      await t.tap(go, warnIfMissed: false);
      held.hold!.complete();
      await t.pumpAndSettle();
      final saves =
          r.setup.calls.where((c) => c.$1 == 'saveIntention').toList();
      expect(saves, hasLength(1));
      expect(saves.first.$2['timeline'], 'few_years');
      expect(r.steps, ['where']);
    });

    testWidgets('keys: a final answer settles the key; busy and failed keep '
        'it (carry A)', (t) async {
      final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
      await _answerD2(t);
      Future<String> save() async {
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        return r.setup.lastWrite.$2['key']! as String;
      }

      final first = await save();
      // The same answers saved again after an ok: a new request.
      final second = await save();
      expect(second, isNot(first));
      r.setup.answer = DatingWrite.busy;
      final busy = await save();
      expect(busy, isNot(second));
      // A busy or failed answer's outcome is unknown: the retry is the
      // same request.
      expect(await save(), busy);
      r.setup.answer = DatingWrite.failed;
      expect(await save(), busy);
      // A named refusal is final: the same request answered, then dropped.
      r.setup.answer = const DatingWrite(ok: false, reason: 'rate_limited');
      expect(await save(), busy);
      r.setup.answer = const DatingWrite(ok: true);
      final after = await save();
      expect(after, isNot(busy));
      expect(r.steps, ['where', 'where', 'where']);
    });

    testWidgets('a failed profile read is generic copy with Retry, never the '
        'error (carry B)', (t) async {
      final setup = _TestSetup()..profileError = StateError(_leaky);
      await _open(t, (nav) => DatingLookingForStep(nav: nav), gateway: setup);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      setup
        ..profileError = null
        ..profile = const DatingMyProfile(intention: 'committed');
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(
        t
            .widget<RadioListTile<String>>(
              find.widgetWithText(
                RadioListTile<String>,
                'A committed relationship',
              ),
            )
            .checked,
        isTrue,
      );
    });

    testWidgets('a write that throws is generic copy and keeps its key '
        '(carry B)', (t) async {
      final setup = _TestSetup()..writeError = StateError(_leaky);
      final r = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        gateway: setup,
      );
      await _answerD2(t);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
      expect(r.steps, isEmpty);
      final key = r.setup.lastWrite.$2['key'];
      setup.writeError = null;
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['key'], key);
      expect(r.steps, ['where']);
    });

    testWidgets('a changed answer asks the attestation again', (t) async {
      await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        profile: const DatingMyProfile(intention: 'committed', attested: true),
      );
      final box = find.byType(CheckboxListTile);
      expect(t.widget<CheckboxListTile>(box).value, isTrue);
      await tapInReach(t, find.text('Marriage'));
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(box).value, isFalse);
    });

    testWidgets('each group label is read once; the intention group never '
        'repeats the title (fix 1, I-2)', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingLookingForStep(nav: nav));
      expect(find.text('What are you looking for?'), findsOneWidget);
      expect(
        t.getSemantics(find.byType(DatingChoiceGroup<String>).first).label,
        'What are you looking for?',
      );
      await tapInReach(t, find.text('Marriage'));
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(
              find.widgetWithText(
                DatingChoiceGroup<String>,
                'When would you like to marry?',
              ),
            )
            .label,
        'When would you like to marry?',
      );
      semantics.dispose();
    });

    testWidgets('an answer given before the saved ones arrive is kept '
        '(fix 1, M-3)', (t) async {
      final setup = _TestSetup()..holdProfile = Completer<DatingMyProfile>();
      await _open(t, (nav) => DatingLookingForStep(nav: nav), gateway: setup);
      await tapInReach(t, find.text('Not sure yet'));
      await t.pump();
      setup.holdProfile!.complete(const DatingMyProfile(intention: 'marriage'));
      await t.pumpAndSettle();
      expect(_radio(t, 'Not sure yet'), isTrue);
      expect(find.text('When would you like to marry?'), findsNothing);
    });

    testWidgets('one answer given early: every other saved answer still '
        'shows and is sent unchanged (fix 2, N-1)', (t) async {
      final setup = _TestSetup()..holdProfile = Completer<DatingMyProfile>();
      final r = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        gateway: setup,
      );
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      setup.holdProfile!.complete(
        const DatingMyProfile(
          intention: 'committed',
          attested: true,
          marital: 'divorced',
          maritalVisible: true,
        ),
      );
      await t.pumpAndSettle();
      expect(_radio(t, 'A committed relationship'), isTrue);
      expect(_radio(t, 'Divorced'), isTrue);
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Show on my profile'),
            )
            .value,
        isTrue,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['intention'], 'committed');
      expect(r.setup.lastWrite.$2['marital'], 'divorced');
      expect(r.setup.lastWrite.$2['maritalVisible'], isTrue);
    });

    testWidgets('Continue waits for the saved answers (fix 2, N-1)', (t) async {
      final setup = _TestSetup()..holdProfile = Completer<DatingMyProfile>();
      await _open(t, (nav) => DatingLookingForStep(nav: nav), gateway: setup);
      await _answerD2(t);
      expect(_primary(t).onPressed, isNull);
      setup.holdProfile!.complete(const DatingMyProfile());
      await t.pumpAndSettle();
      expect(_primary(t).onPressed, isNotNull);
    });

    testWidgets('a saved answer cleared on purpose is sent as cleared '
        '(fix 2, N-1)', (t) async {
      final r = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        profile: const DatingMyProfile(
          intention: 'committed',
          attested: true,
          marital: 'divorced',
          maritalVisible: true,
        ),
      );
      expect(_radio(t, 'Divorced'), isTrue);
      await tapInReach(t, find.text('Divorced'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['intention'], 'committed');
      expect(r.setup.lastWrite.$2['marital'], isNull);
      expect(r.setup.lastWrite.$2['maritalVisible'], isFalse);
    });

    testWidgets('a failed profile read never lets Continue save (fix 1, M-3)', (
      t,
    ) async {
      final setup = _TestSetup()..profileError = StateError(_leaky);
      await _open(t, (nav) => DatingLookingForStep(nav: nav), gateway: setup);
      await _answerD2(t);
      expect(_primary(t).onPressed, isNull);
    });

    testWidgets('married before: optional, can be taken back, and the toggle '
        'only for divorced or widowed (fix 1, M-4, M-7)', (t) async {
      final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
      await tapInReach(t, find.text('Married before? (optional)'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Never'));
      await t.pump();
      expect(find.text('Show on my profile'), findsNothing);
      await tapInReach(t, find.text('Widowed'));
      await t.pump();
      expect(find.text('Show on my profile'), findsOneWidget);
      await tapInReach(t, find.text('Divorced'));
      await t.pump();
      expect(_radio(t, 'Divorced'), isTrue);
      await tapInReach(t, find.text('Divorced'));
      await t.pump();
      expect(_radio(t, 'Divorced'), isFalse);
      expect(find.text('Show on my profile'), findsNothing);
      await _answerD2(t);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['marital'], isNull);
      expect(r.setup.lastWrite.$2['maritalVisible'], isFalse);
    });

    testWidgets('the timeline opens over 200 ms, at once under reduce motion '
        '(fix 1, M-7)', (t) async {
      await _open(t, (nav) => DatingLookingForStep(nav: nav));
      expect(
        t.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        const Duration(milliseconds: 200),
      );
      await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        reduceMotion: true,
      );
      expect(
        t.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        Duration.zero,
      );
    });

    testWidgets('separated but not divorced: the sheet', (t) async {
      await _open(t, (nav) => DatingLookingForStep(nav: nav));
      await tapInReach(t, find.text("I'm separated but not divorced"));
      await t.pumpAndSettle();
      expect(find.textContaining('Once your divorce is final'), findsOneWidget);
    });

    testWidgets(
      'D8: another account starts empty, even while its read is held',
      (t) async {
        final r = await _open(
          t,
          (nav) => DatingLookingForStep(nav: nav),
          profile: const DatingMyProfile(
            intention: 'marriage',
            marriageTimeline: 'few_years',
            attested: true,
          ),
        );
        expect(find.text('When would you like to marry?'), findsOneWidget);
        r.setup.holdProfile = Completer<DatingMyProfile>();
        _c(t).read(datingTestAccount.notifier).state = 'kofi';
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 40));
          expect(find.text('When would you like to marry?'), findsNothing);
          expect(
            t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
            isFalse,
          );
        }
        r.setup.holdProfile!.complete(const DatingMyProfile());
        await t.pumpAndSettle();
        expect(find.text('When would you like to marry?'), findsNothing);
      },
    );

    testWidgets('a busy server is said calmly; offline disables Continue', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
      r.setup.answer = DatingWrite.busy;
      await tapInReach(t, find.text('Not sure yet'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      final off = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        online: false,
      );
      await tapInReach(t, find.text('Not sure yet'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(off.setup.writes, isEmpty);
      expect(find.text('Connect to save this answer.'), findsOneWidget);
    });
  });

  group('D3', () {
    testWidgets('preselected from the SIM; a closed region blocks Continue and '
        'can be asked for', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: 'GB'),
      );
      expect(find.text('Ghana'), findsOneWidget);
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Volta').last);
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Dating is open in Greater Accra and Ashanti for now.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      await tapInReach(t, find.text("Tell me when it's open in Volta"));
      await t.pumpAndSettle();
      expect(r.home.requests, [('GH', 'TV')]);
    });

    testWidgets('a side, the scope, and the save', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
      );
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Greater Accra').last);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Tema and Ashaiman'));
      await t.pump();
      await tapInReach(t, find.text('My side'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'country': 'GH',
        'region': 'AA',
        'side': 'tema',
        'scope': 'side',
      });
      expect(r.steps, ['privacy']);
    });

    testWidgets('the region picker is sorted by name, not code (T5 M-8)', (
      t,
    ) async {
      await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
      );
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      final rows = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      );
      expect(
        [
          for (final row in t.widgetList<ListTile>(rows))
            (row.title! as Text).data,
        ],
        ['Ashanti', 'Greater Accra', 'Volta'],
      );
    });

    testWidgets('failed lists are generic copy with Retry, never the error '
        '(carry B)', (t) async {
      final setup = _TestSetup()..listsError = StateError(_leaky);
      await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
        gateway: setup,
      );
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.textContaining('+233'), findsNothing);
      expect(find.text('Ghana'), findsNothing);
      setup.listsError = null;
      await tapInReach(t, find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(find.text('Ghana'), findsOneWidget);
    });

    Future<_Run> openVolta(WidgetTester t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
      );
      await _pickVolta(t);
      return r;
    }

    testWidgets("Tell me: every answer is said, calmly (fix 1, I-1)", (
      t,
    ) async {
      final r = await openVolta(t);
      for (final (result, text) in [
        (DatingNoticeResult.failed, 'Something went wrong. Try again.'),
        (DatingNoticeResult.invalid, 'Something went wrong. Try again.'),
        (
          DatingNoticeResult.rateLimited,
          "You've done this a lot today. Try again tomorrow.",
        ),
        (
          DatingNoticeResult.notEligible,
          "We can't set this up on this account.",
        ),
        (
          DatingNoticeResult.busy,
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        (
          DatingNoticeResult.saved,
          "We'll let you know. You can turn this off in Settings.",
        ),
      ]) {
        r.home.noticeResult = result;
        await tapInReach(t, find.text("Tell me when it's open in Volta"));
        await t.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: '$result');
      }
      expect(find.text("Tell me when it's open in Volta"), findsNothing);
      expect(r.home.requests, hasLength(6));
    });

    testWidgets('Tell me: a double tap sends one request (fix 1, I-1)', (
      t,
    ) async {
      final r = await openVolta(t);
      r.home.noticeHold = Completer<void>();
      final ask = find.text("Tell me when it's open in Volta");
      await tapInReach(t, ask);
      await t.tap(ask);
      await t.pump();
      await t.tap(find.byType(FlowSecondaryButton), warnIfMissed: false);
      r.home.noticeHold!.complete();
      await t.pumpAndSettle();
      expect(r.home.requests, [('GH', 'TV')]);
    });

    testWidgets('Tell me: open already reads the lists again and Continue '
        'goes on (fix 1, I-1)', (t) async {
      final r = await openVolta(t);
      final reads = r.setup.calls.where((c) => c.$1 == 'lists').length;
      r.home.noticeResult = DatingNoticeResult.alreadyOpen;
      r.setup.listsValue = _voltaOpen;
      await tapInReach(t, find.text("Tell me when it's open in Volta"));
      await t.pumpAndSettle();
      expect(r.setup.calls.where((c) => c.$1 == 'lists').length, reads + 1);
      expect(find.textContaining('for now.'), findsNothing);
      expect(_primary(t).onPressed, isNotNull);
    });

    testWidgets("Tell me: the last account's answer never shows on the next "
        '(fix 1, I-1, D8)', (t) async {
      final r = await openVolta(t);
      r.home.noticeHold = Completer<void>();
      await tapInReach(t, find.text("Tell me when it's open in Volta"));
      await t.pump();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      // The next account is on the same closed region when the last
      // account's answer lands.
      await _pickVolta(t);
      r.home.noticeHold!.complete();
      await t.pumpAndSettle();
      expect(
        find.text("We'll let you know. You can turn this off in Settings."),
        findsNothing,
      );
      expect(find.text("Tell me when it's open in Volta"), findsOneWidget);
    });

    testWidgets('D8: D3 shows nothing of the last account while the next '
        'read is held (fix 1, I-3)', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          regionScope: 'region',
        ),
      );
      expect(find.text('the United Kingdom'), findsOneWidget);
      expect(find.text('London'), findsOneWidget);
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(find.text('the United Kingdom'), findsNothing);
        expect(find.text('London'), findsNothing);
      }
      r.setup.holdProfile!.complete(const DatingMyProfile());
      await t.pumpAndSettle();
      expect(find.text('the United Kingdom'), findsNothing);
      expect(find.text('London'), findsNothing);
    });

    testWidgets('a place picked before the saved one arrives is kept, and '
        'Continue waits for the read (fix 2, N-1)', (t) async {
      final setup = _TestSetup()..holdProfile = Completer<DatingMyProfile>();
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
        gateway: setup,
      );
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ashanti').last);
      await t.pumpAndSettle();
      expect(_primary(t).onPressed, isNull);
      setup.holdProfile!.complete(
        const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          regionScope: 'country',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Ghana'), findsOneWidget);
      expect(find.text('Ashanti'), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['country'], 'GH');
      expect(r.setup.lastWrite.$2['region'], 'AH');
    });

    testWidgets('a saved side and scope are sent unchanged (fix 2, N-1)', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          sideCode: 'tema',
          regionScope: 'side',
        ),
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'country': 'GH',
        'region': 'AA',
        'side': 'tema',
        'scope': 'side',
      });
    });

    testWidgets('a side can be taken back to "Either side" (fix 1)', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
      );
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Greater Accra').last);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Tema and Ashaiman'));
      await t.pump();
      await tapInReach(t, find.text('Either side'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['side'], isNull);
      expect(r.setup.lastWrite.$2['scope'], 'region');
    });

    testWidgets('the abroad row is disabled and says why', (t) async {
      await _open(t, (nav) => DatingWhereStep(nav: nav));
      expect(
        find.text('Also open to people in other countries'),
        findsOneWidget,
      );
      expect(
        find.text(
          "Available once you're verified and your account is 14 days old.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refused country change is named', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          regionScope: 'region',
        ),
      );
      r.setup.answer = const DatingWrite(
        ok: false,
        reason: 'country_change_limited',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text('You can change your Dating country once every 30 days.'),
        findsOneWidget,
      );
    });
  });

  group('D4', () {
    testWidgets(
      'Agree waits for the box; then three consents and the enrolment',
      (t) async {
        final r = await _open(t, (nav) => DatingPrivacyStep(nav: nav));
        expect(find.text('Step 3 of 12'), findsOneWidget);
        await tapInReach(t, find.text('Agree and continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, isEmpty);
        await tapInReach(
          t,
          find.textContaining('I agree that Attune can use my answers'),
        );
        await t.pump();
        await tapInReach(t, find.text('Agree and continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, ['agreeAndBegin']);
        expect(r.steps, ['you']);
      },
    );

    testWidgets('five semantic headings', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingPrivacyStep(nav: nav));
      for (final head in [
        'Why we ask',
        'Who sees what',
        'What we never do',
        "How it's protected",
        'Leaving',
      ]) {
        expect(
          t.getSemantics(find.text(head)).hasFlag(SemanticsFlag.isHeader),
          isTrue,
          reason: head,
        );
      }
      semantics.dispose();
    });
  });

  group('D4 fix 1', () {
    testWidgets("D8: D4's tick never carries to the next account (I-3)", (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingPrivacyStep(nav: nav));
      await tapInReach(
        t,
        find.textContaining('I agree that Attune can use my answers'),
      );
      await t.pump();
      expect(_primary(t).onPressed, isNotNull);
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(
          t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        expect(_primary(t).onPressed, isNull);
      }
      r.setup.holdProfile!.complete(const DatingMyProfile());
    });

    testWidgets('offline: Agree stays off after the tick (M-7)', (t) async {
      await _open(t, (nav) => DatingPrivacyStep(nav: nav), online: false);
      await tapInReach(
        t,
        find.textContaining('I agree that Attune can use my answers'),
      );
      await t.pump();
      expect(_primary(t).onPressed, isNull);
    });

    for (final (link, title) in [
      ('Dating terms', 'Terms of Service'),
      ('Privacy notice', 'Privacy Policy'),
    ]) {
      testWidgets('$link opens $title (R-31, M-7)', (t) async {
        await _open(t, (nav) => DatingPrivacyStep(nav: nav));
        await tapInReach(t, find.text(link));
        await t.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text(title), findsOneWidget);
      });
    }
  });

  testWidgets("D3: My country isn't listed opens §3.10 for the SIM country "
      '(fix 1, M-7)', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.step('where'),
      overrides: [
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        deviceCountryProvider.overrideWith(
          (ref) async => (sim: 'GH', region: null),
        ),
      ],
    );
    await tapInReach(t, find.text('Country'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text("My country isn't listed"));
    await t.pumpAndSettle();
    expect(
      t.widget<DatingNotOpenScreen>(find.byType(DatingNotOpenScreen)).country,
      'GH',
    );
  });

  testWidgets('a step moves on once, however fast the taps (fix 1, M-2)', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('how'),
      overrides: [
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        deviceCountryProvider.overrideWith(
          (ref) async => (sim: 'GH', region: null),
        ),
      ],
    );
    await tapInReach(t, find.text('Set up Dating'));
    await t.tap(find.text('Set up Dating'));
    await t.pumpAndSettle();
    expect(find.byType(DatingLookingForStep), findsOneWidget);
    s.router.pop();
    await t.pumpAndSettle();
    expect(find.byType(DatingHowStep), findsOneWidget);
    expect(find.byType(DatingLookingForStep), findsNothing);
    // Back on D1, it moves on again.
    await tapInReach(t, find.text('Set up Dating'));
    await t.pumpAndSettle();
    expect(find.byType(DatingLookingForStep), findsOneWidget);
  });

  // Fix 1 (dark theme, controller ruling): every colour is a theme token;
  // the error row is the theme's error red (light #C62828, W10).
  testWidgets('D1-D4 in the dark theme: tokens only, contrast holds', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final dark = AppTheme.darkTheme;
    for (final screen in <Widget Function(DatingStepNav)>[
      (nav) => DatingHowStep(nav: nav),
      (nav) => DatingLookingForStep(nav: nav),
      (nav) => DatingWhereStep(nav: nav),
      (nav) => DatingPrivacyStep(nav: nav),
    ]) {
      await _open(t, screen, device: (sim: 'GH', region: null), theme: dark);
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        dark.colorScheme.surface,
      );
      await expectFlowGuidelines(t);
    }
    // The error rows (a failed read; a refused write) in dark and light.
    for (final (theme, red) in [
      (dark, dark.colorScheme.error),
      (AppTheme.lightTheme, const Color(0xFFC62828)),
    ]) {
      final setup = _TestSetup()..profileError = StateError(_leaky);
      await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        gateway: setup,
        theme: theme,
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

  // Carry E: D1-D4 are pages of the one step route (datingRoute), so they
  // inherit the Dating lock: a deep link asks for the PIN first.
  testWidgets('D1-D4 open at their step paths, behind the Dating lock', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('where'),
      locked: true,
      pinSet: true,
      overrides: [
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        deviceCountryProvider.overrideWith(
          (ref) async => (sim: 'GH', region: null),
        ),
      ],
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Where are you?'), findsNothing);
    s.container.read(datingUnlockedProvider.notifier).unlock();
    for (final (step, screen) in [
      ('how', DatingHowStep),
      ('looking-for', DatingLookingForStep),
      ('where', DatingWhereStep),
      ('privacy', DatingPrivacyStep),
    ]) {
      s.router.go(DatingPaths.step(step));
      await t.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: step);
      expect(s.location, DatingPaths.step(step));
    }
  });

  testWidgets('guidelines on every screen', (t) async {
    final semantics = t.ensureSemantics();
    for (final screen in <Widget Function(DatingStepNav)>[
      (nav) => DatingHowStep(nav: nav),
      (nav) => DatingLookingForStep(nav: nav),
      (nav) => DatingWhereStep(nav: nav),
      (nav) => DatingPrivacyStep(nav: nav),
    ]) {
      await _open(t, screen, device: (sim: 'GH', region: null));
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  for (final (name, screen) in <(String, Widget Function(DatingStepNav))>[
    ('d1_how', (nav) => DatingHowStep(nav: nav)),
    ('d2_looking_for', (nav) => DatingLookingForStep(nav: nav)),
    ('d3_where', (nav) => DatingWhereStep(nav: nav)),
    ('d4_privacy', (nav) => DatingPrivacyStep(nav: nav)),
  ]) {
    testWidgets('$name goldens', (t) async {
      final nav = DatingStepNav(next: (_) {}, back: () {}, toMe: () {});
      await expectFlowGoldens(
        t,
        name,
        () => screen(nav),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: DatingHome(
                state: DatingHomeState.notStarted,
                firstDropAt: DateTime.utc(2026, 11, 12, 19),
              ),
            ),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          deviceCountryProvider.overrideWith(
            (ref) async => (sim: 'GH', region: null),
          ),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
        ],
      );
    });
  }
}
