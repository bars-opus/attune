// Widget tests for AiConsentScreen (AI Assistant spec §10.1): the
// standalone consent disclosure/grant/waiting/withdraw screen.
//
// Idempotency-key note: `AiAssistantRepository.recordConsent(String
// relationshipId, String action)` takes exactly two parameters — the
// idempotency key is generated INSIDE the repository
// (`_generateUuidV4()` in ai_assistant_repository.dart), one fresh key
// per call, and this screen never sees or supplies one. So the
// "not a hardcoded/reused value across two separate taps" guarantee is
// asserted here at the gateway/rpc-params level: two separate `rpc()`
// calls to `record_ai_processing_consent` must receive two different
// `p_idempotency_key` values, and each must look UUID-shaped. There is
// no seam in this screen's own code that could pass a caller-supplied
// key — see this task's report for why the brief's "client-generated
// idempotency key" framing doesn't map to a param this method accepts.
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class _FakeAiAssistantGateway implements AiAssistantGateway {
  Object? nextRpcError;
  dynamic nextRpcResult;
  int rpcCallCount = 0;
  final List<Map<String, dynamic>?> rpcParamsCalls = [];
  final List<String> rpcFunctionCalls = [];

  /// Queue of consent-status rows returned by successive
  /// `get_ai_processing_consent_status` calls (the screen re-fetches
  /// after every grant/withdraw via `ref.invalidate`) — each call
  /// consumes the next entry, and the last entry repeats once
  /// exhausted, matching a real backend's "nothing changes if you ask
  /// again" behavior between distinct RPCs.
  List<Map<String, dynamic>> consentStatusRows = [
    {'caller_granted': false, 'both_granted': false, 'policy_version': 'v1'},
  ];
  int _consentStatusCallIndex = 0;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    throw UnsupportedError('AiConsentScreen must never call an edge function');
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    rpcFunctionCalls.add(function);
    rpcParamsCalls.add(params);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    if (function == 'get_ai_processing_consent_status') {
      final index = _consentStatusCallIndex < consentStatusRows.length
          ? _consentStatusCallIndex
          : consentStatusRows.length - 1;
      _consentStatusCallIndex++;
      return [consentStatusRows[index]];
    }

    rpcCallCount++;
    if (nextRpcError != null) {
      final error = nextRpcError!;
      nextRpcError = null;
      throw error;
    }
    return nextRpcResult;
  }

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) async {
    throw UnsupportedError('AiConsentScreen must never check a Planning link');
  }
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  required _FakeAiAssistantGateway gateway,
  String relationshipId = 'rel-1',
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
        home: AiConsentScreen(relationshipId: relationshipId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return container;
}

void main() {
  group('disclosure copy', () {
    testWidgets(
      'the disclosure text is genuinely present and not a placeholder '
      '(mentions the third-party AI provider, training, and both '
      "partners' consent — spec §10.1/§5.2)",
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        await _pumpScreen(tester, gateway: gateway);

        final disclosureFinder = find.byKey(
          const ValueKey('ai-consent-disclosure-text'),
        );
        expect(disclosureFinder, findsOneWidget);

        final disclosureWidget = tester.widget<Text>(disclosureFinder);
        final disclosureText = disclosureWidget.data ?? '';

        expect(disclosureText, isNot(contains('TODO')));
        expect(disclosureText, isNot(contains('placeholder')));
        expect(disclosureText.toLowerCase(), contains('third-party'));
        expect(disclosureText.toLowerCase(), contains('train'));
        expect(disclosureText.toLowerCase(), contains('both partners'));
        expect(disclosureText.length, greaterThan(80));
      },
    );
  });

  group('grant flow', () {
    testWidgets(
      'tapping the grant button calls recordConsent(relationshipId, '
      "'granted') via a single record_ai_processing_consent RPC with a "
      'UUID-shaped p_idempotency_key',
      (tester) async {
        final gateway = _FakeAiAssistantGateway();
        await _pumpScreen(tester, gateway: gateway, relationshipId: 'rel-42');

        expect(find.byKey(const ValueKey('ai-consent-grant-button')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('ai-consent-grant-button')));
        await tester.pumpAndSettle();

        final consentCalls = <Map<String, dynamic>?>[];
        for (var i = 0; i < gateway.rpcFunctionCalls.length; i++) {
          if (gateway.rpcFunctionCalls[i] == 'record_ai_processing_consent') {
            consentCalls.add(gateway.rpcParamsCalls[i]);
          }
        }

        expect(consentCalls, hasLength(1));
        expect(consentCalls.single!['p_relationship_id'], 'rel-42');
        expect(consentCalls.single!['p_action'], 'granted');

        final key = consentCalls.single!['p_idempotency_key'] as String;
        expect(_uuidV4Pattern.hasMatch(key), isTrue,
            reason: 'p_idempotency_key must be a UUID-shaped value, got "$key"');
      },
    );

    testWidgets(
      'granting twice (e.g. a retry) sends two DIFFERENT idempotency '
      'keys, never a hardcoded/reused one',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..consentStatusRows = [
            {'caller_granted': false, 'both_granted': false, 'policy_version': 'v1'},
            {'caller_granted': false, 'both_granted': false, 'policy_version': 'v1'},
          ];
        await _pumpScreen(tester, gateway: gateway);

        await tester.tap(find.byKey(const ValueKey('ai-consent-grant-button')));
        await tester.pumpAndSettle();

        // Still shows the grant button because callerGranted stayed
        // false in the faked re-fetch — allows a second, independent
        // grant tap in the same test.
        expect(find.byKey(const ValueKey('ai-consent-grant-button')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ai-consent-grant-button')));
        await tester.pumpAndSettle();

        final keys = <String>[];
        for (var i = 0; i < gateway.rpcFunctionCalls.length; i++) {
          if (gateway.rpcFunctionCalls[i] == 'record_ai_processing_consent') {
            keys.add(gateway.rpcParamsCalls[i]!['p_idempotency_key'] as String);
          }
        }

        expect(keys, hasLength(2));
        expect(keys[0], isNot(equals(keys[1])),
            reason: 'each grant call must generate its own fresh idempotency key');
        for (final key in keys) {
          expect(_uuidV4Pattern.hasMatch(key), isTrue);
        }
      },
    );
  });

  group('waiting-for-partner state', () {
    testWidgets(
      'after granting, if the partner has not yet granted, the screen '
      'shows the waiting state without erroring',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..consentStatusRows = [
            {'caller_granted': false, 'both_granted': false, 'policy_version': 'v1'},
            {'caller_granted': true, 'both_granted': false, 'policy_version': 'v1'},
          ];
        await _pumpScreen(tester, gateway: gateway);

        await tester.tap(find.byKey(const ValueKey('ai-consent-grant-button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('ai-consent-waiting-for-partner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ai-consent-granted-confirmation')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'once both partners have granted, no waiting state is shown',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..consentStatusRows = [
            {'caller_granted': true, 'both_granted': true, 'policy_version': 'v1'},
          ];
        await _pumpScreen(tester, gateway: gateway);

        expect(
          find.byKey(const ValueKey('ai-consent-waiting-for-partner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('ai-consent-withdraw-button')),
          findsOneWidget,
        );
      },
    );
  });

  group('withdrawal', () {
    testWidgets(
      'withdrawing (after confirming the dialog) calls '
      "recordConsent(relationshipId, 'withdrawn')",
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..consentStatusRows = [
            {'caller_granted': true, 'both_granted': true, 'policy_version': 'v1'},
            {'caller_granted': false, 'both_granted': false, 'policy_version': 'v1'},
          ];
        await _pumpScreen(tester, gateway: gateway, relationshipId: 'rel-9');

        expect(find.byKey(const ValueKey('ai-consent-withdraw-button')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ai-consent-withdraw-button')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears; confirm it.
        expect(find.text('Withdraw'), findsOneWidget);
        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        final consentCalls = <Map<String, dynamic>?>[];
        for (var i = 0; i < gateway.rpcFunctionCalls.length; i++) {
          if (gateway.rpcFunctionCalls[i] == 'record_ai_processing_consent') {
            consentCalls.add(gateway.rpcParamsCalls[i]);
          }
        }

        expect(consentCalls, hasLength(1));
        expect(consentCalls.single!['p_relationship_id'], 'rel-9');
        expect(consentCalls.single!['p_action'], 'withdrawn');
      },
    );

    testWidgets(
      'cancelling the withdrawal dialog calls recordConsent zero times',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..consentStatusRows = [
            {'caller_granted': true, 'both_granted': true, 'policy_version': 'v1'},
          ];
        await _pumpScreen(tester, gateway: gateway);

        await tester.tap(find.byKey(const ValueKey('ai-consent-withdraw-button')));
        await tester.pumpAndSettle();

        expect(find.text('Cancel'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final consentCalls = gateway.rpcFunctionCalls
            .where((f) => f == 'record_ai_processing_consent');
        expect(consentCalls, isEmpty);
      },
    );
  });
}
