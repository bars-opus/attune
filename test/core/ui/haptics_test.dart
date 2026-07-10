// test/core/ui/haptics_test.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeHaptics counts calls for assertions', () {
    final h = FakeHaptics();
    h.light();
    h.light();
    h.selection();
    expect(h.lightCount, 2);
    expect(h.selectionCount, 1);
  });
}
