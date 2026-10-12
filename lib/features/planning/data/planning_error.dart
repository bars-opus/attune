import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Every failure the Planning repository throws. The server raises
/// `planning:<code>` with a JSON HINT (migration 20261012200100); this
/// type is the only thing the UI branches on — never message text.
sealed class PlanningError implements Exception {
  const PlanningError();

  /// Permanent errors must never be retried (checklist 3.10).
  bool get isPermanent => this is! PlanningNetwork;
}

/// Not signed in, or the relationship ended/archived. The UI fails
/// closed: it leaves Planning (spec §9).
class PlanningUnauthorized extends PlanningError {
  const PlanningUnauthorized({required this.inactive});
  final bool inactive;
}

/// Missing or not yours — the server deliberately does not say which.
class PlanningNotFound extends PlanningError {
  const PlanningNotFound();
}

/// Someone saved first. [current] is the server's row as of now.
class PlanningStaleVersion extends PlanningError {
  const PlanningStaleVersion(this.current);
  final Map<String, dynamic> current;
}

class PlanningLimitReached extends PlanningError {
  const PlanningLimitReached(this.limit);
  final String limit;
}

class PlanningInvalidInput extends PlanningError {
  const PlanningInvalidInput(this.field);
  final String field;
}

/// Transient: offline, timeout, 5xx. Safe to retry.
class PlanningNetwork extends PlanningError {
  const PlanningNetwork(this.cause);
  final Object cause;
}

PlanningError mapPlanningError(Object error) {
  if (error is PlanningError) return error;
  if (error is PostgrestException) {
    if (error.code == '42501') return const PlanningUnauthorized(inactive: false);
    if (error.code == 'P0001' && error.message.startsWith('planning:')) {
      final detail = _decodeHint(error.hint);
      switch (error.message.substring('planning:'.length)) {
        case 'unauthenticated':
          return const PlanningUnauthorized(inactive: false);
        case 'inactive':
          return const PlanningUnauthorized(inactive: true);
        case 'not_found':
          return const PlanningNotFound();
        case 'stale_version':
          final current = detail['current'];
          return PlanningStaleVersion(
              current is Map ? Map<String, dynamic>.from(current) : const {});
        case 'limit_reached':
          return PlanningLimitReached(detail['limit'] as String? ?? 'unknown');
        case 'invalid_input':
          return PlanningInvalidInput(detail['field'] as String? ?? 'unknown');
      }
    }
    // SQLSTATE classes 22 (data) and 23 (integrity) can never succeed on retry.
    final code = error.code ?? '';
    if (code.startsWith('22') || code.startsWith('23')) {
      return const PlanningInvalidInput('unknown');
    }
  }
  return PlanningNetwork(error);
}

Map<String, dynamic> _decodeHint(String? hint) {
  if (hint == null || hint.isEmpty) return const {};
  try {
    final decoded = jsonDecode(hint);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

/// User-facing copy (checklist 5.1, 5.5): actionable, no internals.
String planningErrorMessage(PlanningError error) => switch (error) {
      PlanningUnauthorized(inactive: true) => 'Planning is closed for this relationship.',
      PlanningUnauthorized() => 'Please sign in again to keep planning.',
      PlanningNotFound() => 'That was removed by your partner.',
      PlanningStaleVersion() => 'Your partner just changed this.',
      PlanningLimitReached(limit: 'blocks_per_entry') => 'This page is full. Remove a block to add another.',
      PlanningLimitReached(limit: 'items_per_block') => 'This list is full. Start a new list to add more.',
      PlanningLimitReached(limit: 'categories') => 'You have the most categories allowed. Hide or delete one first.',
      PlanningLimitReached(limit: 'text_plain_chars') => 'That text is too long. Split it into two blocks.',
      PlanningLimitReached(limit: 'pinned_per_category') => 'You can pin up to 20 plans here. Unpin one to pin this.',
      PlanningLimitReached() => 'That is over the limit. Make it shorter and try again.',
      PlanningInvalidInput(field: 'title') => 'Give it a title (up to 120 characters).',
      PlanningInvalidInput(field: 'name') => 'Give it a name (up to 40 characters).',
      PlanningInvalidInput(field: 'text') => 'Write something (up to 500 characters).',
      PlanningInvalidInput(field: 'attribute') => 'Some formatting is not supported. Remove it and save again.',
      PlanningInvalidInput() => 'That could not be saved. Check it and try again.',
      PlanningNetwork() => 'Could not reach Attune. Check your connection and try again.',
    };
