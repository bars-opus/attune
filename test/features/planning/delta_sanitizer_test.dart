import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allowed formatting is kept verbatim', () {
    final ops = [
      {'insert': 'Bali', 'attributes': {'bold': true, 'background': 'yellow', 'link': 'https://x.com'}},
      {'insert': '\n', 'attributes': {'header': 2, 'align': 'center'}},
    ];
    final r = sanitizeDelta(ops);
    expect(r.changed, isFalse);
    expect(r.ops, ops);
  });

  test('pasted foreign attributes are stripped (Review Focus 4)', () {
    final r = sanitizeDelta([
      {'insert': 'Pasted', 'attributes': {'font': 'serif', 'size': 'large', 'color': '#ff0000', 'bold': true}},
      {'insert': '\n', 'attributes': {'list': 'checked'}},
    ]);
    expect(r.changed, isTrue);
    expect(r.ops, [
      {'insert': 'Pasted', 'attributes': {'bold': true}},
      {'insert': '\n'},
    ]);
  });

  test('null-valued attributes from toggling are dropped silently', () {
    final r = sanitizeDelta([
      {'insert': 'x', 'attributes': {'bold': null}},
      {'insert': '\n'},
    ]);
    expect(r.ops.first, {'insert': 'x'});
    expect(r.changed, isFalse);
  });

  test('embeds are removed; unsafe links are unlinked', () {
    final r = sanitizeDelta([
      {'insert': {'image': 'x.png'}},
      {'insert': 'click', 'attributes': {'link': 'javascript:alert(1)'}},
      {'insert': '\n'},
    ]);
    expect(r.changed, isTrue);
    expect(r.ops, [{'insert': 'click'}, {'insert': '\n'}]);
  });

  test('a missing trailing newline is added; empty input becomes one newline', () {
    expect(sanitizeDelta([{'insert': 'no newline'}]).ops.last, {'insert': '\n'});
    expect(sanitizeDelta(const []).ops, [{'insert': '\n'}]);
  });

  test('plain text mirrors the server projection', () {
    expect(deltaPlainText(const [{'insert': 'Buy '}, {'insert': 'fresh'}, {'insert': '\n\n'}]), 'Buy fresh');
  });
}
