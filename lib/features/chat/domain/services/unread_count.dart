/// Parses the result of the `count_unread_messages` RPC.
///
/// PostgREST returns a scalar function's value bare; some wrappers hand it
/// back as `[{"count_unread_messages": n}]`. A badge must never throw, so
/// anything unrecognised (or negative) is 0.
int parseUnreadCount(Object? raw) {
  if (raw is num) return raw < 0 ? 0 : raw.toInt();
  if (raw is List) return raw.isEmpty ? 0 : parseUnreadCount(raw.first);
  if (raw is Map) return raw.isEmpty ? 0 : parseUnreadCount(raw.values.first);
  return 0;
}
