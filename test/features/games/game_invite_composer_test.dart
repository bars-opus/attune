import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/invites/services/game_invite_service.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInviteGateway implements GameInviteGateway {
  final List<String> keys = [];
  final List<String> gameTypes = [];
  final List<String> accepted = [];
  final List<String> declined = [];

  /// Fails the first create only, so a retry can be observed.
  bool failFirstCreate = false;
  GameInviteApiError? failWith;

  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    gameTypes.add(gameType);
    if (failFirstCreate && keys.length == 1) {
      throw const GameInviteApiError(
        code: 'NETWORK',
        message: 'Slow down a moment.',
      );
    }
    final error = failWith;
    if (error != null) throw error;
    return GameInvite(sessionId: 'session-${keys.length}', existing: false);
  }

  @override
  Future<void> accept(String sessionId) async => accepted.add(sessionId);

  @override
  Future<void> decline(String sessionId) async => declined.add(sessionId);
}

void main() {
  ProviderContainer harness(_FakeInviteGateway gateway) {
    final container = ProviderContainer(
      overrides: [gameInviteGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the composer', () {
    test('staging a game sends nothing', () async {
      // The whole point of the composer. Picking a game used to create
      // the session on the spot, so glancing at the catalogue posted a
      // card that could not be taken back.
      final gateway = _FakeInviteGateway();
      final container = harness(gateway);

      container.read(gameComposerProvider.notifier).stage('mirror');

      expect(container.read(gameComposerProvider).isStaged, isTrue);
      expect(container.read(gameComposerProvider).gameType, 'mirror');
      expect(gateway.keys, isEmpty, reason: 'staging reached the server');
    });

    test('cancelling leaves no trace', () async {
      final gateway = _FakeInviteGateway();
      final container = harness(gateway);
      final notifier =
          container.read(gameComposerProvider.notifier)
            ..stage('mirror')
            ..cancel();

      expect(container.read(gameComposerProvider).isStaged, isFalse);
      expect(gateway.keys, isEmpty);
      expect(notifier, isNotNull);
    });

    test('sending creates the invitation and clears the composer', () async {
      final gateway = _FakeInviteGateway();
      final container = harness(gateway);
      final notifier = container.read(gameComposerProvider.notifier)
        ..stage('scenario');

      final sessionId = await notifier.send(relationshipId: 'r1');

      expect(sessionId, 'session-1');
      expect(gateway.gameTypes, ['scenario']);
      expect(container.read(gameComposerProvider).isStaged, isFalse);
    });

    test(
      'a failed send keeps its key so a retry is the same request',
      () async {
        // Checklist 1.1 / 2.18. A send whose response was dropped may well
        // have created the invitation; a fresh key on the second tap posts
        // a SECOND card for a player who thinks they sent one.
        final gateway = _FakeInviteGateway()..failFirstCreate = true;
        final container = harness(gateway);
        final notifier = container.read(gameComposerProvider.notifier)
          ..stage('mirror');

        expect(await notifier.send(relationshipId: 'r1'), isNull);
        expect(await notifier.send(relationshipId: 'r1'), isNotNull);

        expect(gateway.keys, hasLength(2));
        expect(
          gateway.keys[1],
          gateway.keys[0],
          reason: 'the retry sent a second invitation',
        );
      },
    );

    test(
      'a failed send keeps the game staged, with a readable reason',
      () async {
        final gateway = _FakeInviteGateway()..failFirstCreate = true;
        final container = harness(gateway);
        final notifier = container.read(gameComposerProvider.notifier)
          ..stage('mirror');
        await notifier.send(relationshipId: 'r1');

        final state = container.read(gameComposerProvider);
        expect(state.isStaged, isTrue, reason: 'the player lost their game');
        expect(state.sending, isFalse);
        expect(state.errorMessage, 'Slow down a moment.');
      },
    );

    test('an unexpected failure never shows the raw exception', () async {
      // Checklist 2.4 / 5.5: a thrown object can carry connection strings
      // and row contents.
      final gateway = _FakeInviteGateway();
      final container = harness(gateway);
      final notifier = container.read(gameComposerProvider.notifier)
        ..stage('mirror');
      gateway.failWith = null;

      // A non-GameInviteApiError: the generic catch must own it.
      final broken = _ThrowingGateway();
      final container2 = ProviderContainer(
        overrides: [gameInviteGatewayProvider.overrideWithValue(broken)],
      );
      addTearDown(container2.dispose);
      final notifier2 = container2.read(gameComposerProvider.notifier)
        ..stage('mirror');
      await notifier2.send(relationshipId: 'r1');

      final message = container2.read(gameComposerProvider).errorMessage;
      expect(message, 'Could not send. Check your connection.');
      expect(message, isNot(contains('postgres')));
      expect(notifier, isNotNull);
    });

    test('staging a different game does not reuse the last key', () async {
      // A key belongs to one game. Carried over, the server would hand
      // back the previous game or refuse the mismatch.
      final gateway = _FakeInviteGateway()..failFirstCreate = true;
      final container = harness(gateway);
      final notifier = container.read(gameComposerProvider.notifier)
        ..stage('mirror');
      await notifier.send(relationshipId: 'r1');

      notifier.stage('scenario');
      await notifier.send(relationshipId: 'r1');

      expect(gateway.keys, hasLength(2));
      expect(gateway.keys[1], isNot(gateway.keys[0]));
      expect(gateway.gameTypes, ['mirror', 'scenario']);
    });

    test('a send already in flight is not sent twice', () async {
      final gateway = _FakeInviteGateway();
      final container = harness(gateway);
      final notifier = container.read(gameComposerProvider.notifier)
        ..stage('mirror');

      await Future.wait([
        notifier.send(relationshipId: 'r1'),
        notifier.send(relationshipId: 'r1'),
      ]);

      expect(gateway.keys, hasLength(1));
    });
  });

  group('the composer bar', () {
    Widget host(
      _FakeInviteGateway gateway, {
      required String gameType,
      VoidCallback? onSend,
      VoidCallback? onCancel,
    }) => ProviderScope(
      overrides: [gameInviteGatewayProvider.overrideWithValue(gateway)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (context, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: GameComposerBar(
                  gameType: gameType,
                  onSend: onSend ?? () {},
                  onCancel: onCancel ?? () {},
                ),
              ),
            ),
      ),
    );

    testWidgets('shows the game it is about to send', (tester) async {
      // What you are about to send should look like what will be sent:
      // the same card, the same name, on the sender bubble's colour.
      await tester.pumpWidget(host(_FakeInviteGateway(), gameType: 'mirror'));
      await tester.pumpAndSettle();

      expect(find.text('Mirror'), findsOneWidget);
      expect(find.text('Invite them to play'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('every one of the ten games renders a name, not a fallback', (
      tester,
    ) async {
      // A game whose type is missing from the display map would show a
      // title-cased id ("Snakes And Ladders") or worse, and the composer
      // is the first place anyone would see it.
      const expected = {
        'this_or_that': 'This or That',
        'truth_or_dare': 'Truth or Dare',
        '36_questions': '36 Questions',
        'mirror': 'Mirror',
        'sliding_scale': 'Sliding Scale',
        'scenario': 'Scenario',
        'love_map': 'Love Map',
        'paint_ball': 'Paint Ball',
        'snakes_and_ladders': 'Snakes and Ladders',
        'word_hunt': 'Word Hunt',
      };

      for (final entry in expected.entries) {
        await tester.pumpWidget(
          host(_FakeInviteGateway(), gameType: entry.key),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: '${entry.key} did not render as "${entry.value}"',
        );
      }
    });

    testWidgets('the send button is offered to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(_FakeInviteGateway(), gameType: 'mirror'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Send game invitation'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a send in flight cannot be tapped again', (tester) async {
      var sends = 0;
      final gateway = _FakeInviteGateway();
      await tester.pumpWidget(
        host(gateway, gameType: 'mirror', onSend: () => sends++),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GameComposerBar)),
      );
      container.read(gameComposerProvider.notifier).stage('mirror');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(sends, 1);
    });

    testWidgets('a failure is shown in the player\'s language', (tester) async {
      // Checklist 5.5: a code or an exception must never reach the bar.
      final gateway = _FakeInviteGateway()..failFirstCreate = true;
      await tester.pumpWidget(host(gateway, gameType: 'mirror'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GameComposerBar)),
      );
      final notifier = container.read(gameComposerProvider.notifier)
        ..stage('mirror');
      await notifier.send(relationshipId: 'r1');
      await tester.pumpAndSettle();

      expect(find.text('Slow down a moment.'), findsOneWidget);
      expect(find.textContaining('NETWORK'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      // The game is still there to retry.
      expect(find.text('Mirror'), findsOneWidget);
    });
  });
}

class _ThrowingGateway implements GameInviteGateway {
  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
  }) async => throw StateError('connection to postgres://secret failed');

  @override
  Future<void> accept(String sessionId) async {}

  @override
  Future<void> decline(String sessionId) async {}
}
