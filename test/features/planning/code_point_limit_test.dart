import 'package:attune/features/planning/domain/code_point_limit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _apply(int max, String oldText, String newText) => CodePointLengthFormatter(max).formatEditUpdate(
    TextEditingValue(text: oldText), TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)));

void main() {
  // The server counts code points (Postgres char_length); Flutter's maxLength
  // counts grapheme clusters. A flag is 1 grapheme but 2 code points.
  test('counts code points like the server, not graphemes', () {
    expect(codePointLength('🇬🇭'), 2);
    expect(codePointLength('é'), 2); // e + combining acute
    expect(codePointLength('é'), 1); // precomposed
  });

  test('21 flags (42 code points) are cut to 20 whole flags for a 40 limit', () {
    final out = _apply(40, '', '🇬🇭' * 21);
    expect(out.text, '🇬🇭' * 20);
    expect(codePointLength(out.text), 40);
    expect(out.selection.baseOffset, out.text.length);
  });

  test('never splits a grapheme: a combining mark is not orphaned', () {
    final out = _apply(3, '', 'aéb'); // a, e+acute (2 cp), b = 4 cp
    expect(out.text, 'aé');
  });

  test('edits within the limit pass through untouched', () {
    final next = TextEditingValue(text: 'Bali', selection: const TextSelection.collapsed(offset: 2));
    expect(CodePointLengthFormatter(40).formatEditUpdate(TextEditingValue.empty, next), next);
  });
}
