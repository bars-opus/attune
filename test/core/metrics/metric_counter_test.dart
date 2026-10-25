// Spec 1 W1c (§4.3 W1b, review S-2): the app can pass only the exact client
// keys the server seeded, with the same pre-auth flag, and a bump never
// waits or throws.
import 'dart:io';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the client keys are exactly the metric_client_keys seed', () {
    final migration = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('_metric_counters.sql'));
    final sql = migration.readAsStringSync();
    final start = sql.indexOf('INSERT INTO public.metric_client_keys');
    final seed = sql.substring(start, sql.indexOf('ON CONFLICT', start));
    final rows = RegExp(
      r"\('([a-z0-9_:>.-]+)', (true|false), 'spec1'\)",
    ).allMatches(seed);
    final seeded = {for (final m in rows) m.group(1)!: m.group(2) == 'true'};

    expect(seeded, hasLength(26));
    expect({for (final k in ClientMetricKey.values) k.key: k.anonOk}, seeded);
  });

  test('bump sends the exact key, without waiting', () async {
    final sent = <String>[];
    MetricCounter(
      (key) async => sent.add(key),
    ).bump(ClientMetricKey.inviteSharedWhatsapp);
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['invite_shared:whatsapp']);
  });

  test('a failing or throwing sender never surfaces an error', () async {
    MetricCounter(
      (key) async => throw Exception('offline'),
    ).bump(ClientMetricKey.signupStarted);
    MetricCounter(
      (key) => throw StateError('no client'),
    ).bump(ClientMetricKey.signupStarted);
    await Future<void>.delayed(Duration.zero);
  });
}
