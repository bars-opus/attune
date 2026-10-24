import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_question_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// 36 Questions screens stay mounted behind the privacy cover and during
/// the Safety lock's return check (stories Wave 3). Before, leaving the
/// screen unmounted them, which stopped the waiting poll and re-read the
/// partner's answer on the way back. The Supabase reads are injected.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [partnerNameProvider.overrideWith((ref) async => 'Sam')],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester t, Widget screen) async {
    // A large phone: wide enough for the test font's square glyphs.
    t.view.physicalSize = const Size(480, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(home: screen),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> lifecycle(WidgetTester t, List<AppLifecycleState> states) async {
    for (final s in states) {
      t.binding.handleAppLifecycleStateChanged(s);
      await t.pump();
    }
  }

  const away = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const back = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  group('the waiting screen', () {
    testWidgets('reads nothing while Attune is not on screen or the lock is '
        'checking, and reads once as soon as it is on screen again', (t) async {
      var reads = 0;
      await pump(
        t,
        ThirtySixWaitingScreen(
          sessionId: 's1',
          roundId: 'r1',
          roundNumber: 1,
          totalRounds: 12,
          chapter: 1,
          questionText: 'Would you like to be famous?',
          answerText: 'Not really.',
          readRound: (_) async {
            reads++;
            return {'both_answered': false, 'reveal_triggered_at': null};
          },
          watchRound: (_, _) => () {},
        ),
      );
      await t.pump(const Duration(seconds: 2));
      expect(reads, 1);

      // Control Centre: the cover is up, the screen is still mounted.
      await lifecycle(t, [AppLifecycleState.inactive]);
      await t.pump(const Duration(seconds: 10));
      expect(reads, 1, reason: 'no DB read behind the cover');
      await lifecycle(t, [AppLifecycleState.resumed]);
      expect(reads, 2, reason: 'one read as soon as it is on screen again');

      // An app switch that returns to the lock's check (as the gate does).
      await lifecycle(t, away);
      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      await t.pump(const Duration(minutes: 5));
      await lifecycle(t, back);
      await t.pump(const Duration(seconds: 10));
      expect(reads, 2, reason: 'no DB read away or while the lock checks');
      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await t.pump();
      expect(reads, 3);

      await t.pump(const Duration(seconds: 2));
      expect(reads, 4, reason: 'the poll carries on while on screen');
    });
  });

  group('the question screen', () {
    testWidgets('re-reads whether the partner answered when Attune is on '
        'screen again, and not before', (t) async {
      var partnerAnswered = false;
      var checks = 0;
      await pump(
        t,
        ThirtySixQuestionScreen(
          sessionId: 's1',
          chapter: 1,
          loadOpenRound:
              () async => (
                id: 'r1',
                number: 1,
                text: 'Would you like to be famous?',
              ),
          readPartnerAnswered: (_) async {
            checks++;
            return partnerAnswered;
          },
          watchRound: (_, _) => () {},
        ),
      );
      await t.pump();
      expect(find.text('Would you like to be famous?'), findsOneWidget);
      expect(find.text('Sam waiting'), findsOneWidget);
      expect(checks, 1);

      // Away for a while; the partner answers, and this phone's socket
      // missed it.
      await lifecycle(t, away);
      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      partnerAnswered = true;
      await lifecycle(t, back);
      await t.pump();
      expect(checks, 1, reason: 'nothing is read while the lock checks');

      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await t.pump();
      await t.pump();
      expect(checks, 2);
      expect(find.text('Sam answered'), findsOneWidget);

      // A Control Centre pull catches up too.
      await lifecycle(t, [AppLifecycleState.inactive]);
      expect(checks, 2);
      await lifecycle(t, [AppLifecycleState.resumed]);
      expect(checks, 3);
    });
  });
}
