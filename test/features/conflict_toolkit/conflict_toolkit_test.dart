// Spec 8 (research 06 B3, 05 Part C; plan review C2, I4, I5, M2, M3, M8):
// the conflict toolkit. Fixed words, editable scaffolds that only fill the
// composer, a timer only the sender sees, one optional fixed reply, and
// nothing anywhere that counts or records who used what.
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/conflict_toolkit/data/pause_service.dart';
import 'package:attune/features/conflict_toolkit/data/pause_timer_store.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/apology_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/hard_moment_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_reply_chip.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_timer_card.dart';
import 'package:attune/features/conflict_toolkit/presentation/repair_tray.dart';
import 'package:attune/features/conflict_toolkit/presentation/start_conversation_sheet.dart';
import 'package:attune/features/safety/presentation/outside_perspective_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePauseService extends PauseService {
  final replies = <String>[];
  bool available = true;

  @override
  Future<bool> replyAvailable(String pauseMessageId) async => available;

  @override
  Future<void> reply({
    required String pauseMessageId,
    required String clientMessageId,
  }) async {
    replies.add(pauseMessageId);
    available = false;
  }
}

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
      ),
    );

/// A button that opens [open] and keeps what it returned.
class _Opener<T> extends StatefulWidget {
  const _Opener(this.open, this.result);
  final Future<T?> Function(BuildContext) open;
  final ValueNotifier<T?> result;
  @override
  State<_Opener<T>> createState() => _OpenerState<T>();
}

class _OpenerState<T> extends State<_Opener<T>> {
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () async => widget.result.value = await widget.open(context),
    child: const Text('open'),
  );
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Message _msg(
  String type, {
  bool mine = false,
  DateTime? at,
  bool deleted = false,
}) => Message(
  id: 'p1',
  clientMessageId: 'c1',
  relationshipId: 'r1',
  senderId: mine ? 'me' : 'them',
  content: type == 'pause' ? kPauseTexts[1]! : kPauseReplyText,
  createdAt: at ?? DateTime.now(),
  status: MessageStatus.sent,
  isMine: mine,
  mediaType: type,
  deletedAt: deleted ? DateTime.now() : null,
);

void main() {
  group('pause messages in the chat', () {
    test('never edited, still deletable, never sent to Ask Attune', () {
      for (final type in ['pause', 'pause_reply']) {
        final m = _msg(type, mine: true);
        expect(m.canEdit(currentUserId: 'me', now: DateTime.now()), isFalse);
        expect(m.canDelete(currentUserId: 'me', now: DateTime.now()), isTrue);
        expect(m.isEligibleForAskAttune, isFalse);
      }
      expect(_msg('pause').isPause, isTrue);
      expect(_msg('pause_reply').isPauseReply, isTrue);
    });

    test('the chip is asked about only under a fresh, received pause', () {
      final now = DateTime.now();
      expect(mayOfferPauseReply(_msg('pause', at: now), now), isTrue);
      expect(
        mayOfferPauseReply(_msg('pause', mine: true, at: now), now),
        isFalse,
      );
      expect(mayOfferPauseReply(_msg('pause_reply', at: now), now), isFalse);
      expect(
        mayOfferPauseReply(_msg('pause', at: now, deleted: true), now),
        isFalse,
      );
      expect(
        mayOfferPauseReply(
          _msg('pause', at: now.subtract(const Duration(minutes: 61))),
          now,
        ),
        isFalse,
      );
    });
  });

  group('fixed words', () {
    test('the six repair phrases, verbatim (Part C)', () {
      expect(kRepairPhrases, const [
        'Can we start over?',
        'I see my part in this.',
        'That came out wrong.',
        "I'm on your side, even now.",
        'Can we slow down?',
        "I need a minute, then I'm back.",
      ]);
    });

    test('the pause texts mirror the server and each names a return', () {
      expect(
        kPauseTexts[1],
        "I'm getting flooded. I'm stepping back for 30 minutes, not away "
        "from you. I'll come back.",
      );
      expect(kPauseTexts.keys, [1, 2, 3]);
      for (final v in kPauseTexts.keys) {
        expect(kPauseTexts[v], contains('${kPauseMinutes[v]} minutes'));
        expect(kPauseMinutes[v], inInclusiveRange(20, 45));
      }
      // Only the spec's own wording ships without a marker.
      expect(kPauseTexts[2], startsWith('[DRAFT]'));
      expect(kPauseTexts[3], startsWith('[DRAFT]'));
      final sql =
          File(
            'supabase/migrations/20261018150100_pause_messages.sql',
          ).readAsStringSync();
      for (final t in kPauseTexts.values) {
        expect(sql.contains(t.replaceAll("'", "''")), isTrue, reason: t);
      }
      expect(kPauseReplyText, "Okay. I'll be here.");
    });

    test('the apology line, verbatim', () {
      expect(kApologyLine, "A promise isn't a repair; an action is.");
    });

    test('the toolkit shows only when both flags are on (I5)', () {
      expect(toolkitVisible(toolkit: true, safetyCheck: true), isTrue);
      expect(toolkitVisible(toolkit: true, safetyCheck: false), isFalse);
      expect(toolkitVisible(toolkit: false, safetyCheck: true), isFalse);
    });
  });

  group('scaffolds', () {
    test(
      'an apology in the person\'s own words, never asking for anything',
      () {
        final text = assembleApology(
          did: 'snapped at you about the dishes.',
          cost: 'left you doing it all',
          repair: 'do them tonight',
          different: 'take a breath before I answer',
        );
        expect(
          text,
          "I'm sorry I snapped at you about the dishes. I know that left you "
          "doing it all. To make it right, I'll do them tonight. Next time, "
          "I'll take a breath before I answer.",
        );
        expect(assembleApology(did: '  '), isNull);
        expect(assembleApology(did: 'was late'), "I'm sorry I was late.");
        expect(text!.toLowerCase().contains('forgive'), isFalse);
      },
    );

    test('a conversation start with the seventh need', () {
      expect(
        assembleConversationStart(
          observation: 'plans change at the last minute',
          feeling: 'unsettled',
          need: 'communal_obligation',
          request: 'tell me a day ahead?',
        ),
        'When plans change at the last minute, I feel unsettled. I need to '
        'honour my family and community. Would you tell me a day ahead?',
      );
      expect(kConversationNeeds.length, 7);
      expect(assembleConversationStart(observation: 'x', feeling: ''), isNull);
    });
  });

  group('sheets', () {
    testWidgets('the hard-moment group offers four tools and the outside '
        'perspective', (tester) async {
      _tallView(tester);
      final result = ValueNotifier<HardMomentAction?>(null);
      await tester.pumpWidget(_app(_Opener(showHardMomentSheet, result)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('In a hard moment'), findsOneWidget);
      for (final t in [
        'Take a pause',
        'Repair',
        'Help me apologise',
        'Start a conversation',
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A trained outside perspective'));
      await tester.pumpAndSettle();
      expect(find.byType(OutsidePerspectiveScreen), findsOneWidget);
    });

    testWidgets('a pause sends the chosen variant, once', (tester) async {
      _tallView(tester);
      final sent = <(int, String)>[];
      final result = ValueNotifier<bool?>(null);
      await tester.pumpWidget(
        _app(
          _Opener(
            (c) =>
                showPauseSheet(c, onSend: (v, id) async => sent.add((v, id))),
            result,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Take a pause'), findsOneWidget);
      expect(find.text('Only you see the timer.'), findsOneWidget);
      await tester.tap(find.text(kPauseTexts[3]!));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent.single.$1, 3);
      expect(result.value, isTrue);
    });

    testWidgets('the repair tray hands back a phrase and sends nothing', (
      tester,
    ) async {
      final result = ValueNotifier<String?>(null);
      await tester.pumpWidget(_app(_Opener(showRepairTray, result)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Can we slow down?'));
      await tester.pumpAndSettle();
      expect(result.value, 'Can we slow down?');
    });

    // Final review m-6: at large text every phrase still reads in full.
    testWidgets('the repair tray wraps at 2x text', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final result = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        ProviderScope(
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => MaterialApp(
                  builder:
                      (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: const TextScaler.linear(2)),
                        child: child!,
                      ),
                  home: Scaffold(body: _Opener(showRepairTray, result)),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final phrase in kRepairPhrases) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(phrase),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: phrase);
        expect(
          tester.getRect(find.text(phrase)).right,
          lessThanOrEqualTo(390),
          reason: '$phrase runs off the screen',
        );
      }
      // The longest phrase needs more than one line here, and gets it.
      expect(
        tester.getSize(find.text("I need a minute, then I'm back.")).height,
        greaterThan(tester.getSize(find.text('Can we slow down?')).height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the apology scaffold fills the composer, with the action line',
      (tester) async {
        _tallView(tester);
        final result = ValueNotifier<String?>(null);
        await tester.pumpWidget(_app(_Opener(showApologySheet, result)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text(kApologyLine), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('apology-did')),
          'forgot your exam',
        );
        await tester.pump();
        await tester.tap(find.text('Add to message'));
        await tester.pumpAndSettle();
        expect(result.value, "I'm sorry I forgot your exam.");
      },
    );

    testWidgets('asking for forgiveness gets a gentle note', (tester) async {
      _tallView(tester);
      final result = ValueNotifier<String?>(null);
      await tester.pumpWidget(_app(_Opener(showApologySheet, result)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('apology-did')),
        'lied, please forgive me',
      );
      await tester.pump();
      expect(find.text(kNoForgivenessNote), findsOneWidget);
    });

    testWidgets('the conversation start offers the seven needs', (
      tester,
    ) async {
      _tallView(tester);
      final result = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        _app(_Opener(showStartConversationSheet, result)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in kConversationNeeds.values) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.enterText(
        find.byKey(const Key('start-observation')),
        'we rush mornings',
      );
      await tester.enterText(find.byKey(const Key('start-feeling')), 'tense');
      await tester.tap(find.text(kConversationNeeds['rest']!));
      await tester.pump();
      await tester.tap(find.text('Add to message'));
      await tester.pumpAndSettle();
      expect(
        result.value,
        'When we rush mornings, I feel tense. I need some rest.',
      );
    });
  });

  group('the sender\'s timer', () {
    test('kept on this device, keyed by relationship', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 10, 18, 9);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pauseClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(pauseTimerProvider('r1')), isNull);
      await c.read(pauseTimerProvider('r1').notifier).start(30);
      expect(
        c.read(pauseTimerProvider('r1')),
        now.add(const Duration(minutes: 30)),
      );
      expect(prefs.getKeys(), {'pause_timer_end_r1'});
      // Survives a restart.
      final c2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pauseClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c2.dispose);
      expect(
        c2.read(pauseTimerProvider('r1')),
        now.add(const Duration(minutes: 30)),
      );
      expect(c2.read(pauseTimerProvider('r2')), isNull);
      await c2.read(pauseTimerProvider('r1').notifier).clear();
      expect(prefs.getKeys(), isEmpty);
    });

    testWidgets('counts down, then offers a gentle return', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 10, 18, 9);
      var started = false;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pauseClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      await container.read(pauseTimerProvider('r1').notifier).start(30);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => MaterialApp(
                  home: Scaffold(
                    body: PauseTimerCard(
                      relationshipId: 'r1',
                      onStartConversation: () => started = true,
                    ),
                  ),
                ),
          ),
        ),
      );
      expect(find.text('Back in about 30 min'), findsOneWidget);
      expect(find.text(kSelfSoothingCopy), findsOneWidget);
      now = now.add(const Duration(minutes: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text(kReturnPrompt), findsOneWidget);
      await tester.tap(find.text('Start a conversation'));
      await tester.pump();
      expect(started, isTrue);
      expect(container.read(pauseTimerProvider('r1')), isNull);
      expect(find.text(kReturnPrompt), findsNothing);
    });
  });

  group('the reply chip', () {
    testWidgets('offered while the server says so; one tap, then gone', (
      tester,
    ) async {
      final fake = _FakePauseService();
      await tester.pumpWidget(
        _app(
          const PauseReplyChip(pauseMessageId: 'p1'),
          overrides: [pauseServiceProvider.overrideWithValue(fake)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(kPauseReplyText));
      await tester.pumpAndSettle();
      expect(fake.replies, ['p1']);
      expect(find.text(kPauseReplyText), findsNothing);
    });

    testWidgets('absent when the server says no', (tester) async {
      final fake = _FakePauseService()..available = false;
      await tester.pumpWidget(
        _app(
          const PauseReplyChip(pauseMessageId: 'p1'),
          overrides: [pauseServiceProvider.overrideWithValue(fake)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(kPauseReplyText), findsNothing);
    });
  });

  test('nothing in the toolkit writes a table, counts, or keeps a record', () {
    final allowedRpcs = {'send_pause', 'send_pause_reply', 'pause_reply_state'};
    for (final f
        in Directory(
          'lib/features/conflict_toolkit',
        ).listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(
        src.contains('.from('),
        isFalse,
        reason: '${f.path} touches a table',
      );
      for (final m in RegExp(r"rpc\(\s*'([a-z_]+)'").allMatches(src)) {
        expect(allowedRpcs, contains(m.group(1)), reason: f.path);
      }
      expect(
        RegExp(
          r'count|tally|history|analytics',
          caseSensitive: false,
        ).hasMatch(src),
        isFalse,
        reason: f.path,
      );
    }
  });
}
