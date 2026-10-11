// ai_session_safety.ts tests. Spec §8.1.
//
// Run: deno test --allow-net --allow-env --allow-read --allow-sys \
//        supabase/functions/_shared/ai_session_safety.test.ts
//
// NO DATABASE. Every function under test is pure, which is the point:
// spec §8.1 requires these checks to run "deterministic synchronous[ly]
// ... before dispatch" and "before publishing on every output field",
// so none of them may touch IO.
//
// WHAT THESE TESTS ASSERT, deliberately: the SPECIFIC rule id, the
// SPECIFIC family, the SPECIFIC tier and the SPECIFIC outcome -- never
// "something was detected". A safety corpus is exactly where that trap
// bites: an implementation whose every match reports the wrong rule id,
// or reports tier 2 for a tier-1 family, satisfies "results.length > 0"
// and "results.some(r => r.family === 'self_harm')" while being wrong
// in the way that matters to the caller that has to decide between a
// hard refusal and a redirect.

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AI_SESSION_SAFETY_CONFIG,
  classifySessionContent,
  detectSessionSafetyConcern,
  isSupportedLanguage,
  SESSION_SAFETY_CONFIG_VERSION,
  SESSION_SAFETY_NEUTRAL_COPY,
} from "./ai_session_safety.ts";
import {
  CHAT_SAFETY_CONFIG,
  detectImmediateFamilies,
  detectTierThreeRuleIds,
  normalizeForTokenPhrase,
} from "./chat_safety.ts";

// ---------------------------------------------------------------------------
// The config itself: versioned, declared-language, and SEPARATE from
// chat_safety.ts's.
// ---------------------------------------------------------------------------

Deno.test("the sessions config is versioned separately from CHAT_SAFETY_CONFIG, and the two versions are not the same string", () => {
  assertEquals(AI_SESSION_SAFETY_CONFIG.config_version, "sessions-1.0.0");
  assertEquals(SESSION_SAFETY_CONFIG_VERSION, "sessions-1.0.0");
  // §8.1: "Sessions need a SEPARATELY VERSIONED, reviewed refusal rule
  // set." Sharing chat's "1.0.0" would make a sessions-side rule change
  // indistinguishable from a chat-side one in any audit keyed on the
  // version.
  assertNotEquals(
    AI_SESSION_SAFETY_CONFIG.config_version,
    CHAT_SAFETY_CONFIG.config_version,
  );
  // The declared supported language set is exactly one, and it is
  // stated rather than implied.
  assertEquals(AI_SESSION_SAFETY_CONFIG.locale, "en");
  assertEquals(AI_SESSION_SAFETY_CONFIG.declared_languages, ["en"]);
  // Normalization is chat_safety.ts's, reused as-is, so the version
  // must match or the two corpora disagree about what they matched on.
  assertEquals(
    AI_SESSION_SAFETY_CONFIG.normalization_version,
    CHAT_SAFETY_CONFIG.normalization_version,
  );
});

Deno.test("the sessions config adds exactly the two families spec §8.1 names, at the tiers it implies, and reuses NONE of chat_safety.ts's family names", () => {
  assertEquals(
    Object.keys(AI_SESSION_SAFETY_CONFIG.tiers).sort(),
    ["coercion_pressure", "self_harm"],
  );
  // THE SPECIFIC TIERS. self_harm is tier 1 (an immediate refusal, not
  // an accumulating pattern); coercion_pressure is tier 2. A config
  // that had both at tier 2, or both at 1, satisfies a mere
  // "the families exist" assertion while changing what every caller
  // does with the result.
  assertEquals(AI_SESSION_SAFETY_CONFIG.tiers.self_harm.tier, 1);
  assertEquals(AI_SESSION_SAFETY_CONFIG.tiers.coercion_pressure.tier, 2);
  // §8.1: "A single concerning phrase may refuse a session request
  // without claiming the historical Tier-3 threshold was met." So both
  // sessions families fire on ONE occurrence -- there is no history to
  // accumulate over, and no window.
  for (const family of Object.values(AI_SESSION_SAFETY_CONFIG.tiers)) {
    assertEquals(family.minimum_occurrences, 1);
    assertEquals(family.window_days, undefined);
  }
  // A name collision with a chat family would make a merged result list
  // ambiguous about which corpus and which version produced it.
  for (const name of Object.keys(AI_SESSION_SAFETY_CONFIG.tiers)) {
    assertEquals(
      Object.hasOwn(CHAT_SAFETY_CONFIG.tiers, name),
      false,
      `${name} collides with a chat_safety.ts family name`,
    );
  }
});

Deno.test("every sessions rule id is unique, namespaced, and distinct from every chat_safety.ts rule id", () => {
  const sessionIds = Object.values(AI_SESSION_SAFETY_CONFIG.tiers)
    .flatMap((family) => family.rules.map((rule) => rule.id));
  assertEquals(
    sessionIds.length,
    new Set(sessionIds).size,
    "duplicate rule id in the sessions corpus",
  );
  const chatIds = new Set(
    Object.values(CHAT_SAFETY_CONFIG.tiers)
      .flatMap((family) => family.rules.map((rule) => rule.id)),
  );
  for (const id of sessionIds) {
    assertEquals(
      chatIds.has(id),
      false,
      `${id} collides with a chat_safety.ts rule id`,
    );
    // The namespace is what makes a rule id traceable to its corpus and
    // therefore to its version, in the one place a rule id is allowed
    // to travel: an operator-side audit record.
    assert(
      id.startsWith("sessions_"),
      `${id} is not namespaced with the sessions_ prefix`,
    );
  }
});

Deno.test("every sessions rule pattern survives normalizeForTokenPhrase unchanged -- a pattern the normalizer rewrites can never match", () => {
  // THE BUG THIS CATCHES, and it is not hypothetical: the matcher tests
  // `normalized.includes(' ' + pattern + ' ')`, so a pattern containing
  // anything normalizeForTokenPhrase strips or collapses -- an
  // uppercase letter, a comma, a double space, a typographic
  // apostrophe -- is DEAD. It compiles, it ships, it matches nothing,
  // and no behavioural test for a phrase nobody thought to write
  // reveals it. chat_safety.ts's own corpus happens to satisfy this;
  // nothing enforced it.
  for (const [familyName, family] of Object.entries(
    AI_SESSION_SAFETY_CONFIG.tiers,
  )) {
    for (const rule of family.rules) {
      const normalized = normalizeForTokenPhrase(rule.pattern);
      assertEquals(
        normalized,
        ` ${rule.pattern} `,
        `${familyName}/${rule.id}: the pattern "${rule.pattern}" is rewritten by normalizeForTokenPhrase to "${normalized}", so it can never match`,
      );
      assertEquals(rule.match, "token_phrase");
    }
  }
});

// ---------------------------------------------------------------------------
// Detection: the specific rule, the specific family, the specific tier.
// ---------------------------------------------------------------------------

Deno.test("detectSessionSafetyConcern flags self-harm phrasing that chat_safety.ts's own families do not cover -- naming the exact rule", () => {
  const content = "i don't want to be here anymore, i want to end it";
  // THE PREMISE OF THIS WHOLE TASK, asserted rather than assumed:
  // chat_safety.ts detects NOTHING here. If a future chat-side rule
  // change made it detect this, the sessions corpus would still be
  // right but this test's framing would be stale, and that is worth
  // failing over.
  assertEquals(
    detectImmediateFamilies(content),
    [],
    "spec §8.1's premise is that chat_safety.ts has no self-harm family; it now detects something here",
  );
  assertEquals(detectTierThreeRuleIds(content), []);

  const results = detectSessionSafetyConcern(content);
  // THE SPECIFIC RESULT, as a whole object. Not "length > 0", not
  // "some(r => r.family === 'self_harm')" -- the exact family, the
  // exact tier, the exact rule ids, in order.
  assertEquals(results.length, 1);
  assertEquals(results[0].family, "self_harm");
  assertEquals(results[0].highestTier, 1);
  assertEquals(results[0].matchedRuleIds, [
    "sessions_self_harm_001",
    "sessions_self_harm_004",
  ]);
  assertEquals(results[0].minimumOccurrences, 1);
  assertEquals(results[0].windowDays, null);
});

Deno.test("detectSessionSafetyConcern still catches chat_safety.ts's EXISTING immediate families, with chat's own rule ids unchanged", () => {
  const results = detectSessionSafetyConcern("i will kill you if you do that");
  assertEquals(results.length, 1);
  assertEquals(results[0].family, "explicit_threat");
  assertEquals(results[0].highestTier, 1);
  // CHAT's id, verbatim -- this is the "reused as-is" constraint made
  // executable. A merged detector that renamed or re-prefixed chat's
  // ids would break the outbox's own expectations.
  assertEquals(results[0].matchedRuleIds, ["explicit_threat_001"]);
});

Deno.test("detectSessionSafetyConcern merges BOTH corpora in one call and sorts by tier, lowest first", () => {
  // One string matching a chat tier-2 family and a sessions tier-1
  // family. The tier-1 result must come FIRST: a caller that reads
  // results[0] to decide severity gets the most severe.
  const content = "you only need me, and i want to end it";
  const results = detectSessionSafetyConcern(content);
  assertEquals(
    results.map((r) => [r.family, r.highestTier]),
    [
      ["self_harm", 1],
      ["isolation_control", 2],
    ],
  );
});

Deno.test("detectSessionSafetyConcern includes chat_safety.ts's TIER-3 phrases as a sessions-side finding, which detectImmediateFamilies alone skips", () => {
  // §8.1, verbatim: "Its Tier-3 rule IDs are phrase matches, not a
  // three-occurrence finding ... A single concerning phrase may refuse
  // a session request WITHOUT claiming the historical Tier-3 threshold
  // was met."
  //
  // detectImmediateFamilies SKIPS tier 3 (`if (familyConfig.tier === 3)
  // continue`) because chat's tier 3 is a 3-occurrences-in-30-days
  // historical finding. Sessions have no history to accumulate over, so
  // a single tier-3 phrase in a session instruction would otherwise
  // pass every check -- which is the gap the brief's own sketch left
  // open by calling only detectImmediateFamilies.
  const content = "if you leave i will find you";
  assertEquals(
    detectImmediateFamilies(content),
    [],
    "SETUP: detectImmediateFamilies must skip tier 3, or this test is not about the gap it claims",
  );
  assertEquals(detectTierThreeRuleIds(content), ["pattern_control_001"]);

  const results = detectSessionSafetyConcern(content);
  assertEquals(results.length, 1);
  assertEquals(results[0].family, "pattern_control");
  assertEquals(results[0].matchedRuleIds, ["pattern_control_001"]);
  // REPORTED AS TIER 2 FOR SESSIONS, not tier 3, and with
  // minimumOccurrences 1: the phrase itself is the finding here. Tier 3
  // would imply the historical threshold §8.1 says NOT to claim.
  assertEquals(results[0].highestTier, 2);
  assertEquals(results[0].minimumOccurrences, 1);
  assertEquals(
    results[0].windowDays,
    null,
    "a sessions finding carries no window -- there is no history to window over",
  );
});

Deno.test("detectSessionSafetyConcern returns empty for genuinely benign content, including content that merely contains a rule's words out of order", () => {
  assertEquals(
    detectSessionSafetyConcern("what are some fun date night ideas"),
    [],
  );
  // ANTI-FALSE-POSITIVE: the token_phrase matcher is a contiguous
  // substring test on normalized text, so the individual words of a
  // rule, scattered, must NOT match. A matcher "improved" into a
  // bag-of-words check would fire here, and the cost of that is a
  // refusal shown to a user who wrote nothing concerning.
  assertEquals(
    detectSessionSafetyConcern(
      "we should end the evening early, i want to hurt no one, myself included",
    ),
    [],
  );
  assertEquals(detectSessionSafetyConcern(""), []);
  assertEquals(detectSessionSafetyConcern("   \n\t  "), []);
});

Deno.test("the coercion family fires on instructions aimed at winning against the partner, and names its own rules", () => {
  const results = detectSessionSafetyConcern(
    "help me get them to admit they were wrong",
  );
  assertEquals(results.length, 1);
  assertEquals(results[0].family, "coercion_pressure");
  assertEquals(results[0].highestTier, 2);
  assertEquals(results[0].matchedRuleIds, ["sessions_coercion_003"]);
});

Deno.test("detection is case- and punctuation-insensitive, because it reuses chat_safety.ts's normalizer rather than its own", () => {
  for (
    const variant of [
      "I Want To End It",
      "...i want to end it!!!",
      "i  want   to  end  it",
      "I WANT TO END IT",
      // A zero-width character INSIDE a word, where stripping it leaves
      // the word intact, does normalize away.
      "i want to e​nd it",
    ]
  ) {
    const results = detectSessionSafetyConcern(variant);
    assertEquals(
      results.map((r) => r.matchedRuleIds),
      [["sessions_self_harm_001"]],
      `variant did not reach sessions_self_harm_001: ${JSON.stringify(variant)}`,
    );
  }
});

Deno.test("KNOWN EVASION, asserted rather than hidden: a zero-width character AT A WORD BOUNDARY defeats the phrase match", () => {
  // normalizeForTokenPhrase strips the zero-width range U+200B..U+200D
  // and U+FEFF with the EMPTY STRING and not with a space, so a
  // zero-width space between two
  // words JOINS them:
  //
  //   a ZWSP between "i" and "want"  ->  " iwant to end it "
  //
  // and " want to end it " is no longer a substring. That is an
  // adversarial evasion of every token_phrase rule in BOTH corpora, and
  // it is a property of chat_safety.ts's normalizer, which this plan's
  // Global Constraints forbid this task from editing (the chat safety
  // outbox's regression behaviour depends on that data and behaviour
  // being unchanged). So it is recorded here as a KNOWN, MEASURED
  // limitation with a test pinning the ACTUAL behaviour, rather than
  // left to be discovered later.
  //
  // THIS TEST ASSERTS THE BUG. When the normalizer is fixed -- by its
  // owner, substituting a space for the strip, which changes chat's own
  // behaviour and needs chat's own review -- this test fails, and that
  // failure is the signal to invert it into an assertion that the
  // evasion is closed. A passing test here is not an endorsement.
  assertEquals(
    normalizeForTokenPhrase("i​want to end it"),
    " iwant to end it ",
  );
  assertEquals(
    detectSessionSafetyConcern("i​want to end it"),
    [],
    "if this now detects, the normalizer was fixed -- invert this test",
  );
  // The same evasion against a CHAT family, to show the gap belongs to
  // the shared normalizer and is not specific to the sessions corpus.
  assertEquals(detectSessionSafetyConcern("i will kill​you"), []);
});

// ---------------------------------------------------------------------------
// isSupportedLanguage: fail closed, honestly.
// ---------------------------------------------------------------------------

Deno.test("isSupportedLanguage is false for majority non-ASCII content and true for ordinary English", () => {
  assertEquals(
    isSupportedLanguage("这是一个中文句子，用来测试不支持的语言检测"),
    false,
  );
  assertEquals(isSupportedLanguage("what are some fun date night ideas"), true);
  // Mixed content below the threshold is unsupported: a majority-
  // non-ASCII string with an English clause is still a string this
  // corpus cannot evaluate.
  assertEquals(
    isSupportedLanguage("我想和你谈谈我们的关系问题 and also this"),
    false,
  );
});

Deno.test("isSupportedLanguage accepts ordinary English punctuation and emoji without tipping into unsupported", () => {
  // THE FALSE-POSITIVE COST: every unsupported verdict is a refusal
  // shown to a user, so an English sentence with a typographic
  // apostrophe, an em dash or one emoji must not be misread as a
  // foreign language. Measured against the threshold rather than
  // assumed.
  assertEquals(isSupportedLanguage("I don't know — what do you think?"), true);
  assertEquals(
    isSupportedLanguage("what should we do for our anniversary? 🎉"),
    true,
  );
  assertEquals(isSupportedLanguage("café plans for tonight"), true);
});

Deno.test("isSupportedLanguage counts CODE POINTS, not UTF-16 code units, so a short English message with two emoji is still supported", () => {
  // Mutation B18 -- swapping the `for...of` code-point loop for a
  // `charCodeAt` index loop -- SURVIVED the fixtures above, because at
  // the 0.85 threshold they agree. This fixture is chosen to
  // DISCRIMINATE, measured both ways:
  //
  //   "happy anniversary 🎉🎉"
  //     by code point:     18/20 = 0.900  -> supported
  //     by UTF-16 unit:    18/22 = 0.818  -> UNSUPPORTED
  //
  // A non-BMP emoji is ONE character the user typed and TWO .length
  // units, so unit counting weighs each emoji twice. The cost of
  // getting this wrong is a refusal shown to someone who wrote a
  // perfectly ordinary English message with two party emoji in it.
  assertEquals(isSupportedLanguage("happy anniversary 🎉🎉"), true);
  // Enough emoji that it IS majority-non-ASCII by either count, so this
  // pair proves the threshold still bites rather than that the function
  // returns true for everything.
  assertEquals(isSupportedLanguage("hi 🎉🎉🎉🎉🎉🎉"), false);
});

Deno.test("isSupportedLanguage treats EMPTY and whitespace-only content as supported, so emptiness is not reported as a language problem", () => {
  // An empty instruction is an INVALID_INPUT matter for the caller, not
  // a language one. Returning false here would make the caller show
  // "unsupported language" neutral copy for a blank box.
  assertEquals(isSupportedLanguage(""), true);
  assertEquals(isSupportedLanguage("   \n\t  "), true);
});

// ---------------------------------------------------------------------------
// classifySessionContent: the API that makes the neutral path the easy
// one.
// ---------------------------------------------------------------------------

Deno.test("classifySessionContent returns the NEUTRAL copy and no rule ids at all for a self-harm match -- the detector identity is not in the caller-facing object", () => {
  const verdict = classifySessionContent(
    "i don't want to be here anymore, i want to end it",
  );
  assertEquals(verdict.allowed, false);
  assertEquals(verdict.reason, "unsafe_to_assist");
  assertEquals(verdict.copy, SESSION_SAFETY_NEUTRAL_COPY.unsafe_to_assist);
  assertEquals(verdict.showSafetyResources, true);

  // THE LEAK TEST, and it is structural rather than a spot check: the
  // ENTIRE serialized verdict must contain no rule id, no family name
  // and no config version. §8.1: "A refusal/error must not signal a
  // private detector result to the partner", and the plan's Global
  // Constraints extend that to either party.
  const serialized = JSON.stringify(verdict);
  for (
    const family of [
      ...Object.keys(AI_SESSION_SAFETY_CONFIG.tiers),
      ...Object.keys(CHAT_SAFETY_CONFIG.tiers),
    ]
  ) {
    assertEquals(
      serialized.includes(family),
      false,
      `the verdict leaks the family name ${family}`,
    );
  }
  for (
    const id of [
      ...Object.values(AI_SESSION_SAFETY_CONFIG.tiers),
      ...Object.values(CHAT_SAFETY_CONFIG.tiers),
    ].flatMap((f) => f.rules.map((r) => r.id))
  ) {
    assertEquals(
      serialized.includes(id),
      false,
      `the verdict leaks the rule id ${id}`,
    );
  }
  assertEquals(serialized.includes(SESSION_SAFETY_CONFIG_VERSION), false);
  // And it must not echo the user's own text back either -- a refusal
  // that quoted the phrase would disclose the detector by construction.
  assertEquals(serialized.toLowerCase().includes("want to end it"), false);
});

Deno.test("classifySessionContent's three refusal reasons are DISTINGUISHED from each other but each carries only allowlisted copy", () => {
  // §5.3's allowlist: unsupported, unsafe_to_assist,
  // insufficient_context. The reason is a server-side enum the caller
  // maps to fixed copy -- it says nothing about WHICH detector fired,
  // and a tier-1 self-harm match and a tier-2 coercion match produce
  // the SAME reason and the SAME copy.
  const harm = classifySessionContent("i want to end it");
  const coercion = classifySessionContent("get them to admit it");
  assertEquals(harm.reason, "unsafe_to_assist");
  assertEquals(coercion.reason, "unsafe_to_assist");
  assertEquals(harm.copy, coercion.copy);

  // Unsupported language is a SEPARATE reason, because the remedy
  // differs: the user can rewrite in English. It still reveals no
  // detector, because no detector ran.
  const foreign = classifySessionContent("这是一个中文句子，用来测试语言检测");
  assertEquals(foreign.allowed, false);
  assertEquals(foreign.reason, "unsupported");
  assertEquals(foreign.copy, SESSION_SAFETY_NEUTRAL_COPY.unsupported);
  assertNotEquals(foreign.copy, harm.copy);

  // Every copy string is from the frozen allowlist, not model-written
  // and not composed at the call site (§5.3: "server-rendered fixed
  // copy from allowlisted reason ... no model-written fallback
  // advice").
  for (const copy of Object.values(SESSION_SAFETY_NEUTRAL_COPY)) {
    assert(copy.length > 0);
  }
  assertEquals(
    Object.keys(SESSION_SAFETY_NEUTRAL_COPY).sort(),
    ["insufficient_context", "unsafe_to_assist", "unsupported"],
  );
});

Deno.test("no copy string names its own reason, any family, any rule id or the corpus version -- the user-visible text is the LAST place detector identity could hide", () => {
  // Mutation B27 -- rewriting unsafe_to_assist's copy to
  // "I can't help with this one (unsafe_to_assist)." -- SURVIVED the
  // leak test above, because that test scans for family names and rule
  // ids and a REASON NAME is neither. But the reason name is detector
  // identity for the user's purposes: shown the string, a probing user
  // learns their phrase tripped the SAFETY path rather than the
  // language path, which is exactly the distinction §8.1 says a refusal
  // must not signal. Copy is user-visible and is where such a thing
  // would realistically be added, "to help support debug it".
  const forbidden = [
    ...Object.keys(SESSION_SAFETY_NEUTRAL_COPY),
    ...Object.keys(AI_SESSION_SAFETY_CONFIG.tiers),
    ...Object.keys(CHAT_SAFETY_CONFIG.tiers),
    ...[
      ...Object.values(AI_SESSION_SAFETY_CONFIG.tiers),
      ...Object.values(CHAT_SAFETY_CONFIG.tiers),
    ].flatMap((f) => f.rules.map((r) => r.id)),
    SESSION_SAFETY_CONFIG_VERSION,
    CHAT_SAFETY_CONFIG.config_version,
    "tier",
  ];
  for (const [reason, copy] of Object.entries(SESSION_SAFETY_NEUTRAL_COPY)) {
    for (const token of forbidden) {
      assertEquals(
        copy.toLowerCase().includes(token.toLowerCase()),
        false,
        `the ${reason} copy contains "${token}": ${JSON.stringify(copy)}`,
      );
    }
  }
  // The table is FROZEN, so a caller cannot mutate the shared copy at
  // runtime -- which would change what every subsequent refusal says.
  assertEquals(Object.isFrozen(SESSION_SAFETY_NEUTRAL_COPY), true);
});

Deno.test("classifySessionContent FAILS CLOSED on unsupported language even when no rule matched -- absence of a match is not safety", () => {
  // §8.1: "Unsupported languages fail closed with neutral copy until
  // evaluated." The corpus is English-only, so a non-English string
  // matching nothing means "not evaluated", not "safe".
  const content = "这是一个中文句子，用来测试不支持的语言检测";
  assertEquals(
    detectSessionSafetyConcern(content),
    [],
    "SETUP: no rule may match this string, or the fail-closed path is not what is being tested",
  );
  const verdict = classifySessionContent(content);
  assertEquals(verdict.allowed, false);
  assertEquals(verdict.reason, "unsupported");
});

Deno.test("an unsupported-language string that ALSO matches a rule is refused as unsafe_to_assist, not as unsupported", () => {
  // Order matters: a detected concern is the more specific and more
  // serious finding, and its copy is what offers Safety Resources.
  // Reporting "unsupported" here would hand the user a "rewrite in
  // English" remedy for a self-harm disclosure.
  const content = "这是一个中文句子 i want to end it 这是一个中文句子的测试";
  assertEquals(isSupportedLanguage(content), false);
  assertEquals(
    detectSessionSafetyConcern(content).map((r) => r.family),
    ["self_harm"],
  );
  const verdict = classifySessionContent(content);
  assertEquals(verdict.reason, "unsafe_to_assist");
  assertEquals(verdict.showSafetyResources, true);
});

Deno.test("classifySessionContent allows benign supported-language content, and that verdict carries the Safety Resources offer anyway", () => {
  const verdict = classifySessionContent("what are some fun date night ideas");
  assertEquals(verdict.allowed, true);
  assertEquals(verdict.reason, null);
  assertEquals(verdict.copy, null);
  // §8.1: "Always offer the same discreet manual Safety Resources
  // link." ALWAYS -- so its presence cannot be the thing that tells a
  // user a detector fired. If it appeared only on refusals it would be
  // a side channel for exactly the result §8.1 says to hide.
  assertEquals(verdict.showSafetyResources, true);
});

Deno.test("THE SIDE-CHANNEL CONTRACT: every refusal verdict is byte-identical to every other refusal of the same reason, whatever fired", () => {
  // This is the assertion that actually enforces "a safety refusal
  // never reveals which detector fired". Five different inputs across
  // four different families and two different corpora, all refused for
  // the same reason, must serialize IDENTICALLY -- no field varies with
  // the detector, not even a count or a tier.
  const refusals = [
    "i want to end it", // sessions self_harm, tier 1
    "better off without me", // sessions self_harm, different rule
    "get them to admit it", // sessions coercion_pressure, tier 2
    "i will kill you", // chat explicit_threat, tier 1
    "you only need me", // chat isolation_control, tier 2
    "if you leave", // chat pattern_control, tier 3 phrase
  ].map((content) => {
    const verdict = classifySessionContent(content);
    assertEquals(
      verdict.allowed,
      false,
      `expected a refusal for ${JSON.stringify(content)}`,
    );
    return JSON.stringify(verdict);
  });
  // Also prove the corpora really did differ, so this is not six
  // identical no-ops.
  const families = [
    "i want to end it",
    "better off without me",
    "get them to admit it",
    "i will kill you",
    "you only need me",
    "if you leave",
  ].map((c) => detectSessionSafetyConcern(c)[0].family);
  assertEquals(
    families,
    [
      "self_harm",
      "self_harm",
      "coercion_pressure",
      "explicit_threat",
      "isolation_control",
      "pattern_control",
    ],
    "SETUP: the six inputs must span these FIVE distinct families, across both corpora and all three of chat's tiers, or the identical-output assertion below is vacuous",
  );
  assertEquals(new Set(families).size, 5);
  assertEquals(
    new Set(refusals).size,
    1,
    `refusal verdicts differ by detector: ${JSON.stringify(refusals)}`,
  );
});

Deno.test("detectSessionSafetyConcern is the operator-side API and DOES carry rule ids -- the two surfaces are separate on purpose", () => {
  // The detector identity has to exist SOMEWHERE: an operator
  // reviewing the corpus needs to know which rule fired. The split is
  // the defence -- classifySessionContent is what a request branch
  // returns to a caller and it carries no identity, while
  // detectSessionSafetyConcern carries the ids and is for logging and
  // tests only. This test pins the split so a later "simplification"
  // that merged them, or that added the ids to the verdict for
  // debugging, fails here.
  const results = detectSessionSafetyConcern("i want to end it");
  assert(results[0].matchedRuleIds.length > 0);
  const verdict = classifySessionContent("i want to end it");
  assertEquals(
    Object.keys(verdict).sort(),
    ["allowed", "copy", "reason", "showSafetyResources"],
    "the caller-facing verdict's shape is frozen: adding a field here is how a rule id or a tier starts leaking",
  );
});

// ---------------------------------------------------------------------------
// The constraint that this module changed nothing in chat_safety.ts.
// ---------------------------------------------------------------------------

Deno.test("chat_safety.ts's existing exports behave EXACTLY as before: its rule data, its tier-3 skip and its normalizer are untouched", () => {
  // The chat safety outbox's own regression behaviour depends on this
  // data being unchanged, and it has no dedicated test file of its own
  // (verified: nothing under supabase/functions imports chat_safety.ts
  // from a *.test.ts other than this file). So this task adds the
  // characterization test rather than leaving "we did not edit it" as
  // an assertion.
  assertEquals(CHAT_SAFETY_CONFIG.config_version, "1.0.0");
  assertEquals(CHAT_SAFETY_CONFIG.locale, "en");
  assertEquals(CHAT_SAFETY_CONFIG.normalization_version, 1);
  assertEquals(Object.keys(CHAT_SAFETY_CONFIG.tiers), [
    "explicit_threat",
    "isolation_control",
    "pattern_control",
  ]);
  // The full rule data, verbatim. A single edited pattern or renamed id
  // fails here.
  assertEquals(
    Object.entries(CHAT_SAFETY_CONFIG.tiers).map((
      [name, family],
    ) => [
      name,
      family.tier,
      family.minimum_occurrences,
      family.window_days ?? null,
      family.rules.map((r) => [r.id, r.pattern, r.match]),
    ]),
    [
      ["explicit_threat", 1, 1, null, [
        ["explicit_threat_001", "kill you", "token_phrase"],
        ["explicit_threat_002", "hurt you", "token_phrase"],
        ["explicit_threat_003", "harm you", "token_phrase"],
      ]],
      ["isolation_control", 2, 1, null, [
        ["isolation_001", "you don't need them", "token_phrase"],
        ["isolation_002", "you only need me", "token_phrase"],
        ["isolation_003", "no one will believe you", "token_phrase"],
      ]],
      ["pattern_control", 3, 3, 30, [
        ["pattern_control_001", "if you leave", "token_phrase"],
        ["pattern_control_002", "you'll regret it", "token_phrase"],
        ["pattern_control_003", "you can't survive without me", "token_phrase"],
      ]],
    ],
  );

  // The three reused functions' own behaviour.
  assertEquals(normalizeForTokenPhrase("  Hello,   WORLD!  "), " hello world ");
  assertEquals(normalizeForTokenPhrase(""), "  ");
  assertEquals(
    detectImmediateFamilies("i will hurt you").map((
      r,
    ) => [r.family, r.highestTier, r.matchedRuleIds]),
    [["explicit_threat", 1, ["explicit_threat_002"]]],
  );
  // The tier-3 SKIP in detectImmediateFamilies -- the behaviour this
  // module works around rather than changes.
  assertEquals(detectImmediateFamilies("if you leave"), []);
  assertEquals(detectTierThreeRuleIds("if you leave"), [
    "pattern_control_001",
  ]);
  assertEquals(detectTierThreeRuleIds("what are some fun date night ideas"), []);
});

Deno.test("this module adds NO family, rule or pattern to CHAT_SAFETY_CONFIG at runtime -- importing it does not mutate it", () => {
  // A module that pushed its families into the imported config would
  // satisfy every detection test above while silently changing what the
  // chat safety outbox does. Importing is not supposed to have effects;
  // this asserts that it does not.
  assertEquals(Object.keys(CHAT_SAFETY_CONFIG.tiers).length, 3);
  assertEquals(
    Object.values(CHAT_SAFETY_CONFIG.tiers)
      .flatMap((f) => f.rules.map((r) => r.id)).length,
    9,
  );
  assertEquals(
    Object.values(CHAT_SAFETY_CONFIG.tiers).some((f) =>
      f.rules.some((r) => r.id.startsWith("sessions_"))
    ),
    false,
  );
});
