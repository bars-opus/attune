import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/chat_identity_card.dart';
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentPulseScoreProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show bothPartnersSharedProvider;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Message imageMessage(String id, DateTime createdAt) => Message(
    id: id,
    clientMessageId: 'cid-$id',
    relationshipId: relId,
    senderId: userId,
    content: '',
    createdAt: createdAt,
    mediaKey: 'chat-media/$relId/$id.jpg',
    mediaType: 'image',
    signedMediaUrl: 'https://example.com/$id.jpg',
    status: MessageStatus.sent,
    isMine: true,
  );

  // Mirrors ephemeral_video_viewer_screen_test's harness: ChatIdentityCard's
  // "See all" tap calls context.pushNamed('chatMedia', ...) and a photo
  // tile's tap calls context.pushNamed('imageViewer', ...), both of which
  // need a real GoRouter ancestor, not just a bare Navigator. Wrapped in a
  // ListView, matching how both real hosts place it (ChatSettingsScreen's
  // own ListView, PulseTab's CustomScrollView sliver) — the card's Column
  // has no intrinsic height limit of its own and overflows a bare Scaffold.
  Widget buildHarness(ProviderContainer container, Widget card) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(body: ListView(children: [card])),
        ),
        GoRoute(
          path: '/chatMedia',
          name: 'chatMedia',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('media gallery'))),
        ),
        GoRoute(
          path: '/imageViewer',
          name: 'imageViewer',
          builder: (context, state) {
            final args = state.extra as ImageViewerRouteArgs;
            return Scaffold(
              body: Center(
                child: Text(
                  'image viewer index=${args.initialIndex} '
                  'count=${args.images.length}',
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/chatScreen',
          name: 'chatScreen',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('chat screen'))),
        ),
        GoRoute(
          path: '/weeklyCheckin',
          name: 'weeklyCheckin',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('weekly checkin'))),
        ),
        GoRoute(
          path: '/quizEntry',
          name: 'quizEntry',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('quiz entry'))),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('shows the 4 most recently shared images, newest first', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final base = DateTime(2026, 1, 1);
    // 5 images seeded so the "only 4" cap is actually exercised, not
    // vacuously true because there happen to be exactly 4.
    for (var i = 0; i < 5; i++) {
      final message = imageMessage('img$i', base.add(Duration(hours: i)));
      repo.serverMessages[message.id] = message;
    }
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
        ChatIdentityCard(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Newest-first per getMediaMessages' own ordering, capped to 4 — img4
    // (the newest) must be showing and img0 (the oldest, 5th-most-recent)
    // must not be, or the row would just be "the first 4 fetched" rather
    // than "the most recent 4".
    expect(find.byType(CachedNetworkImage), findsNWidgets(4));
    final shown =
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((w) => w.cacheKey)
            .toList();
    // Non-null by construction (every seeded message has a mediaKey), so a
    // literal-string membership check is safe without further narrowing.
    expect(shown, contains('chat-media/$relId/img4.jpg'));
    expect(shown, isNot(contains('chat-media/$relId/img0.jpg')));
  });

  testWidgets('renders nothing for the photo row when no images exist yet', (
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
        ChatIdentityCard(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();
    await tester.pump();

    // An empty row would otherwise render as 4 grey placeholder boxes,
    // which reads as broken rather than "nothing shared yet".
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets(
    'tapping a photo tile opens the IMAGE VIEWER for that photo, never the '
    'media gallery',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final message = imageMessage('img0', DateTime(2026, 1, 1));
      repo.serverMessages[message.id] = message;
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byType(CachedNetworkImage).first);
      await tester.pumpAndSettle();

      expect(find.text('image viewer index=0 count=1'), findsOneWidget);
      expect(find.text('media gallery'), findsNothing);
    },
  );

  testWidgets(
    'each photo tile carries a Hero tagged with its own clientMessageId, '
    'so tapping it flies into the image viewer instead of cutting to it',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final first = imageMessage('img0', DateTime(2026, 1, 1));
      final second = imageMessage('img1', DateTime(2026, 1, 2));
      repo.serverMessages[first.id] = first;
      repo.serverMessages[second.id] = second;
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();

      final heroes = tester.widgetList<Hero>(find.byType(Hero)).toList();
      final tags = heroes.map((h) => h.tag).toSet();
      // Newest-first, so img1 (the newer of the two) leads the strip.
      expect(
        tags,
        containsAll([second.clientMessageId, first.clientMessageId]),
      );
      // Distinct tags — a collision here would make Flutter's Hero
      // controller silently pick one flight and drop the other whenever
      // both were visible at once (never true for this strip today since
      // it never repeats an image, but worth guarding against a future
      // change that could).
      expect(heroes.map((h) => h.tag).toList().toSet().length, heroes.length);
    },
  );

  testWidgets(
    'tapping the SECOND of several photos opens the viewer at the matching '
    'chronological index, with the full (uncapped) image list',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final base = DateTime(2026, 1, 1);
      // 6 images: exercises the newest-first-strip -> chronological-viewer
      // index translation against a list bigger than what's visible on the
      // card (4), which is exactly the case a naive "reuse the tapped
      // index as-is" implementation gets wrong.
      for (var i = 0; i < 6; i++) {
        final message = imageMessage('img$i', base.add(Duration(hours: i)));
        repo.serverMessages[message.id] = message;
      }
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Strip shows the 4 newest, newest-first: img5, img4, img3, img2.
      // Tapping the SECOND tile (img4) in chronological order (img0..img5)
      // is index 4.
      await tester.tap(find.byType(CachedNetworkImage).at(1));
      await tester.pumpAndSettle();

      expect(find.text('image viewer index=4 count=6'), findsOneWidget);
    },
  );

  group('"See all"', () {
    Future<ProviderContainer> pumpWithImages(
      WidgetTester tester, {
      required int count,
    }) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < count; i++) {
        final message = imageMessage('img$i', base.add(Duration(hours: i)));
        repo.serverMessages[message.id] = message;
      }
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();
      return container;
    }

    testWidgets('is hidden when there are 4 or fewer shared images', (
      tester,
    ) async {
      await pumpWithImages(tester, count: 4);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('is hidden for exactly 1 shared image too', (tester) async {
      await pumpWithImages(tester, count: 1);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('appears once there are more than 4 shared images', (
      tester,
    ) async {
      await pumpWithImages(tester, count: 5);
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('tapping it opens the media gallery, not the image viewer', (
      tester,
    ) async {
      await pumpWithImages(tester, count: 5);

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();

      expect(find.text('media gallery'), findsOneWidget);
    });
  });

  group('recent photos strip: flush filmstrip with outer-corner-only '
      'rounding', () {
    Future<ProviderContainer> pumpWithImages(
      WidgetTester tester, {
      required int count,
    }) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < count; i++) {
        final message = imageMessage('img$i', base.add(Duration(hours: i)));
        repo.serverMessages[message.id] = message;
      }
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();
      return container;
    }

    List<BorderRadius> tileRadii(WidgetTester tester) {
      // The strip's own ClipRRects only — MessageBubble/other screens don't
      // exist in this harness, so byType is unambiguous here, but scoping
      // to the Row keeps the intent explicit regardless.
      return tester
          .widgetList<ClipRRect>(
            find.descendant(
              of: find.byType(Row),
              matching: find.byType(ClipRRect),
            ),
          )
          .map((w) => w.borderRadius as BorderRadius)
          .toList();
    }

    testWidgets('a single photo is rounded on all four corners', (
      tester,
    ) async {
      await pumpWithImages(tester, count: 1);

      final radii = tileRadii(tester);
      expect(radii, hasLength(1));
      expect(radii.single, BorderRadius.circular(12));
    });

    testWidgets(
      'two photos: only the outer corners round (left tile\'s left side, '
      'right tile\'s right side)',
      (tester) async {
        await pumpWithImages(tester, count: 2);

        final radii = tileRadii(tester);
        expect(radii, hasLength(2));

        final left = radii[0];
        expect(left.topLeft, const Radius.circular(12));
        expect(left.bottomLeft, const Radius.circular(12));
        // The seam between the two tiles must NOT be rounded, or they'd read
        // as two separate cards rather than one strip.
        expect(left.topRight, Radius.zero);
        expect(left.bottomRight, Radius.zero);

        final right = radii[1];
        expect(right.topLeft, Radius.zero);
        expect(right.bottomLeft, Radius.zero);
        expect(right.topRight, const Radius.circular(12));
        expect(right.bottomRight, const Radius.circular(12));
      },
    );

    testWidgets('four photos: only the strip\'s two outer edges round, the two '
        'middle tiles are square on every side', (tester) async {
      await pumpWithImages(tester, count: 4);

      final radii = tileRadii(tester);
      expect(radii, hasLength(4));

      expect(radii[0].topLeft, const Radius.circular(12));
      expect(radii[0].bottomLeft, const Radius.circular(12));
      expect(radii[0].topRight, Radius.zero);
      expect(radii[0].bottomRight, Radius.zero);

      // Both middle tiles: zero on every corner.
      expect(radii[1], BorderRadius.zero);
      expect(radii[2], BorderRadius.zero);

      expect(radii[3].topLeft, Radius.zero);
      expect(radii[3].bottomLeft, Radius.zero);
      expect(radii[3].topRight, const Radius.circular(12));
      expect(radii[3].bottomRight, const Radius.circular(12));
    });

    testWidgets('tiles sit flush with no gap between them', (tester) async {
      await pumpWithImages(tester, count: 2);

      final tileFinder = find.descendant(
        of: find.byType(Row),
        matching: find.byType(AspectRatio),
      );
      expect(tileFinder, findsNWidgets(2));
      final firstRect = tester.getRect(tileFinder.at(0));
      final secondRect = tester.getRect(tileFinder.at(1));
      // The first tile's right edge must meet the second tile's left edge
      // exactly — any gap would break the "one continuous strip" look the
      // outer-corner-only rounding is designed for.
      expect(firstRect.right, closeTo(secondRect.left, 0.01));
    });
  });

  testWidgets('renders the identity row (name + explanatory subtitle) and '
      'the dummy relationship center panel, with no name field inline', (
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
        ChatIdentityCard(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The editable field only exists inside the sheet now — the card itself
    // is a single tappable InfoRowWidget showing the current name.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Partner'), findsOneWidget); // activeConversation's name
    expect(find.textContaining('Choose a couple tag like'), findsOneWidget);
    expect(find.text('Relationship Center'), findsOneWidget);
    expect(find.text('Weekly check-in'), findsOneWidget);
    expect(find.text('Relationship tips'), findsOneWidget);
  });

  group('Relationship Center panel: real Pulse data', () {
    PulseScore pulseScore({
      required int overall,
      int? overallDelta,
      String confidence = 'medium',
    }) {
      return PulseScore(
        id: 'pulse-1',
        relationshipId: relId,
        weekEnding: DateTime(2026, 1, 4),
        computedAt: DateTime(2026, 1, 4),
        overallScore: overall,
        communication: 70,
        connection: 70,
        conflictHealth: 70,
        alignment: 70,
        emotionalSafety: 70,
        dataConfidence: confidence,
        deltaVsPrevious:
            overallDelta == null ? null : {'overall': overallDelta},
      );
    }

    Future<void> pumpWithPulse(
      WidgetTester tester, {
      PulseScore? pulse,
      bool bothSharedQuiz = false,
    }) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => testUser(userId)),
          currentPulseScoreProvider.overrideWith((ref) async => pulse),
          bothPartnersSharedProvider.overrideWith(
            (ref) async => bothSharedQuiz,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildHarness(
          container,
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the real overall score, signed weekly delta, and '
        'confidence label', (tester) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 72, overallDelta: 3, confidence: 'high'),
      );

      expect(find.text('72'), findsOneWidget);
      // Signed so a rise reads unambiguously as movement, not a raw score.
      expect(find.text('+3'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Pulse'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Confidence'), findsOneWidget);
    });

    testWidgets('renders a negative delta with its sign intact', (
      tester,
    ) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 61, overallDelta: -4),
      );

      expect(find.text('-4'), findsOneWidget);
    });

    testWidgets('a first-ever score (no previous week) shows a placeholder '
        'delta, never a misleading "0"', (tester) async {
      await pumpWithPulse(
        tester,
        // deltaVsPrevious null — compute-pulse omits it entirely when there
        // is no prior week to diff against.
        pulse: pulseScore(overall: 55),
      );

      expect(find.text('55'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      // Both the delta and nothing else should be the em-dash placeholder.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a couple with no computed Pulse yet shows placeholders '
        'rather than zeros or an error', (tester) async {
      await pumpWithPulse(tester, pulse: null);

      // All three tiles fall back — a brand-new relationship is a normal
      // state, not a failure.
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('confidence "none" renders as "Early", not "None"', (
      tester,
    ) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 40, confidence: 'none'),
      );

      // PULSE.md §7's own copy for this state is encouraging ("keep using
      // Attune"); a bare "None" reads as the couple's failure.
      expect(find.text('Early'), findsOneWidget);
      expect(find.text('None'), findsNothing);
    });

    testWidgets('never renders a streak tile — PULSE.md §6 bans streaks '
        'outright as a permanent ATTUNE_SOUL.md constraint', (tester) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 72, overallDelta: 3),
      );

      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('Streak'), findsNothing);
      // The other two originally-dummy tiles are equally forbidden:
      // response rate is chat-derived per-partner attribution (chat→Pulse
      // spec Privacy section + permanent constraint #2).
      expect(find.textContaining('Response rate'), findsNothing);
    });

    testWidgets('the attachment-quiz row reflects whether BOTH partners '
        'have shared', (tester) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 72),
        bothSharedQuiz: true,
      );

      expect(find.text('Attachment styles'), findsOneWidget);
      expect(find.text('You have both shared your results'), findsOneWidget);
    });

    testWidgets('the attachment-quiz row nudges when they have not both '
        'shared', (tester) async {
      await pumpWithPulse(
        tester,
        pulse: pulseScore(overall: 72),
        bothSharedQuiz: false,
      );

      expect(
        find.text('Take it together to strengthen your Pulse'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Weekly check-in opens the real check-in route', (
      tester,
    ) async {
      await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

      await tester.tap(find.text('Weekly check-in'));
      await tester.pumpAndSettle();

      expect(find.text('weekly checkin'), findsOneWidget);
    });

    testWidgets('tapping Attachment styles opens the real quiz route', (
      tester,
    ) async {
      await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

      await tester.tap(find.text('Attachment styles'));
      await tester.pumpAndSettle();

      expect(find.text('quiz entry'), findsOneWidget);
    });

    testWidgets('Relationship tips is present but NOT tappable — it has no '
        'backing feature yet and must not route anywhere', (tester) async {
      await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

      expect(find.text('Relationship tips'), findsOneWidget);
      await tester.tap(find.text('Relationship tips'));
      await tester.pumpAndSettle();

      // Still on the card — no navigation happened.
      expect(find.text('Relationship tips'), findsOneWidget);
      expect(find.text('weekly checkin'), findsNothing);
      expect(find.text('quiz entry'), findsNothing);
    });
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
        ChatIdentityCard(conversation: activeConversation(relId)),
      ),
    );
    await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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

      // Column, not the old Row: avatar sits above the field, both centered,
      // rather than side-by-side. Scoped to the sheet's own ProfileAvatar —
      // the identity row behind the sheet renders its own (smaller) one via
      // InfoRowWidget, so an unscoped find.byType would match two.
      final avatarCenter = tester.getCenter(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(ProfileAvatar),
        ),
      );
      final fieldCenter = tester.getCenter(find.byType(TextFormField));
      expect(avatarCenter.dy, lessThan(fieldCenter.dy));
      expect((avatarCenter.dx - fieldCenter.dx).abs(), lessThan(1));
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
          ChatIdentityCard(conversation: activeConversation(relId)),
        ),
      );
      await tester.pump();
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
