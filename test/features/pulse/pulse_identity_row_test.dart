import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/pulse/presentation/screens/pulse_identity_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart';

/// PulseIdentityRow is what's left of the old ChatIdentityCard once its
/// photo strip was deleted (see chat_settings_static_rows.dart's own
/// "Media, docs and links" row, which already covers shared photos) and
/// its "Relationship Center" panel moved into PulseScreen. This just
/// covers the identity row itself and its tap-to-edit sheet.
void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  // Wrapped in a ListView, matching its real host (pulse_tab.dart's
  // _ChatSettingsRowsTab, itself inside a CustomScrollView sliver) — the
  // row has no intrinsic height limit of its own.
  Widget buildHarness(ProviderContainer container, Widget row) {
    return UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        child: MaterialApp(
          home: Scaffold(body: ListView(children: [row])),
        ),
      ),
    );
  }

  testWidgets('renders the identity row (name + explanatory subtitle), '
      'with no name field inline', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWith((ref) => testUser(userId)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      buildHarness(
        container,
        PulseIdentityRow(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();

    // The editable field only exists inside the sheet — the row itself is
    // a single tappable InfoRowWidget showing the current name.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Partner'), findsOneWidget); // activeConversation's name
    expect(find.textContaining('Choose a couple tag like'), findsOneWidget);
  });

  testWidgets('renders even when the couple has not set an avatar yet '
      '(avatarUrl is null)', (tester) async {
    // InfoRowWidget's own constructor asserts icon != null || imageUrl !=
    // null — a bare null avatarUrl (the real state for a brand-new couple)
    // must not crash the row.
    final repo = FakeChatRepository(currentUserId: userId);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWith((ref) => testUser(userId)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      buildHarness(
        container,
        PulseIdentityRow(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Partner'), findsOneWidget);
  });

  group('edit sheet', () {
    testWidgets('tapping the identity row opens a bottom sheet with a '
        'centered avatar above a pre-filled name field', (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      expect(find.text('Edit chat identity'), findsOneWidget);
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Partner');

      // Autofocused: typing is the obvious next action the instant the
      // sheet opens, so the field should already own focus/the keyboard
      // without an extra tap. EditableText owns the actual FocusNode, so
      // checking the currently-focused element's ancestry (rather than
      // Focus.of on the TextFormField itself, which has no Focus widget of
      // its own) is what actually reflects real keyboard-open state.
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      expect(
        focusedContext!.findAncestorWidgetOfExactType<TextFormField>(),
        isNotNull,
      );
    });

    testWidgets('a valid name autosaves after the debounce and reports it '
        'inline (no Save button, no snackbar)', (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'NewCoupleName1');
      // No Save button — the field's own debouncer commits ~500ms after
      // typing stops, so wait the window out explicitly.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repo.setChatNameCalls, [
        (relationshipId: relId, chatName: 'NewCoupleName1'),
      ]);
      // Inline status line, not a snackbar — the debounce can commit
      // several times in one editing session and stacked toasts read as
      // noise.
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Chat name updated.'), findsNothing);
    });

    testWidgets('an invalid name shows a validation error inside the sheet '
        'without calling the repository', (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      // Empty (after trimming) is the one thing
      // validateRelationshipChatName actually rejects. Clearing the field
      // mid-edit is a normal thing to do, so this must show the rule and
      // write nothing — never wipe the stored name.
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repo.setChatNameCalls, isEmpty);
      expect(find.text('Enter a name for your chat.'), findsOneWidget);
    });

    testWidgets('typing does NOT save before the debounce elapses', (
      tester,
    ) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Partly typed');
      // Well inside the 500ms window — a save here would mean every
      // keystroke hits the network.
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.setChatNameCalls, isEmpty);

      // Let it settle so the pending debounce doesn't leak into teardown.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    testWidgets('opening the sheet and letting the debounce fire without '
        'editing writes nothing — the unchanged name is not re-saved', (
      tester,
    ) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Autosave must be a no-op when nothing actually changed, or simply
      // opening the sheet would burn a write.
      expect(repo.setChatNameCalls, isEmpty);
    });

    testWidgets('a failed autosave surfaces an inline error and does not '
        'claim the name was saved', (tester) async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..setChatNameError = Exception('network down');
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'WillFail');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Checklist 5.5: generic copy, no internal error text leaked.
      expect(
        find.text("Couldn't update the name — try again."),
        findsOneWidget,
      );
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('an edit still inside the debounce window when the sheet is '
        'dismissed is still saved, not dropped', (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          PulseIdentityRow(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Partner'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'TypedThenClosed');
      // Dismiss well INSIDE the 500ms debounce — AppTextFormField cancels
      // (rather than flushes) its debouncer on dispose, so without the
      // sheet's own dispose-time flush this edit would vanish silently.
      await tester.pump(const Duration(milliseconds: 100));
      Navigator.of(tester.element(find.byType(TextFormField))).pop();
      await tester.pumpAndSettle();

      expect(repo.setChatNameCalls, [
        (relationshipId: relId, chatName: 'TypedThenClosed'),
      ]);
    });
  });
}
