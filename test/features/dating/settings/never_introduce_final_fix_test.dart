// Spec 2 W5 final fix wave (final-client-review.md), "Never introduce me":
// Remove's confirm names the row it removes, with a no-name form (M-3, T9
// N-1); a number of a possible length for its country is taken even when
// the bundled ranges don't list it, while garbage and wrong lengths are
// still refused (M-6, T9 N-2 Ruling); the country code holds still while
// an add is out (M-7, T9 N-3); and the page and the confirm in dark (M-14).
import 'dart:async';

import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/never_introduce_phone.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _list = DatingNeverIntroduceList(
  ok: true,
  items: [
    DatingNeverIntroduceItem(id: 'n1', label: 'Kwame', lastTwo: '42'),
    DatingNeverIntroduceItem(id: 'n2', lastTwo: '07'),
  ],
);

final _number = find.byKey(const ValueKey('dating_never_number'));

PhoneCountry _country(String iso) =>
    PhoneCountries.all.firstWhere((c) => c.isoCode == iso);

void main() {
  final loc = AppLocalizationsEn();

  setUp(() => WidgetsApp.debugAllowBannerOverride = false);
  tearDown(() => WidgetsApp.debugAllowBannerOverride = true);

  Future<FakeNeverIntroduce> open(
    WidgetTester t, {
    FakeNeverIntroduce? fake,
    bool dark = false,
  }) async {
    final f = fake ?? FakeNeverIntroduce(_list);
    await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      overrides: [datingNeverIntroduceGatewayProvider.overrideWithValue(f)],
      wrap:
          dark
              ? (_, child) => Theme(data: AppTheme.darkTheme, child: child)
              : null,
    );
    return f;
  }

  Finder removeOf(String spoken) =>
      find.bySemanticsLabel(loc.dating_neverRemoveLabel(spoken));

  group('M-3: the confirm names the row', () {
    testWidgets('a named row: "Remove Kwame, ending 42?"', (t) async {
      await open(t);
      await tap(t, removeOf(loc.dating_neverRowSpoken('Kwame', '42')));
      await t.pumpAndSettle();
      expect(
        find.text(loc.dating_neverRemoveTitleNamed('Kwame', '42')),
        findsOneWidget,
      );
      expect(find.text('Remove Kwame, ending 42?'), findsOneWidget);
      expect(find.text(loc.dating_neverRemoveTitle), findsNothing);
    });

    testWidgets('a row with no name: "Remove the number ending 07?"', (
      t,
    ) async {
      await open(t);
      await tap(t, removeOf(loc.dating_neverRowNoLabel('07')));
      await t.pumpAndSettle();
      expect(
        find.text(loc.dating_neverRemoveTitleNoName('07')),
        findsOneWidget,
      );
      expect(find.text('Remove the number ending 07?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('Kwame'),
        ),
        findsNothing,
      );
    });
  });

  group('M-6: a number of a possible length is taken', () {
    test('ranges the bundled metadata doesn\'t list; the rest still holds', () {
      final gh = _country('GH');
      final gb = _country('GB');
      for (final (text, country, want) in [
        // Ghana ranges newer than the metadata (T9 N-2).
        ('025 123 4567', gh, '+233251234567'),
        ('0601234567', gh, '+233601234567'),
        ('+233 25 123 4567', gb, '+233251234567'),
        // The UK number the review found refused.
        ('+447911123456', gh, '+447911123456'),
        ('07911 123456', gb, '+447911123456'),
        // Known numbers read as before.
        ('024 123 4567', gh, '+233241234567'),
        ('+44 7400 123456', gh, '+447400123456'),
        // Still refused: not digits, too short, too long, wrong country.
        ('024-ABC-4567', gh, null),
        ('0241234', gh, null),
        ('024123456789', gh, null),
        ('07400 123456', gh, null),
        ('+233 24', gh, null),
        ('+999 1234 5678', gh, null),
        ('++233241234567', gh, null),
        // The parser alone would drop these stray marks and take the rest.
        ('024 123 4567x', gh, null),
        ('024*1234567', gh, null),
        ('024 123 4567;', gh, null),
      ]) {
        expect(
          datingNeverE164(text, country),
          want,
          reason: '$text (${country.isoCode})',
        );
      }
    });

    testWidgets('the add sends a GH 025 number and says "Added."', (t) async {
      final fake = await open(t);
      await t.enterText(_number, '025 123 4567');
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      expect(fake.adds.single.$2, '+233251234567');
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
      expect(find.text(loc.dating_neverCheckNumber), findsNothing);
    });
  });

  testWidgets('M-7: the country code holds still while an add is out', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final fake = FakeNeverIntroduce(_list)..addHold = Completer<void>();
    await open(t, fake: fake);
    await t.enterText(_number, '0241234567');
    await t.pump();
    await tap(t, find.text(loc.dating_neverAdd));
    expect(fake.adds, hasLength(1));
    final code = find.widgetWithText(OutlinedButton, '+233');
    expect(t.widget<OutlinedButton>(code).onPressed, isNull);
    final node = t.getSemantics(
      find.bySemanticsLabel(loc.dating_neverCountryCode('+233')),
    );
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    // (The Add button's busy spinner turns: no settle while it does.)
    await tapInReach(t, code);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsNothing);
    fake.addHold!.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(loc.dating_neverAdded), findsOneWidget);
    expect(t.widget<OutlinedButton>(code).onPressed, isNotNull);
    handle.dispose();
  });

  testWidgets('M-14: the manual names the person, and says a listed '
      'person\'s introduction is taken away', (t) async {
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
    final match = content('dating_double_opt_in');
    expect(match, contains('"You and (the person\'s name) are both'));
    expect(match, isNot(contains('their name')));
    final never = content('dating_never_introduce');
    expect(never, contains('An introduction already made is taken away;'));
    expect(never, isNot(contains('at your next answer')));
  });

  group('M-14: dark', () {
    testWidgets('the page: golden and guidelines', (t) async {
      await open(t, dark: true);
      expect(find.text(loc.dating_neverTitle), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/never_introduce.dark.png'),
      );
      await expectFlowGuidelines(t);
    });

    testWidgets('the Remove confirm: golden and guidelines', (t) async {
      await open(t, dark: true);
      await tap(t, removeOf(loc.dating_neverRowSpoken('Kwame', '42')));
      await t.pumpAndSettle();
      expect(
        find.text(loc.dating_neverRemoveTitleNamed('Kwame', '42')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/never_introduce_remove.dark.png'),
      );
      await expectFlowGuidelines(t);
    });
  });
}
