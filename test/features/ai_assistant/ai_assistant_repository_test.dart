// Repository-level tests exercise error MAPPING and request/response
// wiring, not live edge-function/RPC behavior (the backend's own
// contract tests already prove ai-assist/ai-understand and Plan A's
// RPCs correct). A fake SupabaseClient stand-in is not practical for
// `.functions.invoke()`/`.rpc()` against the real generic client (the
// same reasoning planning_repository_test.dart gives for faking its
// own gateway interface instead) — so this repository takes an
// injected gateway interface, and these tests fake THAT, not
// SupabaseClient itself. See
// lib/features/planning/data/repositories/planning_repository.dart
// and its test file for the established pattern this matches.
import 'package:attune/features/ai_assistant/data/models/assist_draft_model.dart';
import 'package:attune/features/ai_assistant/data/models/understand_result_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/assistant_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAiAssistantGateway implements AiAssistantGateway {
  // functions.invoke
  Object? nextInvokeError;
  dynamic nextInvokeResult;
  String? lastInvokedFunction;
  Map<String, dynamic>? lastInvokeBody;

  // rpc
  Object? nextRpcError;
  dynamic nextRpcResult;
  String? lastCalledFunction;
  Map<String, dynamic>? lastCalledParams;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    lastInvokedFunction = functionName;
    lastInvokeBody = body;
    if (nextInvokeError != null) {
      final error = nextInvokeError!;
      nextInvokeError = null;
      throw error;
    }
    return nextInvokeResult;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    lastCalledFunction = function;
    lastCalledParams = params;
    if (nextRpcError != null) {
      final error = nextRpcError!;
      nextRpcError = null;
      throw error;
    }
    return nextRpcResult;
  }
}

Map<String, dynamic> _ideasResponse() => {
  'draft_id': 'draft-1',
  'reply_text': 'Try a picnic.',
  'suggested_planning_item': {
    'kind': 'task',
    'title': 'Plan a picnic',
    'event_date': null,
  },
  'sources': [],
  'expires_at': '2026-09-16T12:15:00.000Z',
};

Map<String, dynamic> _nearbyResponse() => {
  'draft_id': 'draft-2',
  'reply_text': 'Here are a few cafe options: Blue Bottle',
  'suggested_planning_item': null,
  'sources': [
    {
      'provider_id': 'mbx.abc',
      'name': 'Blue Bottle Coffee',
      'formatted_address': '123 Main St',
      'category': 'cafe',
      'map_url': 'https://www.mapbox.com/search/mbx.abc',
    },
  ],
  'expires_at': '2026-09-16T12:15:00.000Z',
};

FunctionException _errorException(
  String code, {
  int? retryAfterSeconds,
  int status = 400,
}) {
  return FunctionException(
    status: status,
    details: {
      'error': true,
      'code': code,
      'retryable': false,
      'retry_after_seconds': retryAfterSeconds,
    },
    reasonPhrase: code,
  );
}

void main() {
  group('requestAssist — ideas', () {
    test('parses a successful ideas response into AssistDraftModel.ideas', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = _ideasResponse();
      final repo = AiAssistantRepository(gateway);

      final result = await repo.requestAssist(
        requestId: 'req-1',
        messageId: 'msg-1',
        assistKind: 'ideas',
        userInstruction: null,
        requesterLocation: null,
      );

      expect(result, isA<AssistDraftIdeas>());
      expect((result as AssistDraftIdeas).draftId, 'draft-1');
      expect(gateway.lastInvokedFunction, 'ai-assist');
      expect(gateway.lastInvokeBody!['assist_kind'], 'ideas');
      expect(gateway.lastInvokeBody!['request_id'], 'req-1');
      expect(gateway.lastInvokeBody!['message_id'], 'msg-1');
    });
  });

  group('requestAssist — nearby', () {
    test('parses a successful nearby response into AssistDraftModel.nearby with sources', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = _nearbyResponse();
      final repo = AiAssistantRepository(gateway);

      final result = await repo.requestAssist(
        requestId: 'req-2',
        messageId: 'msg-2',
        assistKind: 'nearby',
        userInstruction: null,
        requesterLocation: (latitude: 37.0, longitude: -122.0, accuracyM: 20.0),
      );

      expect(result, isA<AssistDraftNearby>());
      final nearby = result as AssistDraftNearby;
      expect(nearby.sources, hasLength(1));
      expect(nearby.sources.first.name, 'Blue Bottle Coffee');
      expect(gateway.lastInvokeBody!['assist_kind'], 'nearby');
      expect(gateway.lastInvokeBody!['requester_location'], {
        'latitude': 37.0,
        'longitude': -122.0,
        'accuracy_m': 20.0,
      });
    });
  });

  group('requestAssist — error mapping (all 12 spec §11 codes)', () {
    final cases = <String, AssistantError>{
      'UNAUTHENTICATED': const AssistantError.unauthenticated(),
      'CONSENT_REQUIRED': const AssistantError.consentRequired(),
      'TARGET_UNAVAILABLE': const AssistantError.targetUnavailable(),
      'INVALID_INPUT': const AssistantError.invalidInput(),
      'UNSUPPORTED_REQUEST': const AssistantError.unsupportedRequest(),
      'LOCATION_REQUIRED': const AssistantError.locationRequired(),
      'NO_RESULTS': const AssistantError.noResults(),
      'RATE_LIMITED': const AssistantError.rateLimited(30),
      'REQUEST_IN_PROGRESS': const AssistantError.requestInProgress(),
      'RESULT_UNAVAILABLE': const AssistantError.resultUnavailable(),
      'PROVIDER_UNAVAILABLE': const AssistantError.providerUnavailable(),
      'INTERNAL_ERROR': const AssistantError.internalError(),
    };

    for (final entry in cases.entries) {
      test('${entry.key} maps to ${entry.value.runtimeType}', () async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeError = _errorException(
            entry.key,
            retryAfterSeconds: entry.key == 'RATE_LIMITED' ? 30 : null,
          );
        final repo = AiAssistantRepository(gateway);

        await expectLater(
          repo.requestAssist(
            requestId: 'req-x',
            messageId: 'msg-x',
            assistKind: 'ideas',
            userInstruction: null,
            requesterLocation: null,
          ),
          throwsA(isA<AssistantError>().having(
            (e) => e.runtimeType,
            'runtimeType',
            entry.value.runtimeType,
          )),
        );
      });
    }

    test('RATE_LIMITED carries retry_after_seconds through into retryAfterSeconds', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeError = _errorException('RATE_LIMITED', retryAfterSeconds: 42);
      final repo = AiAssistantRepository(gateway);

      try {
        await repo.requestAssist(
          requestId: 'req-y',
          messageId: 'msg-y',
          assistKind: 'ideas',
          userInstruction: null,
          requesterLocation: null,
        );
        fail('expected AssistantError.rateLimited to be thrown');
      } catch (e) {
        expect(e, isA<AssistantRateLimitedError>());
        expect((e as AssistantRateLimitedError).retryAfterSeconds, 42);
      }
    });
  });

  group('requestAssist — malformed success response', () {
    test('maps a malformed success-status response to AssistantError.internalError()', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = {'not': 'the expected shape'};
      final repo = AiAssistantRepository(gateway);

      await expectLater(
        repo.requestAssist(
          requestId: 'req-z',
          messageId: 'msg-z',
          assistKind: 'ideas',
          userInstruction: null,
          requesterLocation: null,
        ),
        throwsA(isA<AssistantInternalError>()),
      );
    });
  });

  group('requestUnderstand', () {
    test('parses a successful ok response', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = {
          'status': 'ok',
          'possible_readings': ['A', 'B'],
          'response_options': ['C', 'D'],
          'confidence': 'low',
        };
      final repo = AiAssistantRepository(gateway);

      final result = await repo.requestUnderstand(
        requestId: 'req-u1',
        messageId: 'msg-u1',
        utcOffsetMinutes: -420,
      );

      expect(gateway.lastInvokedFunction, 'ai-understand');
      expect(gateway.lastInvokeBody!['utc_offset_minutes'], -420);
      expect(result, isA<UnderstandResultOk>());
      expect((result as UnderstandResultOk).possibleReadings, ['A', 'B']);
    });

    test('maps a malformed success response to AssistantError.internalError()', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = {'status': 'not_a_real_status'};
      final repo = AiAssistantRepository(gateway);

      await expectLater(
        repo.requestUnderstand(
          requestId: 'req-u2',
          messageId: 'msg-u2',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AssistantInternalError>()),
      );
    });

    test('maps a CONSENT_REQUIRED failure', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeError = _errorException('CONSENT_REQUIRED');
      final repo = AiAssistantRepository(gateway);

      await expectLater(
        repo.requestUnderstand(
          requestId: 'req-u3',
          messageId: 'msg-u3',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AssistantConsentRequiredError>()),
      );
    });
  });

  group('shareDraft', () {
    test('calls share_ai_assist_draft with exactly p_draft_id', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextRpcResult = {'id': 'msg-1', 'content': 'shared'};
      final repo = AiAssistantRepository(gateway);

      await repo.shareDraft('draft-1');

      expect(gateway.lastCalledFunction, 'share_ai_assist_draft');
      expect(gateway.lastCalledParams, {'p_draft_id': 'draft-1'});
    });

    test('maps a PostgrestException-shaped rpc failure to AssistantError.internalError()', () async {
      final gateway = _FakeAiAssistantGateway()..nextRpcError = Exception('boom');
      final repo = AiAssistantRepository(gateway);

      await expectLater(
        repo.shareDraft('draft-1'),
        throwsA(isA<AssistantInternalError>()),
      );
    });
  });

  group('getConsentStatus / recordConsent', () {
    test('getConsentStatus calls get_ai_processing_consent_status with p_relationship_id', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextRpcResult = [
          {'caller_granted': true, 'both_granted': false, 'policy_version': 'v1'},
        ];
      final repo = AiAssistantRepository(gateway);

      final status = await repo.getConsentStatus('rel-1');

      expect(gateway.lastCalledFunction, 'get_ai_processing_consent_status');
      expect(gateway.lastCalledParams, {'p_relationship_id': 'rel-1'});
      expect(status.callerGranted, true);
      expect(status.bothGranted, false);
      expect(status.policyVersion, 'v1');
    });

    test('recordConsent calls record_ai_processing_consent with p_relationship_id, p_action, p_idempotency_key', () async {
      final gateway = _FakeAiAssistantGateway()..nextRpcResult = null;
      final repo = AiAssistantRepository(gateway);

      await repo.recordConsent('rel-1', 'granted');

      expect(gateway.lastCalledFunction, 'record_ai_processing_consent');
      expect(gateway.lastCalledParams!['p_relationship_id'], 'rel-1');
      expect(gateway.lastCalledParams!['p_action'], 'granted');
      expect(gateway.lastCalledParams!['p_idempotency_key'], isNotNull);
    });
  });

  group('addToPlanning', () {
    test('calls create_planning_from_assist_message with p_message_id, p_edited_title, p_edited_date', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextRpcResult = [
          {'planning_item_id': 'item-1', 'planning_event_id': null},
        ];
      final repo = AiAssistantRepository(gateway);

      final editedDate = DateTime.parse('2026-10-01');
      await repo.addToPlanning(
        'msg-1',
        editedTitle: 'New title',
        editedDate: editedDate,
      );

      expect(gateway.lastCalledFunction, 'create_planning_from_assist_message');
      expect(gateway.lastCalledParams!['p_message_id'], 'msg-1');
      expect(gateway.lastCalledParams!['p_edited_title'], 'New title');
      expect(gateway.lastCalledParams!['p_edited_date'], '2026-10-01');
    });

    test('passes null p_edited_title/p_edited_date when not overridden', () async {
      final gateway = _FakeAiAssistantGateway()
        ..nextRpcResult = [
          {'planning_item_id': 'item-2', 'planning_event_id': null},
        ];
      final repo = AiAssistantRepository(gateway);

      await repo.addToPlanning('msg-2');

      expect(gateway.lastCalledParams!['p_edited_title'], isNull);
      expect(gateway.lastCalledParams!['p_edited_date'], isNull);
    });
  });
}
