# Healing Mode Self-Report Entry Point — Design

## Problem

`HealingJourneyScreen` and its backing RPC (`get_or_create_healing_journey`)
already fully support a self-reported, no-relationship healing journey:

- `healing_journeys.relationship_id` is nullable
  (`supabase/migrations/20260703193000_healing_mode_v1_1.sql:7`).
- `breakup_at_source` has a `CHECK` allowing `'user_reported'` alongside
  `'relationship'` (`20260703193000_healing_mode_v1_1.sql:9-10`).
- A dedicated partial unique index,
  `healing_journeys_solo_active_unique` (`...:42-44`), already exists
  specifically to prevent a user from having two concurrent
  no-relationship journeys.
- `get_or_create_healing_journey`'s SQL body branches on
  `p_relationship_id IS NULL` and, in that branch, validates
  `p_breakup_at_source = 'user_reported'` and reuses any existing solo
  `active`/`paused` journey before creating a new one
  (`...:257-289`).
- `HealingRepository.getOrCreateJourney` (`lib/features/healing/data/
  repositories/healing_repository.dart:53-68`) already takes
  `relationshipId` as nullable and passes both fields straight through.

The gap is entirely client-side: nothing in the app ever calls
`getOrCreateJourney` with `breakupAtSource: 'user_reported'`. The only
caller today is `healingStartContextProvider`
(`lib/features/healing/presentation/providers/healing_providers.dart:26-40`),
which returns non-null only when `getStartableRelationship()` finds an
**ended, in-app-tracked** relationship. A user who is single because of a
breakup that happened before they ever joined Attune — the exact audience
the master spec calls out
(`lib/architecture/attune/ATTUNE_MASTER_SPEC.md:258-259, 2203`,
"Personal mode → Healing mode (if user flags a recent breakup)") — has no
UI path to trigger this at all. `ChatCouplesLockedScreen`'s empty-state
copy in `HealingJourneyScreen` even alludes to it ("Healing Mode becomes
available after an ended relationship or a previously saved journey" —
`healing_journey_screen.dart:230`) without ever being reachable that way.

## Goal

Add a discoverable, low-pressure entry point on `ChatCouplesLockedScreen`
that lets a personal-mode user self-report a breakup date and start a
solo healing journey, using the backend path that already exists.

## Non-Goals

- No onboarding changes. `OnboardingModeStep` keeps its current two-choice
  question; no breakup-recency follow-up step is added in this pass.
- No changes to `healingStartContextProvider`, `get_or_create_healing_journey`,
  or any table/migration. This is additive client wiring against an
  already-shipped, already-tested backend contract.
- No changes to the relationship-ended healing entry point
  (`EndRelationshipAction`) — it keeps calling `context.push(RouteNames.healingJourney)`
  directly and is unaffected.
- No new AI/analysis behavior inside Healing Mode itself — stage screens,
  post-mortem, portrait, readiness scoring are all unchanged. This only
  adds a way to *start* a journey without a tracked relationship.

## User Flow

1. A `personal`-mode user is on `ChatCouplesLockedScreen` with no pending
   invite (`_invite == null`).
2. Below the existing `_ReflectionEntryCard`, a new card is shown: a
   `_HealingEntryCard` — matching the same visual language and priority
   as the reflection card, not merged into it. Label: "Healing from a
   breakup?" / subtitle: "Start a private healing journey, even if it
   wasn't tracked in Attune."
3. Tapping it triggers a lightweight existence check (`hasActiveSoloHealingJourneyProvider`,
   new — see Components). Two outcomes:
   - **Existing active/paused solo journey found:** skip the prompt
     entirely, `context.push(RouteNames.healingJourney)` directly. This
     mirrors `get_or_create_healing_journey`'s own idempotent behavior
     (`...:281-289` reuses an existing solo journey) so the UI doesn't
     ask a question the backend would silently ignore the answer to.
   - **No existing solo journey:** open a bottom sheet (via the existing
     `BottomSheetUtils.showDocumentationBottomSheet` shell, `widget:`
     param) containing a new `_HealingSelfReportSheet` — a short prompt
     with a date field ("When did this happen?", defaulting unset, capped
     at today, no earliest bound) and a primary action button
     ("Start healing journey", disabled until a date is chosen) plus a
     dismiss affordance.
4. Confirming calls `healingRepositoryProvider.getOrCreateJourney(
   relationshipId: null, breakupAt: pickedDate, breakupAtSource:
   'user_reported')`, then `ref.invalidate(healingJourneyProvider)`
   (already done inside the existing `createHealingJourneyProvider`
   family — see Components for why this path calls the repository
   directly instead), pops the sheet, and pushes `RouteNames.healingJourney`.
5. On RPC failure (e.g. rare race against the solo-unique index), show an
   inline error in the sheet and keep it open, following the same
   try/catch-with-snackbar-or-inline-error convention used by
   `EndRelationshipAction` (`end_relationship_action.dart:48-54`) — here
   inline in the sheet rather than a snackbar, since the sheet stays open
   on failure and a snackbar behind a modal is not reliably visible.

## Components

### `hasActiveSoloHealingJourneyProvider` (new)

`FutureProvider<bool>` in `healing_providers.dart`. Queries
`healing_journeys` for the current user where `relationship_id IS NULL`
and `status IN ('active', 'paused')`, returning whether any row exists.
This is a thin, purpose-built read — not a reuse of
`healingJourneyProvider` (which returns the single most relevant journey
of *either* kind and is driven by `healingStartContextProvider`'s
relationship-only context) or `healingStartContextProvider` (relationship-only
by construction, per Problem above). Implemented as a direct
`HealingRepository` query rather than an RPC, since it's a simple
ownership-scoped `SELECT`, consistent with `getStartableRelationship()`'s
own direct-query style (`healing_repository.dart:37-51`).

```dart
Future<bool> hasActiveSoloJourney() async {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return false;
  final result = await _supabase
      .from('healing_journeys')
      .select('id')
      .eq('user_id', userId)
      .isFilter('relationship_id', null)
      .inFilter('status', ['active', 'paused'])
      .maybeSingle();
  return result != null;
}
```

RLS already scopes `healing_journeys` to the owning user (existing policy
from `20260703193000_healing_mode_v1_1.sql`), so no new policy is needed —
confirmed by reading the migration's policy block before finalizing this
design.

### `_HealingEntryCard` (new widget)

Same file as `_ReflectionEntryCard`
(`lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`),
placed immediately after it, inside the same `if (!_isCreatingInvite) if
(_invite == null)` guard it currently sits outside of — this card is
specific to the true-single, not-mid-invite state, unlike the reflection
card which is shown unconditionally. Visually mirrors
`_ReflectionEntryCard`'s card shell (icon, title, subtitle, tap target)
so the two entry points read as siblings, not as a primary/secondary
pair.

### `_HealingSelfReportSheet` (new widget)

New file:
`lib/features/healing/presentation/widgets/healing_self_report_sheet.dart`.
A `ConsumerStatefulWidget` holding local `DateTime? _selectedDate` and
`bool _submitting` state. Structure:

- Title + explanatory subtitle (see copy above).
- A date-selection row (label + chosen date or placeholder, tapping opens
  `showDatePicker` with `firstDate: DateTime(2020)` and `lastDate:
  DateTime.now()`, matching the existing convention used by
  `log_moment_details_screen.dart:211-212`, the only other
  `showDatePicker` call site in this codebase — no other precedent
  exists, so this one is authoritative).
- Primary button ("Start healing journey"), disabled when `_selectedDate
  == null` or `_submitting == true`, showing a small inline spinner while
  submitting.
- Inline error `Text` shown below the button on failure, cleared on next
  attempt.

On success, the sheet itself calls `Navigator.of(context).pop()` before
the caller pushes `RouteNames.healingJourney`, matching how
`ConfirmationDialog`'s `onConfirm` callbacks in this codebase close their
own sheet before navigating (see `EndRelationshipAction`, which calls
`context.push` after its dialog's internal dismissal).

### `ChatCouplesLockedScreen` changes

- Import the new sheet widget and `hasActiveSoloHealingJourneyProvider`.
- Convert the relevant `State` to watch/read the new provider on tap
  (not `watch` at build time — this avoids an extra always-on query for
  users who never tap the card; a `ref.read` at tap time is enough since
  the result only needs to be fresh at the moment of the decision).
- Add `_HealingEntryCard` per the User Flow section above.

## Data Flow Summary

```
ChatCouplesLockedScreen (_HealingEntryCard.onTap)
  -> ref.read(hasActiveSoloHealingJourneyProvider.future)
       -> true:  context.push(RouteNames.healingJourney)
       -> false: showDocumentationBottomSheet(widget: _HealingSelfReportSheet)
            -> user picks date, confirms
            -> healingRepositoryProvider.getOrCreateJourney(
                 relationshipId: null,
                 breakupAt: pickedDate,
                 breakupAtSource: 'user_reported',
               )
            -> get_or_create_healing_journey RPC (existing, unchanged)
            -> ref.invalidate(healingJourneyProvider)
            -> pop sheet, context.push(RouteNames.healingJourney)
```

## Testing

- Unit test for `hasActiveSoloHealingJourneyProvider`'s repository method
  against a fake/mocked Supabase client: returns `true` when an
  `active`/`paused` solo row exists, `false` when none exists or all solo
  rows are `completed`/`archived`, `false` for an unauthenticated user.
- Widget test for `_HealingSelfReportSheet`: primary button disabled with
  no date selected, enabled after a date is picked, shows inline error
  text when the injected repository call throws.
- Widget test for `ChatCouplesLockedScreen`: `_HealingEntryCard` is
  present when `_invite == null`, absent when an invite exists or is
  being created. No existing test currently covers the sibling carousel
  block in this conditional, so this is new coverage scoped only to the
  new card — not an extension of pre-existing tests.
- No new SQL/migration, so no new backend test surface — the RPC and its
  existing test coverage (if any, from the original healing-mode-v1.1
  cycle) are unchanged and out of scope here.

## Open Questions Resolved During Brainstorming

- **Entry point placement:** CTA on `ChatCouplesLockedScreen`, not folded
  into onboarding (user's explicit choice) — reaches existing single
  users today, not just future signups.
- **Idempotency UX:** if a solo journey already exists, skip the prompt
  and navigate straight in, rather than asking the user to pick a date a
  second time that the backend would ignore.
