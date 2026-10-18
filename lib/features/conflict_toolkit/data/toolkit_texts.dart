// lib/features/conflict_toolkit/data/toolkit_texts.dart
//
// Spec 8 (research 06 B3, 05 Part C; plan review M2, M3): the toolkit's
// fixed words, bound verbatim, and the two scaffolds that put a person's
// own words into the composer. Nothing here sends.
//
// The repair phrases belong in l10n; the chat surface has no l10n yet (the
// CHAT_SYSTEM_SPEC extraction gate), so they live here, once.

/// The three pause messages; the server holds the same words
/// (`pause_text`) and the client sends only which one. 2 and 3 await
/// clinician wording.
const kPauseTexts = <int, String>{
  1:
      "I'm getting flooded. I'm stepping back for 30 minutes, not away from "
      "you. I'll come back.",
  2:
      "[DRAFT] I need a short break so I don't say something I don't mean. "
      "I'll be back in 20 minutes.",
  3:
      '[DRAFT] This matters to me and I want to get it right. Can we come '
      'back to it in 45 minutes?',
};

/// The return each pause names, for the sender's own timer.
const kPauseMinutes = <int, int>{1: 30, 2: 20, 3: 45};

/// The partner's one optional answer.
const kPauseReplyText = "Okay. I'll be here.";

/// Part C, verbatim.
const kRepairPhrases = <String>[
  'Can we start over?',
  'I see my part in this.',
  'That came out wrong.',
  "I'm on your side, even now.",
  'Can we slow down?',
  "I need a minute, then I'm back.",
];

const kApologyLine = "A promise isn't a repair; an action is.";

/// Shown when an apology asks for forgiveness (Part C: never a request).
const kNoForgivenessNote = "An apology doesn't need to ask for anything back.";

/// The sender's own card while the pause runs.
const kSelfSoothingCopy =
    "[DRAFT] Do something absorbing: a walk, music, a shower. Try not to "
    'rehearse the argument.';

/// Generic on purpose: it says nothing to anyone glancing at the screen.
const kReturnPrompt = 'Time to check back in';

/// The seven needs (the translator's taxonomy), as they read after
/// "I need". The seventh's definition awaits clinician sign-off.
const kConversationNeeds = <String, String>{
  'respect': 'to feel respected',
  'fairness': 'things to feel fair',
  'affection': 'to feel cared for',
  'security': 'to feel safe with you',
  'autonomy': 'some space',
  'rest': 'some rest',
  'communal_obligation': 'to honour my family and community',
};

/// Both flags, so the toolkit never shows without the safety check that
/// gates its one conjoint step (plan review I5).
bool toolkitVisible({required bool toolkit, required bool safetyCheck}) =>
    toolkit && safetyCheck;

String _clause(String s) =>
    s.trim().replaceFirst(RegExp(r'[.!?,;:\s]+$'), '').trim();

/// "I'm sorry I …. I know that …. To make it right, I'll …. Next time,
/// I'll …." from the four fields; null without the first. Never adds a
/// request for forgiveness.
String? assembleApology({
  required String did,
  String cost = '',
  String repair = '',
  String different = '',
}) {
  final d = _clause(did);
  if (d.isEmpty) return null;
  final c = _clause(cost);
  final r = _clause(repair);
  final n = _clause(different);
  return [
    "I'm sorry I $d.",
    if (c.isNotEmpty) 'I know that $c.',
    if (r.isNotEmpty) "To make it right, I'll $r.",
    if (n.isNotEmpty) "Next time, I'll $n.",
  ].join(' ');
}

/// Observation, feeling, need, request; null without the first two.
String? assembleConversationStart({
  String observation = '',
  String feeling = '',
  String? need,
  String request = '',
}) {
  final o = _clause(observation);
  final f = _clause(feeling);
  if (o.isEmpty || f.isEmpty) return null;
  final n = need == null ? null : kConversationNeeds[need];
  final q = _clause(request);
  return [
    'When $o, I feel $f.',
    if (n != null) 'I need $n.',
    if (q.isNotEmpty) 'Would you $q?',
  ].join(' ');
}
