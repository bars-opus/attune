// Spec 2 W3a Task 4 fix round 1 (Minor 5): turning "Tell me when Dating
// opens" off is never silent: busy and failed answers say so, the switch
// waits while the cancel runs, and a saved cancel re-reads the home.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

const _asked = DatingHome(
  state: DatingHomeState.countryClosed,
  country: 'NG',
  hasData: true,
  notice: DatingNotice(available: true, requested: true),
);

Future<FakeDatingHomeGateway> _pump(WidgetTester t) async {
  final home = FakeDatingHomeGateway(home: _asked);
  await pumpFlowScreen(
    t,
    () => const DatingSettingsScreen(),
    overrides: datingShellOverrides(home: home),
  );
  return home;
}

void main() {
  for (final (result, text) in [
    (
      DatingNoticeResult.busy,
      'This is taking a little longer than usual. Try again in a moment.',
    ),
    (DatingNoticeResult.failed, 'Something went wrong. Try again.'),
  ]) {
    testWidgets('a ${result.name} cancel says so; the row stays on', (t) async {
      final home = await _pump(t);
      home.noticeResult = result;
      await tapInReach(t, find.text('Tell me when Dating opens'));
      await t.pumpAndSettle();
      expect(home.cancels, 1);
      expect(find.text(text), findsOneWidget);
      final row = t.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Tell me when Dating opens'),
      );
      expect(row.value, isTrue);
      expect(row.onChanged, isNotNull);
    });
  }

  testWidgets('the switch waits while the cancel runs; saved re-reads the '
      'home and the row goes', (t) async {
    final home = await _pump(t);
    home.noticeHold = Completer<void>();
    final reads = home.reads;
    home.home = const DatingHome(
      state: DatingHomeState.countryClosed,
      country: 'NG',
      notice: DatingNotice(available: true),
    );
    final row = find.widgetWithText(
      SwitchListTile,
      'Tell me when Dating opens',
    );
    await tapInReach(t, row);
    await t.pump();
    expect(t.widget<SwitchListTile>(row).onChanged, isNull);
    await t.tap(row, warnIfMissed: false);
    await t.pump();
    expect(home.cancels, 1);
    home.noticeHold!.complete();
    await t.pumpAndSettle();
    expect(home.reads, reads + 1);
    expect(find.text('Tell me when Dating opens'), findsNothing);
  });
}
