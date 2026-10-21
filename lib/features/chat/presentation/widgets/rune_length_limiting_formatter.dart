import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'package:attune/features/chat/domain/entities/message.dart';

/// Shown when a paste/typed insert was trimmed to fit the message limit.
String overLimitPasteNotice() =>
    'That was too long to paste in full — we kept what fits in the '
    '${_limitLabel()}-character limit.';

/// Shown when a draft over the limit is refused at send/save time.
String tooLongMessageNotice() =>
    'That message is too long — the limit is ${_limitLabel()} characters. '
    'Trim it a little and try again.';

String _limitLabel() {
  final digits = Message.maxContentRunes.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Caps a field at [maxRunes] Unicode code points — the unit the server's
/// `char_length(content) <= 10000` CHECK counts. Flutter's
/// LengthLimitingTextInputFormatter counts grapheme clusters, which can
/// exceed the code-point budget (a flag emoji is 1 grapheme, 2 code points),
/// so a draft it accepted could still be refused server-side.
///
/// The existing draft is kept whole: only the text just inserted (the diff
/// between the old and new value) is trimmed, and the caret lands at the end
/// of what was kept. While an IME composition is active the value passes
/// through untouched; once it commits, the old value may be over the limit
/// only because of it, so the insert is measured against the last value
/// that was within the limit — the composed text is trimmed, never the
/// draft after it. Only with no such value (a draft set over the limit
/// programmatically) are the first [maxRunes] code points kept instead; the
/// send-time guard is the backstop.
///
/// [onTruncated] fires once per at-limit episode and re-arms when the text
/// drops below the limit. Keep one instance per field so that state lives.
class RuneLengthLimitingTextInputFormatter extends TextInputFormatter {
  RuneLengthLimitingTextInputFormatter(this.maxRunes, {this.onTruncated})
    : assert(maxRunes > 0);

  final int maxRunes;
  final VoidCallback? onTruncated;
  bool _notified = false;

  /// The last value this formatter let through within the limit.
  List<int>? _lastWithin;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newRunes = newValue.text.runes.toList();
    if (newRunes.length < maxRunes) _notified = false;
    if (newRunes.length <= maxRunes) {
      _lastWithin = newRunes;
      return newValue;
    }

    final composing = newValue.composing;
    if (composing.isValid && !composing.isCollapsed) return newValue;

    var oldRunes = oldValue.text.runes.toList();
    if (oldRunes.length > maxRunes && _overOnlyByComposition(oldValue)) {
      // Over only because a composition passed through: diff against the
      // value before it.
      oldRunes = _lastWithin!;
    }
    late final List<int> kept;
    int caretRunes;
    if (oldRunes.length > maxRunes) {
      kept = newRunes.sublist(0, maxRunes);
      final keptLen = String.fromCharCodes(kept).length;
      final ext = newValue.selection.extentOffset;
      final units =
          newValue.selection.isValid ? math.min(ext, keptLen) : keptLen;
      caretRunes = String.fromCharCodes(kept).substring(0, units).runes.length;
    } else {
      // Suffix: the text after the insertion point. Trust a valid caret.
      var suffix = 0;
      final sel = newValue.selection;
      if (sel.isValid &&
          sel.extentOffset <= newValue.text.length &&
          sel.extentOffset >= 0) {
        final tail =
            newValue.text.substring(sel.extentOffset).runes.toList().length;
        if (tail <= oldRunes.length &&
            _endsWith(oldRunes, newRunes.sublist(newRunes.length - tail))) {
          suffix = tail;
        } else {
          suffix = _commonSuffix(oldRunes, newRunes);
        }
      } else {
        suffix = _commonSuffix(oldRunes, newRunes);
      }
      var prefix = 0;
      final maxPrefix = math.min(
        oldRunes.length - suffix,
        newRunes.length - suffix,
      );
      while (prefix < maxPrefix && oldRunes[prefix] == newRunes[prefix]) {
        prefix++;
      }
      final inserted = newRunes.sublist(prefix, newRunes.length - suffix);
      final room = math.max(maxRunes - prefix - suffix, 0);
      final keptInserted = inserted.take(room).toList();
      kept = [
        ...newRunes.sublist(0, prefix),
        ...keptInserted,
        ...newRunes.sublist(newRunes.length - suffix),
      ];
      caretRunes = prefix + keptInserted.length;
    }

    _lastWithin = kept;
    final keptText = String.fromCharCodes(kept);
    final caret = String.fromCharCodes(kept.take(caretRunes)).length;
    if (!_notified) {
      _notified = true;
      onTruncated?.call();
    }
    return TextEditingValue(
      text: keptText,
      selection: TextSelection.collapsed(offset: caret),
      composing: TextRange.empty,
    );
  }

  /// Whether [oldValue] is the last within-limit value with an IME
  /// composition inserted — its text outside the composing range is exactly
  /// that value. Anything else (a draft set over the limit in code, which no
  /// formatter sees) keeps the first-[maxRunes] fallback.
  bool _overOnlyByComposition(TextEditingValue oldValue) {
    final lastWithin = _lastWithin;
    final composing = oldValue.composing;
    if (lastWithin == null ||
        !composing.isValid ||
        composing.isCollapsed ||
        composing.end > oldValue.text.length) {
      return false;
    }
    final outside =
        oldValue.text.substring(0, composing.start) +
        oldValue.text.substring(composing.end);
    return outside == String.fromCharCodes(lastWithin);
  }

  static bool _endsWith(List<int> a, List<int> tail) {
    if (tail.length > a.length) return false;
    final off = a.length - tail.length;
    for (var i = 0; i < tail.length; i++) {
      if (a[off + i] != tail[i]) return false;
    }
    return true;
  }

  static int _commonSuffix(List<int> a, List<int> b) {
    var n = 0;
    final m = math.min(a.length, b.length);
    while (n < m && a[a.length - 1 - n] == b[b.length - 1 - n]) {
      n++;
    }
    return n;
  }
}
