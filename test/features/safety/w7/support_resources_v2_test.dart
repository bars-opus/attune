// Spec 1 W7a (§8 W7a, §2.3): Support resources v2. Today's screen while
// support_resources_v2 is off; with it on: the country line, emergency
// first, every number and link only after a confirmation that says what it
// may leave on the phone, "Not the police" on help that isn't, the
// fallback for a country without a checked list, the grief and youth
// views; goldens at 1.0, 1.3, 2.0 and right to left.
//   flutter test --update-goldens test/features/safety/w7/support_resources_v2_test.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

Map<String, Object?> _entry(
  String n,
  String country,
  String category,
  String name, {
  int sort = 100,
  String? url,
  String? phone = '0800 000 000',
  String? sms,
  String? whatsapp,
  bool police = false,
}) => {
  'id': '5f7a0000-0000-0000-0000-0000000000$n',
  'country_code': country,
  'category': category,
  'name': name,
  'phone': phone,
  'sms': sms,
  'whatsapp': whatsapp,
  'url': url,
  'languages': <String>[],
  'is_police': police,
  'sort_order': sort,
  'verified_at': '2026-11-03',
  'verified_by': 'test fixture',
};

/// Test rows only (never the shipped catalogue; plan P-4).
final _fixture = jsonEncode({
  'catalogue_version': 'fixture-1',
  'resources': [
    _entry(
      '01',
      'GH',
      'emergency',
      'Fixture emergency',
      phone: '999',
      police: true,
    ),
    _entry('02', 'GH', 'dv', 'Fixture police unit', sort: 10, police: true),
    _entry(
      '03',
      'GH',
      'dv',
      'Fixture DV line',
      sort: 20,
      url: 'https://dv.example.org/help',
    ),
    _entry('04', 'GH', 'grief', 'Fixture grief line', sort: 10),
    _entry(
      '05',
      'XX',
      'crisis',
      'Fixture directory',
      url: 'https://findahelpline.com',
      phone: null,
    ),
  ],
});

class _Launches {
  final urls = <String>[];
}

List<Override> _overrides(
  _Launches launches, {
  bool v2 = true,
  String? region = 'GH',
  bool signedIn = false,
}) => [
  supportResourcesV2Provider.overrideWithValue(v2),
  supportResourcesRepositoryProvider.overrideWithValue(
    SupportResourcesRepository(
      rpc: (_, __) async => throw StateError('offline'),
      loadBundled: () async => _fixture,
    ),
  ),
  deviceCountryProvider.overrideWith(
    (ref) async => (sim: null, region: region),
  ),
  supportLauncherProvider.overrideWithValue(
    (context, url) async => launches.urls.add(url),
  ),
  safetySelfCheckEnabledProvider.overrideWith((ref) async => false),
  homeAuthProvider.overrideWithValue(
    FakeHomeAuth(signedIn ? testUser('u-support') : null),
  ),
];

const _noPinOffer = {SafetyPinPromptCard.dismissedKey: true};

Future<FlowHarness> _pump(
  WidgetTester tester,
  _Launches launches, {
  bool v2 = true,
  String? region = 'GH',
  SupportFocus? focus,
  bool signedIn = false,
  Size size = const Size(390, 844),
}) => pumpFlowScreen(
  tester,
  () => SafetyResourcesScreen(focus: focus),
  prefsValues: _noPinOffer,
  overrides: _overrides(launches, v2: v2, region: region, signedIn: signedIn),
  size: size,
);

/// A test's second pump reuses the first one's ProviderScope container, so
/// its overrides (the country, the repository) are not applied again: one
/// country per testWidgets (batch-2 review m5).
List<Override> _textAndWhatsApp(_Launches launches) => [
  ..._overrides(launches),
  supportResourcesRepositoryProvider.overrideWithValue(
    SupportResourcesRepository(
      rpc: (_, __) async => throw StateError('offline'),
      loadBundled:
          () async => jsonEncode({
            'catalogue_version': 'fixture-3',
            'resources': [
              _entry(
                '21',
                'GH',
                'crisis',
                'Fixture text line',
                phone: null,
                sms: '116 123',
                whatsapp: '+233 20 000 0000',
              ),
            ],
          }),
    ),
  ),
];

void main() {
  testWidgets('flag off: today\'s screen, unchanged', (tester) async {
    // A tall view: today's helpline cards overflow a 390-wide phone (a
    // pre-existing layout bug of the v1 screen, plan P-14; not touched).
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), v2: false),
      size: const Size(800, 1600),
    );
    expect(find.text('Helplines'), findsOneWidget);
    expect(find.text('Ghana Police DOVVSU'), findsOneWidget);
    expect(find.byType(SupportResourcesV2Screen), findsNothing);
  });

  testWidgets('flag on: the country, emergency first, the tags', (
    tester,
  ) async {
    await _pump(tester, _Launches());
    expect(find.byType(SupportResourcesV2Screen), findsOneWidget);
    expect(find.text('Help for Ghana'), findsOneWidget);
    final emergency = tester.getTopLeft(find.text('In an emergency')).dy;
    final abuse = tester.getTopLeft(find.text('Domestic abuse')).dy;
    expect(emergency, lessThan(abuse));
    expect(
      tester.getTopLeft(find.text('Fixture police unit')).dy,
      lessThan(tester.getTopLeft(find.text('Fixture DV line')).dy),
    );
    expect(find.text('Police'), findsNWidgets(2));
    // The DV line, the grief line and the directory.
    expect(find.text('Not the police'), findsNWidgets(3));
    expect(find.text('Anywhere in the world'), findsOneWidget);
    expect(find.text('Fixture directory'), findsOneWidget);
    expect(find.text('Helplines'), findsNothing);
  });

  testWidgets('a call is confirmed first, and says what it leaves', (
    tester,
  ) async {
    final launches = _Launches();
    await _pump(tester, launches);
    await tapInReach(tester, find.text('Call 999'));
    await tester.pumpAndSettle();
    expect(find.text('Call 999?'), findsOneWidget);
    expect(
      find.text("Calls may show in your phone's call history."),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches.urls, isEmpty);
    await tester.tap(find.text('Call 999'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Call'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['tel:999']);
  });

  testWidgets('a website is confirmed first too', (tester) async {
    final launches = _Launches();
    await _pump(tester, launches);
    await tester.ensureVisible(find.text('Website').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Website').first);
    await tester.pumpAndSettle();
    expect(find.text('Open dv.example.org?'), findsOneWidget);
    expect(find.text('It may show in your browser history.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['https://dv.example.org/help']);
  });

  testWidgets('a country without a checked list: the fallback', (tester) async {
    final launches = _Launches();
    await _pump(tester, launches, region: 'KE');
    expect(find.text('Help for Kenya'), findsOneWidget);
    expect(
      find.text("We don't have a checked list for Kenya yet."),
      findsOneWidget,
    );
    expect(
      find.text('In an emergency, call your local emergency number.'),
      findsOneWidget,
    );
    expect(find.text('Fixture DV line'), findsNothing);
    await tapInReach(tester, find.text('Find a helpline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['https://findahelpline.com']);
  });

  testWidgets('a checked list without an emergency number says what to do', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: [
        ..._overrides(_Launches(), region: 'GB'),
        supportResourcesRepositoryProvider.overrideWithValue(
          SupportResourcesRepository(
            rpc: (_, __) async => throw StateError('offline'),
            loadBundled:
                () async => jsonEncode({
                  'catalogue_version': 'fixture-2',
                  'resources': [
                    _entry('11', 'GB', 'dv', 'Fixture GB line'),
                    _entry(
                      '12',
                      'XX',
                      'crisis',
                      'Fixture directory',
                      url: 'https://findahelpline.com',
                      phone: null,
                    ),
                  ],
                }),
          ),
        ),
      ],
    );
    expect(find.text('Fixture GB line'), findsOneWidget);
    expect(find.text('In an emergency'), findsNothing);
    expect(
      find.text('In an emergency, call your local emergency number.'),
      findsOneWidget,
    );
  });

  testWidgets('no country known: asked to choose one', (tester) async {
    await _pump(tester, _Launches(), region: null);
    expect(
      find.text('Choose your country to see help near you.'),
      findsOneWidget,
    );
    await tapInReach(tester, find.text('Choose a country'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneCountryPickerSheet), findsOneWidget);
  });

  testWidgets('a chosen country is used, and kept in memory only', (
    tester,
  ) async {
    final harness = await _pump(tester, _Launches(), region: 'KE');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SupportResourcesV2Screen)),
    );
    container.read(supportCountryOverrideProvider.notifier).state = 'GH';
    await tester.pumpAndSettle();
    expect(find.text('Help for Ghana'), findsOneWidget);
    expect(find.text('Fixture DV line'), findsOneWidget);
    expect(
      harness.prefs.getKeys().where(
        (k) => k != SafetyPinPromptCard.dismissedKey,
      ),
      isEmpty,
    );
  });

  testWidgets('grief: grief help and the journal, signed in', (tester) async {
    await _pump(tester, _Launches(), focus: SupportFocus.grief, signedIn: true);
    expect(find.text('Grief support'), findsOneWidget);
    expect(find.text('Fixture grief line'), findsOneWidget);
    expect(find.text('Fixture DV line'), findsNothing);
    expect(find.text('Fixture emergency'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Write about it in your journal'),
      200,
    );
    await tapInReach(tester, find.text('Write about it in your journal'));
    await tester.pumpAndSettle();
    expect(find.text('at /reflectionJournal'), findsOneWidget);
  });

  // Final review M-7: someone who has just lost a person is never told
  // help is "Not relevant right now"; a focused view's way out says Back.
  testWidgets('grief and youth: the way out says Back', (tester) async {
    final harness = await _pump(
      tester,
      _Launches(),
      focus: SupportFocus.grief,
      size: const Size(390, 2400),
    );
    expect(find.text('Not relevant right now'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(harness.location, '/home');
  });

  testWidgets('youth: the way out says Back too', (tester) async {
    await _pump(
      tester,
      _Launches(),
      focus: SupportFocus.youth,
      size: const Size(390, 2400),
    );
    expect(find.text('Not relevant right now'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
  });

  testWidgets('grief, signed out: no journal', (tester) async {
    await _pump(tester, _Launches(), focus: SupportFocus.grief);
    expect(find.text('Write about it in your journal'), findsNothing);
  });

  testWidgets('youth with no list: fallback', (tester) async {
    await _pump(tester, _Launches(), focus: SupportFocus.youth);
    expect(find.text('Support for young people'), findsOneWidget);
    expect(
      find.text("We don't have a checked list for this in Ghana yet."),
      findsOneWidget,
    );
    expect(find.text('Find a helpline'), findsOneWidget);
  });

  testWidgets('nothing moves and quick exit is in reach', (tester) async {
    await _pump(tester, _Launches());
    expect(find.byTooltip('Quick exit'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    await tester.scrollUntilVisible(find.text('Exit now'), 200);
    expect(find.text('Exit now'), findsOneWidget);
  });

  // A tall surface, so the lazy list builds every control (batch-2 review
  // I1); one country per test (m5).
  testWidgets('accessibility guidelines: Ghana, the whole list', (
    tester,
  ) async {
    await _pump(tester, _Launches(), size: const Size(390, 2400));
    expect(find.text('Exit now'), findsOneWidget);
    expect(find.text('Not relevant right now'), findsOneWidget);
    await expectFlowGuidelines(tester);
  });

  testWidgets('accessibility guidelines: Kenya, the fallback', (tester) async {
    await _pump(tester, _Launches(), region: 'KE', size: const Size(390, 2400));
    expect(find.text('Find a helpline'), findsOneWidget);
    expect(find.text('Exit now'), findsOneWidget);
    await expectFlowGuidelines(tester);
  });

  testWidgets('accessibility guidelines: the confirmation', (tester) async {
    await _pump(tester, _Launches());
    await tapInReach(tester, find.text('Call 999'));
    await tester.pumpAndSettle();
    expect(find.text('Call 999?'), findsOneWidget);
    await expectFlowGuidelines(tester);
  });

  testWidgets('a text is confirmed first, and says what it leaves', (
    tester,
  ) async {
    final launches = _Launches();
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _textAndWhatsApp(launches),
      size: const Size(390, 2400),
    );
    await tester.tap(find.text('Text 116 123'));
    await tester.pumpAndSettle();
    expect(find.text('Text 116 123?'), findsOneWidget);
    expect(find.text('Messages may stay on your phone.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches.urls, isEmpty);
    await tester.tap(find.text('Text 116 123'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['sms:116123']);
  });

  testWidgets('WhatsApp is confirmed first, and says it stays in WhatsApp', (
    tester,
  ) async {
    final launches = _Launches();
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _textAndWhatsApp(launches),
      size: const Size(390, 2400),
    );
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('Open WhatsApp?'), findsOneWidget);
    expect(
      find.text('The chat may stay in WhatsApp on your phone.'),
      findsOneWidget,
    );
    expect(find.text('It may show in your browser history.'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches.urls, isEmpty);
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['https://wa.me/233200000000']);
  });

  testWidgets('the country picker is on screen in the first frame', (
    tester,
  ) async {
    await _pump(tester, _Launches(), region: null);
    await tapInReach(tester, find.text('Choose a country'));
    await tester.pump();
    expect(find.byType(PhoneCountryPickerSheet), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(PhoneCountryPickerSheet)).dy,
      lessThan(844 * 0.2),
    );
  });

  testWidgets('"Not relevant right now" leaves even with nothing to pop', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      _Launches(),
      size: const Size(390, 2400),
    );
    await tester.tap(find.text('Not relevant right now'));
    await tester.pumpAndSettle();
    expect(harness.location, '/home');
  });

  testWidgets('a load that fails is not "no checked list"', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: [
        ..._overrides(_Launches()),
        supportResourcesRepositoryProvider.overrideWithValue(
          SupportResourcesRepository(
            rpc: (_, __) async => throw StateError('offline'),
            loadBundled: () async => throw StateError('no bundle'),
          ),
        ),
      ],
      size: const Size(390, 2400),
    );
    expect(find.text('Help for Ghana'), findsOneWidget);
    expect(find.textContaining("We don't have a checked list"), findsNothing);
    expect(find.text('Find a helpline'), findsOneWidget);
    expect(
      find.text('In an emergency, call your local emergency number.'),
      findsOneWidget,
    );
  });

  // "Exit now" stays a red danger button, at 4.5:1 in both themes (§2.3;
  // B2 fix round 2): the app's error/onError pair is 3.7:1 in light.
  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('"Exit now" is red and at least 4.5:1 ($name)', (tester) async {
      await pumpFlowScreen(
        tester,
        () => Theme(data: theme, child: const SafetyResourcesScreen()),
        prefsValues: _noPinOffer,
        overrides: _overrides(_Launches()),
        size: const Size(390, 2400),
      );
      final style =
          tester
              .widget<FilledButton>(
                find.ancestor(
                  of: find.text('Exit now'),
                  matching: find.byType(FilledButton),
                ),
              )
              .style!;
      final background = style.backgroundColor!.resolve({})!;
      final foreground = style.foregroundColor!.resolve({})!;
      // Red: the red channel well above green and blue.
      expect(background.r, greaterThan(background.g + 0.3));
      expect(background.r, greaterThan(background.b + 0.3));
      final l1 = background.computeLuminance();
      final l2 = foreground.computeLuminance();
      final ratio = (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'ratio $ratio');
    });
  }

  testWidgets('goldens: Ghana', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_ghana',
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches()),
    );
  });

  // The cards, tags and buttons at every size (batch-2 review m4): the
  // plain goldens end, at 2.0, before the first card.
  testWidgets('goldens: Ghana, the cards', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_ghana_cards',
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches()),
      before: (t) async {
        await t.drag(find.byType(ListView), const Offset(0, -700));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('goldens: no checked list', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_unsupported',
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), region: 'KE'),
    );
  });

  testWidgets('goldens: grief', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_grief',
      () => const SafetyResourcesScreen(focus: SupportFocus.grief),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), signedIn: true),
    );
  });

  // The shell clamps every route to 1.0, dialogs and sheets included, and
  // pumpFlowScreen's builder does the same (final review I-1): the call
  // confirmation and the country picker let large text through, to 2.0.
  double renderedScale(WidgetTester tester, Finder text) =>
      tester.renderObject<RenderParagraph>(text).textScaler.scale(10) / 10;

  testWidgets('the confirmation is drawn at the phone\'s large text', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches()),
      textScale: 2.0,
      size: const Size(390, 2400),
    );
    // Under the 1.0 clamp: the Navigator, and so every route, reads 1.0.
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(Navigator).first),
      ).scale(10),
      10,
    );
    await tester.ensureVisible(find.text('Call 999'));
    await tester.tap(find.text('Call 999'));
    await tester.pumpAndSettle();
    expect(
      renderedScale(
        tester,
        find.text("Calls may show in your phone's call history."),
      ),
      2.0,
    );
    expect(renderedScale(tester, find.text('Call 999?')), 2.0);
    expect(renderedScale(tester, find.text('Cancel')), 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the country picker is drawn at the phone\'s large text', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), region: null),
      textScale: 2.0,
      size: const Size(390, 2400),
    );
    await tester.tap(find.text('Choose a country'));
    await tester.pumpAndSettle();
    final sheetText =
        find
            .descendant(
              of: find.byType(PhoneCountryPickerSheet),
              matching: find.byType(RichText),
            )
            .first;
    expect(renderedScale(tester, sheetText), 2.0);
    expect(tester.takeException(), isNull);
  });
}
