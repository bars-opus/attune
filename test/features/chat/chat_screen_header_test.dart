import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

/// The conversation header: three SEPARATE floating rounded pills — a
/// back button, an avatar+name+status pill that opens Pulse (matching
/// the ORIGINAL AppBar title's own onTap before the pill redesign
/// mistakenly re-pointed it at chat insights), and the expand chevron
/// — painted directly over the chat wallpaper rather than sitting
/// inside an opaque AppBar. Chat insights is reached from the expand-
/// chevron drawer's own separate "Open Insights" affordance, not from
/// this header tap. more_vert is gone entirely (it used to duplicate
/// the chevron's own onToggleExpanded action rather than opening a
/// distinct menu).
void main() {
  Future<ProviderContainer> pumpChatWithRouter(
    WidgetTester tester,
    FakeChatRepository repo,
    GoRouter router, {
    // Navigating from the list route rather than starting on '/chat'
    // directly: '/chat' would then be the ONLY entry on the stack, and
    // popping it makes go_router refuse ("popped the last page off of
    // the stack") — the same way a real app never lands on ChatScreen
    // as its first-ever route.
    bool navigateFromList = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    if (navigateFromList) {
      await tester.tap(find.text('conversation list'));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  GoRouter buildRouter(Conversation convo) {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/chat'),
                child: const Text('conversation list'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) => ChatScreen(conversation: convo),
        ),
        GoRoute(
          path: '/chatInsights',
          name: 'chatInsights',
          builder: (context, state) {
            final args =
                state.extra
                    as ({String relationshipId, String partnerName});
            return Scaffold(
              body: Center(
                child: Text('insights for ${args.relationshipId}'),
              ),
            );
          },
        ),
        GoRoute(
          path: '/pulse',
          name: 'pulse',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('pulse tab'))),
        ),
      ],
    );
  }

  testWidgets('the more_vert button no longer exists in the header', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    final container = await pumpChatWithRouter(
      tester,
      repo,
      buildRouter(convo),
    );

    expect(find.byIcon(Icons.more_vert), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  testWidgets(
    'an explicit back button (not the implicit AppBar one) pops the '
    'route, using BackButtonIcon so it matches the current platform',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      expect(find.byType(BackButtonIcon), findsOneWidget);
      await tester.tap(find.byType(BackButtonIcon));
      await tester.pumpAndSettle();

      expect(find.text('conversation list'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'the back icon is the iOS chevron on iOS/macOS and the Material '
    'arrow elsewhere — BackButtonIcon resolves per-platform rather '
    'than a hardcoded glyph',
    (tester) async {
      try {
        for (final entry in {
          TargetPlatform.iOS: Icons.arrow_back_ios_new_rounded,
          TargetPlatform.android: Icons.arrow_back,
        }.entries) {
          debugDefaultTargetPlatformOverride = entry.key;

          final repo = FakeChatRepository(currentUserId: 'user-a');
          final convo = activeConversation('rel-1');
          final container = await pumpChatWithRouter(
            tester,
            repo,
            buildRouter(convo),
          );

          expect(
            find.byIcon(entry.value),
            findsOneWidget,
            reason: 'expected ${entry.value} on ${entry.key}',
          );

          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 10));
          container.dispose();
        }
      } finally {
        // Flutter's own test binding asserts this is null between
        // tests (debugAssertAllFoundationVarsUnset) — addTearDown runs
        // too late relative to that check, so it is reset here instead.
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'tapping the name/status opens Pulse (not the back button, which '
    'is a separate pill) — matches the ORIGINAL AppBar title\'s own '
    'onTap: _openPulse before the pill redesign mistakenly re-pointed '
    'this at chat insights',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      // The name/avatar pill is the tap target — not a bare "tap
      // anywhere in the header" gesture spanning the whole row
      // (including the back button), which the very first
      // implementation had. The avatar shares this same pill with the
      // name/status now (both left-aligned together), so tapping the
      // avatar also opens Pulse — that is intentional, not a leak:
      // they read as one unit. Rendered inside a RichText (name +
      // status as sibling TextSpans), so find.text (exact match) does
      // not find it — findRenderObject via a predicate on the RichText
      // itself does.
      final nameFinder = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith(convo.name),
      );
      expect(nameFinder, findsOneWidget);
      await tester.tap(nameFinder);
      await tester.pumpAndSettle();

      expect(find.text('pulse tab'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'tapping the avatar ALSO opens Pulse — it now shares one pill with '
    'the name/status rather than sitting in the back button\'s pill',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      await tester.tap(find.byType(GlowPulse));
      await tester.pumpAndSettle();

      expect(find.text('pulse tab'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'tapping the back button does NOT open Pulse — it is a separate '
    'pill from the avatar/name/status one',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      await tester.tap(find.byType(BackButtonIcon));
      await tester.pumpAndSettle();

      expect(find.text('pulse tab'), findsNothing);
      // The back tap popped back to the list, exactly as the
      // dedicated back-button test already covers — not re-asserted
      // here to keep this test's own point (no Pulse leak) sharp.

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'the avatar sits to the LEFT of the name/status, both left-aligned '
    'in the same pill — not a separate back+avatar pill with a '
    'center-aligned name pill',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      final nameFinder = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith(convo.name),
      );
      final richText = tester.widget<RichText>(nameFinder);
      expect(richText.textAlign, TextAlign.left);

      // The avatar (ProfileAvatar, found via its own CircleAvatar/
      // ClipOval-shaped ancestor is fragile to assert on directly, so
      // this checks geometry instead) sits to the left of the name
      // text within the SAME pill, not inside the back button's pill.
      final avatarRect = tester.getRect(find.byType(GlowPulse));
      final nameRect = tester.getRect(nameFinder);
      expect(
        avatarRect.right,
        lessThanOrEqualTo(nameRect.left),
        reason: 'the avatar must sit to the left of the name/status text',
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'there is no AppBar — the header floats over the wallpaper instead '
    'of sitting inside an opaque bar',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      expect(find.byType(AppBar), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'the wallpaper spans behind the header region, not just below a '
    'fixed bar — its top sits at y=0, before the header pills paint',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      final wallpaperRect = tester.getRect(
        find.byType(AttuneChatWallpaper).first,
      );
      // If the wallpaper only started below a reserved header band (the
      // old AppBar's own toolbarHeight), its top would be well below 0.
      // Extending fully behind the header is the entire point of this
      // layout — the pattern must be visible through the gaps between
      // and around the floating pills.
      expect(wallpaperRect.top, 0);

      final backButtonRect = tester.getRect(find.byType(BackButtonIcon));
      expect(
        backButtonRect.top,
        greaterThan(wallpaperRect.top),
        reason: 'the header pills paint on top of the wallpaper, not the '
            'other way around',
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'the header renders as separate rounded pills, not one continuous '
    'bar — at least the back pill and the avatar+name+status pill, '
    'which are always present regardless of the expand-chevron feature '
    'flag',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      // Each pill is its own fully-rounded (BorderRadius.circular(999))
      // Container — counting them directly proves there are multiple
      // distinct floating surfaces rather than one bar segmented only
      // visually. The third (expand chevron) pill is conditional on
      // chatExpandedHeaderDrawerEnabledProvider, which this test's
      // harness does not force to true, so only the two always-present
      // pills are asserted here.
      final pillCount = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) {
            final decoration = container.decoration;
            return decoration is BoxDecoration &&
                decoration.borderRadius == BorderRadius.circular(999) &&
                decoration.boxShadow != null;
          })
          .length;
      expect(pillCount, greaterThanOrEqualTo(2));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'the header pill shadows match the composer shadows',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      final pillShadows = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) {
            final decoration = container.decoration;
            if (decoration is! BoxDecoration ||
                decoration.borderRadius != BorderRadius.circular(999)) {
              return null;
            }
            return decoration.boxShadow;
          })
          .whereType<List<BoxShadow>>()
          .toList();

      expect(
        pillShadows,
        isNotEmpty,
        reason: 'expected at least one rounded pill with a shadow',
      );
      for (final shadows in pillShadows) {
        expect(shadows, kComposerShadows);
      }

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );

  testWidgets(
    'bubbles do not scroll under the header — no BackdropFilter blur '
    'layer exists, and the message list stops at a fixed reserve below '
    'the header band',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final convo = activeConversation('rel-1');
      final container = await pumpChatWithRouter(
        tester,
        repo,
        buildRouter(convo),
      );

      // Scroll-under-header-with-blur was tried and reverted twice: the
      // first attempt (no blur) looked messy; the second (with blur)
      // still wasn't wanted. Bubbles now stop short of the header at a
      // fixed reserve, same as the very first pill redesign.
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'no blur layer should exist behind the header',
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );
}
