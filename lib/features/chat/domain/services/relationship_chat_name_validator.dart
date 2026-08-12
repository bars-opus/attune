/// Pure validation for a relationship's chat name (Checklist 2.17: side
/// effects isolated, core logic testable without mocking I/O). Mirrors the
/// same 1-30 trimmed-length rule enforced server-side by the
/// set_relationship_chat_name RPC's own CHECK constraint — kept here so the
/// UI can reject an invalid name before ever making a network call, and so
/// this logic is unit-testable without a Supabase client.
///
/// Length is measured in Dart UTF-16 code units (`String.length`), which can
/// differ by a unit or two from Postgres's `char_length()` for names
/// containing surrogate-pair characters (most emoji) right at the boundary.
/// The DB constraint is the authoritative backstop either way, so this
/// client-side check only needs to be a close, not exact, match.
class RelationshipChatNameValidationResult {
  const RelationshipChatNameValidationResult._({
    required this.isValid,
    this.trimmedName,
    this.errorMessage,
  });

  const RelationshipChatNameValidationResult.valid(String trimmedName)
    : this._(isValid: true, trimmedName: trimmedName);

  const RelationshipChatNameValidationResult.invalid(String errorMessage)
    : this._(isValid: false, errorMessage: errorMessage);

  final bool isValid;
  final String? trimmedName;
  final String? errorMessage;
}

RelationshipChatNameValidationResult validateRelationshipChatName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const RelationshipChatNameValidationResult.invalid(
      'Enter a name for your chat.',
    );
  }
  if (trimmed.length > 30) {
    return const RelationshipChatNameValidationResult.invalid(
      'Keep it under 30 characters.',
    );
  }
  return RelationshipChatNameValidationResult.valid(trimmed);
}
