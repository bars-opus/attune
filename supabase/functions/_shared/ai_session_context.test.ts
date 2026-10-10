// ai_session_context.ts tests. Spec §4.2, §4.3, §11 item 7.
//
// Run: deno test --allow-net --allow-env --allow-read --allow-sys \
//        supabase/functions/_shared/ai_session_context.test.ts
//
// Requires: scripts/local_pg_setup.sh --no-tests.
//
// Every assertion names a SPECIFIC expected value. In particular the
// determinism tests do NOT merely assert "two digests match": a
// function returning a constant would pass that. They pair each
// equality claim with a change that MUST move the digest, and they
// assert the pre-image format directly, so a digest that is stable
// because it ignores its inputs fails.

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ApprovalDigestInput,
  buildDigestPreimage,
  canonicalTimestamp,
  civilDayStartUtc,
  clipToScalars,
  computeApprovalDigest,
  isValidUtcOffsetMinutes,
  PER_MESSAGE_CHAR_CAP,
  scalarLength,
  selectSharedWindow,
  selectWindowFromRows,
  TRUNCATION_MARKER,
  WINDOW_ROW_CAP,
  WINDOW_TOTAL_CHAR_CAP,
} from "./ai_session_context.ts";
import {
  makeServiceRoleClient,
  serviceRoleQuery,
} from "./test_support/pg_rls_client.ts";

// Fixture ids are c2*, distinct from Task 1's c1* set. Phone numbers
// +1555200200x -- swept against the whole suite before use (users.phone
// is UNIQUE and an ON CONFLICT DO NOTHING insert hides a collision).
const REL = "c2000000-0000-0000-0000-000000000001";
const USER_A = "c2000000-0000-0000-0000-00000000000a";
const USER_B = "c2000000-0000-0000-0000-00000000000b";

async function resetFixtures(): Promise<void> {
  await serviceRoleQuery(
    `DELETE FROM public.messages WHERE relationship_id = $1`,
    [REL],
  );
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [
    REL,
  ]);
  await serviceRoleQuery(`DELETE FROM public.users WHERE id IN ($1, $2)`, [
    USER_A,
    USER_B,
  ]);
  await serviceRoleQuery(`DELETE FROM auth.users WHERE id IN ($1, $2)`, [
    USER_A,
    USER_B,
  ]);
  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4)`,
    [USER_A, "win_a@t.test", USER_B, "win_b@t.test"],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
       ($1, '+15552002001', 'WinA'), ($2, '+15552002002', 'WinB')`,
    [USER_A, USER_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status)
     VALUES ($1, $2, $3, 'active')`,
    [REL, USER_A, USER_B],
  );
}

async function insertMessage(
  content: string,
  createdAt: Date,
  overrides: Record<string, unknown> = {},
): Promise<string> {
  const id = crypto.randomUUID();
  await serviceRoleQuery(
    `INSERT INTO public.messages
       (id, relationship_id, sender_id, client_message_id, content, source,
        created_at, is_system_notice, message_origin, media_url, game_session_id)
     VALUES ($1, $2, $3, $4, $5, 'native', $6, $7, $8, $9, $10)`,
    [
      id,
      REL,
      USER_A,
      crypto.randomUUID(),
      content,
      createdAt.toISOString(),
      overrides.is_system_notice ?? false,
      overrides.message_origin ?? "user",
      overrides.media_url ?? null,
      overrides.game_session_id ?? null,
    ],
  );
  return id;
}

/// A fully-populated digest input. Each test mutates exactly one field
/// from this baseline so a moved digest can only be attributed to that
/// field.
function baseDigestInput(): ApprovalDigestInput {
  return {
    sessionId: "c2000000-0000-0000-0000-0000000000f1",
    policyVersion: "2026-09-22-sessions-v1",
    kind: "ideas",
    visibility: "shared",
    participants: [USER_A, USER_B],
    sources: [
      { messageId: "aaaaaaaa-0000-0000-0000-000000000001", sourceVersion: "2026-10-10T08:00:00.000Z" },
      { messageId: "aaaaaaaa-0000-0000-0000-000000000002", sourceVersion: "2026-10-10T09:00:00.000Z" },
    ],
    displayedSnippets: ["first snippet", "second snippet"],
    utcOffsetMinutes: 60,
    civilDayStartUtc: "2026-10-09T23:00:00.000Z",
    contextRevision: 1,
  };
}

// ===========================================================================
// §4.3 determinism -- the constraint that makes a shared session able to
// activate at all.
// ===========================================================================

Deno.test("THE determinism contract: two digest computations at different wall-clock times are byte-identical", async () => {
  const input = baseDigestInput();

  const first = await computeApprovalDigest(input);
  const tBefore = Date.now();
  // Burn real wall-clock time between the two calls. Spec §4.3's two
  // approvals happen minutes or hours apart; if anything in the digest
  // path read the clock, this is where it would show.
  while (Date.now() - tBefore < 1100) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  // Also hand the SECOND call a structurally-equal but distinct object,
  // with the participant array in the opposite order -- the two
  // partners' calls have no reason to enumerate members identically.
  const second = await computeApprovalDigest({
    ...baseDigestInput(),
    participants: [USER_B, USER_A],
  });

  assert(
    Date.now() - tBefore >= 1000,
    "the test must actually span wall-clock time, or it proves nothing",
  );
  assertEquals(
    first,
    second,
    "two approvals of the same snapshot at different times MUST produce the identical digest, or activate_ai_session's count(DISTINCT digest)=1 check can never pass",
  );
});

Deno.test("the digest is a real SHA-256 of the documented pre-image, not a constant", async () => {
  const input = baseDigestInput();
  const preimage = buildDigestPreimage(input);

  const expected = Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(preimage)),
    ),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");

  assertEquals(await computeApprovalDigest(input), expected);
  assertEquals((await computeApprovalDigest(input)).length, 64);
});

Deno.test("EVERY digest input changes the digest -- field by field, one at a time", async () => {
  const base = await computeApprovalDigest(baseDigestInput());

  // Each entry is a single-field mutation. Asserting them one at a time
  // means a field the pre-image forgot to include names ITSELF in the
  // failure, instead of hiding behind a sibling that did change.
  const mutations: Record<string, ApprovalDigestInput> = {
    sessionId: { ...baseDigestInput(), sessionId: "c2000000-0000-0000-0000-0000000000f2" },
    policyVersion: { ...baseDigestInput(), policyVersion: "2026-09-22-sessions-v2" },
    kind: { ...baseDigestInput(), kind: "nearby" },
    visibility: { ...baseDigestInput(), visibility: "private" },
    contextRevision: { ...baseDigestInput(), contextRevision: 2 },
    utcOffsetMinutes: { ...baseDigestInput(), utcOffsetMinutes: -300 },
    civilDayStartUtc: { ...baseDigestInput(), civilDayStartUtc: "2026-10-10T23:00:00.000Z" },
    "a snippet's text": {
      ...baseDigestInput(),
      displayedSnippets: ["first snippet", "CHANGED snippet"],
    },
    "snippet ORDER (display order is part of the approval)": {
      ...baseDigestInput(),
      displayedSnippets: ["second snippet", "first snippet"],
    },
    "a dropped snippet": {
      ...baseDigestInput(),
      displayedSnippets: ["first snippet"],
    },
    "a source's version (an EDIT to an approved message)": {
      ...baseDigestInput(),
      sources: [
        { messageId: "aaaaaaaa-0000-0000-0000-000000000001", sourceVersion: "2026-10-10T08:00:00.001Z" },
        { messageId: "aaaaaaaa-0000-0000-0000-000000000002", sourceVersion: "2026-10-10T09:00:00.000Z" },
      ],
    },
    "a source's message id": {
      ...baseDigestInput(),
      sources: [
        { messageId: "aaaaaaaa-0000-0000-0000-00000000000f", sourceVersion: "2026-10-10T08:00:00.000Z" },
        { messageId: "aaaaaaaa-0000-0000-0000-000000000002", sourceVersion: "2026-10-10T09:00:00.000Z" },
      ],
    },
    "two sources SWAPPING versions (pairing must be bound)": {
      ...baseDigestInput(),
      sources: [
        { messageId: "aaaaaaaa-0000-0000-0000-000000000001", sourceVersion: "2026-10-10T09:00:00.000Z" },
        { messageId: "aaaaaaaa-0000-0000-0000-000000000002", sourceVersion: "2026-10-10T08:00:00.000Z" },
      ],
    },
    "an EXTRA participant": {
      ...baseDigestInput(),
      participants: [USER_A, USER_B, "c2000000-0000-0000-0000-00000000000c"],
    },
    "a DIFFERENT participant": {
      ...baseDigestInput(),
      participants: [USER_A, "c2000000-0000-0000-0000-00000000000c"],
    },
  };

  for (const [field, mutated] of Object.entries(mutations)) {
    assertNotEquals(
      await computeApprovalDigest(mutated),
      base,
      `changing ${field} MUST change the digest -- it is not bound into the pre-image`,
    );
  }
});

Deno.test("the pre-image encoding is injective: a moved field boundary cannot be hidden", async () => {
  // Without length prefixes, (["ab"],["c"]) and (["a"],["bc"]) share a
  // concatenation. This is the classic length-extension-shaped bug in a
  // hand-rolled canonical form, and the reason buildDigestPreimage
  // prefixes every field with its scalar length.
  const left = await computeApprovalDigest({
    ...baseDigestInput(),
    displayedSnippets: ["ab", "c"],
  });
  const right = await computeApprovalDigest({
    ...baseDigestInput(),
    displayedSnippets: ["a", "bc"],
  });
  assertNotEquals(
    left,
    right,
    "a snippet boundary moved without changing the digest -- the pre-image is ambiguous",
  );

  // And the prefix is really there, with the SCALAR length.
  const preimage = buildDigestPreimage({
    ...baseDigestInput(),
    displayedSnippets: ["héllo 👋"],
  });
  assertEquals(scalarLength("héllo 👋"), 7);
  assert(
    preimage.includes("snippet[0]=7:héllo 👋"),
    `pre-image must length-prefix each field in SCALARS; got:\n${preimage}`,
  );
});

Deno.test("the pre-image is versioned, so two code versions cannot silently agree on a differently-shaped digest", () => {
  const preimage = buildDigestPreimage(baseDigestInput());
  assertEquals(preimage.split("\n")[0], "ai-session-digest-v1");
});

// ===========================================================================
// §4.2 civil day -- the other determinism trap.
// ===========================================================================

Deno.test("the civil day is computed in UTC, so the HOST's timezone cannot change it", () => {
  // 2026-10-10T00:30:00Z with offset +60 is 01:30 local on the 10th, so
  // the civil day began at 2026-10-09T23:00:00Z.
  const now = new Date("2026-10-10T00:30:00.000Z");
  assertEquals(
    civilDayStartUtc(now, 60).toISOString(),
    "2026-10-09T23:00:00.000Z",
  );

  // Same instant, offset -300 (UTC-5): local time is 19:30 on the 9th,
  // so the civil day began at 2026-10-09T05:00:00Z.
  assertEquals(
    civilDayStartUtc(now, -300).toISOString(),
    "2026-10-09T05:00:00.000Z",
  );

  // The extremes §4.1 permits.
  assertEquals(
    civilDayStartUtc(now, 840).toISOString(),
    "2026-10-09T10:00:00.000Z",
  );
  // 00:30Z at UTC-14 is 10:30 local on the 9th, so the civil day began
  // 2026-10-09T00:00 local == 2026-10-09T14:00Z.
  assertEquals(
    civilDayStartUtc(now, -840).toISOString(),
    "2026-10-09T14:00:00.000Z",
  );

  // THE HOST-TZ ASSERTION.
  //
  // The expectations above are absolute UTC instants, but they are NOT
  // on their own sufficient: I mutation-tested the UTC getters to their
  // local counterparts and the whole file still passed, under TZ=UTC
  // AND TZ=Europe/Berlin. The reason is that the two forms agree unless
  // the HOST's own offset pushes the shifted instant's DATE across a
  // boundary, which none of the cases above happened to do. Measured
  // divergences for the local-getter form:
  //
  //   TZ=America/New_York   now=2026-10-10T00:30Z offset=0
  //     utc getters   -> 2026-10-10T00:00Z   (correct)
  //     local getters -> 2026-10-09T00:00Z   (a whole day early)
  //   TZ=Pacific/Kiritimati now=2026-10-10T23:00Z offset=+840
  //     utc getters   -> 2026-10-10T10:00Z
  //     local getters -> 2026-10-11T10:00Z
  //
  // So the assertion must hold the property independently of the
  // runner's TZ, rather than hoping the runner is one that exposes it.
  // Below: compute the reference boundary from first principles --
  // floor the offset-shifted epoch to a whole number of days, which
  // involves no Date component getter of EITHER flavour and so cannot
  // consult a timezone at all -- and sweep every half hour of a full
  // day against every offset extreme. A local-getter implementation
  // diverges from this reference on any host whose offset is non-zero.
  const DAY_MS = 86_400_000;
  for (const offset of [-840, -720, -300, -60, 0, 60, 330, 720, 840]) {
    for (let halfHour = 0; halfHour < 48; halfHour++) {
      const instant = new Date(Date.UTC(2026, 9, 10) + halfHour * 1_800_000);
      const shiftedEpoch = instant.getTime() + offset * 60_000;
      const expected = Math.floor(shiftedEpoch / DAY_MS) * DAY_MS -
        offset * 60_000;
      assertEquals(
        civilDayStartUtc(instant, offset).getTime(),
        expected,
        `offset ${offset}, ${instant.toISOString()}: the civil-day boundary must be a pure function of (now, offset). A getFullYear/getMonth/getDate implementation fails this on any host not set to UTC (TZ=${
          Intl.DateTimeFormat().resolvedOptions().timeZone
        } here).`,
      );
    }
  }

  // And the algebraic property: one day later is exactly 24h later, for
  // every offset, with no DST-shaped discontinuity.
  for (const offset of [-840, -300, -60, 0, 60, 330, 840]) {
    const a = civilDayStartUtc(new Date("2026-03-28T12:00:00.000Z"), offset);
    const b = civilDayStartUtc(new Date("2026-03-29T12:00:00.000Z"), offset);
    assertEquals(
      b.getTime() - a.getTime(),
      86_400_000,
      `offset ${offset}: a civil-day boundary must advance exactly 24h across a date change`,
    );
  }
});
Deno.test("civilDayStartUtc is a pure function of (now, offset) -- repeated calls over real elapsed time agree", async () => {
  const now = new Date("2026-10-10T00:30:00.000Z");
  const first = civilDayStartUtc(now, 330).toISOString();
  await new Promise((resolve) => setTimeout(resolve, 1100));
  assertEquals(civilDayStartUtc(now, 330).toISOString(), first);
});

Deno.test("an out-of-range UTC offset is rejected, never clamped", async () => {
  assertEquals(isValidUtcOffsetMinutes(840), true);
  assertEquals(isValidUtcOffsetMinutes(-840), true);
  assertEquals(isValidUtcOffsetMinutes(841), false);
  assertEquals(isValidUtcOffsetMinutes(-841), false);
  assertEquals(isValidUtcOffsetMinutes(60.5), false);
  assertEquals(isValidUtcOffsetMinutes(NaN), false);
  assertEquals(isValidUtcOffsetMinutes("60"), false);

  const service = await makeServiceRoleClient();
  // A clamped offset would compute a different civil day than the
  // client displayed, so §4.2's "the DISPLAYED, validated offset"
  // requires a refusal.
  let threw: unknown = null;
  try {
    await selectSharedWindow(service as never, REL, null, 900, new Date());
  } catch (err) {
    threw = err;
  }
  assert(threw instanceof RangeError, `expected RangeError, got ${threw}`);
});

// ===========================================================================
// Timestamp canonicalization.
// ===========================================================================

Deno.test("canonicalTimestamp collapses every rendering of one stored instant to one string", () => {
  // The three renderings this code actually receives (see the module
  // header). Microsecond precision from Postgres/PostgREST, millisecond
  // from the Deno pg driver's Date round-trip, and a +00:00 offset form.
  const micro = "2026-10-10T21:27:52.511438+00:00";
  const milliZ = "2026-10-10T21:27:52.511Z";
  const offsetForm = "2026-10-10T22:27:52.511+01:00";

  assertEquals(canonicalTimestamp(micro), "2026-10-10T21:27:52.511Z");
  assertEquals(canonicalTimestamp(milliZ), "2026-10-10T21:27:52.511Z");
  assertEquals(canonicalTimestamp(offsetForm), "2026-10-10T21:27:52.511Z");

  // And the consequence that matters: approvals computed from the two
  // different renderings agree.
  assertEquals(canonicalTimestamp(micro), canonicalTimestamp(milliZ));

  // A genuinely different instant still differs.
  assertNotEquals(
    canonicalTimestamp("2026-10-10T21:27:52.512438+00:00"),
    canonicalTimestamp(micro),
  );

  assertEquals(canonicalTimestamp("not a timestamp"), null);
});

// ===========================================================================
// §4.2 clipping and budget -- the pure core.
// ===========================================================================

Deno.test("per-message clipping counts the marker INSIDE the 600-scalar cap", () => {
  const long = "x".repeat(1000);
  const { content, truncated } = clipToScalars(long, PER_MESSAGE_CHAR_CAP);
  assertEquals(truncated, true);
  assertEquals(
    scalarLength(content),
    PER_MESSAGE_CHAR_CAP,
    "a clipped message must be EXACTLY the cap, marker included -- not cap + marker",
  );
  assert(content.endsWith(TRUNCATION_MARKER));

  // Exactly at the cap: untouched, no marker.
  const exact = "y".repeat(PER_MESSAGE_CHAR_CAP);
  assertEquals(clipToScalars(exact, PER_MESSAGE_CHAR_CAP), {
    content: exact,
    truncated: false,
  });
});

Deno.test("clipping counts Unicode SCALARS, not UTF-16 units, and never splits a surrogate pair", () => {
  // 10 astral emoji = 10 scalars but 20 UTF-16 code units. §4.1:
  // "identical Unicode-scalar counting ... not JavaScript UTF-16
  // length".
  const emoji = "👋".repeat(10);
  assertEquals(emoji.length, 20, "precondition: UTF-16 length is 20");
  assertEquals(scalarLength(emoji), 10, "precondition: scalar length is 10");

  // Cap of 15 scalars against 20 emoji scalars: the marker is 12
  // scalars, so exactly 3 emoji survive.
  const longer = "👋".repeat(20);
  assertEquals(scalarLength(longer), 20);
  const { content, truncated } = clipToScalars(longer, 15);
  assertEquals(truncated, true);
  assertEquals(scalarLength(content), 15);
  assertEquals(content, "👋👋👋" + TRUNCATION_MARKER);

  // Under the cap: untouched.
  assertEquals(clipToScalars(emoji, 15), { content: emoji, truncated: false });

  // The decisive assertion: no lone surrogate anywhere. A code-unit
  // slice at an odd index would leave one, which §4.1 forbids outright
  // ("Reject unpaired surrogates").
  for (const char of content) {
    const code = char.codePointAt(0)!;
    assert(
      code < 0xd800 || code > 0xdfff,
      `clipped output contains a lone surrogate U+${code.toString(16)}`,
    );
  }
});

Deno.test("the window clips the OLDEST fitting entry rather than dropping it whole", () => {
  // Six messages of 500 scalars = 3,000 raw, over the 2,400 budget.
  // Newest-first, as the DESC query delivers them.
  const rows = Array.from({ length: 6 }, (_, i) => ({
    id: `00000000-0000-0000-0000-00000000000${i}`,
    created_at: new Date(Date.UTC(2026, 9, 10, 12, 6 - i)).toISOString(),
    edited_at: null,
    content: "x".repeat(500),
    deleted_at: null,
    is_system_notice: false,
    message_origin: null,
    media_url: null,
    game_session_id: null,
  }));

  const window = selectWindowFromRows({ rows, excludeMessageId: null });

  // 4 full messages = 2,000, leaving 400 for the fifth -- which must be
  // CLIPPED IN, not dropped. A "drop whole" implementation returns 4
  // entries totalling 2,000.
  assertEquals(window.length, 5, "the partially-fitting entry must be clipped in, not dropped");
  const total = window.reduce((sum, m) => sum + scalarLength(m.content), 0);
  assertEquals(total, WINDOW_TOTAL_CHAR_CAP, "the budget must be used exactly, not under-filled");

  // Chronological for display (§4.2), so the clipped one is FIRST.
  for (let i = 1; i < window.length; i++) {
    assert(
      window[i].createdAt >= window[i - 1].createdAt,
      "window must be ordered chronologically for display",
    );
  }
  assertEquals(window[0].truncated, true, "the OLDEST included entry is the clipped one");
  assertEquals(scalarLength(window[0].content), 400);
  assertEquals(window[0].content.endsWith(TRUNCATION_MARKER), true);
  for (let i = 1; i < window.length; i++) {
    assertEquals(window[i].truncated, false);
  }
});

Deno.test("the window never exceeds six rows even when far more are eligible", () => {
  const rows = Array.from({ length: 20 }, (_, i) => ({
    id: `00000000-0000-0000-0000-0000000000${String(i).padStart(2, "0")}`,
    created_at: new Date(Date.UTC(2026, 9, 10, 12, 20 - i)).toISOString(),
    edited_at: null,
    content: "short",
    deleted_at: null,
    is_system_notice: false,
    message_origin: null,
    media_url: null,
    game_session_id: null,
  }));
  assertEquals(
    selectWindowFromRows({ rows, excludeMessageId: null }).length,
    WINDOW_ROW_CAP,
  );
});

Deno.test("the six-row cap applies to ELIGIBLE rows, so ineligible rows cannot starve the window", () => {
  // Six ineligible rows NEWER than three eligible ones. If the cap were
  // applied before the eligibility filter, the window would be empty.
  const ineligible = Array.from({ length: 6 }, (_, i) => ({
    id: `00000000-0000-0000-0000-0000000000f${i}`,
    created_at: new Date(Date.UTC(2026, 9, 10, 13, i)).toISOString(),
    edited_at: null,
    content: "system",
    deleted_at: null,
    is_system_notice: true,
    message_origin: null,
    media_url: null,
    game_session_id: null,
  }));
  const eligible = Array.from({ length: 3 }, (_, i) => ({
    id: `00000000-0000-0000-0000-0000000000e${i}`,
    created_at: new Date(Date.UTC(2026, 9, 10, 12, i)).toISOString(),
    edited_at: null,
    content: `real ${i}`,
    deleted_at: null,
    is_system_notice: false,
    message_origin: null,
    media_url: null,
    game_session_id: null,
  }));
  // Newest first, as the query delivers.
  const rows = [...ineligible.reverse(), ...eligible.reverse()];

  const window = selectWindowFromRows({ rows, excludeMessageId: null });
  assertEquals(window.length, 3);
  assertEquals(window.map((m) => m.content), ["real 0", "real 1", "real 2"]);
});

Deno.test("selectWindowFromRows is a pure function of the ROW SET -- shuffling tied timestamps cannot change its output", () => {
  // Two messages sharing a created_at: millisecond canonicalization
  // makes this reachable from microsecond-distinct stored values.
  const rows = [
    {
      id: "00000000-0000-0000-0000-0000000000b2",
      created_at: "2026-10-10T12:00:00.000Z",
      edited_at: null,
      content: "beta",
      deleted_at: null,
      is_system_notice: false,
      message_origin: null,
      media_url: null,
      game_session_id: null,
    },
    {
      id: "00000000-0000-0000-0000-0000000000b1",
      created_at: "2026-10-10T12:00:00.000Z",
      edited_at: null,
      content: "alpha",
      deleted_at: null,
      is_system_notice: false,
      message_origin: null,
      media_url: null,
      game_session_id: null,
    },
  ];

  const forward = selectWindowFromRows({ rows, excludeMessageId: null });
  const reversed = selectWindowFromRows({
    rows: [...rows].reverse(),
    excludeMessageId: null,
  });
  assertEquals(
    forward.map((m) => m.messageId),
    reversed.map((m) => m.messageId),
    "the display order of timestamp-tied messages must be decided by the id tiebreak, not by the input order -- otherwise the two partners' digests depend on row arrival order",
  );
  // And it is the id-ascending order specifically.
  assertEquals(forward.map((m) => m.content), ["alpha", "beta"]);
});

Deno.test("every §4.2 exclusion is enforced, each one named", () => {
  const base = {
    created_at: "2026-10-10T12:00:00.000Z",
    edited_at: null,
    content: "text",
    deleted_at: null,
    is_system_notice: false,
    message_origin: null,
    media_url: null,
    game_session_id: null,
  };
  const cases: Record<string, Record<string, unknown>> = {
    "deleted messages": { ...base, deleted_at: "2026-10-10T12:30:00.000Z" },
    "system notices": { ...base, is_system_notice: true },
    "Assist-origin messages": { ...base, message_origin: "attune_assist" },
    "media/captions": { ...base, media_url: "https://example.test/x.jpg" },
    games: { ...base, game_session_id: "00000000-0000-0000-0000-00000000aaaa" },
    "whitespace-only text": { ...base, content: "   \n\t " },
    "non-string content": { ...base, content: null },
  };

  for (const [label, row] of Object.entries(cases)) {
    const window = selectWindowFromRows({
      rows: [{ id: "00000000-0000-0000-0000-00000000000a", ...row }],
      excludeMessageId: null,
    });
    assertEquals(
      window.length,
      0,
      `§4.2 requires excluding ${label}, but the window included it`,
    );
  }

  // Control: an ordinary row IS included, so the test above is not
  // passing because the function returns nothing.
  assertEquals(
    selectWindowFromRows({
      rows: [{ id: "00000000-0000-0000-0000-00000000000a", ...base }],
      excludeMessageId: null,
    }).length,
    1,
  );
});

Deno.test("the selected target is excluded from the window", () => {
  const targetId = "00000000-0000-0000-0000-0000000000a1";
  const rows = [
    {
      id: targetId,
      created_at: "2026-10-10T12:01:00.000Z",
      edited_at: null,
      content: "the target",
      deleted_at: null,
      is_system_notice: false,
      message_origin: null,
      media_url: null,
      game_session_id: null,
    },
    {
      id: "00000000-0000-0000-0000-0000000000a2",
      created_at: "2026-10-10T12:00:00.000Z",
      edited_at: null,
      content: "ordinary",
      deleted_at: null,
      is_system_notice: false,
      message_origin: null,
      media_url: null,
      game_session_id: null,
    },
  ];
  const window = selectWindowFromRows({ rows, excludeMessageId: targetId });
  assertEquals(window.map((m) => m.content), ["ordinary"]);
});

// ===========================================================================
// The query path, against real Postgres.
// ===========================================================================

Deno.test({
  name: "selectSharedWindow filters to the civil day BEFORE the limit, so yesterday's messages cannot fill the window",
  fn: async () => {
    await resetFixtures();
    const service = await makeServiceRoleClient();

    // A fixed `now` so the civil day is a known constant.
    const now = new Date("2026-10-10T12:00:00.000Z");
    const dayStart = civilDayStartUtc(now, 0); // 2026-10-10T00:00:00Z

    // Ten messages YESTERDAY, newer-looking in no sense but all before
    // the boundary; two TODAY. A query that limited before filtering
    // would return yesterday's rows and yield an empty or wrong window.
    for (let i = 0; i < 10; i++) {
      await insertMessage(
        `yesterday ${i}`,
        new Date(dayStart.getTime() - (i + 1) * 60_000),
      );
    }
    await insertMessage("today one", new Date(dayStart.getTime() + 60_000));
    await insertMessage("today two", new Date(dayStart.getTime() + 120_000));

    const window = await selectSharedWindow(service as never, REL, null, 0, now);
    assertEquals(
      window.map((m) => m.content),
      ["today one", "today two"],
      "only today's messages belong in the window, in chronological order",
    );
  },
});

Deno.test({
  name: "selectSharedWindow takes the NEWEST six of the day, not the oldest",
  fn: async () => {
    // Caught by mutation M15: flipping the query's ORDER BY from DESC to
    // ASC left every other test in this file green, because none of
    // them seeded more than six same-day messages -- so "the newest
    // six" and "the oldest six" were the same set. §4.2 says "orders
    // (created_at DESC, id DESC), limits six", and a window of the
    // oldest six would hand the model this morning's conversation
    // instead of the one the user is actually having.
    await resetFixtures();
    const service = await makeServiceRoleClient();
    const now = new Date("2026-10-10T18:00:00.000Z");
    const dayStart = civilDayStartUtc(now, 0);

    // Ten same-day messages, labelled in time order.
    for (let i = 0; i < 10; i++) {
      await insertMessage(
        `msg ${i}`,
        new Date(dayStart.getTime() + (i + 1) * 60 * 60_000),
      );
    }

    const window = await selectSharedWindow(service as never, REL, null, 0, now);
    assertEquals(
      window.map((m) => m.content),
      ["msg 4", "msg 5", "msg 6", "msg 7", "msg 8", "msg 9"],
      "the window must be the SIX NEWEST same-day messages, in chronological display order",
    );
  },
});

Deno.test({
  name: "selectSharedWindow is deterministic: the same (relationship, offset, now) queried twice over elapsed time yields an identical window AND an identical digest",
  fn: async () => {
    await resetFixtures();
    const service = await makeServiceRoleClient();
    const now = new Date("2026-10-10T12:00:00.000Z");
    const dayStart = civilDayStartUtc(now, 0);

    for (let i = 0; i < 4; i++) {
      await insertMessage(
        `message ${i} with some ordinary conversational text`,
        new Date(dayStart.getTime() + (i + 1) * 60_000),
      );
    }

    const first = await selectSharedWindow(service as never, REL, null, 0, now);
    const firstDigest = await computeApprovalDigest({
      ...baseDigestInput(),
      sources: first.map((m) => ({ messageId: m.messageId, sourceVersion: m.sourceVersion })),
      displayedSnippets: first.map((m) => m.content),
      utcOffsetMinutes: 0,
      civilDayStartUtc: dayStart.toISOString(),
    });

    await new Promise((resolve) => setTimeout(resolve, 1100));

    const second = await selectSharedWindow(service as never, REL, null, 0, now);
    const secondDigest = await computeApprovalDigest({
      ...baseDigestInput(),
      sources: second.map((m) => ({ messageId: m.messageId, sourceVersion: m.sourceVersion })),
      displayedSnippets: second.map((m) => m.content),
      utcOffsetMinutes: 0,
      civilDayStartUtc: dayStart.toISOString(),
    });

    assertEquals(first.length, 4, "precondition: the window is non-empty");
    assertEquals(JSON.stringify(first), JSON.stringify(second));
    assertEquals(
      firstDigest,
      secondDigest,
      "the SAME underlying content approved at two different times MUST digest identically",
    );
  },
});

Deno.test({
  name: "an EDIT to a windowed message moves BOTH the source version and the digest -- and created_at alone would NOT have",
  fn: async () => {
    await resetFixtures();
    const service = await makeServiceRoleClient();
    const now = new Date("2026-10-10T12:00:00.000Z");
    const dayStart = civilDayStartUtc(now, 0);
    const messageId = await insertMessage(
      "the original text",
      new Date(dayStart.getTime() + 60_000),
    );

    const snapshot = async () => {
      const window = await selectSharedWindow(service as never, REL, null, 0, now);
      const digest = await computeApprovalDigest({
        ...baseDigestInput(),
        sources: window.map((m) => ({ messageId: m.messageId, sourceVersion: m.sourceVersion })),
        displayedSnippets: window.map((m) => m.content),
        utcOffsetMinutes: 0,
        civilDayStartUtc: dayStart.toISOString(),
      });
      return { window, digest };
    };

    const before = await snapshot();
    assertEquals(before.window.length, 1, "precondition: exactly one windowed message");
    assertEquals(
      before.window[0].sourceVersion,
      before.window[0].createdAt,
      "an unedited message's source version IS its created_at",
    );

    // Edit exactly as the two shipped edit RPCs do (20260831120000 and
    // 20260950110000): content changes, edited_at is stamped,
    // created_at is left alone.
    await serviceRoleQuery(
      `UPDATE public.messages SET content = $2, edited_at = clock_timestamp() WHERE id = $1`,
      [messageId, "the text was edited after approval"],
    );

    const after = await snapshot();

    // THE LOAD-BEARING ASSERTION. §4.3 requires revalidating "source
    // existence/VERSION against the frozen snapshot", so the version
    // must move on an edit. created_at does NOT move -- asserted here
    // so the reason this module uses COALESCE(edited_at, created_at) is
    // proven, not merely commented. If a future refactor reverted
    // sourceVersion to created_at, THIS is the line that fails.
    assertEquals(
      after.window[0].createdAt,
      before.window[0].createdAt,
      "precondition for the finding: messages.created_at is unchanged by an edit, so it cannot serve as a source version",
    );
    assertNotEquals(
      after.window[0].sourceVersion,
      before.window[0].sourceVersion,
      "an edit MUST move the source version, or §4.3's source-version revalidation is blind to edits",
    );
    assertNotEquals(
      after.digest,
      before.digest,
      "an edit to an approved source MUST change the digest, or a partner would be approving text that is no longer what the other saw",
    );
  },
});

Deno.test("an edit that restores the ORIGINAL TEXT still moves the source version", async () => {
  // The case the snippet binding alone misses: a message edited and
  // then edited back has identical displayed text, so a digest bound
  // only to snippets would match the pre-edit approval. §4.3's version
  // binding is what catches it -- the partner's frozen snapshot
  // referenced a version that no longer exists.
  const unedited = {
    id: "00000000-0000-0000-0000-0000000000c1",
    created_at: "2026-10-10T12:00:00.000Z",
    edited_at: null,
    content: "same words",
    deleted_at: null,
    is_system_notice: false,
    message_origin: "user",
    media_url: null,
    game_session_id: null,
  };
  const editedBack = { ...unedited, edited_at: "2026-10-10T12:05:00.000Z" };

  const a = selectWindowFromRows({ rows: [unedited], excludeMessageId: null });
  const b = selectWindowFromRows({ rows: [editedBack], excludeMessageId: null });

  assertEquals(a[0].content, b[0].content, "precondition: the displayed text is identical");
  assertNotEquals(
    a[0].sourceVersion,
    b[0].sourceVersion,
    "an edit-and-revert must still move the source version",
  );

  const digestFor = (w: typeof a) =>
    computeApprovalDigest({
      ...baseDigestInput(),
      sources: w.map((m) => ({ messageId: m.messageId, sourceVersion: m.sourceVersion })),
      displayedSnippets: w.map((m) => m.content),
    });
  assertNotEquals(await digestFor(a), await digestFor(b));
});

Deno.test({
  name: "selectSharedWindow applies the same offset-derived civil day the pure helper computes",
  fn: async () => {
    await resetFixtures();
    const service = await makeServiceRoleClient();
    // 00:30 UTC. For offset 0 the day began 30 minutes ago; for offset
    // -300 (UTC-5) it is still the PREVIOUS local day, which began
    // 19.5 hours ago -- so a message from 23:00 UTC yesterday is IN the
    // UTC-5 window and OUT of the UTC window.
    const now = new Date("2026-10-10T00:30:00.000Z");
    await insertMessage("yesterday 23:00Z", new Date("2026-10-09T23:00:00.000Z"));
    await insertMessage("today 00:15Z", new Date("2026-10-10T00:15:00.000Z"));

    const utc = await selectSharedWindow(service as never, REL, null, 0, now);
    assertEquals(utc.map((m) => m.content), ["today 00:15Z"]);

    const minus5 = await selectSharedWindow(service as never, REL, null, -300, now);
    assertEquals(
      minus5.map((m) => m.content),
      ["yesterday 23:00Z", "today 00:15Z"],
      "a UTC-5 viewer's civil day began at 2026-10-09T05:00Z, so both messages are in it",
    );
  },
});

Deno.test("canonicalTimestamp accepts a Date WITHOUT losing milliseconds -- String(date) would", () => {
  // A measured defect, not hypothetical. The Deno pg driver decodes a
  // timestamptz to a JS Date, and String() on a Date renders
  //   "Sat Oct 10 2026 23:17:59 GMT+0000 (Greenwich Mean Time)"
  // which has no millisecond field. A caller that stringified first
  // would hash a timestamp 159ms from the one a caller receiving ISO
  // text hashes -- two partners, two digests, a session that can never
  // activate.
  const instant = new Date("2026-10-10T23:17:59.159Z");

  // The trap, demonstrated.
  assertEquals(
    new Date(String(instant)).toISOString(),
    "2026-10-10T23:17:59.000Z",
    "precondition: String(date) really does drop the milliseconds",
  );

  // And the function does not fall into it.
  assertEquals(canonicalTimestamp(instant), "2026-10-10T23:17:59.159Z");
  // A Date and the ISO string of the same instant agree, which is the
  // property the digest depends on.
  assertEquals(
    canonicalTimestamp(instant),
    canonicalTimestamp("2026-10-10T23:17:59.159Z"),
  );
  // And two instants 1ms apart still differ.
  assertNotEquals(
    canonicalTimestamp(instant),
    canonicalTimestamp(new Date("2026-10-10T23:17:59.160Z")),
  );

  // Non-timestamp inputs are null, not a hashed "Invalid Date".
  assertEquals(canonicalTimestamp(new Date("nonsense")), null);
  assertEquals(canonicalTimestamp(null), null);
  assertEquals(canonicalTimestamp(undefined), null);
  assertEquals(canonicalTimestamp(12345), null);
  assertEquals(canonicalTimestamp({}), null);
});
