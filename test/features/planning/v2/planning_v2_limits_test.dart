import 'dart:convert';
import 'dart:io';

import 'package:attune/features/planning/v2/domain/planning_v2_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart limits mirror planning_limits() exactly (spec §3.11)', () {
    final sql = File('supabase/migrations/20261012200100_planning_v2_helpers.sql').readAsStringSync();
    final match = RegExp(r"SELECT '(\{[^']*\})'::jsonb").firstMatch(sql);
    expect(match, isNotNull, reason: 'planning_limits() literal not found');
    final server = (jsonDecode(match!.group(1)!) as Map<String, dynamic>).cast<String, int>();
    expect(PlanningV2Limits.all, server);
  });
}
