import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deleting a moment goes through the soft_delete_timeline_event RPC
/// (plan ruling R4): a raw UPDATE of deleted_at only works while PostgREST
/// does not read the row back, since the read policy hides deleted rows.
void main() {
  test('deleteEvent calls the soft-delete RPC, not a table update', () {
    final source =
        File(
          'lib/features/timeline/data/repositories/timeline_repository.dart',
        ).readAsStringSync();
    final start = source.indexOf('Future<void> deleteEvent(');
    expect(start, isNot(-1));
    final body = source.substring(start, source.indexOf('\n  }\n', start));

    expect(body, contains("'soft_delete_timeline_event'"));
    expect(body, contains("'p_event_id': eventId"));
    expect(body, isNot(contains('.update(')));
  });
}
