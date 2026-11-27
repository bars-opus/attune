// Every guide belongs to a section of the guides list (2026-11-26), so a new
// guide can't land in "Start here" by accident.
import 'package:attune/app/documentations/user_manual/data/documentation_groups.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every registered guide has a section, and no section names a missing guide', () {
    DocumentationRegistry.initialize();
    final ids = DocumentationRegistry.getAllModules().map((m) => m.id).toSet();
    expect(ids.difference(documentationGroupOf.keys.toSet()), isEmpty,
        reason: 'add the new guide to documentationGroupOf');
    expect(documentationGroupOf.keys.toSet().difference(ids), isEmpty,
        reason: 'documentationGroupOf names a guide that is not registered');
  });

  test('every section has at least one guide', () {
    for (final g in DocumentationGroup.values) {
      expect(documentationGroupOf.values, contains(g), reason: g.title);
    }
  });
}
