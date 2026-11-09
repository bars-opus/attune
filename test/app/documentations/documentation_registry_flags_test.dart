// The manual only lists a topic while the features it explains are switched
// on, and the registry is built once.
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DocumentationRegistry.initialize);

  test('initialize is idempotent', () {
    final before = DocumentationRegistry.getAllModules().length;
    DocumentationRegistry.initialize();
    DocumentationRegistry.initialize();
    expect(DocumentationRegistry.getAllModules().length, before);
  });

  test('ungated topics are always visible; gated ones need every flag', () {
    final all = DocumentationRegistry.getAllModules();
    final none = DocumentationRegistry.visibleModules(const {});
    for (final m in all) {
      final flags = DocumentationRegistry.requiredFlags(m.id);
      expect(none.contains(m), flags.isEmpty, reason: m.id);
      expect(
        DocumentationRegistry.visibleModules(flags.toSet()).contains(m),
        isTrue,
        reason: '${m.id} with $flags',
      );
    }
  });

  // Spec 1 W3c (P-27): the paths topic only while both flags are on.
  test('How you use Attune needs flow_signin_v2 and flow_paths_v2', () {
    bool listed(Set<String> on) => DocumentationRegistry.visibleModules(
      on,
    ).any((m) => m.id == 'howYouUseAttune');
    expect(
      DocumentationRegistry.getAllModules().any(
        (m) => m.id == 'howYouUseAttune',
      ),
      isTrue,
    );
    expect(listed(const {}), isFalse);
    expect(listed(const {'flow_paths_v2'}), isFalse);
    expect(listed(const {'flow_signin_v2', 'flow_paths_v2'}), isTrue);
  });

  test('every flag a topic needs is one the app reads', () {
    expect(DocumentationRegistry.allRequiredFlags, isNotEmpty);
    for (final f in DocumentationRegistry.allRequiredFlags) {
      expect(
        f,
        isIn(const {
          'conflict_toolkit',
          'private_safety_check',
          'appreciation_notes',
          'share_a_win',
          'quiet_states',
          'couple_map_enabled',
          'quiz_clinical_signoff',
          'chat_ephemeral_video',
          'chat_video_sharing',
          // Spec 1 W3c: How you use Attune.
          'flow_signin_v2',
          'flow_paths_v2',
          // Spec 1 W5: About us.
          'flow_couples_v2',
          'couple_profile',
          // Spec 1 W7a: Support resources v2.
          'support_resources_v2',
          // Spec 1 W9b: Opinions safety.
          'opinions_safety_v1',
          // Spec 2 W3c: Dating (R-35).
          'dating_mode_enabled',
        }),
      );
    }
  });

  // Spec 2 W3c (§4.10, R-35): the Dating topic needs all three flags, and
  // the manual reads dating_mode_enabled through get_dating_home.
  test('Dating is listed only with sign-in v2, paths v2 and Dating on', () {
    bool listed(Set<String> on) =>
        DocumentationRegistry.visibleModules(on).any((m) => m.id == 'datingMode');
    expect(listed(const {'flow_signin_v2', 'flow_paths_v2'}), isFalse);
    expect(listed(const {'flow_signin_v2', 'flow_paths_v2', 'dating_mode_enabled'}), isTrue);
    final source = File('lib/app/documentations/user_manual/data/documentation_flags.dart').readAsStringSync();
    // dating_mode_enabled itself is answered by get_dating_home (R-35),
    // on Dating's own client, never the global one (T12 carry E).
    expect(
      source,
      matches(RegExp(
        r'flag == DatingFeatureFlags\.datingModeEnabled\s*\?\s*'
        r'await DatingFeatureFlags\.isDatingModeAvailable\(\s*'
        r'ref\.read\(datingSupabaseClientProvider\),?\s*\)',
      )),
    );
  });
}
