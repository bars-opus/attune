import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:go_router/go_router.dart';

/// The conversation a chat route was pushed with.
///
/// go_router can rebuild the current page from its saved route state — on
/// iOS this happens when the app goes inactive and comes back, for example
/// around the system "Allow Paste" prompt. That saved state carries the
/// route's `extra` as a decoded map, not the [Conversation] object, so a
/// plain `state.extra as Conversation?` threw a type error and the screen
/// went red (and the paste then wrote into the torn-down text field).
///
/// This returns the conversation when the extra is one, remembers it, and
/// falls back to the last one seen when the extra arrives as anything else.
/// Null only when no conversation was ever pushed in this run.
Conversation? conversationFromRouteExtra(Object? extra) {
  if (extra is Conversation) {
    _lastConversation = extra;
    return extra;
  }
  // Only a restored (wrong-typed) extra falls back; no extra stays none.
  return extra == null ? null : _lastConversation;
}

Conversation? _lastConversation;

/// A route's `extra` as a [T], for every other route. The same restored-
/// state map that broke the chat routes reaches these too; instead of a
/// type error this returns the last [T] the route was built with (per
/// route), or null so the route shows its own "unavailable" fallback.
T? routeExtra<T>(GoRouterState state) {
  final key = '${state.fullPath ?? state.matchedLocation}|$T';
  final extra = state.extra;
  if (extra is T) {
    _lastExtras[key] = extra;
    return extra;
  }
  // Only a restored (wrong-typed) extra falls back. A route opened with no
  // extra on purpose (e.g. your own profile) must not get the last one.
  if (extra == null) return null;
  final last = _lastExtras[key];
  return last is T ? last : null;
}

final Map<String, Object?> _lastExtras = {};

/// Test-only: forget every remembered extra between tests.
void resetConversationRouteExtraForTesting() {
  _lastConversation = null;
  _lastExtras.clear();
}
