import 'package:flutter/foundation.dart';

/// PII-safe, debug-only logger for the chat feature.
///
/// Checklist 4.4: message content, sender names, emails, phone numbers and
/// participant IDs are PII and must never reach production logs. Every chat
/// log call routes through here so that:
///   1. Nothing is emitted in release/profile builds (`kDebugMode` gate).
///   2. Free-text (message bodies, names, previews) is redacted to a shape
///      (length only) even in debug, so screen-shared dev sessions don't leak.
///   3. IDs are shortened to their last 6 chars for correlation without
///      exposing the full identifier.
class ChatLog {
  const ChatLog._();

  /// Emits [message] only in debug builds. Caller is responsible for having
  /// already redacted any PII via [redact] / [shortId] / [shape].
  static void d(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Emits an error line in debug builds. [error] is converted to a category
  /// shape rather than its full string to avoid leaking SDK internals/PII.
  static void e(String context, Object? error) {
    if (kDebugMode) {
      debugPrint('[CHAT] $context | ${shape(error?.toString())}');
    }
  }

  /// Emits an error with its MESSAGE INTACT, for failures where the reason
  /// is the whole diagnostic value — a Postgres CHECK violation, an RLS
  /// denial, a MIME allowlist rejection, a feature-flag gate.
  ///
  /// [e] shapes errors down to a length, which is right for anything that
  /// might carry message content but useless for infrastructure errors: a
  /// swallowed `chat_image_sharing is unavailable` logged as `<len=34>` is
  /// indistinguishable from any other failure, and a real bug survived
  /// three rounds of fixes behind exactly that.
  ///
  /// Only use for errors raised by the backend about the REQUEST (keys,
  /// constraints, policies) — never for anything holding message bodies,
  /// names, or other user text. Debug-only, like every call here.
  static void diagnostic(String context, Object? error) {
    if (kDebugMode) debugPrint('[CHAT] $context | $error');
  }

  /// Replaces free-text with a non-reversible shape: `<text:len=12>`.
  /// Use for message content, captions, previews, names.
  static String redact(String? text) {
    if (text == null) return '<null>';
    if (text.isEmpty) return '<empty>';
    return '<text:len=${text.length}>';
  }

  /// Last 6 chars of an identifier (UUID / channel URL / message id), enough
  /// to correlate log lines without exposing the full ID.
  static String shortId(String? id) {
    if (id == null || id.isEmpty) return '<none>';
    return id.length <= 6 ? id : '…${id.substring(id.length - 6)}';
  }

  /// Shapes a list of IDs to `[count] …abc123, …def456` (first two only).
  static String shortIds(Iterable<String> ids) {
    final list = ids.toList();
    final preview = list.take(2).map(shortId).join(', ');
    return '[${list.length}] $preview${list.length > 2 ? ', …' : ''}';
  }

  /// Generic shape for any nullable string: length only, never the value.
  static String shape(String? value) {
    if (value == null) return '<null>';
    if (value.isEmpty) return '<empty>';
    return '<len=${value.length}>';
  }
}
