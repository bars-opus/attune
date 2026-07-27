// lib/features/opinions/data/models/muted_author_model.dart

/// One row of the caller's own mute list (ATTUNE_MASTER_SPEC.md §8.11
/// "Muting and hiding").
///
/// Carries the opaque `author_handle` and nothing else identifying: the mute
/// list is keyed on the handle rather than a user_id precisely so that even a
/// full dump of it reveals "this viewer muted these handles" and never who
/// those handles belong to (FORUM.md §3). There is deliberately no display
/// name or avatar to resolve it against — the management screen shows the
/// handle as-is.
///
/// A named class rather than a bare record because it crosses the
/// repository → provider → screen boundary and gets a `fromRow` factory like
/// every other model in this feature; an inline `({String, DateTime})` would
/// be the only untyped shape in the layer.
class MutedAuthor {
  /// Opaque per-author handle, the same value [OpinionModel.authorHandle]
  /// carries and the key the mute is stored under.
  final String authorHandle;

  /// When the caller muted this handle. Server default `now()`, so never null.
  final DateTime mutedAt;

  const MutedAuthor({required this.authorHandle, required this.mutedAt});

  /// Parses one row of `get_muted_authors()`, whose columns are
  /// `author_handle` and `muted_at`.
  factory MutedAuthor.fromRow(Map<String, dynamic> row) {
    return MutedAuthor(
      authorHandle: row['author_handle'] as String? ?? '',
      mutedAt: DateTime.parse(row['muted_at'] as String),
    );
  }
}
