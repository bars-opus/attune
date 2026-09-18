// Model tests for the AI Assistant domain models. These prove
// fromJson-style parsing against the exact real wire shapes the two
// edge functions return (spec §5.2/§5.3/§6.2, and ai-assist/
// ai-understand's own index.ts, which is the more authoritative,
// more-recently-verified source of truth for the exact field names).
import 'package:attune/features/ai_assistant/data/models/assist_draft_model.dart';
import 'package:attune/features/ai_assistant/data/models/place_source_model.dart';
import 'package:attune/features/ai_assistant/data/models/understand_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceSourceModel', () {
    test('parses the exact §5.2 PlaceSource field list', () {
      final model = PlaceSourceModel.fromJson({
        'provider_id': 'mbx.abc123',
        'name': 'Blue Bottle Coffee',
        'formatted_address': '123 Main St, Springfield',
        'category': 'cafe',
        'map_url': 'https://www.mapbox.com/search/mbx.abc123',
      });

      expect(model.providerId, 'mbx.abc123');
      expect(model.name, 'Blue Bottle Coffee');
      expect(model.formattedAddress, '123 Main St, Springfield');
      expect(model.category, 'cafe');
      expect(model.mapUrl, 'https://www.mapbox.com/search/mbx.abc123');
    });

    test('allows formatted_address, category, and map_url to be null', () {
      final model = PlaceSourceModel.fromJson({
        'provider_id': 'mbx.def456',
        'name': 'Some Park',
        'formatted_address': null,
        'category': null,
        'map_url': null,
      });

      expect(model.formattedAddress, isNull);
      expect(model.category, isNull);
      expect(model.mapUrl, isNull);
    });

    test('throws on missing required provider_id rather than defaulting', () {
      expect(
        () => PlaceSourceModel.fromJson({
          'name': 'Some Park',
          'formatted_address': null,
          'category': null,
          'map_url': null,
        }),
        throwsA(anything),
      );
    });

    test('throws on missing required name rather than defaulting', () {
      expect(
        () => PlaceSourceModel.fromJson({
          'provider_id': 'mbx.ghi789',
          'formatted_address': null,
          'category': null,
          'map_url': null,
        }),
        throwsA(anything),
      );
    });
  });

  group('AssistDraftModel — ideas branch', () {
    test('parses reply_text and suggested_planning_item, no sources', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-123',
        'reply_text': 'Try a picnic in the park with a themed playlist.',
        'suggested_planning_item': {
          'kind': 'task',
          'title': 'Plan a picnic',
          'event_date': null,
        },
        'sources': [],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'ideas');

      expect(model, isA<AssistDraftIdeas>());
      final ideas = model as AssistDraftIdeas;
      expect(ideas.draftId, 'draft-123');
      expect(ideas.replyText, 'Try a picnic in the park with a themed playlist.');
      expect(ideas.expiresAt, DateTime.parse('2026-09-16T12:15:00.000Z'));
      expect(ideas.suggestedPlanningItem, isNotNull);
      expect(ideas.suggestedPlanningItem!.kind, SuggestedPlanningItemKind.task);
      expect(ideas.suggestedPlanningItem!.title, 'Plan a picnic');
      expect(ideas.suggestedPlanningItem!.eventDate, isNull);
    });

    test('parses an event-kind suggested_planning_item with event_date', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-124',
        'reply_text': 'A rooftop dinner could be fun.',
        'suggested_planning_item': {
          'kind': 'event',
          'title': 'Rooftop dinner',
          'event_date': '2026-10-01',
        },
        'sources': [],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'ideas');

      final ideas = model as AssistDraftIdeas;
      expect(ideas.suggestedPlanningItem!.kind, SuggestedPlanningItemKind.event);
      expect(ideas.suggestedPlanningItem!.eventDate, DateTime.parse('2026-10-01'));
    });

    test('allows a null suggested_planning_item', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-125',
        'reply_text': 'Some ideas without a concrete plan.',
        'suggested_planning_item': null,
        'sources': [],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'ideas');

      final ideas = model as AssistDraftIdeas;
      expect(ideas.suggestedPlanningItem, isNull);
    });

    test('an ideas draft never carries sources', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-126',
        'reply_text': 'Ideas text.',
        'suggested_planning_item': null,
        'sources': [],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'ideas');

      expect(model, isA<AssistDraftIdeas>());
      // AssistDraftIdeas has no `sources` field at all — this is a
      // compile-time guarantee from the sealed-class shape, not just a
      // runtime check; the isA<AssistDraftIdeas>() above is the proof.
    });
  });

  group('AssistDraftModel — nearby branch', () {
    test('parses reply_text and sources, no suggested_planning_item', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-200',
        'reply_text': 'Here are a few cafe options nearby: Blue Bottle, Ritual',
        'suggested_planning_item': null,
        'sources': [
          {
            'provider_id': 'mbx.abc123',
            'name': 'Blue Bottle Coffee',
            'formatted_address': '123 Main St',
            'category': 'cafe',
            'map_url': 'https://www.mapbox.com/search/mbx.abc123',
          },
          {
            'provider_id': 'mbx.xyz789',
            'name': 'Ritual Coffee',
            'formatted_address': null,
            'category': 'cafe',
            'map_url': null,
          },
        ],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'nearby');

      expect(model, isA<AssistDraftNearby>());
      final nearby = model as AssistDraftNearby;
      expect(nearby.draftId, 'draft-200');
      expect(nearby.replyText, startsWith('Here are a few cafe options'));
      expect(nearby.sources, hasLength(2));
      expect(nearby.sources[0].name, 'Blue Bottle Coffee');
      expect(nearby.sources[1].formattedAddress, isNull);
    });

    test('a nearby draft never carries suggestedPlanningItem', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-201',
        'reply_text': 'Nearby text.',
        'suggested_planning_item': null,
        'sources': <Map<String, dynamic>>[],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'nearby');

      expect(model, isA<AssistDraftNearby>());
      // AssistDraftNearby has no `suggestedPlanningItem` field at all —
      // the sealed-class shape itself is the proof, not a runtime null
      // check on a shared field.
    });

    test('nearby with an empty sources list still parses (server-side NO_RESULTS is a separate error path)', () {
      final model = AssistDraftModel.fromJson({
        'draft_id': 'draft-202',
        'reply_text': 'Nearby text.',
        'suggested_planning_item': null,
        'sources': <Map<String, dynamic>>[],
        'expires_at': '2026-09-16T12:15:00.000Z',
      }, assistKind: 'nearby');

      expect((model as AssistDraftNearby).sources, isEmpty);
    });
  });

  group('AssistDraftModel — malformed input', () {
    test('throws on an unrecognized assist_kind rather than defaulting', () {
      expect(
        () => AssistDraftModel.fromJson({
          'draft_id': 'draft-300',
          'reply_text': 'text',
          'suggested_planning_item': null,
          'sources': [],
          'expires_at': '2026-09-16T12:15:00.000Z',
        }, assistKind: 'something_else'),
        throwsA(anything),
      );
    });

    test('throws on a missing draft_id rather than constructing with a default', () {
      expect(
        () => AssistDraftModel.fromJson({
          'reply_text': 'text',
          'suggested_planning_item': null,
          'sources': [],
          'expires_at': '2026-09-16T12:15:00.000Z',
        }, assistKind: 'ideas'),
        throwsA(anything),
      );
    });

    test('throws on a missing expires_at rather than constructing with a default', () {
      expect(
        () => AssistDraftModel.fromJson({
          'draft_id': 'draft-301',
          'reply_text': 'text',
          'suggested_planning_item': null,
          'sources': [],
        }, assistKind: 'ideas'),
        throwsA(anything),
      );
    });

    test('throws on an unrecognized suggested_planning_item.kind', () {
      expect(
        () => AssistDraftModel.fromJson({
          'draft_id': 'draft-302',
          'reply_text': 'text',
          'suggested_planning_item': {
            'kind': 'goal',
            'title': 'Nope',
            'event_date': null,
          },
          'sources': [],
          'expires_at': '2026-09-16T12:15:00.000Z',
        }, assistKind: 'ideas'),
        throwsA(anything),
      );
    });
  });

  group('UnderstandResultModel — ok branch', () {
    test('parses possibleReadings, responseOptions, confidence', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'ok',
        'possible_readings': [
          'They might be tired and short on words.',
          'They might be annoyed about the earlier plan change.',
        ],
        'response_options': [
          'Want to talk about it tonight?',
          'No worries, let me know if you need space.',
        ],
        'confidence': 'medium',
      });

      expect(model, isA<UnderstandResultOk>());
      final ok = model as UnderstandResultOk;
      expect(ok.possibleReadings, hasLength(2));
      expect(ok.responseOptions, hasLength(2));
      expect(ok.confidence, UnderstandConfidence.medium);
    });

    test('accepts confidence: low', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'ok',
        'possible_readings': ['A', 'B'],
        'response_options': ['C', 'D'],
        'confidence': 'low',
      });
      expect((model as UnderstandResultOk).confidence, UnderstandConfidence.low);
    });

    test('accepts three-element arrays', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'ok',
        'possible_readings': ['A', 'B', 'C'],
        'response_options': ['D', 'E', 'F'],
        'confidence': 'low',
      });
      final ok = model as UnderstandResultOk;
      expect(ok.possibleReadings, hasLength(3));
      expect(ok.responseOptions, hasLength(3));
    });

    test('an ok result never carries reason', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'ok',
        'possible_readings': ['A', 'B'],
        'response_options': ['C', 'D'],
        'confidence': 'low',
      });
      expect(model, isA<UnderstandResultOk>());
      // UnderstandResultOk has no `reason` field — the sealed-class
      // shape is the proof.
    });
  });

  group('UnderstandResultModel — cannotHelp branch', () {
    test('parses reason', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'cannot_help',
        'reason': 'unsafe_to_infer',
      });

      expect(model, isA<UnderstandResultCannotHelp>());
      expect((model as UnderstandResultCannotHelp).reason, 'unsafe_to_infer');
    });

    test('a cannotHelp result never carries possibleReadings', () {
      final model = UnderstandResultModel.fromJson({
        'status': 'cannot_help',
        'reason': 'insufficient_context',
      });
      expect(model, isA<UnderstandResultCannotHelp>());
      // UnderstandResultCannotHelp has no `possibleReadings` field — the
      // sealed-class shape is the proof.
    });
  });

  group('UnderstandResultModel — malformed input', () {
    test('throws on an unrecognized status rather than defaulting', () {
      expect(
        () => UnderstandResultModel.fromJson({'status': 'weird'}),
        throwsA(anything),
      );
    });

    test('throws on an unrecognized confidence value', () {
      expect(
        () => UnderstandResultModel.fromJson({
          'status': 'ok',
          'possible_readings': ['A', 'B'],
          'response_options': ['C', 'D'],
          'confidence': 'high',
        }),
        throwsA(anything),
      );
    });

    test('throws on a missing reason for cannot_help', () {
      expect(
        () => UnderstandResultModel.fromJson({'status': 'cannot_help'}),
        throwsA(anything),
      );
    });

    test('throws on a missing possible_readings for ok', () {
      expect(
        () => UnderstandResultModel.fromJson({
          'status': 'ok',
          'response_options': ['C', 'D'],
          'confidence': 'low',
        }),
        throwsA(anything),
      );
    });
  });
}
