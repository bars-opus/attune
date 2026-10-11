// Sessions-specific safety corpus extension. Spec §8.1:
//
//   "The existing chat_safety.ts immediate families are a reusable
//    component, not a complete safety classifier. Its Tier-3 rule IDs
//    are phrase matches, not a three-occurrence finding; its inspected
//    configuration contains no self-harm family and normalizes to
//    English ASCII. Sessions need a separately versioned, reviewed
//    refusal rule set including self-harm/coercion and declared
//    supported languages. A single concerning phrase may refuse a
//    session request without claiming the historical Tier-3 threshold
//    was met. Unsupported languages fail closed with neutral copy until
//    evaluated. No claim that regex detects all abuse."
//
// ===========================================================================
// NO CLAIM OF COMPLETENESS. This is a narrow, mechanical phrase-match
// extension for a single declared language (English), not a clinical
// safety classifier and not an abuse detector. Spec §8.1's own words:
// "No claim that regex detects all abuse"; §8.1 again: "Model-level
// adherence is evaluated residual risk, not guaranteed by JSON/schema/
// rules." A human-reviewed eval corpus (spec §11 item 9) is a release
// gate that this file's existence does not satisfy on its own, and the
// phrase list below is a starting point for that review rather than its
// output. Every phrase here is a true positive for "do not let a
// language model answer this instruction"; the set is nowhere near
// exhaustive, and the right response to a miss is a new reviewed
// version of this config, not a regex made cleverer.
// ===========================================================================
//
// WHAT THIS FILE DOES NOT DO. It does not edit chat_safety.ts -- not its
// exported functions' signatures, not their behavior, and not
// CHAT_SAFETY_CONFIG's existing rule data. The chat safety outbox's own
// regression behaviour depends on that data being unchanged (plan Global
// Constraints). This module IMPORTS and REUSES normalizeForTokenPhrase,
// detectImmediateFamilies and detectTierThreeRuleIds as-is, and adds a
// new, separately versioned config and new exported functions ALONGSIDE
// them. ai_session_safety.test.ts carries a characterization test over
// chat_safety.ts's full rule data and its three functions' behaviour,
// because that module has no dedicated test file of its own -- so "we
// did not change it" is executable here rather than asserted.

// ===========================================================================
// TWO KNOWN, MEASURED EVASIONS, recorded here rather than discovered
// later. Both belong to the REUSED machinery, which this task is
// forbidden to edit, so both are pinned by tests that assert the actual
// (wrong) behaviour and say so.
//
//  1. ZERO-WIDTH AT A WORD BOUNDARY defeats every token_phrase rule in
//     BOTH corpora. normalizeForTokenPhrase strips
//     the zero-width range U+200B..U+200D and U+FEFF with the
//     EMPTY STRING rather than with a space, so
//     a zero-width space between "i" and "want" normalizes the
//     pair to " iwant " and
//     " want to end it " is no longer a substring. Fixing it means
//     changing chat_safety.ts's normalizer, which changes what the chat
//     safety outbox matches and needs chat's own review and regression
//     run -- not a sessions-side edit. See the "KNOWN EVASION" test.
//
//  2. A LATIN-SCRIPT NON-ENGLISH LANGUAGE reports SUPPORTED (it is
//     majority ASCII) while none of this corpus's English phrases can
//     match it -- so it is evaluated by a corpus that cannot evaluate
//     it. See isSupportedLanguage's own comment. Closing it needs real
//     language identification plus a reviewed corpus per language
//     (spec §11 item 9), not a cleverer threshold.
//
// Neither is a reason to withhold this corpus: both are strictly
// narrower than the status quo, which is no self-harm family at all.
// ===========================================================================

import {
  CHAT_SAFETY_CONFIG,
  detectImmediateFamilies,
  detectTierThreeRuleIds,
  normalizeForTokenPhrase,
  SafetyConfig,
  SafetyDetectionResult,
  SafetyFamilyConfig,
} from "./chat_safety.ts";

/// The sessions corpus version, exported separately so a caller can
/// record WHICH corpus produced a finding without importing the whole
/// config. §8.1 requires the sessions rule set to be "separately
/// versioned" from chat's, and chat's is "1.0.0" -- the `sessions-`
/// prefix makes the two impossible to confuse in an audit record.
///
/// Bump this on ANY change to the rule data below, including adding a
/// phrase. The version is what lets an operator say which corpus a
/// recorded finding came from, and a silent rule change makes every
/// older finding unreproducible.
export const SESSION_SAFETY_CONFIG_VERSION = "sessions-1.0.0";

/// SafetyConfig plus the one field §8.1 requires that chat's shape has
/// no slot for: the DECLARED supported languages. `locale` says what the
/// patterns are written in; this says what the corpus claims to be able
/// to evaluate, which is the thing isSupportedLanguage gates on. This
/// plan declares exactly one.
export interface SessionSafetyConfig extends SafetyConfig {
  declared_languages: readonly string[];
}

/// The sessions families. SEPARATE from CHAT_SAFETY_CONFIG -- a new
/// object, not a spread of it and not a mutation of it.
///
/// EVERY PATTERN IS PRE-NORMALIZED. The matcher is
/// `normalized.includes(' ' + pattern + ' ')` against
/// normalizeForTokenPhrase output, so a pattern containing an uppercase
/// letter, punctuation other than an apostrophe, or a double space is
/// DEAD: it compiles, ships, and matches nothing. The test file asserts
/// `normalizeForTokenPhrase(pattern) === ' ' + pattern + ' '` for every
/// rule, which is the only thing that makes a new phrase's deadness
/// visible at review time rather than never.
///
/// Rule ids are namespaced `sessions_`. A rule id is the ONE piece of
/// detector identity allowed to travel, and only to an operator-side
/// record -- see classifySessionContent for why it never reaches a
/// caller. The namespace is what makes such a record traceable to this
/// config and therefore to its version.
export const AI_SESSION_SAFETY_CONFIG: SessionSafetyConfig = {
  config_version: SESSION_SAFETY_CONFIG_VERSION,
  locale: "en",
  // Chat's normalizer is reused verbatim, so the normalization version
  // MUST track chat's. If chat's normalizer ever changes version, this
  // corpus's patterns were written against the old one and need
  // re-review -- the test file asserts the two agree, which is what
  // turns that into a failing build rather than a silent divergence.
  normalization_version: CHAT_SAFETY_CONFIG.normalization_version,
  // §8.1: "declared supported languages". Exactly one, stated
  // honestly. isSupportedLanguage's conservatism is the enforcement.
  declared_languages: ["en"],
  tiers: {
    /// TIER 1 -- an immediate refusal on a single phrase. A session
    /// instruction disclosing self-harm must not be sent to a language
    /// model to be answered as a relationship question; the response is
    /// the neutral copy plus the Safety Resources link §8.1 requires be
    /// offered always.
    ///
    /// Deliberately NOT a help-seeking detector: these phrases are
    /// first-person statements of intent or hopelessness, not questions
    /// about the topic. "how do i support a friend who self harms" does
    /// not match any of them, and should not -- refusing that would
    /// teach users the feature is unusable for the conversations it
    /// exists for.
    self_harm: {
      tier: 1,
      // §8.1: "A single concerning phrase may refuse a session request
      // WITHOUT claiming the historical Tier-3 threshold was met."
      // There is no session history to accumulate over and no window.
      minimum_occurrences: 1,
      rules: [
        {
          id: "sessions_self_harm_001",
          pattern: "want to end it",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_002",
          pattern: "kill myself",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_003",
          pattern: "hurt myself",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_004",
          pattern: "don't want to be here anymore",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_005",
          pattern: "better off without me",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_006",
          pattern: "end my life",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_007",
          pattern: "no reason to go on",
          match: "token_phrase",
        },
        {
          id: "sessions_self_harm_008",
          pattern: "harm myself",
          match: "token_phrase",
        },
      ],
    },
    /// TIER 2 -- coercion/pressure instructions. These are not threats
    /// and not abuse; they are requests to turn the assistant into a
    /// tool for winning against the partner, which §8.1 forbids in its
    /// own words: "No partner intent interpretation, fault ranking,
    /// compliance scripts, guilt, isolation, surveillance or 'the AI
    /// agrees with me' framing."
    ///
    /// A session is a SHARED surface. An answer composed to make one
    /// partner concede is the "the AI agrees with me" framing arriving
    /// through the front door, and no output-field check can catch it
    /// after the fact -- the model will have written something perfectly
    /// well-formed. So it is refused at the instruction, before
    /// dispatch.
    coercion_pressure: {
      tier: 2,
      minimum_occurrences: 1,
      rules: [
        {
          id: "sessions_coercion_001",
          pattern: "make them agree",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_002",
          pattern: "prove they are wrong",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_003",
          pattern: "get them to admit",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_004",
          pattern: "convince them they are",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_005",
          pattern: "prove i'm right",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_006",
          pattern: "make them feel guilty",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_007",
          pattern: "take my side",
          match: "token_phrase",
        },
        {
          id: "sessions_coercion_008",
          pattern: "tell them they are wrong",
          match: "token_phrase",
        },
      ],
    },
  },
};

/// The sessions tier a chat TIER-3 phrase is reported at.
///
/// WHY NOT 3. §8.1: "Its Tier-3 rule IDs are phrase matches, not a
/// three-occurrence finding ... A single concerning phrase may refuse a
/// session request WITHOUT claiming the historical Tier-3 threshold was
/// met." Chat's tier 3 means "three occurrences in thirty days", a
/// historical finding over a message corpus. A session instruction has
/// no history, so reporting tier 3 here would assert a threshold that
/// was never evaluated. Reported as 2 -- a real concern on the phrase
/// alone -- with minimumOccurrences 1 and windowDays null, which is the
/// honest shape.
const SESSION_TIER_FOR_CHAT_TIER_THREE = 2;

/// Spec §5.3's allowlisted redirect reasons, and §8.1's requirement
/// that a refusal carry "server-rendered fixed copy from allowlisted
/// reason" with "no model-written fallback advice".
export type SessionSafetyReason =
  | "unsupported"
  | "unsafe_to_assist"
  | "insufficient_context";

/// The FROZEN copy table. Three strings, one per allowlisted reason,
/// composed here and never at a call site -- a caller that interpolated
/// anything into them (the matched phrase, a family name, a count)
/// would be the leak this module exists to prevent.
///
/// The copy is deliberately uninformative about WHY. A requester who
/// typed a coercion instruction and a requester who disclosed self-harm
/// see the SAME unsafe_to_assist string: §8.1 says "A refusal/error
/// must not signal a private detector result to the partner", and the
/// plan's Global Constraints extend that to either party, including the
/// requester. Differentiated copy would be a side channel that tells a
/// probing user exactly which phrase tripped which rule.
export const SESSION_SAFETY_NEUTRAL_COPY: Readonly<
  Record<SessionSafetyReason, string>
> = Object.freeze({
  unsupported:
    "I can't help with this one. Try rephrasing in English, or start a new question.",
  unsafe_to_assist:
    "I can't help with this one. If you'd like support, the Safety Resources link is always available.",
  insufficient_context:
    "I don't have enough to go on here. Try adding a bit more detail, or start a new question.",
});

/// What a request branch returns to a caller. Its SHAPE is the privacy
/// mechanism: four fields, none of which can carry a rule id, a family
/// name, a tier, a count or a config version. The test file freezes
/// `Object.keys(verdict)` precisely so a later field added "just for
/// debugging" fails there rather than shipping.
export interface SessionSafetyVerdict {
  allowed: boolean;
  /// null when allowed. Otherwise an allowlisted §5.3 reason -- which
  /// is NOT detector identity: `unsafe_to_assist` is returned
  /// identically for a tier-1 self-harm match, a tier-2 coercion match
  /// and any chat family.
  reason: SessionSafetyReason | null;
  /// null when allowed. Otherwise the frozen neutral string for
  /// `reason`, copied from SESSION_SAFETY_NEUTRAL_COPY verbatim.
  copy: string | null;
  /// ALWAYS true. §8.1: "Always offer the same discreet manual Safety
  /// Resources link." It is a constant and not a signal: if it appeared
  /// only on refusals, its presence would itself disclose that a
  /// detector fired, which is the exact result §8.1 says to hide. It is
  /// in the verdict rather than left implicit so a caller cannot forget
  /// to render it on the allowed path.
  showSafetyResources: boolean;
}

function matchFamily(
  normalized: string,
  familyName: string,
  family: SafetyFamilyConfig,
  reportedTier: number,
): SafetyDetectionResult | null {
  const matchedRuleIds = family.rules
    .filter((rule) => normalized.includes(` ${rule.pattern} `))
    .map((rule) => rule.id);
  if (matchedRuleIds.length === 0) return null;
  return {
    highestTier: reportedTier,
    family: familyName,
    matchedRuleIds,
    minimumOccurrences: family.minimum_occurrences,
    windowDays: family.window_days ?? null,
  };
}

/// This module's OWN families only. Not exported: a caller that wanted
/// just these would be skipping chat's, and there is no legitimate
/// reason to run a partial corpus.
function detectSessionOwnFamilies(content: string): SafetyDetectionResult[] {
  const normalized = normalizeForTokenPhrase(content);
  if (normalized.trim().length === 0) return [];

  const results: SafetyDetectionResult[] = [];
  for (
    const [familyName, family] of Object.entries(
      AI_SESSION_SAFETY_CONFIG.tiers,
    )
  ) {
    const result = matchFamily(normalized, familyName, family, family.tier);
    if (result) results.push(result);
  }
  return results;
}

/// Chat's TIER-3 phrases, re-reported as a sessions finding.
///
/// THE GAP THIS CLOSES. detectImmediateFamilies skips tier 3 outright
/// (`if (familyConfig.tier === 3) continue`), correctly, because chat's
/// tier 3 is a historical three-in-thirty-days finding that a single
/// message cannot establish. But a session has no history, so a session
/// instruction containing "if you leave" or "you can't survive without
/// me" would pass detectImmediateFamilies clean -- and §8.1 says in so
/// many words that a single such phrase MAY refuse a session request.
/// Calling only detectImmediateFamilies, as the task brief's own sample
/// code does, leaves all three of chat's tier-3 phrases undetected in
/// Sessions.
///
/// detectTierThreeRuleIds is reused as-is to find them, and its rule
/// ids are reported verbatim under chat's own family name, at the
/// sessions tier with no window -- so the finding claims exactly what
/// was observed and nothing more.
function detectChatTierThreeAsSessionFinding(
  content: string,
): SafetyDetectionResult[] {
  const matchedRuleIds = detectTierThreeRuleIds(content);
  if (matchedRuleIds.length === 0) return [];
  return [{
    highestTier: SESSION_TIER_FOR_CHAT_TIER_THREE,
    // Chat's own family name, verbatim. The ids in matchedRuleIds are
    // chat's, so the family they belong to must be too -- renaming it
    // here would make an operator-side record say a rule came from a
    // family that does not contain it.
    family: "pattern_control",
    matchedRuleIds,
    // 1, NOT CHAT_SAFETY_CONFIG.tiers.pattern_control.minimum_occurrences
    // (which is 3): the finding here is the phrase itself, and
    // reporting 3 would claim the historical threshold §8.1 says in so
    // many words not to claim.
    minimumOccurrences: 1,
    // null, NOT chat's window_days (30): there is no session history to
    // window over, so a window would describe a lookback that never
    // happened.
    windowDays: null,
  }];
}

/// Runs BOTH chat_safety.ts's existing detectors and this module's own
/// families against the same content, merged and sorted by tier
/// (lowest/most severe first, matching detectImmediateFamilies' own
/// ordering) so a caller reading results[0] gets the most severe.
///
/// THE OPERATOR-SIDE API. It carries matchedRuleIds, which is detector
/// identity. It is for operator-side logging and for tests -- NEVER for
/// a response body. A request branch calls classifySessionContent
/// instead, which is the caller-facing surface and carries no identity
/// at all; see its doc comment for how Task 4 is meant to keep the two
/// apart.
///
/// Sessions bypass the message safety pipeline entirely (§8.1), so this
/// is the ONLY safety net a session turn's own content passes through --
/// unlike a posted chat message, which also gets
/// process-chat-safety-outbox's async pass after this synchronous one.
/// Synchronous and pure by construction: §8.1 requires these checks
/// before dispatch and before publish, and an IO-bearing check could
/// not be run on every output field within §8.2.1's budget.
export function detectSessionSafetyConcern(
  content: string,
): SafetyDetectionResult[] {
  return [
    ...detectImmediateFamilies(content),
    ...detectChatTierThreeAsSessionFinding(content),
    ...detectSessionOwnFamilies(content),
  ].sort((a, b) => a.highestTier - b.highestTier);
}

/// The ASCII-majority share at or above which content is treated as
/// evaluable by this English-only corpus.
///
/// 0.85 rather than 0.9: the false-positive cost is a refusal shown to
/// a user who wrote ordinary English, and ordinary English carries
/// non-ASCII more often than a threshold-setter expects -- a
/// typographic apostrophe, an em dash, "café", one emoji (which is TWO
/// UTF-16 code units but one `for...of` iteration, hence the iteration
/// by code point below). Measured against the test file's English
/// fixtures. Lowering it further would start admitting genuinely
/// non-English strings that this corpus cannot evaluate, which is the
/// other error and the one §8.1 cares about.
const ASCII_MAJORITY_THRESHOLD = 0.85;

/// Deliberately conservative, and deliberately crude: an ASCII-majority
/// heuristic that matches chat_safety.ts's own stated English-ASCII
/// normalization limit honestly rather than claiming language coverage
/// this MVP does not have. It is NOT language identification and does
/// not pretend to be -- it distinguishes "this corpus can be applied"
/// from "this corpus cannot", which is the only question §8.1 asks of
/// it: "Unsupported languages fail closed with neutral copy until
/// evaluated."
///
/// KNOWN AND ACCEPTED LIMITATION, stated rather than hidden: a Latin-
/// script non-English language (French, Spanish, German) is majority
/// ASCII and so reports SUPPORTED, while this corpus's English phrases
/// will not match it -- so it is evaluated by a corpus that cannot
/// evaluate it, and a concerning instruction in Spanish passes. That is
/// a real gap, it is the honest consequence of an ASCII heuristic, and
/// closing it needs actual language identification plus a reviewed
/// corpus per language (spec §11 item 9), not a cleverer threshold.
/// Recorded here so it is a known residual risk rather than a
/// discovered one.
///
/// EMPTY IS SUPPORTED. An empty or whitespace-only instruction is an
/// INVALID_INPUT matter for the caller, not a language one; returning
/// false would make a blank box render "unsupported language" copy.
export function isSupportedLanguage(content: string): boolean {
  const trimmed = content.trim();
  if (trimmed.length === 0) return true;

  let asciiCount = 0;
  let total = 0;
  // Iterated by CODE POINT, not by UTF-16 code unit: a single emoji is
  // one character the user typed but two `.length` units, and counting
  // units would make one emoji in a short English sentence weigh twice
  // as heavily against it as it should.
  for (const char of trimmed) {
    total++;
    const code = char.codePointAt(0) ?? 0;
    if (code <= 0x7f) asciiCount++;
  }
  return asciiCount / total >= ASCII_MAJORITY_THRESHOLD;
}

/// THE CALLER-FACING API, and the one a request branch should use.
///
/// HOW THIS KEEPS THE DETECTOR IDENTITY FROM LEAKING, which is the plan
/// Global Constraint "A safety refusal never reveals which detector
/// fired, to either party":
///
///  1. The returned object has no field that CAN carry identity. No
///     rule id, no family, no tier, no match count, no config version,
///     and no echo of the user's own text. The test file freezes the
///     verdict's key set and serializes it to assert that no family
///     name or rule id from EITHER corpus appears anywhere in it.
///  2. `reason` is one of §5.3's three allowlisted values, and
///     `unsafe_to_assist` is returned identically for a tier-1
///     self-harm match, a tier-2 coercion match and any chat family --
///     so two refusals of the same reason are BYTE-IDENTICAL whatever
///     fired. The test file asserts exactly that across six inputs
///     spanning five families and both corpora.
///  3. `copy` is copied verbatim from the frozen
///     SESSION_SAFETY_NEUTRAL_COPY table. Nothing is interpolated, so
///     there is no path by which a phrase or a rule name reaches a
///     string a user sees.
///  4. `showSafetyResources` is ALWAYS true, including on the allowed
///     path, so its presence is not itself a signal (§8.1: "Always
///     offer the same discreet manual Safety Resources link").
///
/// WHAT TASK 4 MUST DO, since this function cannot enforce it from
/// here:
///
///  - Return THIS object's `reason`/`copy` to the requester, and never
///    call detectSessionSafetyConcern in a code path whose value
///    reaches a response body. The rule ids exist for an
///    OPERATOR-SIDE record only -- a server log or a safety audit row
///    the requester cannot read -- and §8.1 separately forbids writing
///    session text into behavioral analytics or per-partner scores, so
///    such a record carries ids and not content.
///  - Show the PARTNER nothing. §5.3: "Safety refusals remain
///    requester-only, not shared transcript events", and §8.1: "A
///    refusal/error must not signal a private detector result to the
///    partner." A refusal must therefore produce no transcript pair, no
///    revision bump the partner can observe, and no timing difference a
///    partner polling `session_revision` could distinguish from the
///    requester simply not having asked anything -- a silent non-post,
///    identical to every other silent non-post.
///  - Run this BEFORE dispatch on the instruction, approved sources and
///    eligible history, and AGAIN before publish on every output field
///    (§8.1). Both passes are synchronous and neither may be skipped on
///    a retry.
export function classifySessionContent(content: string): SessionSafetyVerdict {
  // ORDER MATTERS, and this is the one ordering decision in the file.
  // A detected concern is checked FIRST, before the language gate: a
  // string that is majority non-ASCII AND contains a self-harm phrase
  // must be refused as `unsafe_to_assist`, not as `unsupported`.
  // Reporting "unsupported" there would hand a user who just disclosed
  // self-harm a "rewrite it in English" remedy and withhold the Safety
  // Resources framing.
  if (detectSessionSafetyConcern(content).length > 0) {
    return {
      allowed: false,
      reason: "unsafe_to_assist",
      copy: SESSION_SAFETY_NEUTRAL_COPY.unsafe_to_assist,
      showSafetyResources: true,
    };
  }

  // FAIL CLOSED. §8.1: "Unsupported languages fail closed with neutral
  // copy until evaluated." Reaching here with unsupported content means
  // "this corpus was not able to evaluate it", which is NOT the same
  // fact as "no rule matched" -- and treating the absence of a match in
  // a language the corpus does not cover as safety is the single
  // easiest way to ship a hole.
  if (!isSupportedLanguage(content)) {
    return {
      allowed: false,
      reason: "unsupported",
      copy: SESSION_SAFETY_NEUTRAL_COPY.unsupported,
      showSafetyResources: true,
    };
  }

  return {
    allowed: true,
    reason: null,
    copy: null,
    // True on the allowed path too -- see the interface comment. This
    // is the field whose constancy is the privacy property.
    showSafetyResources: true,
  };
}
