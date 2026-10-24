# Stories robustness review — shared brief (2026-10-23)

## What stories are (owner's words, paraphrased)
Private stories between the two people in a couple, working like Snapchat / Instagram / WhatsApp stories: post photos/videos, the partner watches them in a full-screen reel, they disappear after 24 hours. The difference: after 24 h a story disappears from the rings but can still be seen on the couple's calendar, to build memories. Entry point: the story button/rings above the chat preview on the Conversations screen.

## Goal
Is everything robustly implemented? Does it pass the Algorithm Quality Review Checklist v3.1 (`lib/architecture/algorithms/algorithm_quality_review_checklist.md`)? Does it meet the Snapchat / Instagram / WhatsApp stories standard (fast, reliable, persistent, fluid, private)?

## Sources of truth
- Spec: `lib/architecture/STORIES.md` (updated to reflect what shipped).
- Plans (history): `docs/superpowers/plans/2026-09-11-stories-plan-{a-backend,b-capture,c-surfaces}.md`, `docs/superpowers/plans/2026-10-14-together-phase4-story.md`.
- App code: `lib/features/stories/**`, shared camera `lib/features/chat/presentation/screens/capture_camera_screen.dart`, calendar `lib/features/timeline/presentation/widgets/{story_day_row,calendar_day_sheet,calendar_day_indicators}.dart`, story replies in chat (`message_bubble.dart` story branch), Together story (`grep -rn story lib/features/together`).
- Server: `supabase/migrations/*stor*` (20260938010000 … 20261018130500), `supabase/functions/process-story-archival`, related: chapters deletion 20261018110000, export 20261018120000, quick exit / PIN (Spec 2), account deletion.
- Tests: `test/features/stories/**`, `test/features/timeline/**` story tests, `supabase/tests/*stor*.sql`.

## Rules (binding for every reviewer)
- READ-ONLY on the repo: never edit, format, stage or commit anything; never run `dart format`; no git state changes. Write ONLY your own output file in `docs/reviews/2026-10-23-stories-review/`.
- Do not dispatch subagents.
- You may run focused `flutter test <file>` and SQL contract files against the local scratch DB `attune_spec3a` only (`psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`; files that BEGIN…ROLLBACK). NEVER use `attune_test`. Never touch the live project. Do not read `.env`, credentials or the keychain.
- Evidence: every finding cites file:line and a concrete failure scenario ("person does X → sees Y"). No speculative findings without a traced path; mark uncertain ones "Needs verification".
- Severity by effect on a real person: Critical (data loss, privacy/security breach, crash on a core path), High (core flow broken or unreliable, standard-breaking UX), Medium (noticeable degradation, edge case on a common path), Low (polish).
- For each finding give a fix design (what to change, where) — no code edits.

## Output format (your file)
1. One-paragraph verdict for your area.
2. What is solid (with evidence).
3. Findings table: `# | Issue | Sev | Evidence (file:line) | Scenario | Fix design`.
4. Checklist notes: for your area, which Algorithm Quality Review Checklist v3.1 items (by phase/ID) pass, fail or are not applicable, with one-line evidence.
5. Standards gap: what Snapchat / Instagram / WhatsApp do in your area that a person would expect here and Attune lacks (only things that matter for a private two-person story; ignore follower/public features).
