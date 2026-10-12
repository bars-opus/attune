import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Length as the SERVER counts it: Postgres `char_length` counts Unicode
/// code points. Flutter's `maxLength` counts grapheme clusters instead, so
/// a flag (1 grapheme, 2 code points) would pass the field and be rejected
/// by the RPC (final review I3).
int codePointLength(String s) => s.runes.length;

/// Caps input at [max] code points, cutting only between whole graphemes so
/// a pasted flag or accented letter is never split in half.
class CodePointLengthFormatter extends TextInputFormatter {
  CodePointLengthFormatter(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (codePointLength(newValue.text) <= max) return newValue;
    final text = truncateCodePoints(newValue.text, max);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// [s] cut to at most [max] code points, only between whole graphemes.
String truncateCodePoints(String s, int max) {
  if (codePointLength(s) <= max) return s;
  final kept = StringBuffer();
  var used = 0;
  for (final g in s.characters) {
    final n = codePointLength(g);
    if (used + n > max) break;
    kept.write(g);
    used += n;
  }
  return kept.toString();
}
