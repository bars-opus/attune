// Spec 5 (R5-9, R5-10; plan review C2-C4, I4): while the invite waits — a
// gentle line before 48 hours, the private reflection space from 48 hours,
// and at a week three plain choices. Time comes from the server.
import 'dart:io';

import 'package:attune/features/onboarding/presentation/widgets/couples_waiting_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInvites extends RelationshipInviteService {
  _FakeInvites(this.age);
  Duration? age;
  final calls = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    calls.add(forceNew ? 'create:new' : 'create');
    return RelationshipInvite(
      relationshipId: 'r1',
      code: forceNew ? 'NEW00002' : 'LIVE0001',
      expiresAt: DateTime.utc(2026, 10, 25),
    );
  }

  @override
  Future<Duration?> inviteAge() async => age;

  @override
  Future<void> withdrawPendingInvites() async => calls.add('withdraw');
}

Future<_FakeInvites> _pump(WidgetTester t, Duration? age, {VoidCallback? onFinish, VoidCallback? onUseAlone}) async {
  t.view.physicalSize = const Size(1170, 5000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  final fake = _FakeInvites(age);
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(
      home: Scaffold(
        body: OnboardingDeckScope(
          cardKey: 3,
          accent: OnboardingDeckAccent.couples,
          enableDeck: false,
          child: CouplesWaitingStep(
            inviteService: fake,
            onFinish: onFinish ?? () {},
            onUseAlone: onUseAlone,
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(seconds: 1)); // past the route's entry transition
  return fake;
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.pump();
  await t.tap(find.text(label));
}

void main() {
  testWidgets('at 47 hours: a gentle line and Continue, no reflection card yet', (t) async {
    var finished = 0;
    await _pump(t, const Duration(hours: 47), onFinish: () => finished++);
    expect(find.text("We'll suggest a private reflection space if this takes a little while."), findsOneWidget);
    expect(find.text('Open reflection mode'), findsNothing);
    await _tap(t, 'Continue');
    expect(finished, 1);
  });

  testWidgets('at 49 hours: the private reflection space', (t) async {
    var finished = 0;
    await _pump(t, const Duration(hours: 49), onFinish: () => finished++);
    expect(find.text('A private space while you wait'), findsOneWidget);
    expect(find.text('Your reflections stay private to you.'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await _tap(t, 'Open reflection mode');
    expect(finished, 1);
  });

  testWidgets('at a week: keep waiting, on my own, or someone else', (t) async {
    var alone = 0;
    final f = await _pump(t, const Duration(days: 7, hours: 1), onUseAlone: () => alone++);
    expect(find.text("It's been a week"), findsOneWidget);
    await _tap(t, 'Keep waiting');
    await t.pump();
    await _tap(t, 'Invite someone else');
    await t.pump();
    await _tap(t, 'Use Attune on my own for now');
    await t.pump();
    await t.pump();
    // First call is the load; then a plain re-fetch, a new code, a withdraw.
    expect(f.calls, ['create', 'create', 'create:new', 'withdraw']);
    expect(alone, 1);
  });

  testWidgets('at a week, deciding later is still possible (final review I-1)', (t) async {
    var finished = 0;
    await _pump(t, const Duration(days: 8), onFinish: () => finished++);
    expect(find.text('Your invite has run its week. What would you like to do?'), findsOneWidget);
    await _tap(t, 'Continue');
    expect(finished, 1);
  });

  test('onboarding finishes "on my own" as personal, never pending (final review I-1)', () {
    final src = File('lib/features/onboarding/presentation/screens/onboarding_flow.dart').readAsStringSync();
    expect(RegExp(r'onUseAlone: \(\) \{\s*setState\(\(\) => _mode = OnboardingMode\.personal\);\s*_finish\(\);').hasMatch(src), isTrue);
  });

  testWidgets('no clock from the server: treated as just started', (t) async {
    await _pump(t, null);
    expect(find.text('Continue'), findsOneWidget);
  });

  test('the locked Chat screen shows the same guide (plan review I4)', () {
    final src = File('lib/features/chat/presentation/screens/chat_couples_locked_screen.dart').readAsStringSync();
    expect(src, contains('PendingInviteGuide('));
    expect(src, contains('inviteAge()'));
    expect(src, contains('withdrawPendingInvites()'));
  });

  test('leaving pending mode drops the withdrawn invite card (final review I-2)', () {
    final src = File('lib/features/chat/presentation/screens/chat_couples_locked_screen.dart').readAsStringSync();
    final at = src.indexOf('void didUpdateWidget(');
    expect(at, greaterThan(-1));
    final body = src.substring(at, src.indexOf('\n  }\n', at));
    expect(body, contains('oldWidget.isPendingCouples && !widget.isPendingCouples'));
    expect(body, contains('_invite = null'));
  });
}
