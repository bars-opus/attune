// Spec 7 (research 06 B1): "I noticed…" notes and the appreciation jar.
import 'dart:io';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/appreciation/presentation/appreciation_jar_screen.dart';
import 'package:attune/features/appreciation/presentation/appreciation_sheet.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';

import '../chat/support/chat_test_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Message _note({required bool mine, DateTime? at}) => Message(
  id: 'm1',
  clientMessageId: 'c1',
  relationshipId: 'r1',
  senderId: mine ? 'me' : 'them',
  content: 'I noticed you made tea. Thank you.',
  createdAt: at ?? DateTime.now(),
  status: MessageStatus.sent,
  isMine: mine,
  mediaType: 'appreciation',
);

class _Fake extends AppreciationService {
  _Fake([this.notes = const []]);
  List<JarNote> notes;
  final calls = <String>[];

  @override
  Future<String> send({
    required String relationshipId,
    required String clientMessageId,
    required String text,
  }) async {
    calls.add('send:$relationshipId:$text');
    return 'new';
  }

  @override
  Future<List<JarNote>> jar() async => notes;

  @override
  Future<void> remove(String messageId) async {
    calls.add('remove:$messageId');
    notes = notes.where((n) => n.messageId != messageId).toList();
  }
}

Widget _app(Widget home, _Fake fake, {bool on = true}) => ProviderScope(
  overrides: [
    appreciationServiceProvider.overrideWithValue(fake),
    appreciationEnabledProvider.overrideWith((ref) async => on),
  ],
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: home),
  ),
);

void main() {
  group('the fixed forms', () {
    test(
      'compose: one of two templates, the middle trimmed of its own full stop',
      () {
        expect(
          composeAppreciation(' remembered Mum. ', thankful: false),
          'I noticed you remembered Mum. Thank you.',
        );
        expect(
          composeAppreciation('you made tea!', thankful: true),
          'Thankful for you because you made tea.',
        );
        expect(composeAppreciation('   ', thankful: false), isNull);
        expect(composeAppreciation('x' * 281, thankful: false), isNull);
      },
    );

    test('a note is never edited, but can be deleted', () {
      final n = _note(mine: true);
      expect(n.isAppreciation, isTrue);
      expect(n.canEdit(currentUserId: 'me', now: DateTime.now()), isFalse);
      expect(n.canDelete(currentUserId: 'me', now: DateTime.now()), isTrue);
    });
  });

  testWidgets(
    'the sheet sends the fixed form; the thankful phrasing only when offered',
    (t) async {
      final fake = _Fake();
      await t.pumpWidget(
        _app(
          const Scaffold(
            body: AppreciationSheet(relationshipId: 'r1', offerThankful: true),
          ),
          fake,
        ),
      );
      expect(find.text('Specific beats sweeping.'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField), 'remembered Mum');
      await t.pump();
      expect(
        find.text('I noticed you remembered Mum. Thank you.'),
        findsOneWidget,
      ); // the preview
      await t.tap(find.text('Thankful for you because…'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'you remembered Mum');
      await t.pump();
      await t.tap(find.text('Send'));
      await t.pump();
      expect(fake.calls, [
        'send:r1:Thankful for you because you remembered Mum.',
      ]);

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        _app(
          const Scaffold(
            body: AppreciationSheet(relationshipId: 'r1', offerThankful: false),
          ),
          _Fake(),
        ),
      );
      expect(find.text('Thankful for you because…'), findsNothing);
    },
  );

  testWidgets('the jar lists kept notes with no count, and lets one go', (
    t,
  ) async {
    final at = DateTime.utc(2026, 10, 1, 9);
    final fake = _Fake([
      JarNote(
        messageId: 'm1',
        relationshipId: 'r1',
        content: 'I noticed you made tea. Thank you.',
        sentAt: at,
      ),
    ]);
    await t.pumpWidget(_app(const AppreciationJarScreen(), fake));
    await t.pumpAndSettle();
    expect(find.text('I noticed you made tea. Thank you.'), findsOneWidget);
    expect(find.text(MyDateFormat.toDate(at.toLocal())), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\d+\s*(notes?|saved|kept)')),
      findsNothing,
    );
    await t.tap(find.byTooltip('Remove from my jar'));
    await t.pumpAndSettle();
    expect(fake.calls, ['remove:m1']);
    expect(find.text('Notes you keep will be here.'), findsOneWidget);
  });

  // Sync audit: the jar guards itself too, like Quiet for a while.
  testWidgets('flag off: the jar shows nothing of its contents', (t) async {
    final fake = _Fake([
      JarNote(
        messageId: 'm1',
        relationshipId: 'r1',
        content: 'I noticed you made tea. Thank you.',
        sentAt: DateTime.utc(2026, 10, 1),
      ),
    ]);
    await t.pumpWidget(_app(const AppreciationJarScreen(), fake, on: false));
    await t.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('I noticed you made tea. Thank you.'), findsNothing);
  });

  testWidgets('Save to my jar is offered on a received note only', (t) async {
    late List<Widget> received, own;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            List<Widget> build(Message m) => buildMessageActionItems(
              context: context,
              message: m,
              currentUserId: 'me',
              isStarred: false,
              isPinned: false,
              onReply: () {},
              onCopy: () {},
              onStar: () {},
              onUnstar: () {},
              onPin: () {},
              onUnpin: () {},
              onInfo: () {},
              onAskAttune: () {},
              onEdit: () {},
              onDelete: () {},
              isInJar: false,
              onSaveToJar: () {},
              onRemoveFromJar: () {},
            );
            received = build(_note(mine: false));
            own = build(_note(mine: true));
            return const SizedBox();
          },
        ),
      ),
    );
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: ListView(children: received))),
    );
    expect(find.text('Save to my jar'), findsOneWidget);
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: ListView(children: own))),
    );
    expect(find.text('Save to my jar'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  test('no counts, totals or streaks anywhere in the feature (M15)', () {
    for (final f
        in Directory(
          'lib/features/appreciation',
        ).listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(
        RegExp(r'\b(count|total|streak)\b', caseSensitive: false).hasMatch(src),
        isFalse,
        reason: f.path,
      );
      expect(RegExp(r'\.length\}').hasMatch(src), isFalse, reason: f.path);
    }
  });

  testWidgets('a note shows its text with a subtle, labelled leaf', (t) async {
    await t.pumpWidget(withScreenUtil(MaterialApp(home: Scaffold(body: MessageBubble(message: _note(mine: false))))));
    expect(find.text('I noticed you made tea. Thank you.'), findsOneWidget);
    expect(find.byKey(const ValueKey('appreciation-leaf')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('An I noticed note')), findsWidgets);
  });

  test('the chat reads only which notes are kept, not their text (final review M-7)', () {
    final chat = File('lib/features/chat/presentation/screens/chat_screen.dart').readAsStringSync();
    expect(chat, contains('appreciationJarIdsProvider'));
    expect(chat, isNot(contains('ref.watch(appreciationJarProvider)')));
    expect(File('lib/features/appreciation/data/appreciation_service.dart').readAsStringSync(),
        contains("rpc('list_my_jar_ids')"));
  });
}
