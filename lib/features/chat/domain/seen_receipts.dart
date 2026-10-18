import 'package:flutter/foundation.dart';

/// What `get_seen_receipts` / `set_seen_receipts` return: my own vote and
/// the couple's effective state. Never the partner's row (Spec 1a Task 2).
@immutable
class SeenReceipts {
  const SeenReceipts({required this.mine, required this.effective});

  static const off = SeenReceipts(mine: false, effective: false);

  factory SeenReceipts.fromJson(Object? raw) {
    if (raw is! Map) return off;
    return SeenReceipts(
      mine: raw['mine'] == true,
      effective: raw['effective'] == true,
    );
  }

  final bool mine;
  final bool effective;

  @override
  bool operator ==(Object other) =>
      other is SeenReceipts &&
      other.mine == mine &&
      other.effective == effective;

  @override
  int get hashCode => Object.hash(mine, effective);

  @override
  String toString() => 'SeenReceipts(mine: $mine, effective: $effective)';
}

/// Copy for "Show when we've seen things" (Spec 1a; research 06 §3 F4).
/// Verbatim strings; the subtitle never says who turned it off.
const seenReceiptsTitle = "Show when we've seen things";

const seenReceiptsAsk1Line =
    'Read receipts are off to start. Turn them on together whenever you like.';

const seenReceiptsFailureCopy = "Couldn't update this setting. Try again.";

String seenReceiptsSubtitle(SeenReceipts s) {
  if (s.effective) {
    return 'On for both of you. Read ticks and story seen marks show. '
        'Either of you can turn this off.';
  }
  if (s.mine) return "Turns on once you've both turned it on.";
  return 'Off. Read ticks and story seen marks stay hidden for both of you. '
      'Turn it on together whenever you like.';
}
