import 'package:attune/features/chat/presentation/widgets/rune_length_limiting_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue apply(
    RuneLengthLimitingTextInputFormatter f,
    String text, {
    int? caret,
  }) => f.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    ),
  );

  test('text within the limit passes through untouched', () {
    final f = RuneLengthLimitingTextInputFormatter(5);
    final v = apply(f, 'abcde');
    expect(v.text, 'abcde');
    expect(v.selection.extentOffset, 5);
  });

  test('counts code points, not UTF-16 units', () {
    var truncated = 0;
    final f = RuneLengthLimitingTextInputFormatter(
      3,
      onTruncated: () => truncated++,
    );
    final v = apply(f, '😀😀😀😀');
    expect(v.text, '😀😀😀');
    expect(v.text.runes.length, 3);
    expect(truncated, 1);
  });

  test('a mid-text paste keeps the caret inside the kept text', () {
    final f = RuneLengthLimitingTextInputFormatter(4);
    // Caret reported past the cut.
    final v = apply(f, 'abcdefgh', caret: 7);
    expect(v.text, 'abcd');
    expect(v.selection.extentOffset, 4);
    expect(v.composing, TextRange.empty);
  });

  test('an emoji straddling the limit is dropped whole, never split', () {
    final f = RuneLengthLimitingTextInputFormatter(3);
    // 'ab' + emoji: the emoji is code point 3 (fits) -> kept whole.
    expect(apply(f, 'ab😀c').text, 'ab😀');
    // 'abc' + emoji: emoji is code point 4 -> dropped, no lone surrogate.
    final v = apply(f, 'abc😀');
    expect(v.text, 'abc');
    expect(v.text.codeUnits.every((u) => u < 0xD800 || u > 0xDFFF), isTrue);
  });

  test('a caret inside a long draft past the cut is clamped, no throw', () {
    final f = RuneLengthLimitingTextInputFormatter(10);
    final v = apply(f, '${'a' * 8}${'b' * 20}${'c' * 5}', caret: 28);
    expect(v.text.runes.length, 10);
    expect(v.selection.extentOffset, lessThanOrEqualTo(v.text.length));
  });

  TextEditingValue edit(
    RuneLengthLimitingTextInputFormatter f,
    TextEditingValue old,
    String text,
    int caret, {
    TextRange composing = TextRange.empty,
  }) => f.formatEditUpdate(
    old,
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
      composing: composing,
    ),
  );

  TextEditingValue val(String t, int caret) => TextEditingValue(
    text: t,
    selection: TextSelection.collapsed(offset: caret),
  );

  test('a mid-draft paste keeps the existing text whole and trims the '
      'insert; caret ends after the kept insert', () {
    final f = RuneLengthLimitingTextInputFormatter(10);
    final old6 = val('HEtail', 2);
    final v = edit(f, old6, 'HE${'p' * 20}tail', 22);
    expect(v.text, 'HEpppptail');
    expect(v.text.endsWith('tail'), isTrue);
    expect(v.text.runes.length, 10);
    expect(v.selection.extentOffset, 6);
  });

  test('replacing a selection frees its room for the insert', () {
    final f = RuneLengthLimitingTextInputFormatter(10);
    // 10-rune draft, 4 selected ("MIDD") and replaced by 9 chars.
    final v = edit(f, val('aaMIDDbbbb', 6), 'aa${'z' * 9}bbbb', 11);
    expect(v.text, 'aa${'z' * 4}bbbb');
    expect(v.selection.extentOffset, 6);
  });

  test('an emoji straddling the insert room is dropped whole', () {
    final f = RuneLengthLimitingTextInputFormatter(5);
    final v = edit(f, val('abXY', 2), 'ab😀😀XY', 6);
    // room = 5-4 = 1 -> one emoji kept, whole.
    expect(v.text, 'ab😀XY');
    expect(v.selection.extentOffset, 4);
  });

  test('typing one more at the limit leaves the text unchanged', () {
    final f = RuneLengthLimitingTextInputFormatter(4);
    final v = edit(f, val('abcd', 4), 'abcde', 5);
    expect(v.text, 'abcd');
    expect(v.selection.extentOffset, 4);
  });

  test('composing text passes through untouched', () {
    final f = RuneLengthLimitingTextInputFormatter(3);
    final v = edit(
      f,
      val('ab', 2),
      'abcdef',
      6,
      composing: const TextRange(start: 2, end: 6),
    );
    expect(v.text, 'abcdef');
    expect(v.composing, const TextRange(start: 2, end: 6));
  });

  test('a composition committed past the limit trims the composed insert, '
      'never the draft after it', () {
    final f = RuneLengthLimitingTextInputFormatter(10);
    // Within the limit, caret mid-draft.
    var cur = edit(f, val('', 0), 'aaaabbbb', 4);
    cur = cur.copyWith(selection: const TextSelection.collapsed(offset: 4));
    // An IME composes three characters at the caret: over the limit, but a
    // composition passes through untouched.
    cur = edit(
      f,
      cur,
      'aaaa中文字bbbb',
      7,
      composing: const TextRange(start: 4, end: 7),
    );
    expect(cur.text, 'aaaa中文字bbbb');
    // Committed: the old value is over the limit only because of it.
    final v = edit(f, cur, 'aaaa中文字bbbb', 7);
    expect(v.text, 'aaaa中文bbbb', reason: 'the draft tail is whole');
    expect(v.text.runes.length, 10);
    expect(v.selection.extentOffset, 6, reason: 'after the kept insert');
    expect(v.composing, TextRange.empty);
  });

  test('a committed composition at the very end trims only the insert', () {
    final f = RuneLengthLimitingTextInputFormatter(5);
    var cur = edit(f, val('', 0), 'abcd', 4);
    cur = edit(f, cur, 'abcd😀🎉', 8, composing: const TextRange(start: 4, end: 8));
    final v = edit(f, cur, 'abcd😀🎉', 8);
    expect(v.text, 'abcd😀');
  });

  test('a draft set over the limit in code keeps the first code points', () {
    // Programmatic text never passes through the formatter, so the last
    // value it saw is stale: it must not be used as the base.
    final f = RuneLengthLimitingTextInputFormatter(5);
    edit(f, val('', 0), 'ab', 2);
    final v = edit(f, val('abcdefg', 7), 'abcdefgh', 8);
    expect(v.text, 'abcde');
  });

  test('notifies once per at-limit episode and re-arms below the limit', () {
    var n = 0;
    final f = RuneLengthLimitingTextInputFormatter(3, onTruncated: () => n++);
    var cur = val('abc', 3);
    for (var i = 0; i < 5; i++) {
      cur = edit(f, cur, '${cur.text}x', cur.text.length + 1);
    }
    expect(n, 1);
    cur = edit(f, cur, 'ab', 2); // drops below the limit
    cur = edit(f, cur, 'abcx', 4);
    expect(n, 2);
  });

  test('an invalid selection lands at the end of the kept text', () {
    final f = RuneLengthLimitingTextInputFormatter(3);
    final v = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'abcdef'),
    );
    expect(v.text, 'abc');
    expect(v.selection.extentOffset, 3);
  });

  test('copy is built from the limit', () {
    expect(overLimitPasteNotice(), contains('10,000-character'));
    expect(tooLongMessageNotice(), contains('10,000 characters'));
  });
}
