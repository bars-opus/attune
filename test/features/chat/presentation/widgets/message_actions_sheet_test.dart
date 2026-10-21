import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool canEditOrDelete = true, DateTime? createdAt}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt:
        createdAt ??
        (canEditOrDelete
            ? DateTime.now()
            : DateTime.now().subtract(const Duration(minutes: 10))),
  );
}

Widget _wrap(List<Widget> Function(BuildContext) build) {
  return ScreenUtilInit(
    designSize: ScreenUtilConfig.designSize,
    minTextAdapt: ScreenUtilConfig.minTextAdapt,
    splitScreenMode: ScreenUtilConfig.splitScreenMode,
    fontSizeResolver: ScreenUtilConfig.resolveFontSize,
    builder:
        (context, child) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(children: build(context)),
            ),
          ),
        ),
  );
}

void main() {
  testWidgets(
    'shows timestamp, Reply, Copy, Star, Pin, Info, Edit, Delete for an own recent message',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(),
            currentUserId: 'u1',
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
          ),
        ),
      );

      expect(find.textContaining('Today At'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.reply_outlined), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    },
  );

  testWidgets('shows date and time on separate lines for older messages', (
    tester,
  ) async {
    final createdAt = DateTime.now().subtract(const Duration(days: 2));
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(canEditOrDelete: false, createdAt: createdAt),
          currentUserId: 'u1',
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
        ),
      ),
    );

    expect(find.textContaining('Today At'), findsNothing);
    // Shortened per MyDateFormat.toWeekdayMonth (e.g. "Sun, November") --
    // no day number, no year -- because the full yMMMMEEEEd format ran
    // too long on this line next to a time stamp.
    expect(
      find.text(MyDateFormat.toWeekdayMonth(createdAt)),
      findsOneWidget,
    );
  });

  testWidgets('omits Edit and Delete when the 5-minute window has passed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(canEditOrDelete: false),
          currentUserId: 'u1',
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
        ),
      ),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('omits Edit and Delete for a message from the other partner', (
    tester,
  ) async {
    final theirMessage = Message.optimistic(
      id: 'm2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: theirMessage,
          currentUserId: 'u1',
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
        ),
      ),
    );

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Info'), findsOneWidget);
  });

  testWidgets('shows Unstar instead of Star when isStarred is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(),
          currentUserId: 'u1',
          isStarred: true,
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
        ),
      ),
    );

    expect(find.text('Unstar'), findsOneWidget);
    expect(find.text('Star'), findsNothing);
  });

  testWidgets('tapping Delete calls onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(),
          currentUserId: 'u1',
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
          onDelete: () => deleted = true,
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  // ===================================================================
  // RULING 23 — the Ask Attune gate (Plan D Task 9)
  // ===================================================================
  //
  // `ai_assist_enabled` is the BASE spec's own missing gate: Task 5
  // confirmed nothing gated Ask Attune across all 16
  // `ChatFeatureFlags.` call sites, so this is a pre-existing finding
  // being closed, not a regression Plan D introduced.
  //
  // The capability is read by the CALLER (ChatScreen) and passed in,
  // because this is a pure function with no Riverpod and
  // `MessageBubble` is a deliberate `StatelessWidget`.

  /// Every call this file already makes, with the new parameter left to
  /// its default — the literal compiled shape of every pre-existing
  /// caller. Used by the regression leg so "unchanged" is asserted
  /// against the real default path rather than an explicit `true`.
  List<Widget> defaultCall(BuildContext context, {bool? assistEnabled}) {
    // Two literal call shapes rather than one with a conditional
    // argument, because the whole point of the first is that the
    // parameter is NOT NAMED — the compiled shape of every
    // pre-existing caller. A single call site passing `assistEnabled:
    // someBool` would exercise the parameter in both legs and prove
    // nothing about the default.
    if (assistEnabled == null) {
      return buildMessageActionItems(
        context: context,
        message: _ownMessage(),
        currentUserId: 'u1',
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
      );
    }
    return buildMessageActionItems(
      context: context,
      message: _ownMessage(),
      currentUserId: 'u1',
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
      assistEnabled: assistEnabled,
    );
  }

  group('the capability parameter is OFF-by-caller: the menu is as it was', () {
    testWidgets(
      'a caller that never names assistEnabled gets the menu it gets '
      'today, Ask Attune included',
      (tester) async {
        // THE REGRESSION PROOF. Six existing tests in this file and
        // every non-chat reuse call `buildMessageActionItems` without
        // the new parameter. If the default had flipped, Ask Attune
        // would vanish for all of them.
        await tester.pumpWidget(_wrap((context) => defaultCall(context)));

        expect(find.text('Ask Attune'), findsOneWidget);
        // And nothing else moved: the full menu for an own recent
        // message, in order.
        expect(find.text('Reply'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Star'), findsOneWidget);
        expect(find.text('Pin'), findsOneWidget);
        expect(find.text('Info'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets('an explicit true is identical to omitting it', (tester) async {
      await tester.pumpWidget(_wrap((context) => defaultCall(context)));
      final omitted = find.byType(ListTile).evaluate().length;
      final omittedTitles =
          tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(ListTile),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data)
              .toList();

      await tester.pumpWidget(
        _wrap((context) => defaultCall(context, assistEnabled: true)),
      );
      expect(find.byType(ListTile).evaluate().length, omitted);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(ListTile),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .toList(),
        omittedTitles,
        reason:
            'the default must not merely be truthy — it must produce '
            'the SAME menu, item for item',
      );
      // Anti-vacuity: an empty comparison would pass the above.
      expect(omittedTitles, contains('Ask Attune'));
      expect(omittedTitles.length, greaterThan(5));
    });
  });

  group('RULING 23: assistEnabled false removes ONLY Ask Attune', () {
    testWidgets('Ask Attune is omitted when the capability is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap((context) => defaultCall(context, assistEnabled: false)),
      );

      expect(
        find.text('Ask Attune'),
        findsNothing,
        reason:
            'RULING 23: §12 ai_assist_enabled gates this entry point, '
            'and it is OFF in every environment today',
      );
    });

    testWidgets('every OTHER action survives the capability being off', (
      tester,
    ) async {
      // The regression risk of this change is not "the gate fails
      // open", it is "the gate takes a neighbour with it". This is the
      // leg that would catch that.
      await tester.pumpWidget(
        _wrap((context) => defaultCall(context, assistEnabled: false)),
      );

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets(
      'the capability is AND-ed with eligibility, not substituted for it',
      (tester) async {
        // A gate that REPLACED the eligibility predicate would show
        // Ask Attune on an ineligible message whenever the flag is on,
        // which is a §3 violation the flag must not be able to cause.
        // Over-4000 characters is the eligibility leg chosen because it
        // is purely about content.
        final tooLong = Message.optimistic(
          id: 'm2',
          clientMessageId: 'c2',
          relationshipId: 'r1',
          senderId: 'u1',
          content: 'a' * 4001,
          createdAt: DateTime.now(),
        );
        expect(tooLong.isEligibleForAskAttune, isFalse);

        await tester.pumpWidget(
          _wrap(
            (context) => buildMessageActionItems(
              context: context,
              message: tooLong,
              currentUserId: 'u1',
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
              assistEnabled: true,
            ),
          ),
        );

        expect(
          find.text('Ask Attune'),
          findsNothing,
          reason:
              'the capability being ON must not override §3 '
              'entry-eligibility',
        );
      },
    );
  });

  testWidgets(
    'omits Edit and Delete on a system notice attributed to me (chat review #19)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (context) => buildMessageActionItems(
            context: context,
            message: _ownMessage().copyWith(
              content: 'Ama took a screenshot',
              isSystemNotice: true,
            ),
            currentUserId: 'u1',
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
          ),
        ),
      );

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Info'), findsOneWidget);
    },
  );

  testWidgets('offers Copy link only when the message has a link (#37)', (
    tester,
  ) async {
    List<Widget> items(BuildContext context, VoidCallback? onCopyLink) =>
        buildMessageActionItems(
          context: context,
          message: _ownMessage(),
          currentUserId: 'u1',
          isStarred: false,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onCopyLink: onCopyLink,
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onInfo: () {},
          onAskAttune: () {},
          onEdit: () {},
          onDelete: () {},
        );

    await tester.pumpWidget(_wrap((context) => items(context, () {})));
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget, reason: 'whole-text copy stays');

    await tester.pumpWidget(_wrap((context) => items(context, null)));
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });
  group('Edit history (final wave round 2)', () {
    Message row({String id = 'm9', bool edited = true, bool notice = false}) =>
        Message(
          id: id,
          clientMessageId: 'c-$id',
          relationshipId: 'r1',
          senderId: 'u2',
          content: 'home at 9',
          createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
          editedAt:
              edited ? DateTime.now().subtract(const Duration(minutes: 1)) : null,
          status: MessageStatus.delivered,
          isMine: false,
          isSystemNotice: notice,
        );

    Future<void> pump(
      WidgetTester tester,
      Message message, {
      VoidCallback? onShowEditHistory,
    }) => tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: message,
          currentUserId: 'u1',
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
          onShowEditHistory: onShowEditHistory,
        ),
      ),
    );

    testWidgets('an edited, server-backed row offers it and it opens', (
      tester,
    ) async {
      var opened = 0;
      await pump(tester, row(), onShowEditHistory: () => opened++);
      expect(find.text('Edit history'), findsOneWidget);
      await tester.tap(find.text('Edit history'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('never without an edit, a server copy, or a callback', (
      tester,
    ) async {
      await pump(tester, row(edited: false), onShowEditHistory: () {});
      expect(find.text('Edit history'), findsNothing);
      await pump(tester, row(id: '_local_1'), onShowEditHistory: () {});
      expect(find.text('Edit history'), findsNothing);
      await pump(tester, row(notice: true), onShowEditHistory: () {});
      expect(find.text('Edit history'), findsNothing);
      await pump(tester, row());
      expect(find.text('Edit history'), findsNothing);
    });
  });
}
