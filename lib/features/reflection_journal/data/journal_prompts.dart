import 'dart:math';

/// Curated, hand-written prompt bank for the Reflection Journal's optional
/// daily inspiration banner. Rules (per design spec §4): concrete and
/// moment-anchored, never abstract; open-ended, never yes/no; never
/// therapy-coded.
const List<String> journalPrompts = [
  "What's one thing that surprised you today?",
  "What moment today do you want to remember?",
  "What's taking up the most space in your mind right now?",
  "What did you notice about how you reacted to something today?",
  "What's something you didn't say out loud today, but wish you had?",
  "What made today feel different from yesterday?",
  "What's a conversation that's still sitting with you?",
  "What's something small that went well today?",
  "What are you carrying into tomorrow?",
  "What did you learn about yourself this week?",
  "What's something you noticed but didn't act on?",
  "What's a feeling you had today that you haven't named yet?",
  "What's something you're avoiding thinking about?",
  "What's one thing you'd tell yourself from this morning?",
  "What's changed in how you see things lately?",
  "What's something you did today that felt like you?",
  "What's a moment today when you felt most like yourself?",
  "What's something you're still figuring out?",
  "What's a pattern you've noticed in yourself this month?",
  "What's something you wish someone had asked you today?",
  "What's a decision you made today, and how did it feel?",
  "What's something you're proud of that no one else noticed?",
  "What's weighing on you that you haven't written down yet?",
  "What's a memory that came up unexpectedly today?",
  "What's something you needed today that you didn't get?",
  "What's a boundary you held, or wish you had?",
  "What's something you're curious about in yourself right now?",
  "What's a moment today you'd like to understand better?",
  "What's something that felt harder than it should have today?",
  "What's a small thing that brought you comfort today?",
  "What's something you're ready to let go of?",
  "What's a question you keep circling back to?",
];

/// [seed] makes the pick deterministic for tests; omit it in production
/// callers to get a real random pick each time.
String randomJournalPrompt({int? seed}) {
  final random = seed == null ? Random() : Random(seed);
  return journalPrompts[random.nextInt(journalPrompts.length)];
}
