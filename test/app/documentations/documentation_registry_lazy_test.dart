// A help button can open a topic before any screen has set the registry up
// (signed in, straight to Planning): looking a topic up loads it.
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('looking up a topic works without initialize() first', () {
    expect(DocumentationRegistry.getById('planning'), isNotNull);
  });
}
