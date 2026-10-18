// Spec 3a (research 06 §3 F1; 05 D.1): the lifecycle model and the service
// calls behind pause, resume, end and seal.
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _row({
  String status = 'ended',
  String? partner = 'Ama',
  String? endedAt = '2026-10-01T10:00:00Z',
  String? windowEndsAt = '2026-10-31T10:00:00Z',
  String? pausedAt,
  String? decideBy,
}) => {
  'relationship_id': 'r1',
  'status': status,
  'partner_first_name': partner,
  'ended_by_me': false,
  'ended_by_partner': true,
  'paused_by_me': false,
  'ended_at': endedAt,
  'window_ends_at': windowEndsAt,
  'paused_at': pausedAt,
  'decide_by': decideBy,
  'sealed_by_me': false,
  'chat_readable': true,
};

void main() {
  group('RelationshipLifecycle', () {
    test('fromRow parses every field', () {
      final l = RelationshipLifecycle.fromRow(_row());
      expect(l.relationshipId, 'r1');
      expect(l.status, LifecycleStatus.ended);
      expect(l.partnerFirstName, 'Ama');
      expect(l.endedByMe, isFalse);
      expect(l.endedByPartner, isTrue);
      expect(l.pausedByMe, isFalse);
      expect(l.endedAt, DateTime.utc(2026, 10, 1, 10));
      expect(l.windowEndsAt, DateTime.utc(2026, 10, 31, 10));
      expect(l.pausedAt, isNull);
      expect(l.decideBy, isNull);
      expect(l.sealedByMe, isFalse);
      expect(l.chatReadable, isTrue);
    });

    test('a missing partner name and missing dates stay null', () {
      final l = RelationshipLifecycle.fromRow(
        _row(
          status: 'archived',
          partner: null,
          endedAt: null,
          windowEndsAt: null,
        ),
      );
      expect(l.status, LifecycleStatus.archived);
      expect(l.partnerFirstName, isNull);
      expect(l.endedAt, isNull);
    });

    test('an unknown status is not a lifecycle', () {
      expect(
        () => RelationshipLifecycle.fromRow(_row(status: 'active')),
        throwsFormatException,
      );
    });

    test('days left count whole days, never below zero', () {
      final now = DateTime.utc(2026, 10, 1, 10);
      expect(daysLeft(now.add(const Duration(days: 30)), now), 30);
      expect(daysLeft(now.add(const Duration(hours: 23)), now), 0);
      expect(daysLeft(now.subtract(const Duration(days: 2)), now), 0);
      expect(daysLeft(null, now), 0);
    });
  });

  group('RelationshipLifecycleService', () {
    late List<(String, Map<String, dynamic>?)> calls;
    Object? fail;
    List<Map<String, dynamic>> rows = [];

    RelationshipLifecycleService service() => RelationshipLifecycleService(
      rpc: (fn, [params]) async {
        calls.add((fn, params));
        if (fail != null) throw fail!;
        return fn == 'get_my_relationship_lifecycle' ? rows : null;
      },
    );

    setUp(() {
      calls = [];
      fail = null;
      rows = [];
    });

    test('each action calls its RPC with the relationship id', () async {
      final s = service();
      await s.pause('r1');
      await s.resume('r1');
      await s.seal('r1');
      await s.endRelationship(relationshipId: 'r1');
      expect(calls.map((c) => c.$1), [
        'pause_relationship',
        'resume_relationship',
        'seal_my_side',
        'end_relationship',
      ]);
      for (final c in calls) {
        expect(c.$2, {'p_relationship_id': 'r1'});
      }
    });

    test('fetchLifecycle: no row is no lifecycle', () async {
      expect(await service().fetchLifecycle(), isNull);
      rows = [_row()];
      expect((await service().fetchLifecycle())!.relationshipId, 'r1');
    });

    test('a space that already changed says so', () async {
      fail = const PostgrestException(message: 'lifecycle:not_active');
      expect(
        () => service().pause('r1'),
        throwsA(
          isA<RelationshipLifecycleException>().having(
            (e) => e.message,
            'message',
            'This shared space has already changed. Reopen Chat to see the latest.',
          ),
        ),
      );
    });

    test('any other failure is a plain retry', () async {
      fail = Exception('offline');
      expect(
        () => service().seal('r1'),
        throwsA(
          isA<RelationshipLifecycleException>().having(
            (e) => e.message,
            'message',
            "Couldn't do that. Please try again.",
          ),
        ),
      );
    });
  });
}
