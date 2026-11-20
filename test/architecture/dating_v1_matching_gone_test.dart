// Spec 2 W5 (§4.10 R12; carry 8): the v1 matching objects are gone from the
// app too. No Dart file under lib/ names a dropped server object or reads a
// v1 payload field, so nothing can call what W5a and W5b dropped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/ names a v1 matching object', () {
    final banned = RegExp(
      r'display_band|explanation_features|dating_feature_snapshots|'
      r'get_my_dating_matches|run_dating_candidate_generation|'
      r'generate_dating_candidates_for_user|dating_alignment|'
      r"'get_my_dating_introductions', \{'p_limit'|class DatingIntroduction\b",
    );
    final hits = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/generated/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });
}
