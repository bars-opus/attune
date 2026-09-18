// lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart
//
// The distinct visual treatment for a shared Attune Assist message
// (AI Assistant spec §5.3): attributed to the requester, rendered as an
// Attune-authored suggestion, never an authorless system notice. The
// entire branch this widget lives in is driven by
// `message.isAttuneAssistOutput` (a check on the server-owned
// `message_origin` column) — never by inspecting `message.content` for
// AI-sounding phrasing. Spec §0's own P0 finding is explicit about why:
// any client that could set a presentation flag from content alone
// could impersonate Attune.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/domain/entities/message.dart';
import '../../data/models/assist_draft_model.dart';
import '../../data/models/place_source_model.dart';
import '../providers/ai_assistant_providers.dart';

/// Decodes `message.assistantPayload`'s raw JSON into the two things
/// this bubble needs to render — `sources` (Nearby) and a suggested
/// Planning proposal (Ideas). Kept file-local: the shared [Message]
/// entity deliberately keeps this payload as a raw map (see its own
/// doc comment), and this is the one feature that actually decodes it.
class _AttuneAssistPayload {
  final List<PlaceSourceModel> sources;
  final SuggestedPlanningItem? suggestedPlanningItem;

  const _AttuneAssistPayload({
    required this.sources,
    required this.suggestedPlanningItem,
  });

  /// Never throws on a malformed/absent payload — a rendering bug in
  /// one bubble must not crash the whole chat screen. Missing/invalid
  /// fields simply render as "no sources, no proposal" rather than
  /// propagating a parse exception up through the widget tree.
  factory _AttuneAssistPayload.fromRaw(Map<String, dynamic>? raw) {
    if (raw == null) {
      return const _AttuneAssistPayload(
        sources: [],
        suggestedPlanningItem: null,
      );
    }
    List<PlaceSourceModel> sources = const [];
    try {
      final rawSources = raw['sources'];
      if (rawSources is List) {
        sources = rawSources
            .map(
              (s) => PlaceSourceModel.fromJson(
                Map<String, dynamic>.from(s as Map),
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      sources = const [];
    }
    SuggestedPlanningItem? suggestedItem;
    try {
      final rawItem = raw['suggested_planning_item'];
      if (rawItem is Map) {
        suggestedItem = SuggestedPlanningItem.fromJson(
          Map<String, dynamic>.from(rawItem),
        );
      }
    } catch (_) {
      suggestedItem = null;
    }
    return _AttuneAssistPayload(
      sources: sources,
      suggestedPlanningItem: suggestedItem,
    );
  }
}

class AttuneAssistBubble extends ConsumerWidget {
  const AttuneAssistBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final payload = _AttuneAssistPayload.fromRaw(message.assistantPayload);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Attune suggestion',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          if (payload.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...payload.sources.map((source) => _SourceTile(source: source)),
            const SizedBox(height: 4),
            Text(
              'Places by Mapbox',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ],
          if (payload.suggestedPlanningItem != null) ...[
            const SizedBox(height: 12),
            _AddToPlanningAffordance(
              message: message,
              suggestedItem: payload.suggestedPlanningItem!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final PlaceSourceModel source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.place_outlined,
            size: 16,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (source.formattedAddress != null)
                  Text(
                    source.formattedAddress!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add to Planning" / "Added to Planning" — driven entirely by
/// [planningLinkProvider], never by client-side local state alone, so
/// two partners' devices converge on the same "added" state once
/// either one confirms it (spec §5.4: at most one Planning entity per
/// message, regardless of which partner's tap wins a race).
class _AddToPlanningAffordance extends ConsumerWidget {
  const _AddToPlanningAffordance({
    required this.message,
    required this.suggestedItem,
  });

  final Message message;
  final SuggestedPlanningItem suggestedItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkAsync = ref.watch(planningLinkProvider(message.id));

    return linkAsync.when(
      loading: () => const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      // Fail closed: a link-check failure must never claim the message
      // is already added when it might not be — showing "Add to
      // Planning" is always safe, since the RPC's own idempotency
      // re-check (spec §5.4) tolerates a redundant confirm.
      error: (_, _) => _AddButton(message: message, suggestedItem: suggestedItem),
      data: (link) {
        if (link != null) {
          return Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Added to Planning',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          );
        }
        return _AddButton(message: message, suggestedItem: suggestedItem);
      },
    );
  }
}

class _AddButton extends ConsumerStatefulWidget {
  const _AddButton({required this.message, required this.suggestedItem});

  final Message message;
  final SuggestedPlanningItem suggestedItem;

  @override
  ConsumerState<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends ConsumerState<_AddButton> {
  bool _confirming = false;

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      final repository = ref.read(aiAssistantRepositoryProvider);
      await repository.addToPlanning(widget.message.id);
      // The RPC is idempotent (spec §5.4) — a concurrent second tap
      // from the partner's device simply gets the same already-created
      // entity back. Invalidating here makes THIS device's bubble
      // reflect "Added" immediately rather than waiting for its next
      // natural rebuild.
      ref.invalidate(planningLinkProvider(widget.message.id));
    } catch (_) {
      // A failed confirm leaves the affordance as "Add to Planning" —
      // the user can simply tap again; addToPlanning's own idempotency
      // means a retry is always safe.
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: _confirming ? null : _confirm,
        icon: _confirming
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add, size: 16),
        label: Text(
          widget.suggestedItem.kind == SuggestedPlanningItemKind.event
              ? 'Add event to Planning'
              : 'Add task to Planning',
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

