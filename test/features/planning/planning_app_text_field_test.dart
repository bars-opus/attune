import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Planning's form fields use the app's AppTextFormField. The only raw
/// TextFields are the two that are part of the note itself: the title and a
/// checklist's "Add item" line, which read as text on the page.
void main() {
  test('no raw TextField in Planning outside the two in-page fields', () {
    final allowed = {
      'lib/features/planning/presentation/screens/planning_entry_screen.dart': 1,
      'lib/features/planning/presentation/widgets/checklist_block_view.dart': 1,
    };
    final found = <String, int>{};
    for (final f in Directory('lib/features/planning').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final n = RegExp(r'(?<![A-Za-z])TextF(?:ield|ormField)\(').allMatches(f.readAsStringSync()).length;
      if (n > 0) found[f.path] = n;
    }
    expect(found, allowed);
  });
}
