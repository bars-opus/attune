// Spec 1 W3c: get_my_journal_reminder / set_my_journal_reminder, in memory.
class FakeReminderRpc {
  Map<String, dynamic> stored = {
    'enabled': false,
    'iso_weekday': null,
    'local_time': null,
  };
  Object? failWith;

  /// How many of the next reads fail (offline at launch, B7 review I-1).
  int failReads = 0;
  final calls = <(String, Map<String, dynamic>?)>[];

  Future<Object?> call(String fn, Map<String, dynamic>? params) async {
    calls.add((fn, params));
    if (fn == 'get_my_journal_reminder') {
      if (failReads > 0) {
        failReads--;
        throw Exception('offline');
      }
      return stored;
    }
    if (failWith != null) throw failWith!;
    stored = {
      'enabled': params!['p_enabled'],
      'iso_weekday': params['p_iso_weekday'] ?? stored['iso_weekday'],
      'local_time': params['p_local_time'] ?? stored['local_time'],
    };
    return null;
  }
}
