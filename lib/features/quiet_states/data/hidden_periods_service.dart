import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec 7 (research 06 B9 (d)): a span of dates that never resurfaces for
/// this person (On this day, memory prompts). Their moments stay in their
/// own list; nobody else is affected.
class HiddenPeriod {
  const HiddenPeriod({
    required this.id,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final DateTime startsOn;
  final DateTime endsOn;

  static HiddenPeriod fromRow(Map<String, dynamic> row) => HiddenPeriod(
    id: row['id'] as String,
    startsOn: DateTime.parse(row['starts_on'] as String),
    endsOn: DateTime.parse(row['ends_on'] as String),
  );
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HiddenPeriodsService {
  Future<List<HiddenPeriod>> mine() async {
    final rows =
        await Supabase.instance.client.rpc('list_my_hidden_periods')
            as List<dynamic>?;
    return [
      for (final r in rows ?? const [])
        HiddenPeriod.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> add(DateTime start, DateTime end) =>
      Supabase.instance.client.rpc(
        'add_hidden_period',
        params: {'p_starts_on': _day(start), 'p_ends_on': _day(end)},
      );

  Future<void> remove(String id) => Supabase.instance.client.rpc(
    'remove_hidden_period',
    params: {'p_id': id},
  );
}

final hiddenPeriodsServiceProvider = Provider<HiddenPeriodsService>(
  (_) => HiddenPeriodsService(),
);
