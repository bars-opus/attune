// lib/features/ai_assistant/data/models/assist_draft_model.dart
import 'place_source_model.dart';

/// The kind of a suggested Planning item Ideas may propose (spec
/// §5.2's `IdeasModelOutput.suggested_planning_item.kind`). The model
/// never creates one — this only carries the proposal for "Add to
/// Planning" (spec §5.4).
enum SuggestedPlanningItemKind { task, event }

SuggestedPlanningItemKind _parseSuggestedPlanningItemKind(Object? value) {
  switch (value) {
    case 'task':
      return SuggestedPlanningItemKind.task;
    case 'event':
      return SuggestedPlanningItemKind.event;
    default:
      throw FormatException(
        'SuggestedPlanningItem.fromJson: unrecognized kind "$value"',
      );
  }
}

/// A Planning Task/Event proposal Ideas may attach to its reply. Matches
/// spec §5.2 exactly: `{ kind: 'task' | 'event', title: string,
/// event_date: string | null }` — `event_date` is only ever non-null
/// when `kind == 'event'`.
class SuggestedPlanningItem {
  final SuggestedPlanningItemKind kind;
  final String title;
  final DateTime? eventDate;

  const SuggestedPlanningItem({
    required this.kind,
    required this.title,
    this.eventDate,
  });

  factory SuggestedPlanningItem.fromJson(Map<String, dynamic> json) {
    final kind = _parseSuggestedPlanningItemKind(json['kind']);
    final title = json['title'];
    if (title is! String || title.isEmpty) {
      throw FormatException(
        'SuggestedPlanningItem.fromJson: missing/invalid title',
      );
    }
    final rawEventDate = json['event_date'];
    DateTime? eventDate;
    if (rawEventDate != null) {
      if (rawEventDate is! String) {
        throw FormatException(
          'SuggestedPlanningItem.fromJson: invalid event_date',
        );
      }
      eventDate = DateTime.parse(rawEventDate);
    }
    return SuggestedPlanningItem(
      kind: kind,
      title: title,
      eventDate: eventDate,
    );
  }
}

/// An Assist draft, as `ai-assist` returns it (spec §5.3, and
/// ai-assist/index.ts's own `handleIdeas`/`handleNearby` response
/// shapes). Sealed on `assist_kind` so the two branches are mutually
/// exclusive at the type level, not just by runtime-null convention:
/// [AssistDraftIdeas] has no `sources` field at all, and
/// [AssistDraftNearby] has no `suggestedPlanningItem` field at all —
/// there is no shared nullable field either branch could accidentally
/// populate for the other.
///
/// `assist_kind` itself is never present in the wire response (the
/// server already knows which branch it is serving); the caller
/// supplies it from the request it made, matching how
/// `ai_assistant_repository.dart` calls this factory.
sealed class AssistDraftModel {
  final String draftId;
  final DateTime expiresAt;

  const AssistDraftModel({required this.draftId, required this.expiresAt});

  /// Throws on any missing/mistyped field rather than defaulting —
  /// this is the boundary where raw server JSON becomes a trusted
  /// model, so a malformed response must never render as if the
  /// server said something it didn't.
  factory AssistDraftModel.fromJson(
    Map<String, dynamic> json, {
    required String assistKind,
  }) {
    final draftId = json['draft_id'];
    if (draftId is! String || draftId.isEmpty) {
      throw FormatException('AssistDraftModel.fromJson: missing draft_id');
    }
    final replyText = json['reply_text'];
    if (replyText is! String || replyText.isEmpty) {
      throw FormatException('AssistDraftModel.fromJson: missing reply_text');
    }
    final rawExpiresAt = json['expires_at'];
    if (rawExpiresAt is! String) {
      throw FormatException('AssistDraftModel.fromJson: missing expires_at');
    }
    final expiresAt = DateTime.parse(rawExpiresAt);

    switch (assistKind) {
      case 'ideas':
        final rawItem = json['suggested_planning_item'];
        SuggestedPlanningItem? suggestedItem;
        if (rawItem != null) {
          if (rawItem is! Map<String, dynamic>) {
            throw FormatException(
              'AssistDraftModel.fromJson: invalid suggested_planning_item',
            );
          }
          suggestedItem = SuggestedPlanningItem.fromJson(rawItem);
        }
        return AssistDraftIdeas(
          draftId: draftId,
          expiresAt: expiresAt,
          replyText: replyText,
          suggestedPlanningItem: suggestedItem,
        );
      case 'nearby':
        final rawSources = json['sources'];
        if (rawSources is! List) {
          throw FormatException('AssistDraftModel.fromJson: missing sources');
        }
        final sources = rawSources
            .map(
              (s) => PlaceSourceModel.fromJson(
                Map<String, dynamic>.from(s as Map),
              ),
            )
            .toList(growable: false);
        return AssistDraftNearby(
          draftId: draftId,
          expiresAt: expiresAt,
          replyText: replyText,
          sources: sources,
        );
      default:
        throw FormatException(
          'AssistDraftModel.fromJson: unrecognized assist_kind "$assistKind"',
        );
    }
  }
}

/// Ideas branch: subjective brainstorming, optionally with one
/// suggested Planning Task/Event (spec §5.1/§5.2). Never carries
/// `sources` — Ideas makes no Mapbox call.
class AssistDraftIdeas extends AssistDraftModel {
  final String replyText;
  final SuggestedPlanningItem? suggestedPlanningItem;

  const AssistDraftIdeas({
    required super.draftId,
    required super.expiresAt,
    required this.replyText,
    this.suggestedPlanningItem,
  });
}

/// Nearby branch: real places from Mapbox (spec §5.1/§5.2). Never
/// carries `suggestedPlanningItem` — Nearby never proposes a Planning
/// item.
class AssistDraftNearby extends AssistDraftModel {
  final String replyText;
  final List<PlaceSourceModel> sources;

  const AssistDraftNearby({
    required super.draftId,
    required super.expiresAt,
    required this.replyText,
    required this.sources,
  });
}
