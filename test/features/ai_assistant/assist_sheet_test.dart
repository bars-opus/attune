// Widget tests for AssistSheet (AI Assistant spec §5): the Ideas/Nearby
// input flow, the private preview, and Share/Edit-as-mine/Close.
//
// Design decisions this test file locks in (spec leaves the UX open,
// brief asks the task to decide and document):
//  - Ideas' 300-char instruction cap DISABLES Generate over the limit
//    (rather than silently truncating) — the user's own text is never
//    silently altered.
//  - Share-time draft-expiry is detected CLIENT-SIDE against the
//    draft's own `expiresAt` (spec §5.3/§11: "it never posts stale
//    content" is a proactive guarantee, and `share_ai_assist_draft`'s
//    real SQL (20260950080000_ai_assist_draft_and_share_rpcs.sql) only
//    ever raises a bare `RAISE EXCEPTION 'Draft expired'`, which
//    AiAssistantRepository's own transport-error mapping (see its
//    class doc) deliberately maps to the generic `internalError()` —
//    there is no `AssistantError` subtype for "expired" among the 12
//    codes, so the sheet cannot distinguish it from any other RPC
//    failure AFTER calling shareDraft; it must know BEFORE calling).
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/assistant_error.dart';
import 'package:attune/features/ai_assistant/data/services/raw_location_service.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/assist_sheet.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiAssistantGateway implements AiAssistantGateway {
  Object? nextInvokeError;
  dynamic nextInvokeResult;
  Map<String, dynamic>? lastInvokeBody;
  int invokeCallCount = 0;

  Object? nextRpcError;
  dynamic nextRpcResult;
  String? lastCalledFunction;
  Map<String, dynamic>? lastCalledParams;
  int rpcCallCount = 0;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    invokeCallCount++;
    lastInvokeBody = body;
    // A real edge-function call always crosses an await boundary later
    // than the very next frame; without this delay a single
    // `tester.pump()` right after the tap would already observe the
    // resolved result, making the "no premature preview" assertion
    // vacuous (it would pass even if AssistSheet showed an optimistic
    // preview synchronously).
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (nextInvokeError != null) {
      final error = nextInvokeError!;
      nextInvokeError = null;
      throw error;
    }
    return nextInvokeResult;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    rpcCallCount++;
    lastCalledFunction = function;
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
    return null;
  }
}

/// A fake RawLocationService is not possible via subclassing (the real
/// one has no virtual seam), so the provider that supplies it to the
/// sheet is overridden directly in tests that need Nearby's location
/// step — see `rawLocationServiceProvider` in
/// `ai_assistant_providers.dart`.
class _FakeRawLocationService implements RawLocationService {
  _FakeRawLocationService(this.nextResult);
  RawPositionResult nextResult;
  int callCount = 0;

  @override
  Future<RawPositionResult> getCurrentPosition() async {
    callCount++;
    return nextResult;
  }
}

Map<String, dynamic> _ideasResponse({
  String draftId = 'draft-1',
  String replyText = 'Try a picnic in the park.',
  String expiresAt = '2999-01-01T00:00:00.000Z',
  Map<String, dynamic>? suggestedPlanningItem,
}) => {
  'draft_id': draftId,
  'reply_text': replyText,
  'suggested_planning_item': suggestedPlanningItem,
  'expires_at': expiresAt,
};

Map<String, dynamic> _nearbyResponse({
  String draftId = 'draft-nearby-1',
  String expiresAt = '2999-01-01T00:00:00.000Z',
}) => {
  'draft_id': draftId,
  'reply_text': 'A few spots nearby.',
  'sources': [
    {
      'provider_id': 'place-1',
      'name': 'Riverside Cafe',
      'formatted_address': '12 River Rd',
      'category': 'cafe',
      'map_url': 'https://maps.example/place-1',
    },
  ],
  'expires_at': expiresAt,
};

Message _message() {
  return Message(
    id: 'm1',
    clientMessageId: 'c-m1',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: 'want to grab dinner this weekend?',
    createdAt: DateTime(2026, 9, 18),
    status: MessageStatus.sent,
    isMine: false,
  );
}

Future<ProviderContainer> _pumpIdeasSheet(
  WidgetTester tester, {
  required _FakeAiAssistantGateway gateway,
  VoidCallback? onShared,
  ValueChanged<String>? onEditAsMine,
}) async {
  final container = ProviderContainer(
    overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(
        AiAssistantRepository(gateway),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AssistSheet(
          message: _message(),
          kind: AssistKind.ideas,
          onShared: onShared ?? () {},
          onEditAsMine: onEditAsMine ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 30));
  return container;
}

Future<ProviderContainer> _pumpNearbySheet(
  WidgetTester tester, {
  required _FakeAiAssistantGateway gateway,
  required _FakeRawLocationService locationService,
  VoidCallback? onShared,
  ValueChanged<String>? onEditAsMine,
}) async {
  final container = ProviderContainer(
    overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(
        AiAssistantRepository(gateway),
      ),
      rawLocationServiceProvider.overrideWithValue(locationService),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AssistSheet(
          message: _message(),
          kind: AssistKind.nearby,
          onShared: onShared ?? () {},
          onEditAsMine: onEditAsMine ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 30));
  return container;
}

void main() {
  group('Ideas input', () {
    testWidgets(
      'an instruction over 300 characters disables Generate',
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        await _pumpIdeasSheet(tester, gateway: gateway);

        final overLimit = 'a' * 301;
        await tester.enterText(find.byType(TextField), overLimit);
        await tester.pump();

        final generateButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Generate'),
        );
        expect(
          generateButton.onPressed,
          isNull,
          reason: 'over-300-char instructions must not be silently truncated '
              'or sent — Generate is disabled instead',
        );
      },
    );

    testWidgets(
      'exactly 300 characters keeps Generate enabled',
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        await _pumpIdeasSheet(tester, gateway: gateway);

        final atLimit = 'a' * 300;
        await tester.enterText(find.byType(TextField), atLimit);
        await tester.pump();

        final generateButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Generate'),
        );
        expect(generateButton.onPressed, isNotNull);
      },
    );

    testWidgets(
      'no preview/Share/Edit/Close appears until generation completes',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse();
        await _pumpIdeasSheet(tester, gateway: gateway);

        expect(find.text('Share in chat'), findsNothing);
        expect(find.text('Edit as my message'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        // Exactly one pump: the request is in flight, nothing has
        // resolved yet — this is the "no premature/optimistic preview"
        // guarantee, checked at the frame right after the tap.
        await tester.pump();

        expect(
          find.text('Share in chat'),
          findsNothing,
          reason: 'must not show a preview before the draft resolves',
        );
        expect(find.text('Edit as my message'), findsNothing);

        await tester.pump(const Duration(milliseconds: 30));
        expect(find.text('Share in chat'), findsOneWidget);
        expect(find.text('Edit as my message'), findsOneWidget);
        expect(find.text('Try a picnic in the park.'), findsOneWidget);
      },
    );
  });

  group('Nearby flow', () {
    testWidgets(
      'the exact §5.2 disclosure copy is shown before any permission '
      'request',
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        final location = _FakeRawLocationService(const RawPositionDenied());
        await _pumpNearbySheet(
          tester,
          gateway: gateway,
          locationService: location,
        );

        expect(
          find.text(
            'Attune will use your approximate location to suggest nearby '
            'places. This is only used for this request and is not stored.',
          ),
          findsOneWidget,
        );
        expect(location.callCount, 0);
        expect(gateway.invokeCallCount, 0);
      },
    );

    testWidgets(
      'declining returns to the sheet WITHOUT calling the repository at '
      'all (declining consumes no quota)',
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        final location = _FakeRawLocationService(const RawPositionDenied());
        await _pumpNearbySheet(
          tester,
          gateway: gateway,
          locationService: location,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(
          gateway.invokeCallCount,
          0,
          reason: 'declining Nearby location must never call ai-assist',
        );
        expect(
          find.text(
            'Attune will use your approximate location to suggest nearby '
            'places. This is only used for this request and is not stored.',
          ),
          findsOneWidget,
          reason: 'declining returns to the disclosure/sheet, not a crash',
        );
      },
    );

    testWidgets(
      'granting location proceeds to generate and show the preview',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _nearbyResponse();
        final location = _FakeRawLocationService(
          const RawPositionSuccess(
            latitude: 1,
            longitude: 2,
            accuracyM: 10,
          ),
        );
        await _pumpNearbySheet(
          tester,
          gateway: gateway,
          locationService: location,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(location.callCount, 1);
        expect(gateway.invokeCallCount, 1);
        expect(find.text('Share in chat'), findsOneWidget);
        expect(find.text('Riverside Cafe'), findsOneWidget);
      },
    );
  });

  group('Share', () {
    testWidgets(
      'tapping Share calls shareDraft with the exact draft id and closes '
      'the sheet on success',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(draftId: 'draft-abc');
        var shared = false;
        await _pumpIdeasSheet(
          tester,
          gateway: gateway,
          onShared: () => shared = true,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));

        gateway.nextRpcResult = null;
        await tester.tap(find.widgetWithText(FilledButton, 'Share in chat'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(gateway.lastCalledFunction, 'share_ai_assist_draft');
        expect(gateway.lastCalledParams, {'p_draft_id': 'draft-abc'});
        expect(shared, isTrue, reason: 'onShared signals sheet completion');
      },
    );
  });

  group('Edit as my message', () {
    testWidgets(
      'copies ONLY replyText and never calls shareDraft/RPC',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(
            replyText: 'A rooftop dinner sounds nice.',
          );
        String? editedText;
        await _pumpIdeasSheet(
          tester,
          gateway: gateway,
          onEditAsMine: (text) => editedText = text,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));

        await tester.tap(find.text('Edit as my message'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(editedText, 'A rooftop dinner sounds nice.');
        expect(
          gateway.rpcCallCount,
          0,
          reason: '"Edit as my message" must never call shareDraft or any '
              'other RPC — sending happens later via the ordinary composer',
        );
      },
    );

    testWidgets(
      'strips provenance entirely — a draft carrying a suggested '
      'Planning item produces an edited value with NO trace of it '
      '(kind/title/date), only the bare replyText',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(
            replyText: 'Want to try that new ramen place?',
            suggestedPlanningItem: {
              'kind': 'event',
              'title': 'Ramen night',
              'event_date': '2026-09-20',
            },
          );
        String? editedText;
        await _pumpIdeasSheet(
          tester,
          gateway: gateway,
          onEditAsMine: (text) => editedText = text,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));

        await tester.tap(find.text('Edit as my message'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(editedText, 'Want to try that new ramen place?');
        expect(editedText, isNot(contains('Ramen night')));
        expect(editedText, isNot(contains('event')));
        expect(editedText, isNot(contains('2026-09-20')));
      },
    );
  });

  group('Close', () {
    testWidgets(
      'discards client-side preview state without calling shareDraft',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse();
        await _pumpIdeasSheet(tester, gateway: gateway);

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.text('Share in chat'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(gateway.rpcCallCount, 0);
      },
    );
  });

  group('errors', () {
    testWidgets(
      'RATE_LIMITED renders retry_after_seconds as actual seconds, never '
      '"tomorrow"',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeError = const AssistantError.rateLimited(97);
        await _pumpIdeasSheet(tester, gateway: gateway);

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(find.textContaining('97'), findsOneWidget);
        expect(find.textContaining('tomorrow'), findsNothing);
        expect(find.textContaining('Tomorrow'), findsNothing);
      },
    );

    testWidgets(
      'an expired draft Share attempt shows the expiry copy and never '
      'calls shareDraft',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _ideasResponse(
            // Already in the past relative to "now" at test run time.
            expiresAt: '2000-01-01T00:00:00.000Z',
          );
        await _pumpIdeasSheet(tester, gateway: gateway);

        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.text('Share in chat'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Share in chat'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(find.text('This suggestion expired — ask again'), findsOneWidget);
        expect(
          gateway.rpcCallCount,
          0,
          reason: 'an expired draft must never attempt to post anything',
        );
      },
    );
  });
}
