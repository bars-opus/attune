// Spec 1 W3c (§3.10 J3, §2.4): the weekly reminder: its summary, its sheet,
// 08:00-21:59 only, turning it off keeps day and time, and the contextual
// notification ask inside the sheet while notifications are off.
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/flow_harness.dart';

Future<(FlowHarness, FakeReminderRpc, FakePushAsker)> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? stored,
  bool pushGranted = true,
  int failReads = 0,
}) async {
  // A fresh ProviderScope each time (pumpWidget would reuse the last one).
  await tester.pumpWidget(const SizedBox());
  final rpc = FakeReminderRpc();
  if (stored != null) rpc.stored = stored;
  rpc.failReads = failReads;
  final asker = FakePushAsker(granted: pushGranted);
  final h = await pumpFlowScreen(
    tester,
    () => const Scaffold(body: JournalReminderRow()),
    overrides: [
      journalReminderRpcProvider.overrideWithValue(rpc.call),
      pushAskerProvider.overrideWithValue(asker),
    ],
  );
  return (h, rpc, asker);
}

void main() {
  test('the wire shape and the allowed times', () {
    final r = JournalReminder.fromJson({
      'enabled': true,
      'iso_weekday': 3,
      'local_time': '20:15',
    });
    expect(r.enabled, isTrue);
    expect(r.isoWeekday, 3);
    expect(r.time, const TimeOfDay(hour: 20, minute: 15));
    expect(JournalReminder.fromJson(null).enabled, isFalse);
    expect(reminderWireTime(const TimeOfDay(hour: 8, minute: 5)), '08:05');
    expect(reminderTimeAllowed(const TimeOfDay(hour: 8, minute: 0)), isTrue);
    expect(reminderTimeAllowed(const TimeOfDay(hour: 21, minute: 59)), isTrue);
    expect(reminderTimeAllowed(const TimeOfDay(hour: 22, minute: 0)), isFalse);
    expect(reminderTimeAllowed(const TimeOfDay(hour: 7, minute: 59)), isFalse);
  });

  testWidgets('the row reads "Off", then "{weekday}s at {time}"', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Remind me to write'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await _pump(
      tester,
      stored: {'enabled': true, 'iso_weekday': 1, 'local_time': '20:00'},
    );
    expect(find.text('Mondays at 08:00 PM'), findsOneWidget);
  });

  testWidgets('turning it on: the chosen day at 20:00 by default', (
    tester,
  ) async {
    final (_, rpc, _) = await _pump(tester);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    expect(find.text('When should we remind you?'), findsOneWidget);
    expect(find.text('Turn off'), findsNothing);
    await tester.tap(find.text('Wed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    final set = rpc.calls.firstWhere((c) => c.$1 == 'set_my_journal_reminder');
    expect(set.$2, {
      'p_enabled': true,
      'p_iso_weekday': 3,
      'p_local_time': '20:00',
    });
    expect(find.text('Wednesdays at 08:00 PM'), findsOneWidget);
  });

  testWidgets('turning it off keeps the day and time', (tester) async {
    final (_, rpc, _) = await _pump(
      tester,
      stored: {'enabled': true, 'iso_weekday': 5, 'local_time': '09:30'},
    );
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    final set = rpc.calls.lastWhere((c) => c.$1 == 'set_my_journal_reminder');
    expect(set.$2, {
      'p_enabled': false,
      'p_iso_weekday': 5,
      'p_local_time': '09:30',
    });
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('a refused quiet-hours time is explained, not saved', (
    tester,
  ) async {
    final (_, rpc, _) = await _pump(tester);
    rpc.failWith = const PostgrestException(
      message: 'journal_reminder:quiet_hours',
      code: 'P0001',
    );
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reminders can be set from 08:00 AM to 09:59 PM.'),
      findsOneWidget,
    );
  });

  // Owner ruling P-20: the picker never takes a time outside 08:00-21:59
  // (the server's CHECK); it keeps the last good time and says why.
  Future<void> pickTime(
    WidgetTester tester,
    String h,
    String m,
    String ampm,
  ) async {
    await tester.tap(find.text('Change time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), h);
    await tester.enterText(fields.at(1), m);
    await tester.tap(find.text(ampm));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('the picker refuses 10:30 PM and keeps 08:00 PM (P-20)', (
    tester,
  ) async {
    final (_, rpc, _) = await _pump(tester);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    await pickTime(tester, '10', '30', 'PM');
    expect(
      find.text('Reminders can be set from 08:00 AM to 09:59 PM.'),
      findsOneWidget,
    );
    expect(find.text('08:00 PM'), findsOneWidget);
    expect(find.text('10:30 PM'), findsNothing);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    final set = rpc.calls.lastWhere((c) => c.$1 == 'set_my_journal_reminder');
    expect(set.$2!['p_local_time'], '20:00');
  });

  testWidgets('the picker refuses 07:59 AM and takes 09:45 PM (P-20)', (
    tester,
  ) async {
    final (_, rpc, _) = await _pump(tester);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    await pickTime(tester, '7', '59', 'AM');
    expect(find.text('08:00 PM'), findsOneWidget);
    expect(
      find.text('Reminders can be set from 08:00 AM to 09:59 PM.'),
      findsOneWidget,
    );
    await pickTime(tester, '9', '45', 'PM');
    expect(find.text('09:45 PM'), findsOneWidget);
    expect(
      find.text('Reminders can be set from 08:00 AM to 09:59 PM.'),
      findsNothing,
    );
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    final set = rpc.calls.lastWhere((c) => c.$1 == 'set_my_journal_reminder');
    expect(set.$2!['p_local_time'], '21:45');
  });

  // B7 review I-1: an unreadable reminder is unknown, never "Off", and is
  // read again; the real day and time are never overwritten meanwhile.
  const friday = {'enabled': true, 'iso_weekday': 5, 'local_time': '09:30'};

  testWidgets('unreadable at first: not "Off"; opening the sheet reads again', (
    tester,
  ) async {
    await _pump(tester, stored: friday, failReads: 1);
    expect(find.text('Off'), findsNothing);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off'), findsOneWidget);
    expect(find.text('Fridays at 09:30 AM'), findsOneWidget);
  });

  testWidgets('still unreadable: says so, offers no Turn on, then retries', (
    tester,
  ) async {
    final (_, rpc, _) = await _pump(tester, stored: friday, failReads: 2);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't load your reminder. Try again."),
      findsOneWidget,
    );
    expect(find.text('Turn on'), findsNothing);
    expect(find.text('Turn off'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off'), findsOneWidget);
    expect(rpc.calls.where((c) => c.$1 == 'set_my_journal_reminder'), isEmpty);
  });

  testWidgets('unreadable at first: read again on resume', (tester) async {
    await _pump(tester, stored: friday, failReads: 1);
    expect(find.text('Fridays at 09:30 AM'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Fridays at 09:30 AM'), findsOneWidget);
  });

  testWidgets('unreadable at first: read again a little later (reconnect)', (
    tester,
  ) async {
    await _pump(tester, stored: friday, failReads: 1);
    expect(find.text('Fridays at 09:30 AM'), findsNothing);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Fridays at 09:30 AM'), findsOneWidget);
  });

  testWidgets('notifications off: the J3 ask is in the sheet', (tester) async {
    final (h, _, asker) = await _pump(tester, pushGranted: false);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    expect(find.text('Reminders need notifications.'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.j3]);
    expect(find.text('Reminders need notifications.'), findsNothing);
    expect(h.metrics, ['push_ask_shown:j3', 'push_ask_granted:j3']);
  });

  testWidgets('notifications on: no ask, nothing counted', (tester) async {
    final (h, _, _) = await _pump(tester);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    expect(find.byType(PushAskRow), findsOneWidget);
    expect(find.text('Reminders need notifications.'), findsNothing);
    expect(h.metrics, isEmpty);
  });

  testWidgets('the sheet meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, pushGranted: false);
    await tester.tap(find.text('Remind me to write'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('J3 sheet goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'j3_sheet',
      () => const Scaffold(body: JournalReminderSheet()),
      overrides: [
        journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
  });
}
