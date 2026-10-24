/// Screen-reader labels and short copy for the story rings (03 L2). Kept
/// in one place so the open l10n extraction gate can lift them together.
library;

String _items(int n) => n == 1 ? '1 item' : '$n items';

/// The `+` (camera) on my ring.
const String storyRingAddLabel = 'Add to your story';

/// My ring with posted stories: "Your story, 3 items".
String storyRingMineLabel(int active) => 'Your story, ${_items(active)}';

/// My ring while a story posts: "Your story, posting, 2 posted".
String storyRingPostingLabel(int posted) =>
    posted > 0 ? 'Your story, posting, $posted posted' : 'Your story, posting';

/// The partner's ring: "Ama's story, 2 new of 5", or, all seen,
/// "Ama's story, 5 items, all seen".
String storyRingPartnerLabel(
  String name, {
  required int active,
  required int unviewed,
}) {
  final fresh = unviewed.clamp(0, active);
  return fresh == 0
      ? "$name's story, ${_items(active)}, all seen"
      : "$name's story, $fresh new of $active";
}

/// A calendar day's ring: "Your stories from this day, 2 items".
String storyDayRingLabel({
  required bool mine,
  required int count,
  String? partnerName,
}) {
  final whose = mine ? 'Your' : "${partnerName ?? 'Your partner'}'s";
  return '$whose stories from this day, ${_items(count)}';
}

/// Under the rings when a read failed (03 M3).
String storyRingsLoadErrorCopy({required bool showingLastKnown}) =>
    showingLastKnown
        ? "Showing your last stories. Couldn't refresh."
        : "Couldn't load stories.";

/// A ring whose only story is still posting (03 L1).
const String storyRingStillPostingCopy =
    "Still posting. It'll be here in a moment.";

/// Stories queued for a relationship that is not the one shown (03 M6).
String storyOrphanedPostsCopy(int count) => count == 1
    ? "A story for a previous relationship couldn't be posted."
    : "$count stories for a previous relationship couldn't be posted.";
