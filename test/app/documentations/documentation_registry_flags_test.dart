// The manual only lists a topic while the features it explains are switched
// on, and the registry is built once.
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
        }),
      );
    }
  });
}
