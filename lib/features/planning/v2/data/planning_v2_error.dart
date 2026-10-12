import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Every failure the v2 repository throws. The server raises
/// `planning:<code>` with a JSON HINT (migration 20261012200100); this
/// type is the only thing the UI branches on — never message text.
sealed class PlanningV2Error implements Exception {
  const PlanningV2Error();

  /// Permanent errors must never be retried (checklist 3.10).
  bool get isPermanent => this is! PlanningV2Network;
}

/// Not signed in, or the relationship ended/archived. The UI fails
/// closed: it leaves Planning (spec §9).
class PlanningV2Unauthorized extends PlanningV2Error {
  const PlanningV2Unauthorized({required this.inactive});
  final bool inactive;
}

/// Missing or not yours — the server deliberately does not say which.
class PlanningV2NotFound extends PlanningV2Error {
  const PlanningV2NotFound();
}

/// Someone saved first. [current] is the server's row as of now.
class PlanningV2StaleVersion extends PlanningV2Error {
  const PlanningV2StaleVersion(this.current);
  final Map<String, dynamic> current;
}

class PlanningV2LimitReached extends PlanningV2Error {
  const PlanningV2LimitReached(this.limit);
  final String limit;
}

class PlanningV2InvalidInput extends PlanningV2Error {
  const PlanningV2InvalidInput(this.field);
  final String field;
}

/// Transient: offline, timeout, 5xx. Safe to retry.
class PlanningV2Network extends PlanningV2Error {
  const PlanningV2Network(this.cause);
  final Object cause;
}

PlanningV2Error mapPlanningV2Error(Object error) {
  if (error is PlanningV2Error) return error;
  if (error is PostgrestException) {
    if (error.code == '42501') return const PlanningV2Unauthorized(inactive: false);
    if (error.code == 'P0001' && error.message.startsWith('planning:')) {
      final detail = _decodeHint(error.hint);
      switch (error.message.substring('planning:'.length)) {
        case 'unauthenticated':
          return const PlanningV2Unauthorized(inactive: false);
        case 'inactive':
          return const PlanningV2Unauthorized(inactive: true);
        case 'not_found':
          return const PlanningV2NotFound();
        case 'stale_version':
          final current = detail['current'];
          return PlanningV2StaleVersion(
              current is Map ? Map<String, dynamic>.from(current) : const {});
        case 'limit_reached':
          return PlanningV2LimitReached(detail['limit'] as String? ?? 'unknown');
        case 'invalid_input':
          return PlanningV2InvalidInput(detail['field'] as String? ?? 'unknown');
      }
    }
    // SQLSTATE classes 22 (data) and 23 (integrity) can never succeed on retry.
    final code = error.code ?? '';
    if (code.startsWith('22') || code.startsWith('23')) {
      return const PlanningV2InvalidInput('unknown');
    }
  }
  return PlanningV2Network(error);
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
String planningV2ErrorMessage(PlanningV2Error error) => switch (error) {
      PlanningV2Unauthorized(inactive: true) => 'Planning is closed for this relationship.',
      PlanningV2Unauthorized() => 'Please sign in again to keep planning.',
      PlanningV2NotFound() => 'That was removed by your partner.',
      PlanningV2StaleVersion() => 'Your partner just changed this.',
      PlanningV2LimitReached(limit: 'blocks_per_entry') => 'This page is full. Remove a block to add another.',
      PlanningV2LimitReached(limit: 'items_per_block') => 'This list is full. Start a new list to add more.',
      PlanningV2LimitReached(limit: 'categories') => 'You have the most categories allowed. Hide or delete one first.',
      PlanningV2LimitReached(limit: 'text_plain_chars') => 'That text is too long. Split it into two blocks.',
      PlanningV2LimitReached(limit: 'pinned_per_category') => 'You can pin up to 20 plans here. Unpin one to pin this.',
      PlanningV2LimitReached() => 'That is over the limit. Make it shorter and try again.',
      PlanningV2InvalidInput(field: 'title') => 'Give it a title (up to 120 characters).',
      PlanningV2InvalidInput(field: 'name') => 'Give it a name (up to 40 characters).',
      PlanningV2InvalidInput(field: 'text') => 'Write something (up to 500 characters).',
      PlanningV2InvalidInput(field: 'attribute') => 'Some formatting is not supported. Remove it and save again.',
      PlanningV2InvalidInput() => 'That could not be saved. Check it and try again.',
      PlanningV2Network() => 'Could not reach Attune. Check your connection and try again.',
    };
