/// A1's name rule (Spec 1 §3.3): W1's invisible and direction characters
/// dropped and whitespace collapsed (as the server's
/// private.normalize_display_name does), then 1–40 characters with at least
/// one letter in any script. Today's ASCII-only rule is not used.
enum DisplayNameError { needsLetter, tooLong }

/// The characters a display name never keeps, the same set as the server's
/// private.strip_name_controls and OnboardingSubmissionService's clamp:
/// U+200B, U+200E, U+200F, U+202A–U+202E, U+2060–U+2064, U+2066–U+2069
/// (bidi isolates) and U+FEFF. ZWNJ (U+200C) and ZWJ (U+200D) stay as typed:
/// Persian and Indic names and emoji sequences need them.
final _invisible = RegExp(
  '[\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
);

/// What is set aside when asking whether anything visible is left (the
/// server's private.name_is_blank): spaces, ZWNJ and ZWJ.
final _blank = RegExp('[\\s\u200C\u200D]');
final _letter = RegExp(r'\p{L}', unicode: true);

/// The name as the server stores it: '' when nothing visible is left.
String normalizeDisplayName(String raw) {
  final name =
      raw.replaceAll(_invisible, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.replaceAll(_blank, '').isEmpty ? '' : name;
}

DisplayNameError? validateDisplayName(String raw) {
  final name = normalizeDisplayName(raw);
  if (!_letter.hasMatch(name)) return DisplayNameError.needsLetter;
  if (name.runes.length > 40) return DisplayNameError.tooLong;
  return null;
}
