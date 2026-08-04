import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';

void main() {
  group('DocumentationRegistry.getRelatedModuleIds', () {
    test('returns the 3 games for "games"', () {
      expect(
        DocumentationRegistry.getRelatedModuleIds('games'),
        ['truthOrDare', 'thisOrThat', 'thirtySixQuestions'],
      );
    });

    test('returns empty for a module with no relations', () {
      expect(DocumentationRegistry.getRelatedModuleIds('healing'), isEmpty);
      expect(DocumentationRegistry.getRelatedModuleIds('chat'), isEmpty);
      expect(DocumentationRegistry.getRelatedModuleIds('truthOrDare'), isEmpty);
    });

    test('returns empty for an unknown id, not a throw', () {
      expect(
        () => DocumentationRegistry.getRelatedModuleIds('not_a_real_id'),
        returnsNormally,
      );
      expect(DocumentationRegistry.getRelatedModuleIds('not_a_real_id'), isEmpty);
    });
  });
}
