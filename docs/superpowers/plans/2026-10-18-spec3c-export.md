# Spec 3c: Export ("Download what's yours"). Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A person can download a ZIP of what is theirs to keep, at any time, including during the 30-day window after an ending (research F1 (5); 05 D.2 Export column). The ZIP holds:
- a JSON bundle of their data;
- their media and the shared media they could see;
- an ICS file of their calendar.

It never contains AI judgement, role attribution, safety data or translator originals (D.3 #6).

**Architecture:**
- **One SQL source of truth.** `export_bundle(p_user_id)` (SECURITY DEFINER, service role only) returns the whole bundle as jsonb, with every inclusion and exclusion rule from D.2. `export_media_manifest(p_user_id)` lists the storage objects to copy.
- **Relationship data is gated.** A relationship's data is included only while `relationship_chat_open_for(rel, user)` holds. This is 3a's gate, made callable for a given user; `relationship_chat_open(rel)` becomes a wrapper over it.
- **Async build.** The client calls `request_my_export()`, which inserts a job. A worker edge function, `build-data-exports` (cron every 2 minutes, service role), claims one job. It then:
  1. calls both SQL functions;
  2. downloads the media;
  3. builds `calendar.ics` with the existing ICS builder;
  4. zips everything with fflate;
  5. uploads to the private bucket `data-exports` at `<user_id>/<job_id>.zip`;
  6. marks the job ready, with expiry in 7 days.

  The file is queued for deletion at expiry.
- **Download.** The edge function `get-export-url` returns a 15-minute signed URL for the caller's own ready export. The app opens it in the browser.

**Spec:** `06-synthesis-roadmap.md` F1 (5) and the Spec 3 row ("export round-trip"). `05` D.2 Export column and D.3 #5 and #6. **Map:** `.superpowers/sdd/spec3c-map.md`.

## Rulings

- **R3c-1. What is included.**
  - **Chat** (each open relationship): `content`, `quoted_text`, `created_at`, `edited_at`, `deleted_at` (as a tombstone), `reply_to`, the media type and dimensions, the sender as `me` or `partner`, `source`, and an `"assist"` flag when `message_origin = 'attune_assist'`. Also place updates.
  - **Media:** the user's own media plus the partner's non-view-once media. There is no per-recipient "viewed" state for ordinary media, so D.2's "as viewed in the window" is applied as "everything visible in the window except view-once".
  - **Planning:** entries, blocks and items. Templates and deleted rows are left out, and so are link-preview images. Expenses are a flat per-entry list with no totals. All planning photos of the relationship are included.
  - **Calendar:** what `together_items_for(me, rel, start, end)` shows the user: their private items and shared items, but never the partner's private ones. `calendar.ics` covers the year before and after the export date.
  - **Also:** reminders, family members, and timeline moments (own plus shared).
  - **Stories:** the user's own, with their media and their own place pins.
  - **Pulse and verdicts:** Pulse history (role-free; the dimension scores only), and published verdicts with headline, strengths, watch areas, one action and disclaimer.
  - **Games:** the user's own answers always. The partner's answers only when the round is `both_answered`, and the subject's mirror truth on the same rule.
  - **Personal** (always):
    - insights (type, body, date);
    - translator usage (the need label, whether the rewrite was chosen, and the date; nothing else is stored);
    - weekly check-ins;
    - journal entries and blocks with photos;
    - Healing reflection answers and breakup date, and readiness answers;
    - quiz responses, psych profile and its history;
    - onboarding answers;
    - the user's own custom questions.
- **R3c-2. What is never included** (one deny list, contract-tested):
  - message AI columns, `assistant_payload`, view-once media, streaks and their clips, system notices, edit history, read marks and seen state;
  - `analysis_sessions`, `patterns` (role and theme data the person never saw as such), the compatibility card, mirror scores, private Pulse scores, quiz shares;
  - journal tone and analysis, and Healing's AI portrait and post-mortem text (D.3 #6 "no AI judgement");
  - 36-question AI observations and chapter reflections;
  - safety events and occurrences, dating, forum and opinions;
  - who ended or paused, `chat_archived_reason`, `legal_hold`;
  - push, notification and session tables;
  - planning expense audit events.
- **R3c-3. The partner is named by first name only**, in the manifest. Every row refers to "me" or "partner", never to a user id. No id of the partner appears anywhere.
- **R3c-4. Limits.**
  - One export at a time per person, and at most one request per 24 hours (a failed job can be retried at once).
  - Media is capped at 500 files and 250 MB per ZIP. Anything over the cap is listed in `media_not_included.json` with a note. Ruling: an edge function builds the archive in memory.
  - Files expire after 7 days. The job row stays as status only; nothing in it is personal.
- **R3c-5. Where it's offered.**
  - Settings → Account → "Download my data", at all times.
  - The ended card in 3a gains "Download what we shared", which opens the same screen.
  - The seal confirm adds: "Download what you shared first: Settings → Download my data."
  - No feature flag: this is the person's right, and it is a safety-floor item.
- **R3c-6. Account deletion removes any export.** `prepare_account_deletion` queues the person's `data-exports` objects.

## Global Constraints

As in 3a and 3b. The pinned dependency is `https://esm.sh/fflate@0.8.2`.

## Review Focus

1. A partner's private calendar item, a view-once photo, a streak clip, an AI column or a safety event never reaches the ZIP. Check with the deny-list contract, whose list is discovered from the AI-only columns, not maintained by hand.
2. After a seal, or after day 30, a relationship's shared data is absent, while personal classes remain.
3. One person cannot request, read or download another person's export.
4. A worker crash leaves the job retryable, not stuck in `building` forever: a stale-claim timeout of 15 minutes.
5. The user's id does not appear in the bundle, and neither does the partner's.

---

### Task 1: SQL: gate, bundle, manifest, jobs, bucket

**Files:**
- `supabase/migrations/20261018120000_data_export.sql`
- `20261018120100_data_export_grants.sql`
- `supabase/tests/data_export_contracts.sql`

**Produces:**
- `relationship_chat_open_for(uuid, uuid) → boolean`
- `export_bundle(uuid) → jsonb`
- `export_media_manifest(uuid) → TABLE(bucket text, object_name text, zip_path text)`
- `request_my_export() → uuid` (`export:too_soon`, `export:in_progress`)
- `get_my_export() → TABLE(id, status, requested_at, ready_at, expires_at)`
- `claim_data_export() → TABLE(id uuid, user_id uuid)` (service role; claims the oldest queued job, or a `building` job stale by 15 minutes)
- `complete_data_export(id, storage_key)` and `fail_data_export(id, error)` (service role)
- the bucket `data-exports`, with an owner read policy on `split_part(name,'/',1) = auth.uid()`

- [ ] **Step 1: Contracts first** (round-trip and deny list). Seed U with partner P in R1 (active) and R0 (archived), Q in R2 (ended and sealed by U). Seed:
  - messages, including AI columns set, a view-once, a streak, a system notice and a deleted one, plus partner media;
  - planning with a template;
  - calendar: U's private event, P's private event, P's `busy_only` event and a shared one;
  - stories by U and by P;
  - pulse, a verdict (with model columns), patterns, `analysis_sessions` and a safety event;
  - games: a revealed round and an unrevealed round;
  - personal rows in every class.

  Assert on `export_bundle(U)`:
  - R1 is present. R0 and R2 relationship data are absent; personal classes are present.
  - The chat has no AI keys anywhere: recursive jsonb key scan for `tone_score`, `nvc_violations`, `bid_type`, `sentiment`, `assistant_payload`, `pursuer`, `read_at` and `safety_`.
  - No view-once or streak media appears in the manifest. The system notice is absent; the deleted message is a tombstone with no content.
  - P's private event is absent and P's `busy_only` event says "Busy". U's private event is present.
  - Only U's stories. Pulse rows have no `emotional_safety`. Verdict rows have no `model_`/`prompt_` keys.
  - The revealed round shows P's answer; the unrevealed one does not.
  - No `analysis`, `pattern`, `compatibility`, `safety`, `dating` or `forum` top-level keys.
  - Neither U's nor P's uuid appears anywhere in the bundle text.

  Jobs:
  - `request_my_export` twice → `export:in_progress`.
  - A ready job less than 24 hours old → `export:too_soon`.
  - `get_my_export` for another user returns nothing.
  - Clients cannot execute `export_bundle`, `export_media_manifest`, `claim` or `complete`.
  - The bucket policy lets only the owner read.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Write the migration, then the grants and the local replay. In the same migration, restate `prepare_account_deletion` to also queue `data-exports/<user>/%` (R3c-6).
- [ ] **Step 4:** GREEN, the full SQL suite, and these mutants:
  - (a) the export includes `tone_score`;
  - (b) the gate is dropped for sealed relationships;
  - (c) the partner's private event leaks.

### Task 2: Worker and URL functions (Deno)

- [ ] `supabase/functions/build-data-exports/` contains:
  - `index.ts`: `requireServiceRole`; `claim_data_export`; bundle plus manifest; downloads within the caps; `calendar.ics`; zip; upload; `complete`/`fail`.
  - `bundle.ts`: pure. `assembleZip(entries)`, `applyMediaCaps(manifest, sizes)` and `calendarItems(bundle)` mapping to `FeedItem`.
  - Tests:
    - caps (500 files and 250 MB, with the overflow list);
    - the ZIP contains `data.json`, `calendar.ics`, `README.txt` and `media/...`;
    - `buildCalendar` output has no `REFRESH-INTERVAL` (file mode).
- [ ] `calendar-feed/ics.ts` gains an optional `{ feed: false }` mode that omits the refresh and TTL lines. The existing ICS tests must still pass.
- [ ] `supabase/functions/get-export-url/index.ts`:
  - `requireUser`; reads the caller's latest ready, unexpired job with the service role, filtered by `user_id`;
  - returns `createSignedUrl(path, 900)`;
  - 404 otherwise.

  Deno source test: it is filtered by the caller and never by a body id.
- [ ] Cron migration `20261018120200_data_export_cron.sql`: `build-data-exports` every 2 minutes via `net.http_post`, following the drain pattern.

### Task 3: Client

- [ ] Data: `DataExportService` with `request()`, `latest()` and `downloadUrl()` (function invoke), plus a `DataExportStatus` model. Tests with fakes.
- [ ] `DataExportScreen` at `/settings/download-my-data` (route name `dataExport`). States:
  - none: "Prepare my download";
  - queued or building: "Getting it ready… you can leave this screen";
  - ready: "Download" opens the URL, plus "Ready until {date}";
  - too soon: "You can ask for a new one after {date}";
  - failed: "Couldn't prepare it. Try again."

  Intro: "A copy of what's yours: your messages and the photos you shared, plans, calendar, stories, check-ins, journal and quiz answers. It never includes Attune's own analysis." Widget tests for each state.
- [ ] Settings row: "Download my data", subtitle "A copy of what's yours", Account section, order 9. Ended card button "Download what we shared". Seal confirm sentence. Wiring and copy tests.

### Task 4: Runs, hand-off, review

- [ ] Full Flutter and SQL suites, plus Deno.
- [ ] Hand-off:
  - push the migrations;
  - deploy `build-data-exports` and `get-export-url`;
  - check the cron's `app.settings`;
  - staging: request an export, wait at most 2 minutes, download, and open the ZIP.
- [ ] Final Fable review, then one fix pass.
