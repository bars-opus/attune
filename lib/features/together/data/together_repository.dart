import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_feed.dart';
import '../domain/couple_event_draft.dart';
import '../domain/together_item.dart';
import '../domain/together_need.dart';
import '../domain/together_overlay.dart';
import '../domain/together_prefs.dart';
import '../domain/together_ritual.dart';
import '../domain/together_story.dart';

/// The RPC seam, so tests run the real repository without Supabase
/// (the same pattern as PlanningRpcGateway).
abstract class TogetherRpcGateway {
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params});
}

class SupabaseTogetherRpcGateway implements TogetherRpcGateway {
  const SupabaseTogetherRpcGateway(this._supabase);
  final SupabaseClient _supabase;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      _supabase.rpc(function, params: params);
}

/// A server refusal: `not_found`, `invalid_input`, `owner_handoff`,
/// `forbidden`, `range`, `unauthenticated`.
class TogetherException implements Exception {
  const TogetherException(this.code);
  final String code;

  @override
  String toString() => 'TogetherException($code)';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class TogetherRepository {
  const TogetherRepository(this._gateway);
  final TogetherRpcGateway _gateway;

  Future<dynamic> _call(String fn, Map<String, dynamic> params) async {
    try {
      return await _gateway.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      final m = RegExp(r'together:([a-z_]+)').firstMatch(e.message);
      if (m != null) throw TogetherException(m.group(1)!);
      rethrow;
    }
  }

  Future<List<TogetherItem>> listItems(
    String relationshipId, {
    required DateTime start,
    required DateTime end,
  }) async {
    final rows =
        await _call('list_together_items', {
              'p_relationship_id': relationshipId,
              'p_start': _ymd(start),
              'p_end': _ymd(end),
            })
            as List;
    return [
      for (final r in rows)
        TogetherItem.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<String> createEvent(
    String relationshipId,
    CoupleEventDraft draft,
  ) async =>
      await _call('create_couple_event', {
            'p_relationship_id': relationshipId,
            'p_event': draft.toPayload(),
          })
          as String;

  Future<void> updateEvent(String eventId, CoupleEventDraft draft) => _call(
    'update_couple_event',
    {'p_event_id': eventId, 'p_event': draft.toPayload()},
  );

  Future<void> deleteEvent(String eventId) =>
      _call('delete_couple_event', {'p_event_id': eventId});

  Future<void> leaveEvent(String eventId) =>
      _call('leave_couple_event', {'p_event_id': eventId});

  Future<String> proposeEvent(
    String relationshipId,
    CoupleEventDraft draft,
    List<ProposalTime> times,
  ) async =>
      await _call('propose_couple_event', {
            'p_relationship_id': relationshipId,
            'p_event': draft.toPayload(),
            'p_options': [
              for (final t in times) t.toJson(allDay: draft.allDay),
            ],
          })
          as String;

  Future<void> decideProposal(
    String eventId, {
    String? optionId,
    required bool accept,
    String? note,
  }) => _call('decide_couple_event', {
    'p_event_id': eventId,
    'p_option_id': optionId,
    'p_accept': accept,
    'p_note': note,
  });

  Future<void> proposeHandoff(String eventId) =>
      _call('propose_owner_handoff', {'p_event_id': eventId});

  Future<void> decideHandoff(String eventId, {required bool accept}) => _call(
    'decide_owner_handoff',
    {'p_event_id': eventId, 'p_accept': accept},
  );

  Future<List<TogetherNeed>> listNeeds(String relationshipId) async {
    final rows =
        await _call('list_together_needs_you', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [
      for (final r in rows)
        TogetherNeed.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<TogetherPrefs> getPrefs(String relationshipId) async =>
      TogetherPrefs.fromJson(
        Map<String, dynamic>.from(
          await _call('get_together_prefs', {
                'p_relationship_id': relationshipId,
              })
              as Map,
        ),
      );

  Future<TogetherPrefs> setPrefs(
    String relationshipId,
    TogetherPrefs prefs,
  ) async => TogetherPrefs.fromJson(
    Map<String, dynamic>.from(
      await _call('set_together_prefs', {
            'p_relationship_id': relationshipId,
            'p_daily_summary': prefs.dailySummary,
            'p_care_nudges': prefs.careNudges,
          })
          as Map,
    ),
  );

  /// Tells the server my device's zone, so the morning summary arrives at
  /// my 8am (the same row Planning writes when it opens).
  Future<void> reportTimezone(String relationshipId, String timezone) => _call(
    'set_planning_timezone',
    {'p_relationship_id': relationshipId, 'p_timezone': timezone},
  );

  Future<List<TogetherRitual>> listRituals(String relationshipId) async {
    final rows =
        await _call('list_together_rituals', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [
      for (final r in rows)
        TogetherRitual.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<String> proposeRitual(
    String relationshipId,
    RitualDraft draft,
  ) async =>
      await _call('propose_ritual', {
            'p_relationship_id': relationshipId,
            'p_ritual': draft.toPayload(),
          })
          as String;

  Future<void> decideRitual(String ritualId, {required bool accept}) =>
      _call('decide_ritual', {'p_ritual_id': ritualId, 'p_accept': accept});

  Future<void> updateRitual(String ritualId, RitualDraft draft) => _call(
    'update_ritual',
    {'p_ritual_id': ritualId, 'p_ritual': draft.toPayload()},
  );

  Future<void> setRitualStatus(String ritualId, String status) =>
      _call('set_ritual_status', {'p_ritual_id': ritualId, 'p_status': status});

  Future<void> skipRitualOccurrence(String eventId) =>
      _call('skip_ritual_occurrence', {'p_event_id': eventId});

  // ── Story (Phase 4) ──

  Future<List<MemoryPrompt>> listMemoryPrompts(
    String relationshipId, {
    required String tz,
  }) async {
    final rows =
        await _call('list_together_memory_prompts', {
              'p_relationship_id': relationshipId,
              'p_tz': tz,
            })
            as List;
    return [
      for (final r in rows) MemoryPrompt.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<String> addEventMemory(String eventId, String line) async =>
      await _call('add_event_memory', {'p_event_id': eventId, 'p_line': line})
          as String;

  Future<void> dismissMemoryPrompt(String eventId) =>
      _call('dismiss_memory_prompt', {'p_event_id': eventId});

  Future<List<OnThisDayItem>> listOnThisDay(
    String relationshipId,
    DateTime today,
  ) async {
    final rows =
        await _call('list_together_on_this_day', {
              'p_relationship_id': relationshipId,
              'p_today': _ymd(today),
            })
            as List;
    return [
      for (final r in rows) OnThisDayItem.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<List<RitualMemory>> listRitualMemories(String ritualId) async {
    final rows =
        await _call('list_together_ritual_memories', {'p_ritual_id': ritualId})
            as List;
    return [
      for (final r in rows) RitualMemory.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// One page of the memories archive, newest first (plan R8).
  Future<List<TimelineEventModel>> listMoments(
    String relationshipId, {
    DateTime? beforeDate,
    String? beforeId,
    int limit = 30,
  }) async {
    final rows =
        await _call('list_together_moments', {
              'p_relationship_id': relationshipId,
              'p_before_date': beforeDate == null ? null : _ymd(beforeDate),
              'p_before_id': beforeId,
              'p_limit': limit,
            })
            as List;
    return [
      for (final r in rows)
        TimelineEventModel.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  // ── Calendar feed (Phase 5) ──

  /// A new private link; any older one stops working. Shown once.
  Future<String> createCalendarFeed() async =>
      await _call('create_calendar_feed_token', const {}) as String;

  Future<void> revokeCalendarFeed() => _call('revoke_calendar_feed', const {});

  Future<CalendarFeedStatus> getCalendarFeedStatus() async {
    final rows = await _call('get_calendar_feed_status', const {}) as List;
    return rows.isEmpty
        ? const CalendarFeedStatus(active: false)
        : CalendarFeedStatus.fromRow(Map<String, dynamic>.from(rows.first));
  }

  // ── Busy overlay (Phase 6) ──

  Future<OverlayLevel> getOverlay(String relationshipId) async {
    final j = await _call('get_together_overlay', {
      'p_relationship_id': relationshipId,
    });
    return OverlayLevel.fromWire(
      (Map<String, dynamic>.from(j as Map))['level'] as String?,
    );
  }

  /// Off deletes my busy times on the server in the same call.
  Future<void> setOverlay(String relationshipId, OverlayLevel level) => _call(
    'set_together_overlay',
    {'p_relationship_id': relationshipId, 'p_level': level.wire},
  );

  Future<int> replaceBusyBlocks(
    String relationshipId,
    List<({DateTime start, DateTime end})> blocks,
  ) async =>
      (await _call('replace_my_busy_blocks', {
                'p_relationship_id': relationshipId,
                'p_blocks': [
                  for (final b in blocks)
                    {
                      'starts_at': b.start.toUtc().toIso8601String(),
                      'ends_at': b.end.toUtc().toIso8601String(),
                    },
                ],
              })
              as num)
          .toInt();

  Future<List<FreeWindow>> listFreeWindows(String relationshipId) async {
    final rows =
        await _call('list_together_free_windows', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [
      for (final r in rows) FreeWindow.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<List<BusyStrip>> listBusyStrips(String relationshipId) async {
    final rows =
        await _call('list_together_busy_strips', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [
      for (final r in rows) BusyStrip.fromRow(Map<String, dynamic>.from(r)),
    ];
  }
}
