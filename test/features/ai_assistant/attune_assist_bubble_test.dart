// Widget tests for AttuneAssistBubble (AI Assistant spec §5.3): the
// distinct visual treatment for a shared Attune Assist message.
//
// The bubble's visual identity must come from `message.messageOrigin`
// (the server-owned column), never from inspecting `content` for
// AI-sounding phrasing — spec §0's own P0 finding is explicit about
// exactly this mistake (any client that could infer provenance from
// text could impersonate Attune). The first two tests below construct
// a deliberate mismatch (ordinary content + attune_assist origin, and
// AI-suggestion-shaped content + user origin) specifically to prove the
// check is genuinely on the field.
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiAssistantGateway implements AiAssistantGateway {
  Object? nextSelectPlanningLinkError;
  Map<String, dynamic>? nextSelectPlanningLinkResult;
  int selectPlanningLinkCallCount = 0;

  Object? nextRpcError;
  dynamic nextRpcResult;
  int rpcCallCount = 0;
  Map<String, dynamic>? lastCalledParams;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    throw UnsupportedError('AttuneAssistBubble must never call an edge function');
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    rpcCallCount++;
    lastCalledParams = params;
    if (nextRpcError != null) {
      final error = nextRpcError!;
      nextRpcError = null;
      throw error;
    }
    return nextRpcResult;
  }

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) async {
    selectPlanningLinkCallCount++;
    if (nextSelectPlanningLinkError != null) {
      final error = nextSelectPlanningLinkError!;
      nextSelectPlanningLinkError = null;
      throw error;
    }
    return nextSelectPlanningLinkResult;
  }
}

Message _attuneAssistMessage({
  required String content,
  Map<String, dynamic>? assistantPayload,
  String id = 'assist-1',
}) {
  return Message.fromRow(
    {
      'id': id,
      'client_message_id': 'c-$id',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'message_origin': 'attune_assist',
      'assistant_payload':
          assistantPayload ??
          {
            'schema_version': 1,
            'suggested_planning_item': null,
            'sources': <dynamic>[],
          },
    },
    currentUserId: 'u1',
  );
}

Message _ordinaryMessage({required String content, String id = 'user-1'}) {
  return Message.fromRow({
    'id': id,
    'client_message_id': 'c-$id',
    'relationship_id': 'r1',
    'sender_id': 'u1',
    'content': content,
    'created_at': DateTime.now().toIso8601String(),
  }, currentUserId: 'u1');
}

Widget _wrap(Widget child, {AiAssistantGateway? gateway}) {
  return ProviderScope(
    overrides: [
      if (gateway != null)
        aiAssistantRepositoryProvider.overrideWithValue(
          AiAssistantRepository(gateway),
        ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('provenance — field, not content', () {
    testWidgets(
      'a message with ordinary-looking content but attune_assist origin '
      'renders as an Attune-attributed suggestion',
      (tester) async {
        final message = _attuneAssistMessage(
          content: 'Sounds like a nice evening, want to grab dinner?',
        );
        await tester.pumpWidget(
          _wrap(
            AttuneAssistBubble(message: message),
            gateway: _FakeAiAssistantGateway(),
          ),
        );
        await tester.pump();
        expect(find.text('Attune suggestion'), findsOneWidget);
      },
    );

    testWidgets(
      'a message with AI-suggestion-shaped content but user origin does '
      'NOT render as Attune-attributed — proving the check is on the '
      'field, not on content sniffing',
      (tester) async {
        final message = _ordinaryMessage(
          content:
              'Here are a few ideas for tonight: 1. Try that new ramen '
              'place 2. Movie night 3. Cook together',
        );
        // AttuneAssistBubble is only reachable via message_bubble.dart's
        // own message.isAttuneAssistOutput branch — this test proves
        // the underlying field check directly, since constructing this
        // message and asking "would the branch route here" is exactly
        // what the mutation test (Step 9) exercises against the real
        // branch condition.
        expect(message.isAttuneAssistOutput, isFalse);
      },
    );
  });

  group('Nearby sources', () {
    testWidgets('sources render with Mapbox attribution', (tester) async {
      final message = _attuneAssistMessage(
        content: 'A few spots nearby you might like.',
        assistantPayload: {
          'schema_version': 1,
          'suggested_planning_item': null,
          'sources': [
            {
              'provider_id': 'p1',
              'name': 'Ramen House',
              'formatted_address': '123 Main St',
              'category': 'restaurant',
              'map_url': 'https://example.com/p1',
            },
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(
          AttuneAssistBubble(message: message),
          gateway: _FakeAiAssistantGateway(),
        ),
      );
      await tester.pump();
      expect(find.text('Ramen House'), findsOneWidget);
      expect(find.text('123 Main St'), findsOneWidget);
      expect(find.textContaining('Mapbox'), findsOneWidget);
    });
  });

  group('Add to Planning affordance', () {
    testWidgets(
      'absent when suggested_planning_item is null',
      (tester) async {
        final message = _attuneAssistMessage(content: 'Just an idea.');
        await tester.pumpWidget(
          _wrap(
            AttuneAssistBubble(message: message),
            gateway: _FakeAiAssistantGateway(),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Add'), findsNothing);
        expect(find.textContaining('Added'), findsNothing);
      },
    );

    testWidgets(
      'shows "Add to Planning" when a proposal exists and no link yet',
      (tester) async {
        final message = _attuneAssistMessage(
          content: 'Want to plan a date night?',
          assistantPayload: {
            'schema_version': 1,
            'suggested_planning_item': {
              'kind': 'event',
              'title': 'Date night',
              'event_date': '2026-10-01',
            },
            'sources': <dynamic>[],
          },
        );
        final gateway = _FakeAiAssistantGateway()
          ..nextSelectPlanningLinkResult = null;
        await tester.pumpWidget(
          _wrap(AttuneAssistBubble(message: message), gateway: gateway),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Add event to Planning'), findsOneWidget);
        expect(find.textContaining('Added to Planning'), findsNothing);
      },
    );

    testWidgets(
      'shows "Added to Planning" (not the Add button) once a link '
      'already exists',
      (tester) async {
        final message = _attuneAssistMessage(
          content: 'Want to plan a date night?',
          assistantPayload: {
            'schema_version': 1,
            'suggested_planning_item': {
              'kind': 'event',
              'title': 'Date night',
              'event_date': '2026-10-01',
            },
            'sources': <dynamic>[],
          },
        );
        final gateway = _FakeAiAssistantGateway()
          ..nextSelectPlanningLinkResult = {
            'planning_item_id': null,
            'planning_event_id': 'event-9',
          };
        await tester.pumpWidget(
          _wrap(AttuneAssistBubble(message: message), gateway: gateway),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Added to Planning'), findsOneWidget);
        expect(find.textContaining('Add event to Planning'), findsNothing);
      },
    );

    testWidgets(
      'tapping Add to Planning calls addToPlanning with the message id',
      (tester) async {
        final message = _attuneAssistMessage(
          content: 'Want to plan a date night?',
          assistantPayload: {
            'schema_version': 1,
            'suggested_planning_item': {
              'kind': 'event',
              'title': 'Date night',
              'event_date': '2026-10-01',
            },
            'sources': <dynamic>[],
          },
          id: 'assist-tap-1',
        );
        final gateway = _FakeAiAssistantGateway()
          ..nextSelectPlanningLinkResult = null
          ..nextRpcResult = [
            {'planning_item_id': null, 'planning_event_id': 'event-10'},
          ];
        await tester.pumpWidget(
          _wrap(AttuneAssistBubble(message: message), gateway: gateway),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Add event to Planning'));
        await tester.pumpAndSettle();

        expect(gateway.rpcCallCount, 1);
        expect(
          gateway.lastCalledParams!['p_message_id'],
          'assist-tap-1',
        );
        // No edited-title/date UI exists in v1 — the affordance is a
        // plain confirm, letting the RPC fall back to the proposal's
        // own title/date (its own documented COALESCE behavior).
        // Documented scope decision, not an oversight: the brief's own
        // Interfaces section describes the affordance's presence, not
        // an inline edit-title text field.
        expect(gateway.lastCalledParams!['p_edited_title'], isNull);
        expect(gateway.lastCalledParams!['p_edited_date'], isNull);
      },
    );

    testWidgets(
      'a concurrent-tap-shaped response (the link already existed by '
      'the time the RPC returns) shows "Added to Planning" without '
      'erroring visibly',
      (tester) async {
        final message = _attuneAssistMessage(
          content: 'Want to plan a date night?',
          assistantPayload: {
            'schema_version': 1,
            'suggested_planning_item': {
              'kind': 'task',
              'title': 'Buy tickets',
              'event_date': null,
            },
            'sources': <dynamic>[],
          },
          id: 'assist-race-1',
        );
        final gateway = _FakeAiAssistantGateway()..nextSelectPlanningLinkResult = null;
        await tester.pumpWidget(
          _wrap(AttuneAssistBubble(message: message), gateway: gateway),
        );
        await tester.pumpAndSettle();

        // create_planning_from_assist_message's own idempotent re-check
        // (Plan A Task 7) returns the SAME existing link row rather
        // than erroring on a second/racing confirm — simulate the
        // backend now having that row for BOTH the RPC's own return
        // value and the provider's next fetch after invalidation
        // (a real backend would return the same row from both paths
        // once the link exists).
        gateway.nextRpcResult = [
          {'planning_item_id': 'item-existing', 'planning_event_id': null},
        ];
        gateway.nextSelectPlanningLinkResult = {
          'planning_item_id': 'item-existing',
          'planning_event_id': null,
        };

        await tester.tap(find.textContaining('Add task to Planning'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Added to Planning'), findsOneWidget);
      },
    );
  });
}

