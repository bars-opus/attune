// Spec 2 W5c Task 9 rulings (§3.12, §3.15; carry 16): the settings row is
// offered on a phone Dating doesn't trust (adding only reduces exposure,
// and the add answers "Added." there too); the labelled buttons can be
// used by a screen reader, and Remove is read as dimmed when it can't be
// used; a list read that fails outright says so. Fix round 1: rows are
// spoken with a comma (M-3) and Remove goes through its confirm (I-2).
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

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
  items: [DatingNeverIntroduceItem(id: 'n1', label: 'Kwame', lastTwo: '42')],
);

class _FailingRead extends FakeNeverIntroduce {
  @override
  Future<DatingNeverIntroduceList> list() async {
    reads++;
    throw StateError('offline');
  }
}

void main() {
  final loc = AppLocalizationsEn();

  testWidgets(
    'Ruling 2: on a phone Dating does not trust, the row is offered and '
    'the add still answers "Added."',
    (t) async {
      final fake = FakeNeverIntroduce(
        const DatingNeverIntroduceList(reason: 'reverify_device'),
      );
      await pumpDatingShell(
        t,
        initial: DatingPaths.settings,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.reverifyDevice),
        ),
        overrides: [
          datingNeverIntroduceGatewayProvider.overrideWithValue(fake),
        ],
      );
      await tap(t, find.text(loc.dating_neverTitle));
      await t.pumpAndSettle();
      expect(find.byType(DatingNeverIntroduceScreen), findsOneWidget);
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('dating_never_number')),
        '0241234567',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      expect(fake.adds.single.$2, '+233241234567');
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
    },
  );

  testWidgets('Ruling 3: a screen reader can open the picker and Remove; '
      'offline Remove is dimmed', (t) async {
    final semantics = t.ensureSemantics();
    final fake = FakeNeverIntroduce(_list);
    final remove = loc.dating_neverRemoveLabel(
      loc.dating_neverRowSpoken('Kwame', '42'),
    );
    await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      overrides: [datingNeverIntroduceGatewayProvider.overrideWithValue(fake)],
    );
    final node = t.getSemantics(find.bySemanticsLabel(remove));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
    final picker = t.getSemantics(
      find.bySemanticsLabel(loc.dating_neverCountryCode('+233')),
    );
    expect(picker.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.semantics.tap(find.semantics.byLabel(remove));
    await t.pumpAndSettle();
    // Fix 1 (I-2): the confirm opens; its Remove sends.
    expect(fake.removes, isEmpty);
    await tapInReach(
      t,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(loc.dating_neverRemove),
      ),
    );
    await t.pumpAndSettle();
    expect(fake.removes, ['n1']);
    semantics.dispose();
  });

  testWidgets('Ruling 3: offline, Remove is read as dimmed and does nothing', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final fake = FakeNeverIntroduce(_list);
    final remove = loc.dating_neverRemoveLabel(
      loc.dating_neverRowSpoken('Kwame', '42'),
    );
    await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      online: false,
      overrides: [datingNeverIntroduceGatewayProvider.overrideWithValue(fake)],
    );
    final node = t.getSemantics(find.bySemanticsLabel(remove));
    expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('Ruling 4: a list read that fails outright says so', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      overrides: [
        datingNeverIntroduceGatewayProvider.overrideWithValue(_FailingRead()),
      ],
    );
    expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    // The add still works: it never depends on the read.
    expect(find.text(loc.dating_neverAdd), findsOneWidget);
  });
}
