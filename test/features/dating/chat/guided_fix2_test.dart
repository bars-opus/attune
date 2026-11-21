// Spec 2 W6c Task 9 fix round 2 (task-9-review.md, Re-review 1). I-4: with
// the revealed pair older than the page read (older pages exist), any
// message of this side's held is after the reveal: no tip, on any open.
// With no page missing and no pair (the brief's test 2) it still shows.
// The conversations list's last line for Close kindly is the app's words.
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

void main() {
  final loc = AppLocalizationsEn();
  final tip = find.byKey(const ValueKey('dating_guided_tip'));
  const afterReveal = DatingGuided(questionId: 'food_every_week', revealed: 1);

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    String initial = '/dating/chat/m1',
  }) => pumpDatingShell(
    t,
    initial: initial,
    overrides: datingChatOverrides(fake),
  );

  group('I-4: the revealed pair older than the page read', () {
    // More than a page followed the first reveal: the newest page holds no
    // guided answer, and older pages exist.
    final newest = [
      for (var i = 50; i > 0; i--)
        datingMessageJson('t$i', 'Message $i', mine: i.isEven, minute: i),
    ];

    testWidgets('this side wrote since: no tip, opened again and again', (
      t,
    ) async {
      final fake = FakeDatingChat(
        page: datingPageJson(messages: newest, more: true),
      )..guidedState = afterReveal;
      for (var visit = 0; visit < 2; visit++) {
        await open(t, fake);
        expect(find.text(loc.dating_guidedTitle), findsOneWidget);
        expect(tip, findsNothing);
      }
    });

    testWidgets('only the other side held: the tip still shows', (t) async {
      final fake = FakeDatingChat(
        page: datingPageJson(
          messages: [
            for (var i = 5; i > 0; i--)
              datingMessageJson('t$i', 'Message $i', minute: i),
          ],
          more: true,
        ),
      )..guidedState = afterReveal;
      await open(t, fake);
      expect(tip, findsOneWidget);
    });

    testWidgets('no page missing and no pair (the brief\'s case): shown', (
      t,
    ) async {
      final fake = FakeDatingChat(page: datingPageJson())
        ..guidedState = afterReveal;
      await open(t, fake);
      expect(tip, findsOneWidget);
    });
  });

  testWidgets('the conversations list: Close kindly in the app\'s words', (
    t,
  ) async {
    Map<String, Object?> row(String id, bool mine) => {
      'match_id': id,
      'display_name': id == 'm1' ? 'Kofi' : 'Yaw',
      'age': 31,
      'last': {
        ...datingMessageJson('c$id', 'SERVER WORDS', mine: mine, minute: 4),
        'kind': 'close_kindly',
      },
      'new': false,
    };
    final fake = FakeDatingChat(
      list: datingConversationsJson(rows: [row('m1', false), row('m2', true)]),
    );
    await open(t, fake, initial: DatingPaths.chats);
    expect(find.text('SERVER WORDS'), findsNothing);
    expect(find.textContaining('SERVER WORDS'), findsNothing);
    expect(find.text(loc.dating_closeKindlyMessage), findsOneWidget);
    expect(
      find.text(loc.dating_chatsYouSaid(loc.dating_closeKindlyMessage)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Kofi, 31, ${loc.dating_closeKindlyMessage}'),
      findsOneWidget,
    );
  });
}
