// Spec 2 W3b (§2.4, §3.2 D5-D8, §7.2 S3/S22, §7.4): D5-D8 on- and
// off-country; the off-country screens never send a same-gender set and
// the "Why?" sheet calls nothing; the country note; D8.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart'
    show FlowPrimaryButton;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/children_step.dart';
import 'package:attune/features/dating/setup/country_note_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/faith_step.dart';
import 'package:attune/features/dating/setup/meet_step.dart';
import 'package:attune/features/dating/setup/you_step.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

const _ghana = DatingMyProfile(
  countryCode: 'GH',
  regionCode: 'AA',
  identity: 'woman',
);
const _uk = DatingMyProfile(
  countryCode: 'GB',
  regionCode: 'TLI',
  identity: 'woman',
);

class _Run {
  _Run(this.setup, this.home, this.steps, this.rpc, this.supportFor);
  final FakeDatingSetupGateway setup;
  final FakeDatingHomeGateway home;
  final List<String> steps;

  /// Every Dating RPC any code sent (fix 1, M-6: §7.2 S3's mock client).
  final List<String> rpc;

  /// The country each support list was asked for (fix 1, M-6).
  final List<String?> supportFor;
}

Future<_Run> _open(
  WidgetTester t,
  Widget Function(DatingStepNav) screen, {
  DatingMyProfile profile = _ghana,
  DatingSetupLists lists = ghanaLists,
  bool forbidSameGender = false,
  // T7 (carries A-G): a test's own gateway, theme, text size, support
  // list and launcher.
  FakeDatingSetupGateway? gateway,
  ThemeData? theme,
  double textScale = 1.0,
  List<SupportResource> support = const [],
  List<String>? launched,
}) async {
  await t.pumpWidget(const SizedBox());
  final setup =
      gateway ?? FakeDatingSetupGateway(profile: profile, listsValue: lists);
  if (forbidSameGender) {
    // §7.4: the off-country screens fail the test if they try. A write
    // swallows what its call throws, so a breach also fails at tear-down.
    final breaches = <Object>[];
    addTearDown(() => expect(breaches, isEmpty));
    setup.guard = (name, args) {
      if (name != 'saveIdentity' && name != 'saveWhoToMeet') return;
      breaches.add('$name $args');
      if (name == 'saveIdentity') {
        expect(args['identity'], isIn(['woman', 'man']));
        expect(args['specific'], isNull);
        expect(args['pronouns'], isNull);
        expect(args['extraPools'], isEmpty);
      }
      if (name == 'saveWhoToMeet') {
        final own = profile.identity;
        expect((args['seeking'] as List).contains(own), isFalse);
        expect((args['seeking'] as List).length, 1);
      }
      breaches.removeLast();
    };
  }
  final home = FakeDatingHomeGateway();
  final steps = <String>[];
  final nav = DatingStepNav(next: steps.add, back: () {}, toMe: () {});
  final rpc = <String>[];
  final supportFor = <String?>[];
  await pumpFlowScreen(
    t,
    () => theme == null ? screen(nav) : Theme(data: theme, child: screen(nav)),
    textScale: textScale,
    overrides: [
      ...datingShellOverrides(home: home),
      datingSetupGatewayProvider.overrideWithValue(setup),
      datingRpcProvider.overrideWithValue(
        DatingRpc.withCall((fn, params) async {
          rpc.add(fn);
          return null;
        }),
      ),
      supportResourcesProvider.overrideWith((ref, country) async {
        supportFor.add(country);
        return SupportResources(
          country: 'GH',
          countrySupported: true,
          catalogueVersion: 'test',
          resources: support,
          fromServer: false,
        );
      }),
      supportLauncherProvider.overrideWithValue(
        (context, url) async => launched?.add(url),
      ),
    ],
  );
  await t.pumpAndSettle();
  return _Run(setup, home, steps, rpc, supportFor);
}

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

/// Server text that must never reach the screen (carry C): it names a
/// phone number, as a raised message can echo what was typed.
const _leaky = 'profile: +233 24 555 0101 refused';

/// The setup fake with held writes and failing reads or writes (carries
/// A-C).
class _TestSetup extends FakeDatingSetupGateway {
  _TestSetup({super.profile});

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

  Future<DatingWrite> _held(
    String name,
    Future<DatingWrite> Function() call,
  ) async {
    final held = hold;
    if (held != null) await held.future;
    final error = writeError;
    if (error != null) {
      calls.add((name, const {}));
      throw error;
    }
    return call();
  }

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) => _held(
    'saveIdentity',
    () => super.saveIdentity(
      key,
      identity: identity,
      specific: specific,
      pronouns: pronouns,
      extraPools: extraPools,
      visible: visible,
    ),
  );

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) => _held(
    'saveWhoToMeet',
    () => super.saveWhoToMeet(
      key,
      seeking: seeking,
      minAge: minAge,
      maxAge: maxAge,
    ),
  );

  @override
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  }) => _held(
    'saveChildren',
    () => super.saveChildren(
      key,
      have: have,
      want: want,
      mustMatch: mustMatch,
      excludeParents: excludeParents,
    ),
  );

  @override
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  }) => _held(
    'saveFaith',
    () => super.saveFaith(
      key,
      faith: faith,
      denomination: denomination,
      importance: importance,
      visible: visible,
    ),
  );

  @override
  Future<DatingWrite> clearFaith(String key) =>
      _held('clearFaith', () => super.clearFaith(key));
}

Future<void> _tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pumpAndSettle();
}

bool _checked<T>(WidgetTester t, String text) =>
    t
        .widget<RadioListTile<T>>(find.widgetWithText(RadioListTile<T>, text))
        .checked;

bool _noneChecked<T>(WidgetTester t) => t
    .widgetList<RadioListTile<T>>(find.byType(RadioListTile<T>))
    .every((r) => !r.checked);

bool _switch(WidgetTester t, String text) =>
    t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, text)).value;

FlowPrimaryButton _primary(WidgetTester t) =>
    t.widget<FlowPrimaryButton>(find.byType(FlowPrimaryButton));

/// Each of D5-D8 with a profile and the taps that make it ready to save.
typedef _Screen =
    ({
      String name,
      Widget Function(DatingStepNav) build,
      DatingMyProfile profile,
      String write,
      Future<void> Function(WidgetTester t) fill,
    });

final _screens = <_Screen>[
  (
    name: 'D5',
    build: (nav) => DatingYouStep(nav: nav),
    profile: _uk,
    write: 'saveIdentity',
    fill: (t) => _tap(t, find.text('Man')),
  ),
  (
    name: 'D6',
    build: (nav) => DatingMeetStep(nav: nav),
    profile: _uk,
    write: 'saveWhoToMeet',
    fill: (t) => _tap(t, find.text('Men')),
  ),
  (
    name: 'D7',
    build: (nav) => DatingChildrenStep(nav: nav),
    profile: _ghana,
    write: 'saveChildren',
    fill: (t) async {
      await _tap(t, find.text('Yes').first);
      await _tap(t, find.text('Open to it'));
    },
  ),
  (
    name: 'D8',
    build: (nav) => DatingFaithStep(nav: nav),
    profile: _ghana,
    write: 'saveFaith',
    fill: (t) async {
      await _tap(t, find.text('Christian'));
      await _tap(t, find.text('Nice if we share'));
      await _tap(t, find.textContaining('Faith is sensitive information.'));
    },
  ),
];

/// Test-only rows (never a real helpline).
const _testSupport = [
  SupportResource(
    id: 't1',
    countryCode: 'GH',
    category: SupportCategory.lgbtqLegal,
    name: 'Test legal line',
    phone: '055 100 0900',
    url: 'https://example.org/legal',
  ),
  SupportResource(
    id: 't2',
    countryCode: 'GH',
    category: SupportCategory.crisis,
    name: 'Test crisis line',
    phone: '1111',
  ),
  SupportResource(
    id: 't3',
    countryCode: 'GH',
    category: SupportCategory.dv,
    name: 'Test other line',
    phone: '2222',
  ),
];

/// Test-only rows: a police line, a text-only and a WhatsApp-only one.
const _testSupportMore = [
  SupportResource(
    id: 't4',
    countryCode: 'GH',
    category: SupportCategory.crisis,
    name: 'Test police line',
    phone: '3333',
    isPolice: true,
  ),
  SupportResource(
    id: 't5',
    countryCode: 'GH',
    category: SupportCategory.crisis,
    name: 'Test text line',
    sms: '4242',
    hours: 'Open all night',
  ),
  SupportResource(
    id: 't6',
    countryCode: 'GH',
    category: SupportCategory.lgbtqLegal,
    name: 'Test chat line',
    whatsapp: '+233 20 000 0000',
  ),
];

void main() {
  group('D5', () {
    testWidgets('off-country (Ghana): Woman or Man only, the line first, '
        'Why? and Support for you', (t) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
      );
      expect(find.text('Non-binary'), findsNothing);
      expect(find.text('Add something more specific'), findsNothing);
      expect(find.text('Pronouns (optional)'), findsNothing);
      expect(
        find.textContaining('In Ghana, Dating introduces men and women'),
        findsOneWidget,
      );
      final line = t.getTopLeft(
        find.textContaining('In Ghana, Dating introduces men and women'),
      );
      final woman = t.getTopLeft(find.text('Woman'));
      expect(line.dy, lessThan(woman.dy));
      await tapInReach(t, find.text('Woman'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['saveIdentity']);
      expect(r.steps, ['meet']);
    });

    testWidgets('off-country: answers saved while the switch was on are '
        'never sent', (t) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          specific: 'trans_woman',
          pronouns: 'she/her',
        ),
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$1, 'saveIdentity');
      expect(r.setup.lastWrite.$2['specific'], isNull);
      expect(r.setup.lastWrite.$2['pronouns'], isNull);
    });

    testWidgets('a country missing from the lists is treated as off', (
      t,
    ) async {
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        lists: const DatingSetupLists(countries: [ghanaListsUk]),
      );
      expect(find.text('Non-binary'), findsNothing);
      expect(find.text('Pronouns (optional)'), findsNothing);
    });

    testWidgets('off-country: the Why? sheet makes no request (10 S3)', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
      );
      final calls = r.setup.calls.length;
      final reads = r.home.reads;
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'In Ghana, relationships between people of the same gender',
        ),
        findsOneWidget,
      );
      expect(r.setup.calls.length, calls);
      expect(r.home.reads, reads);
      expect(r.rpc, isEmpty);
    });

    testWidgets('on-country (UK): the full set, the own-words field filtered '
        'here and on the server', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Non-binary'));
      await t.pumpAndSettle();
      expect(
        find.text('Should we also introduce you to people looking for:'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Women'));
      await t.pump();
      await tapInReach(t, find.text('Add something more specific'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Genderqueer'));
      await t.enterText(
        find.byKey(const ValueKey('dating_pronouns')),
        'they/them',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['identity'], 'non_binary');
      expect(r.setup.lastWrite.$2['specific'], 'genderqueer');
      expect(r.setup.lastWrite.$2['extraPools'], ['woman']);
      expect(r.setup.lastWrite.$2['pronouns'], 'they/them');
      expect(r.setup.lastWrite.$2['visible'], isFalse);
    });

    testWidgets('a refusal from a modified client reads as not available', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      r.setup.answer = const DatingWrite(ok: false, reason: 'not_available');
      await tapInReach(t, find.text('Man'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text("This choice isn't available here."), findsOneWidget);
    });

    testWidgets('D8: the next account sees nothing of the last one\'s answer '
        'while its read is held', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Non-binary'));
      await t.pumpAndSettle();
      r.setup.holdProfile = Completer<DatingMyProfile>();
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
          .read(datingTestAccount.notifier)
          .state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(
          find.text('Should we also introduce you to people looking for:'),
          findsNothing,
        );
      }
      r.setup.holdProfile!.complete(_uk);
      await t.pumpAndSettle();
    });
  });

  group('D6', () {
    testWidgets('off-country: no choice; "You\'ll be introduced to men."', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        forbidSameGender: true,
      );
      expect(find.text('Everyone'), findsNothing);
      expect(find.text("You'll be introduced to men."), findsOneWidget);
      expect(
        find.textContaining('In Ghana, Attune introduces men and women'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['seeking'], ['man']);
      expect(r.setup.lastWrite.$2['minAge'], 25);
      expect(r.setup.lastWrite.$2['maxAge'], 35);
    });

    testWidgets('on-country, Everyone: the explicit full set', (t) async {
      final r = await _open(t, (nav) => DatingMeetStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Everyone'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['seeking'], ['man', 'non_binary', 'woman']);
    });

    testWidgets('a Tier 1 phone and a choice that includes her own gender: the '
        'note first, never animated; Go back saves nothing', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: _uk,
        lists: const DatingSetupLists(
          countries: [ghanaListsUk],
          phoneCountry: 'GH',
          noteCountry: 'GH',
          defaultAges: (25, 35),
        ),
      );
      await tapInReach(t, find.text('Women'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      expect(find.text('Before you save this'), findsOneWidget);
      expect(
        find.textContaining('Your phone number is from Ghana'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Go back'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['saveWhoToMeet']);
    });

    testWidgets('the slider reads both ends and steps them', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingMeetStep(nav: nav), profile: _uk);
      // Fix 1 (M-2): the label names the end, the value is the age.
      expect(
        t.getSemantics(find.bySemanticsLabel('Youngest')),
        containsSemantics(label: 'Youngest', value: '25'),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Oldest')),
        containsSemantics(label: 'Oldest', value: '35'),
      );
      t.semantics.increase(find.semantics.byLabel('Youngest'));
      await t.pumpAndSettle();
      expect(find.text('Ages 26 to 35'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('D7', () {
    testWidgets('both questions required; no option to seek parents', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingChildrenStep(nav: nav));
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      expect(
        find.textContaining('meet people who have children'),
        findsOneWidget,
      );
      expect(
        find.textContaining(RegExp('only meet people', caseSensitive: false)),
        findsNothing,
      );
      await tapInReach(t, find.text('Yes').first);
      await t.pump();
      await tapInReach(t, find.text('Open to it'));
      await t.pump();
      await tapInReach(
        t,
        find.text("I'd rather not meet people who have children"),
      );
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'have': true,
        'want': 'open',
        'mustMatch': false,
        'excludeParents': true,
      });
      expect(r.steps, ['faith']);
    });
  });

  group('D8', () {
    testWidgets('Skip stores nothing (the clear, never gated)', (t) async {
      final r = await _open(t, (nav) => DatingFaithStep(nav: nav));
      await tapInReach(t, find.text('Skip'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['clearFaith']);
      expect(r.steps, ['photos']);
    });

    testWidgets('a faith needs the importance and the consent', (t) async {
      final r = await _open(t, (nav) => DatingFaithStep(nav: nav));
      await tapInReach(t, find.text('Christian'));
      await t.pumpAndSettle();
      expect(find.text('Denomination (optional)'), findsOneWidget);
      await tapInReach(t, find.text('Methodist'));
      await t.pump();
      await tapInReach(t, find.text('We must share it'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Please agree, or choose Skip.'), findsOneWidget);
      expect(r.setup.writes, isEmpty);
      await tapInReach(
        t,
        find.textContaining('Faith is sensitive information.'),
      );
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['faith'], 'christian');
      expect(r.setup.lastWrite.$2['denomination'], 'methodist');
      expect(r.setup.lastWrite.$2['importance'], 'must_share');
      expect(r.setup.lastWrite.$2['visible'], isFalse);
    });

    testWidgets('the country\'s own list (Ghana has no Hindu row)', (t) async {
      await _open(t, (nav) => DatingFaithStep(nav: nav));
      expect(find.text('Muslim'), findsOneWidget);
      expect(find.text('Hindu'), findsNothing);
    });
  });

  testWidgets('guidelines on every screen, both countries', (t) async {
    final semantics = t.ensureSemantics();
    for (final profile in [_ghana, _uk]) {
      for (final screen in <Widget Function(DatingStepNav)>[
        (nav) => DatingYouStep(nav: nav),
        (nav) => DatingMeetStep(nav: nav),
        (nav) => DatingChildrenStep(nav: nav),
        (nav) => DatingFaithStep(nav: nav),
      ]) {
        await _open(t, screen, profile: profile);
        await expectFlowGuidelines(t);
      }
    }
    semantics.dispose();
  });

  for (final (name, profile, screen)
      in <(String, DatingMyProfile, Widget Function(DatingStepNav))>[
        ('d5_you_off_country', _ghana, (nav) => DatingYouStep(nav: nav)),
        ('d5_you', _uk, (nav) => DatingYouStep(nav: nav)),
        ('d6_meet_off_country', _ghana, (nav) => DatingMeetStep(nav: nav)),
        ('d6_meet', _uk, (nav) => DatingMeetStep(nav: nav)),
        ('d7_children', _ghana, (nav) => DatingChildrenStep(nav: nav)),
        ('d8_faith', _ghana, (nav) => DatingFaithStep(nav: nav)),
      ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => screen(DatingStepNav(next: (_) {}, back: () {}, toMe: () {})),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: profile),
          ),
        ],
      );
    });
  }

  // T7 carries A-H (the frame as Tasks 1-6 left it).
  group('carry A: saved answers per field, D8, one write', () {
    // The spinner never settles, so the read is held on an account switch
    // (pumpFlowScreen settles before a test starts).
    testWidgets('D5: no option until the rule is known (fix 1, M-1); then '
        'every saved answer fills and is sent unchanged', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(_primary(t).onPressed, isNull);
        expect(find.byType(RadioListTile<String>), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      r.setup.holdProfile!.complete(
        const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          identity: 'woman',
          pronouns: 'she/her',
          genderVisible: true,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_checked<String>(t, 'Woman'), isTrue);
      expect(find.text('Non-binary'), findsOneWidget);
      expect(find.text('she/her'), findsWidgets);
      expect(_switch(t, 'Show my gender on my profile'), isTrue);
      await _tap(t, find.text('Man'));
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['identity'], 'man');
      expect(r.setup.lastWrite.$2['pronouns'], 'she/her');
      expect(r.setup.lastWrite.$2['visible'], isTrue);
    });

    testWidgets('D6: ages stepped before the saved answers arrive are kept; '
        'the saved choice fills', (t) async {
      final semantics = t.ensureSemantics();
      final setup = _TestSetup(
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          identity: 'man',
          seeking: ['woman'],
          minAge: 30,
          maxAge: 40,
        ),
      )..holdProfile = Completer<DatingMyProfile>();
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        gateway: setup,
      );
      t.semantics.increase(find.semantics.byLabel('Youngest'));
      await t.pumpAndSettle();
      expect(find.text('Ages 26 to 35'), findsOneWidget);
      expect(_primary(t).onPressed, isNull);
      setup.holdProfile!.complete(setup.profile);
      await t.pumpAndSettle();
      expect(find.text('Ages 26 to 35'), findsOneWidget);
      expect(_checked<String>(t, 'Women'), isTrue);
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['seeking'], ['woman']);
      expect(r.setup.lastWrite.$2['minAge'], 26);
      expect(r.setup.lastWrite.$2['maxAge'], 35);
      semantics.dispose();
    });

    testWidgets('D6: saved ages and choice fill; a saved set the screen '
        "can't show is asked again, never widened", (t) async {
      await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          identity: 'woman',
          seeking: ['man', 'woman'],
          minAge: 30,
          maxAge: 40,
        ),
      );
      expect(find.text('Ages 30 to 40'), findsOneWidget);
      expect(_noneChecked<String>(t), isTrue);
      expect(_primary(t).onPressed, isNull);
    });

    testWidgets('D7: an answer given before the saved ones arrive is kept; '
        'every other saved answer fills and is sent unchanged', (t) async {
      final setup = _TestSetup(
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          childrenHave: false,
          childrenWant: 'no',
          excludeParents: true,
        ),
      )..holdProfile = Completer<DatingMyProfile>();
      final r = await _open(
        t,
        (nav) => DatingChildrenStep(nav: nav),
        gateway: setup,
      );
      await _tap(t, find.text('Yes').first);
      await _tap(t, find.text('Open to it'));
      // Both questions answered, but Continue waits for the saved toggles.
      expect(_primary(t).onPressed, isNull);
      setup.holdProfile!.complete(setup.profile);
      await t.pumpAndSettle();
      expect(_checked<bool>(t, 'Yes'), isTrue);
      expect(_checked<String>(t, 'Open to it'), isTrue);
      expect(
        _switch(t, "I'd rather not meet people who have children"),
        isTrue,
      );
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['have'], isTrue);
      expect(r.setup.lastWrite.$2['want'], 'open');
      expect(r.setup.lastWrite.$2['mustMatch'], isFalse);
      expect(r.setup.lastWrite.$2['excludeParents'], isTrue);
    });

    // D8's list is the profile country's, so nothing can be touched before
    // the read lands; the saved answers fill and are sent unchanged, and a
    // new faith drops the saved denomination.
    testWidgets('D8: saved answers fill and are sent unchanged; a new faith '
        'drops the old denomination', (t) async {
      final r = await _open(
        t,
        (nav) => DatingFaithStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          faith: 'christian',
          denomination: 'methodist',
          importance: 'must_share',
          faithVisible: true,
        ),
      );
      expect(_checked<String>(t, 'Christian'), isTrue);
      expect(_checked<String?>(t, 'Methodist'), isTrue);
      expect(_checked<String>(t, 'We must share it'), isTrue);
      expect(_switch(t, 'Show my faith on my profile'), isTrue);
      await _tap(t, find.textContaining('Faith is sensitive information.'));
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'faith': 'christian',
        'denomination': 'methodist',
        'importance': 'must_share',
        'visible': true,
      });
      await _tap(t, find.text('Muslim'));
      expect(find.text('Denomination (optional)'), findsNothing);
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['faith'], 'muslim');
      expect(r.setup.lastWrite.$2['denomination'], isNull);
    });

    testWidgets('D5: the next account sees nothing typed or picked by the '
        'last one, while its read is held and after', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await _tap(t, find.text('Non-binary'));
      await _tap(t, find.text('Women'));
      await _tap(t, find.text('Add something more specific'));
      await _tap(t, find.text('In my own words'));
      await t.enterText(
        find.byKey(const ValueKey('dating_ownWords')),
        'Two-spirit',
      );
      await t.enterText(find.byKey(const ValueKey('dating_pronouns')), 'xe');
      await _tap(t, find.text('Show my gender on my profile'));
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      void nothingOld() {
        expect(find.text('Two-spirit'), findsNothing);
        expect(find.text('xe'), findsNothing);
        expect(
          find.text('Should we also introduce you to people looking for:'),
          findsNothing,
        );
        expect(_noneChecked<String>(t), isTrue);
        expect(_noneChecked<String?>(t), isTrue);
        expect(_switch(t, 'Show my gender on my profile'), isFalse);
      }

      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        nothingOld();
      }
      r.setup.holdProfile!.complete(
        const DatingMyProfile(countryCode: 'GB', regionCode: 'TLI'),
      );
      await t.pumpAndSettle();
      nothingOld();
      // The more specific choices are closed again: only the link.
      expect(find.byType(RadioListTile<String?>), findsNothing);
      expect(find.text('Add something more specific'), findsOneWidget);
      await _tap(t, find.text('Add something more specific'));
      await _tap(t, find.text('In my own words'));
      expect(find.text('Two-spirit'), findsNothing);
    });

    testWidgets('D6: the next account sees nothing picked by the last one', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          identity: 'woman',
          seeking: ['woman'],
          minAge: 30,
          maxAge: 40,
        ),
      );
      expect(find.text('Ages 30 to 40'), findsOneWidget);
      await _tap(t, find.text('Everyone'));
      t.semantics.increase(find.semantics.byLabel('Youngest'));
      await t.pumpAndSettle();
      expect(find.text('Ages 31 to 40'), findsOneWidget);
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(find.textContaining('to 40'), findsNothing);
        expect(_noneChecked<String>(t), isTrue);
      }
      r.setup.holdProfile!.complete(_uk);
      await t.pumpAndSettle();
      expect(find.text('Ages 25 to 35'), findsOneWidget);
      expect(_noneChecked<String>(t), isTrue);
      semantics.dispose();
    });

    testWidgets('D7: the next account sees nothing picked by the last one', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingChildrenStep(nav: nav));
      await _tap(t, find.text('Yes').first);
      await _tap(t, find.text('Open to it'));
      await _tap(
        t,
        find.text(
          'Only introduce me to people whose answer fits '
          'mine',
        ),
      );
      await _tap(t, find.text("I'd rather not meet people who have children"));
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      void nothingOld() {
        expect(_noneChecked<bool>(t), isTrue);
        expect(_noneChecked<String>(t), isTrue);
        expect(
          _switch(t, 'Only introduce me to people whose answer fits mine'),
          isFalse,
        );
        expect(
          _switch(t, "I'd rather not meet people who have children"),
          isFalse,
        );
      }

      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        nothingOld();
      }
      r.setup.holdProfile!.complete(_ghana);
      await t.pumpAndSettle();
      nothingOld();
    });

    testWidgets('D8: the next account sees nothing picked by the last one', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingFaithStep(nav: nav));
      await _tap(t, find.text('Christian'));
      await _tap(t, find.text('Methodist'));
      await _tap(t, find.text('We must share it'));
      await _tap(t, find.text('Show my faith on my profile'));
      await _tap(t, find.textContaining('Faith is sensitive information.'));
      r.setup.holdProfile = Completer<DatingMyProfile>();
      _c(t).read(datingTestAccount.notifier).state = 'kofi';
      void nothingOld() {
        expect(find.text('Denomination (optional)'), findsNothing);
        expect(find.text('We must share it'), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(_noneChecked<String>(t), isTrue);
      }

      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        nothingOld();
      }
      r.setup.holdProfile!.complete(_ghana);
      await t.pumpAndSettle();
      nothingOld();
      await _tap(t, find.text('Christian'));
      expect(_noneChecked<String?>(t), isTrue);
      expect(_noneChecked<String>(t), isFalse);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(_switch(t, 'Show my faith on my profile'), isFalse);
    });

    for (final s in _screens) {
      testWidgets('${s.name}: a double tap on Continue sends one write', (
        t,
      ) async {
        final setup = _TestSetup(profile: s.profile)..hold = Completer<void>();
        final r = await _open(t, s.build, profile: s.profile, gateway: setup);
        await s.fill(t);
        final go = find.byType(FlowPrimaryButton);
        await tapInReach(t, go);
        await t.tap(go, warnIfMissed: false);
        await t.pump();
        await t.tap(go, warnIfMissed: false);
        setup.hold!.complete();
        await t.pumpAndSettle();
        expect(r.setup.writes.where((w) => w == s.write), hasLength(1));
        expect(r.steps, hasLength(1));
      });
    }

    testWidgets('D8: a double tap on Skip clears once', (t) async {
      final setup = _TestSetup(profile: _ghana)..hold = Completer<void>();
      final r = await _open(
        t,
        (nav) => DatingFaithStep(nav: nav),
        gateway: setup,
      );
      final skip = find.text('Skip');
      await tapInReach(t, skip);
      await t.tap(skip, warnIfMissed: false);
      await t.pump();
      await t.tap(skip, warnIfMissed: false);
      setup.hold!.complete();
      await t.pumpAndSettle();
      expect(r.setup.writes, ['clearFaith']);
      expect(r.steps, ['photos']);
    });

    // A pointer's second tap is absorbed by the Navigator until the next
    // frame; a screen reader's double activation is not, so it is the
    // proof the screen itself shows one note.
    testWidgets('D6: a double activation shows one country note', (t) async {
      final semantics = t.ensureSemantics();
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: _uk,
        lists: const DatingSetupLists(
          countries: [ghanaListsUk],
          phoneCountry: 'GH',
          noteCountry: 'GH',
          defaultAges: (25, 35),
        ),
      );
      await _tap(t, find.text('Women'));
      t.semantics.tap(find.semantics.byLabel('Continue'));
      t.semantics.tap(find.semantics.byLabel('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Before you save this'), findsOneWidget);
      await _tap(t, find.text('Go back'));
      expect(find.text('Before you save this'), findsNothing);
      expect(r.setup.writes, isEmpty);
      semantics.dispose();
    });
  });

  group('carry B: keys', () {
    for (final s in _screens) {
      testWidgets('${s.name}: busy or failed keeps the key; a final answer '
          'settles it', (t) async {
        final r = await _open(t, s.build, profile: s.profile);
        await s.fill(t);
        Future<String> save() async {
          await _tap(t, find.text('Continue'));
          return r.setup.lastWrite.$2['key']! as String;
        }

        r.setup.answer = DatingWrite.busy;
        final first = await save();
        r.setup.answer = DatingWrite.failed;
        expect(await save(), first);
        r.setup.answer = const DatingWrite(ok: true);
        expect(await save(), first);
        expect(await save(), isNot(first));
        expect(r.steps, hasLength(2));
      });
    }
  });

  group('carry C: no server text', () {
    for (final s in _screens) {
      testWidgets('${s.name}: a failed read or write is generic copy, never '
          'the error', (t) async {
        final setup = _TestSetup(profile: s.profile)
          ..profileError = StateError(_leaky);
        await _open(t, s.build, profile: s.profile, gateway: setup);
        expect(find.text('Something went wrong. Try again.'), findsOneWidget);
        expect(find.textContaining('+233'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
        expect(_primary(t).onPressed, isNull);
        setup.profileError = null;
        await _tap(t, find.text('Retry'));
        expect(find.text('Something went wrong. Try again.'), findsNothing);
        await s.fill(t);
        setup.writeError = StateError(_leaky);
        await _tap(t, find.text('Continue'));
        expect(find.text('Something went wrong. Try again.'), findsOneWidget);
        expect(find.textContaining('+233'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
      });
    }

    for (final s in _screens.where((s) => s.name != 'D7')) {
      testWidgets('${s.name}: failed lists are generic copy with Retry', (
        t,
      ) async {
        final setup = _TestSetup(profile: s.profile)
          ..listsError = StateError(_leaky);
        await _open(t, s.build, profile: s.profile, gateway: setup);
        expect(find.text('Something went wrong. Try again.'), findsOneWidget);
        expect(find.textContaining('+233'), findsNothing);
        expect(_primary(t).onPressed, isNull);
        setup.listsError = null;
        await _tap(t, find.text('Retry'));
        expect(find.text('Something went wrong. Try again.'), findsNothing);
        await s.fill(t);
        expect(_primary(t).onPressed, isNotNull);
      });
    }

    test('D5-D8, the note and the support sheet log nothing', () {
      for (final f in [
        'you_step',
        'meet_step',
        'children_step',
        'faith_step',
        'country_note_screen',
        'dating_support_sheet',
      ]) {
        final src =
            File('lib/features/dating/setup/$f.dart').readAsStringSync();
        for (final banned in [
          'print(',
          'debugPrint',
          'dart:developer',
          'toString()',
          'SharedPreferences',
          'Exception',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$f: $banned');
        }
      }
    });
  });

  group('carry D: the age adjustables', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('label, value, the stepped values and only the steps each '
          'end can take (text at $scale)', (t) async {
        final semantics = t.ensureSemantics();
        await _open(
          t,
          (nav) => DatingMeetStep(nav: nav),
          profile: _uk,
          textScale: scale,
        );
        expect(t.takeException(), isNull);
        expect(
          t.getSemantics(find.bySemanticsLabel('Youngest')),
          containsSemantics(
            label: 'Youngest',
            value: '25',
            increasedValue: '26',
            decreasedValue: '24',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ),
        );
        expect(
          t.getSemantics(find.bySemanticsLabel('Oldest')),
          containsSemantics(
            label: 'Oldest',
            value: '35',
            increasedValue: '36',
            decreasedValue: '34',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ),
        );
        t.semantics.decrease(find.semantics.byLabel('Oldest'));
        await t.pumpAndSettle();
        expect(find.text('Ages 25 to 34'), findsOneWidget);
        semantics.dispose();
      });
    }

    testWidgets('at 18 and 99, and with both ends together, no step past '
        'them is offered', (t) async {
      final semantics = t.ensureSemantics();
      for (final (lo, hi) in [(18, 99), (30, 30)]) {
        await _open(
          t,
          (nav) => DatingMeetStep(nav: nav),
          profile: DatingMyProfile(
            countryCode: 'GB',
            regionCode: 'TLI',
            identity: 'woman',
            seeking: const ['man'],
            minAge: lo,
            maxAge: hi,
          ),
        );
        final young = t.getSemantics(find.bySemanticsLabel('Youngest'));
        final old = t.getSemantics(find.bySemanticsLabel('Oldest'));
        expect(young.getSemanticsData().value, '$lo');
        expect(old.getSemanticsData().value, '$hi');
        expect(
          young.getSemanticsData().hasAction(SemanticsAction.decrease),
          lo > 18,
        );
        expect(
          young.getSemanticsData().hasAction(SemanticsAction.increase),
          lo < hi,
        );
        expect(
          old.getSemanticsData().hasAction(SemanticsAction.increase),
          hi < 99,
        );
        expect(
          old.getSemanticsData().hasAction(SemanticsAction.decrease),
          hi > lo,
        );
      }
      semantics.dispose();
    });
  });

  group('carry E: off-country, no same-gender call', () {
    testWidgets('D5: a non-binary answer saved while the switch was on is no '
        'choice; only Woman or Man is sent', (t) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'non_binary',
          pools: ['woman'],
        ),
        forbidSameGender: true,
      );
      expect(_noneChecked<String>(t), isTrue);
      expect(_primary(t).onPressed, isNull);
      await _tap(t, find.text('Woman'));
      await _tap(t, find.text('Continue'));
      expect(r.setup.writes, ['saveIdentity']);
      expect(r.setup.lastWrite.$2['extraPools'], isEmpty);
    });

    testWidgets('D6: a wider set saved while the switch was on is never '
        'sent; a non-binary identity has nothing to send', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          seeking: ['man', 'non_binary', 'woman'],
        ),
        forbidSameGender: true,
      );
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['seeking'], ['man']);
      final nb = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'non_binary',
        ),
        forbidSameGender: true,
      );
      expect(find.textContaining("You'll be introduced to"), findsNothing);
      expect(_primary(t).onPressed, isNull);
      expect(nb.setup.writes, isEmpty);
    });

    testWidgets('D5: Support for you shows the legal and crisis rows, opens '
        'nothing unasked and calls no setup RPC', (t) async {
      final launched = <String>[];
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
        support: _testSupport,
        launched: launched,
      );
      final calls = r.setup.calls.length;
      final reads = r.home.reads;
      await _tap(t, find.text('Support for you'));
      expect(r.supportFor, ['GH']);
      expect(find.text('Test legal line'), findsOneWidget);
      expect(find.text('Test crisis line'), findsOneWidget);
      expect(find.text('Test other line'), findsNothing);
      // A call says it may stay in the call history, and dials the digits.
      await _tap(t, find.text('Call 055 100 0900'));
      expect(
        find.text("Calls may show in your phone's call history."),
        findsOneWidget,
      );
      await _tap(t, find.text('Cancel'));
      expect(launched, isEmpty);
      await _tap(t, find.text('Call 055 100 0900'));
      await _tap(t, find.text('Call'));
      expect(launched, ['tel:0551000900']);
      await _tap(t, find.text('Website'));
      expect(find.text('It may show in your browser history.'), findsOneWidget);
      await _tap(t, find.text('Open'));
      expect(launched.last, 'https://example.org/legal');
      expect(r.setup.calls.length, calls);
      expect(r.home.reads, reads);
      expect(r.rpc, isEmpty);
    });

    testWidgets('D5 support rows (fix 1, I-1): the police tag, and a text- '
        'or WhatsApp-only row can reach someone', (t) async {
      final launched = <String>[];
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
        support: _testSupportMore,
        launched: launched,
      );
      await _tap(t, find.text('Support for you'));
      expect(find.text('Police'), findsOneWidget);
      expect(find.text('Not the police'), findsNWidgets(2));
      expect(find.text('Open all night'), findsOneWidget);
      await _tap(t, find.text('Text 4242'));
      expect(find.text('Messages may stay on your phone.'), findsOneWidget);
      await _tap(t, find.text('Open'));
      expect(launched, ['sms:4242']);
      await _tap(t, find.text('WhatsApp'));
      expect(
        find.text('The chat may stay in WhatsApp on your phone.'),
        findsOneWidget,
      );
      await _tap(t, find.text('Open'));
      expect(launched.last, 'https://wa.me/233200000000');
    });

    testWidgets('D5: with no checked list, Find a helpline opens the '
        'directory after asking', (t) async {
      final launched = <String>[];
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
        launched: launched,
      );
      await _tap(t, find.text('Support for you'));
      await _tap(t, find.text('Find a helpline'));
      expect(find.text('It may show in your browser history.'), findsOneWidget);
      await _tap(t, find.text('Open'));
      expect(launched, [supportDirectoryUrl]);
    });

    testWidgets('D6: the Why? sheet makes no request', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        forbidSameGender: true,
      );
      final calls = r.setup.calls.length;
      final reads = r.home.reads;
      await _tap(t, find.text('Why?'));
      expect(
        find.textContaining(
          'In Ghana, relationships between people of the same gender',
        ),
        findsOneWidget,
      );
      expect(r.setup.calls.length, calls);
      expect(r.home.reads, reads);
      expect(r.rpc, isEmpty);
    });

    testWidgets('D5 own words: refused here unless letters, spaces and '
        'hyphens', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await _tap(t, find.text('Add something more specific'));
      await _tap(t, find.text('In my own words'));
      await t.enterText(
        find.byKey(const ValueKey('dating_ownWords')),
        'call 0244',
      );
      await _tap(t, find.text('Continue'));
      expect(
        find.text('Use letters, spaces and hyphens only, up to 30.'),
        findsOneWidget,
      );
      expect(r.setup.writes, isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('dating_ownWords')),
        'Two-spirit',
      );
      await t.pump();
      expect(
        find.text('Use letters, spaces and hyphens only, up to 30.'),
        findsNothing,
      );
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['specific'], 'Two-spirit');
    });
  });

  group('carry F: routes', () {
    testWidgets('D5-D8 open at their step paths, behind the Dating lock', (
      t,
    ) async {
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('you'),
        locked: true,
        pinSet: true,
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: _uk),
          ),
        ],
      );
      expect(s.location, startsWith('/dating/unlock?from='));
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
      expect(find.text('Which best describes you?'), findsNothing);
      s.container.read(datingUnlockedProvider.notifier).unlock();
      for (final (step, screen) in [
        ('you', DatingYouStep),
        ('meet', DatingMeetStep),
        ('children', DatingChildrenStep),
        ('faith', DatingFaithStep),
      ]) {
        s.router.go(DatingPaths.step(step));
        await t.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: step);
        expect(s.location, DatingPaths.step(step));
      }
    });

    testWidgets('the country note: Set a PIN first opens the PIN setup, then '
        'back to the note; Save goes on to D7 (R-18)', (t) async {
      final setup = FakeDatingSetupGateway(
        profile: _uk,
        listsValue: const DatingSetupLists(
          countries: [ghanaListsUk],
          phoneCountry: 'GH',
          noteCountry: 'GH',
          defaultAges: (25, 35),
        ),
      );
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('meet'),
        overrides: [datingSetupGatewayProvider.overrideWithValue(setup)],
      );
      await _tap(t, find.text('Women'));
      await _tap(t, find.text('Continue'));
      expect(find.text('Before you save this'), findsOneWidget);
      await _tap(t, find.text('Set a PIN first'));
      expect(find.text('PIN SETUP'), findsOneWidget);
      s.router.pop();
      await t.pumpAndSettle();
      expect(find.text('Before you save this'), findsOneWidget);
      expect(setup.writes, isEmpty);
      await _tap(t, find.text('Save'));
      expect(setup.writes, ['saveWhoToMeet']);
      expect(find.byType(DatingChildrenStep), findsOneWidget);
    });
  });

  group('carry G: dark theme and large text', () {
    testWidgets('D5-D8 and the sheets in the dark theme: tokens only, '
        'contrast holds', (t) async {
      final semantics = t.ensureSemantics();
      final dark = AppTheme.darkTheme;
      for (final profile in [_ghana, _uk]) {
        for (final screen in <Widget Function(DatingStepNav)>[
          (nav) => DatingYouStep(nav: nav),
          (nav) => DatingMeetStep(nav: nav),
          (nav) => DatingChildrenStep(nav: nav),
          (nav) => DatingFaithStep(nav: nav),
        ]) {
          await _open(t, screen, profile: profile, theme: dark);
          expect(
            t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
            dark.colorScheme.surface,
          );
          await expectFlowGuidelines(t);
        }
      }
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        theme: dark,
        support: _testSupport,
      );
      await _tap(t, find.text('Why?'));
      await expectFlowGuidelines(t);
      await _tap(t, find.text('Close'));
      await _tap(t, find.text('Support for you'));
      expect(find.text('Test legal line'), findsOneWidget);
      await expectFlowGuidelines(t);
      // The refusal row in dark (the theme's own red) and light (#C62828).
      for (final (theme, red) in [
        (dark, dark.colorScheme.error),
        (AppTheme.lightTheme, const Color(0xFFC62828)),
      ]) {
        final r = await _open(
          t,
          (nav) => DatingYouStep(nav: nav),
          profile: _uk,
          theme: theme,
        );
        r.setup.answer = const DatingWrite(ok: false, reason: 'not_available');
        await _tap(t, find.text('Man'));
        await _tap(t, find.text('Continue'));
        final icon = find.descendant(
          of: find.byType(FlowErrorLine),
          matching: find.byType(Icon),
        );
        expect(t.widget<Icon>(icon).color, red);
        await expectFlowGuidelines(t);
      }
      semantics.dispose();
    });

    testWidgets('the country note in the dark theme, and at 2.0', (t) async {
      final semantics = t.ensureSemantics();
      for (final (theme, scale) in [
        (AppTheme.darkTheme, 1.0),
        (AppTheme.lightTheme, 2.0),
      ]) {
        await t.pumpWidget(const SizedBox());
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearAllTestValues);
        DatingNoteChoice? choice;
        await t.pumpWidget(
          ScreenUtilConfig.builder(
            builder:
                (_) => MaterialApp(
                  theme: theme,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Builder(
                    builder:
                        (context) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () async {
                                choice = await showDatingCountryNote(
                                  context,
                                  country: 'GH',
                                );
                              },
                              child: const Text('open'),
                            ),
                          ),
                        ),
                  ),
                ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pump();
        // Never animated (§3.15): there on the first frame.
        expect(find.text('Before you save this'), findsOneWidget);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          t.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
          theme.colorScheme.surface,
        );
        await expectFlowGuidelines(t);
        await _tap(t, find.text('Go back'));
        expect(choice, DatingNoteChoice.back);
      }
      semantics.dispose();
    });

    testWidgets('the Why? and support sheets at 2.0: nothing clipped, '
        'Close in reach', (t) async {
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        textScale: 2.0,
        support: _testSupport,
      );
      await _tap(t, find.text('Why?'));
      expect(t.takeException(), isNull);
      await _tap(t, find.text('Close'));
      expect(find.text('Close'), findsNothing);
      await _tap(t, find.text('Support for you'));
      expect(find.text('Test crisis line'), findsOneWidget);
      expect(t.takeException(), isNull);
      await _tap(t, find.text('Close'));
      expect(find.text('Close'), findsNothing);
    });
  });

  group('fix round 1', () {
    // I-2: the note for a Tier 1/2 phone when the choice includes the
    // person's own gender, or the person is non-binary (§3.2 D6).
    const noteLists = DatingSetupLists(
      countries: [ghanaListsUk],
      phoneCountry: 'GH',
      noteCountry: 'GH',
      defaultAges: (25, 35),
    );
    DatingMyProfile ukAs(String identity) => DatingMyProfile(
      countryCode: 'GB',
      regionCode: 'TLI',
      identity: identity,
    );

    testWidgets('I-2: a non-binary person choosing Men sees the note; Go '
        'back saves nothing', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: ukAs('non_binary'),
        lists: noteLists,
      );
      await _tap(t, find.text('Men'));
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      expect(find.text('Before you save this'), findsOneWidget);
      await _tap(t, find.text('Go back'));
      expect(r.setup.writes, isEmpty);
    });

    testWidgets('I-2: a woman choosing Men sees no note; the answer is saved', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: ukAs('woman'),
        lists: noteLists,
      );
      await _tap(t, find.text('Men'));
      await _tap(t, find.text('Continue'));
      expect(find.text('Before you save this'), findsNothing);
      expect(r.setup.writes, ['saveWhoToMeet']);
      expect(r.setup.lastWrite.$2['seeking'], ['man']);
    });

    testWidgets('I-2: a man choosing Everyone sees the note', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: ukAs('man'),
        lists: noteLists,
      );
      await _tap(t, find.text('Everyone'));
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      expect(find.text('Before you save this'), findsOneWidget);
      await _tap(t, find.text('Save'));
      expect(r.setup.lastWrite.$2['seeking'], datingEveryone);
    });

    testWidgets('M-3: D6 off-country with a non-binary answer says why '
        'nothing can be chosen', (t) async {
      await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'non_binary',
        ),
        forbidSameGender: true,
      );
      expect(
        find.text(
          'In Ghana, Dating introduces men and women to each other for now. '
          "If neither of these fits you, Dating can't introduce you safely "
          'here yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Why?'), findsOneWidget);
      expect(_primary(t).onPressed, isNull);
    });

    testWidgets('M-4: a saved denomination no longer on the list is not '
        'sent', (t) async {
      final r = await _open(
        t,
        (nav) => DatingFaithStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          faith: 'christian',
          denomination: 'anglican',
          importance: 'nice_to_share',
        ),
      );
      expect(_noneChecked<String?>(t), isTrue);
      await _tap(t, find.textContaining('Faith is sensitive information.'));
      await _tap(t, find.text('Continue'));
      expect(r.setup.lastWrite.$2['faith'], 'christian');
      expect(r.setup.lastWrite.$2['denomination'], isNull);
    });
  });

  group('M-5: quick exit', () {
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

    testWidgets('from D5 with own words typed: nothing of it stays', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('you'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: _uk),
          ),
        ],
      );
      await _tap(t, find.text('Add something more specific'));
      await _tap(t, find.text('In my own words'));
      await t.enterText(
        find.byKey(const ValueKey('dating_ownWords')),
        'Two-spirit',
      );
      await t.pump();
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.text('Two-spirit', skipOffstage: false), findsNothing);
      expect(find.byType(DatingYouStep, skipOffstage: false), findsNothing);
    });

    testWidgets('from D6 with the country note up: the note goes too', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('meet'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(
              profile: _uk,
              listsValue: const DatingSetupLists(
                countries: [ghanaListsUk],
                phoneCountry: 'GH',
                noteCountry: 'GH',
                defaultAges: (25, 35),
              ),
            ),
          ),
        ],
      );
      await _tap(t, find.text('Women'));
      await _tap(t, find.text('Continue'));
      expect(find.text('Before you save this'), findsOneWidget);
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(
        find.text('Before you save this', skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(DatingMeetStep, skipOffstage: false), findsNothing);
    });

    testWidgets('from D5 with the support sheet up: the sheet goes too', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.step('you'),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: _ghana),
          ),
          supportResourcesProvider.overrideWith(
            (ref, country) async => const SupportResources(
              country: 'GH',
              countrySupported: true,
              catalogueVersion: 'test',
              resources: _testSupport,
              fromServer: false,
            ),
          ),
        ],
      );
      await _tap(t, find.text('Support for you'));
      expect(find.text('Test legal line'), findsOneWidget);
      await quickExit(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.text('Test legal line', skipOffstage: false), findsNothing);
    });
  });
}
