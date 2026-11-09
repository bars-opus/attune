// Spec 2 W3c Task 10 fix round 1 (I-2, M-5): the server's own text rules,
// checked on the device first so a refused answer is said where it can be
// fixed. They mirror the live bodies: `private.dating_has_invisible`
// (U+200B-U+200F, U+202A-U+202E, U+2060-U+2069, U+FEFF: this refuses every
// emoji joined with U+200D), `private.dating_trim` then `char_length` (code
// points, so runes here), and `save_dating_prompts`' "at least one letter
// or digit" (`[[:alnum:]]` under pg_c_utf8). The server stays the judge:
// anything it still refuses is said generically.
import 'package:flutter/services.dart';

final _invisible = RegExp(r'[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]');
// pg_c_utf8's [[:alnum:]]: Unicode Alphabetic, and ASCII 0-9 only (fix 2).
final _word = RegExp(r'[\p{Alphabetic}0-9]', unicode: true);

/// The text has a character the server refuses (checked on the text as
/// typed, so one the trim would take is caught too).
bool datingHasInvisible(String text) => _invisible.hasMatch(text);

/// The text has a letter or a digit.
bool datingHasWord(String text) => _word.hasMatch(text);

/// The length the server counts: code points after the trim.
int datingTextLength(String text) => text.trim().runes.length;

/// Limits a field to [max] code points, as the server counts (a field's
/// `maxLength` counts what is drawn, so an accented or joined character
/// would let more through).
class DatingRuneLimit extends TextInputFormatter {
  const DatingRuneLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final runes = newValue.text.runes;
    if (runes.length <= max) return newValue;
    final text = String.fromCharCodes(runes.take(max));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
