# ATTUNE - SAFETY SYSTEM SPECIFICATION

**Version:** 1.1  
**Created:** July 2026  
**Last corrected:** July 3, 2026  
**Status:** Implementation-ready; production release is professionally and legally gated  
**Part of:** Core Safety Infrastructure  
**Launch requirement:** Yes

**Governing documents, in precedence order:**

1. `attune/ATTUNE_SOUL.md`
2. `attune/ATTUNE_CLINICAL.md`
3. `attune/ATTUNE_MASTER_SPEC.md` Section 8.7
4. `algorithms/algorithm_quality_review_checklist.md`
5. `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`

---

## How to use this document

This document is the implementation contract for Attune's relationship-chat
safety system. Build in the order in Section 11. A production release remains
blocked until every gate in Section 14 has written evidence.

The detector is deterministic, versioned, and non-LLM. No generative model,
embedding model, hosted moderation model, sentiment model, or AI fallback may
decide whether a safety event fires. Detection must complete independently of
the normal AI analysis pipeline.

This is a best-effort resource-routing feature, not monitoring by a human, a
clinical assessment, emergency dispatch, or a guarantee that abuse or danger
will be detected.

---

## 1. Scope and permanent boundaries

### 1.1 Purpose

The system detects a narrow, professionally reviewed set of recipient-directed
threat and coercive-control phrases in relationship chat. When a rule fires, it
quietly makes support resources available to the message recipient. The sender
is not notified, the message is not blocked, and the feature makes no accusation
or relationship decision.

### 1.2 Permanent invariants

| Invariant | Required behavior |
|---|---|
| Non-LLM detection | Only the versioned deterministic rules engine decides triggers |
| Recipient-only routing | The at-risk user is the authenticated relationship member receiving the message |
| Sender secrecy | No sender notification, UI state, delivery change, API response, or timing signal reveals a trigger |
| Fail-open delivery | Safety subsystem failure never blocks or delays message delivery |
| Private resources | Safety events and dismissals are readable only by the at-risk user through a user-scoped API |
| No accusation | Copy never says the partner is abusive, dangerous, or was flagged |
| No punishment | No account lock, message block, reputation score, report, or enforcement action follows a trigger |
| Free access | Resources, quick exit, and app lock are never paywalled |
| No training | Messages, matches, events, and dismissals are never used to train a model |
| No personalization suppression | A dismissal never weakens protection or suppresses later trigger detection for that user |

### 1.3 Included surfaces in v1.1

- incoming one-to-one messages in an **active relationship chat**
- manual access to Safety Resources from Settings/Profile without a trigger
- a global quick-exit mechanism and app-switcher privacy cover
- user-scoped dismissal and resource-view tracking

### 1.4 Explicitly excluded surfaces

The following must not be connected to this pipeline without a separate spec,
routing model, clinical review, and tests:

- sender-authored self-harm or suicide statements
- Personal Mode journals or solo reflections
- anonymous forum posts or comments
- Truth or Dare, 36 Questions, or other game answers
- images, audio, video, links, or attachments
- historical message backfills
- automatic police, emergency-service, partner, moderator, or family contact
- abuse classification, perpetrator labeling, or relationship-health scoring

These exclusions are safety decisions, not missing integrations. In particular,
the locked recipient-only rule would route help to the wrong person for a sender
expressing self-harm. Manual crisis resources remain available while a separate
self-harm protocol is designed.

---

## 2. System architecture

### 2.1 Authoritative path

```text
Authenticated sender submits message
  -> message service validates relationship membership
  -> message is committed and acknowledged normally
  -> durable safety job is created in the same transaction/outbox
  -> safety worker loads message through service-role scope
  -> deterministic detector evaluates versioned rules
  -> no match: mark safety stage complete; release message to normal analysis
  -> match: atomically create/dedupe event and notification work
  -> mark safety stage complete; release message to normal analysis
```

The safety job must be created transactionally with message persistence so a
worker outage cannot silently lose messages. Message delivery is acknowledged
without waiting, but downstream AI analysis for that message begins only after
the safety stage records success or a handled failure. A safety failure is
alerted and dead-lettered; it does not block delivery or indefinitely block
normal analysis. Match state must not change sender-visible timing or status.

### 2.2 Server authority only

Do not run trigger detection on the sender client. Client-side matching can
leak trigger behavior, drift from server configuration, be bypassed, and create
duplicate events. Recipient clients render only server-authorized resource
state; they do not re-scan message content.

### 2.3 AI isolation

- Safety processing does not call or wait for Claude or any other model.
- Normal AI prompts never receive `safety_event` rows, matched rule IDs, or
  dismissal behavior.
- A safety worker failure does not prevent normal chat or resource access.
- Normal AI failure does not prevent safety processing.
- The detector package must not import an AI SDK or generic moderation service.

### 2.4 Identity derivation

The worker derives identities from trusted database state:

```text
sender = messages.sender_id
relationship = messages.relationship_id
at_risk_user = the other active relationship member
```

Never accept `sender_id`, `relationship_id`, or `at_risk_user_id` from an
untrusted request payload. If membership is missing, ambiguous, inactive, or
not exactly two people, record an operational error without message content and
do not create a safety event.

### 2.5 Delivery and processing guarantees

- At-least-once jobs with idempotent effects.
- Unique source event key prevents duplicate safety events.
- Worker retries transient failures with bounded exponential backoff and jitter.
- Permanent validation failures go to a restricted dead-letter queue.
- Alert when oldest unprocessed job exceeds 60 seconds or failures exceed the
  staging-approved threshold.
- Sender-facing message API returns the same shape and timing class whether a
  trigger matches or not.

---

## 3. Trigger configuration contract

### 3.1 Versioned configuration

Store rules in a bundled, reviewed asset such as:

```text
assets/config/safety_triggers.v1.json
```

The server owns the canonical copy. Every release pins a checksum and semantic
`config_version`. Runtime remote edits are prohibited in v1.1. A config change
requires code review, automated tests, DV-professional approval, clinical
approval, cultural/language review, and a changelog entry.

Required shape:

```json
{
  "config_version": "1.0.0",
  "locale": "en",
  "normalization_version": 1,
  "tiers": {
    "explicit_threat": {
      "tier": 1,
      "minimum_occurrences": 1,
      "rules": [
        {
          "id": "explicit_threat_001",
          "pattern": "<professionally reviewed recipient-directed phrase>",
          "match": "token_phrase"
        }
      ]
    },
    "isolation_control": {
      "tier": 2,
      "minimum_occurrences": 1,
      "rules": []
    },
    "pattern_control": {
      "tier": 3,
      "minimum_occurrences": 3,
      "window_days": 30,
      "rules": []
    }
  }
}
```

The final production phrase list is deliberately not approved by this document.
It must be supplied and signed off by the reviewers in Section 14. Examples in
the Master Spec are test ideas, not an approved exhaustive lexicon.

### 3.2 Tier semantics

| Tier | Meaning | Trigger threshold | User presentation |
|---|---|---:|---|
| 1 | Explicit recipient-directed threat in approved lexicon | First matching message | Resources available; highest internal priority |
| 2 | Approved isolation/coercive-control phrase | First matching message | Same neutral notification; resources prioritize specialist support |
| 3 | Lower-specificity control phrase | Third distinct matching message within rolling 30 days | Same neutral notification |

Tiers are internal routing metadata. Never show tier, confidence, rule ID, match
count, or matched phrase to either user.

### 3.3 Normalization

The pure detector applies only these documented transformations in order:

1. Unicode normalize to NFKC.
2. Apply locale-stable lowercase for the configured language.
3. Convert approved apostrophe variants to ASCII apostrophe.
4. Replace runs of Unicode whitespace with one space.
5. Trim leading/trailing whitespace.

Do not strip all punctuation, remove diacritics, perform stemming, use fuzzy
matching, expand slang, or decode deliberate obfuscation in v1.1. Those changes
materially alter false-positive behavior and require a new normalization version.

### 3.4 Matching

- `token_phrase` matches complete normalized tokens in contiguous order.
- A short token such as `kill` must not match inside `skill`, `killer outfit`,
  URLs, usernames, or another larger token.
- Empty strings and messages over the chat service's maximum length are rejected
  by normal message validation, not the detector.
- Multiple matching rules in one message create one safety event containing the
  highest tier and a set of internal rule IDs.
- The detector is a deterministic pure function returning rule IDs/tier only.
- Do not store the normalized text, excerpt, matched phrase, surrounding text,
  or detector input.

### 3.5 Known context limits

Deterministic phrase matching cannot reliably distinguish quotation, jokes,
song/movie text, negation, reclaimed language, threats toward a third party, or
culturally specific meaning. The product addresses this through narrow reviewed
rules, neutral copy, easy dismissal, quality measurement, and no punitive action.
It must never claim comprehensive detection.

---

## 4. Tier 3 pattern memory

### 4.1 Counting contract

Pattern memory is scoped to:

```text
(relationship_id, at_risk_user_id, rule_id, config_version)
```

- Count distinct source messages, not the number of phrase occurrences.
- Use a rolling 30-day window based on server timestamps.
- Fire when the third distinct message matches within the window.
- After firing, continue counting for quality metrics but notification rate
  limiting still applies.
- A config-version change starts a new count; never reinterpret old text.
- Concurrent messages must increment atomically and fire once at the boundary.
- Ended relationships are no longer processed.

### 4.2 Storage minimization

Store rule ID, source event key, and timestamps only. Do not store message ID,
sender ID, content, excerpt, or a reversible content hash in pattern memory.

---

## 5. Event, notification, and dismissal behavior

### 5.1 Event creation

On a qualifying match, one trusted transaction:

1. verifies the source event has not already been processed
2. creates at most one safety event
3. updates Tier 3 memory when applicable
4. applies the notification rate limit
5. creates notification work only when allowed
6. marks the outbox job complete

Retries return the existing result without duplicate events or notifications.

### 5.2 Notification routing

Only `at_risk_user_id` receives notification work. Never notify the sender,
both partners, relationship owner, moderator, or administrator.

Required generic payload:

```json
{
  "title": "Attune",
  "body": "Some resources are available.",
  "data": {
    "type": "safety_resources",
    "event_token": "<opaque single-purpose token>"
  }
}
```

The lock-screen payload must not mention safety, abuse, danger, a partner,
message content, rule type, or relationship. Push preview safety and wording
require DV-professional approval. Do not include event IDs or user IDs in a
guessable deep link.

### 5.3 Rate limiting

- Maximum one safety push per at-risk user per rolling 24 hours.
- Every qualifying event is still recorded, even when its push is suppressed.
- The newest resource screen may show `Updated resources are available` without
  exposing trigger count.
- Tier 1 does not bypass the v1.1 push rate limit unless a DV professional and
  lawyer approve a documented exception.
- Rate-limit check and enqueue are atomic under concurrent events.

### 5.4 Failure behavior

- Push-provider failure never retries synchronously in message delivery.
- Retry notification work asynchronously with a stable idempotency key.
- After bounded retries, move to a restricted dead-letter queue and alert.
- Resources remain manually accessible even if push is disabled or fails.
- Do not fall back to email, SMS, partner notification, or an explicit in-app
  banner without separate consent and safety review.

### 5.5 Resource view and dismissal

The resource screen starts a server-issued view session. `Not relevant right
now` dismisses the current presentation only; it does not delete the event,
disable detection, notify the sender, or suppress future protection.

Store server timestamps for `first_viewed_at` and `dismissed_at`. Derive
dismissal latency server-side. A dismissal under 60 seconds is a **quality-review
signal only**, not proof of a false positive and not a user-level classifier.

---

## 6. Safety Resources screen

### 6.1 Access and presentation

- Available without a trigger from Profile/Settings and relevant empty states.
- Never paywalled, advertised, or gated by Couples Mode.
- Requires the normal authenticated session; cached emergency numbers remain
  available offline after first app install/update.
- Shows an always-visible `Quick exit` action plus the global triple-tap gesture.
- Does not show why it appeared, the triggering message, sender, tier, rule,
  event history, or a claim that abuse has occurred.
- Screen capture protection is enabled where supported; no sensitive analytics
  events or screenshots are collected.

Required opening copy:

```text
Support resources

If something does not feel safe, these contacts and planning resources may be
useful. Attune cannot assess an emergency or contact help for you.
```

### 6.2 Resource data model

Resources are versioned content, not literals scattered through widgets:

```text
resource_id
country_code
service_name
audience/limitations
phone_e164
display_phone
website_https
hours_text
languages_text
emergency boolean
verified_at
verified_by
source_url
content_version
```

The bundled resource file is signed/reviewed with the app release. Remote
updates, if later introduced, require signature verification, schema validation,
safe cached fallback, and no third-party tracking.

### 6.3 Provisionally verified contacts

These values were checked on July 3, 2026 but still require the professional
and pre-release verification gates below:

| Country | Resource | Contact | Authoritative source |
|---|---|---|---|
| Ghana | Ghana Police DOVVSU Helpline | `055 100 0900` | [Ghana Police DOVVSU](https://police.gov.gh/en/index.php/domestic-violence-victims-support-unit-dovvsu/) |
| Ghana | Police emergency | `191` | [Ghana Police publications](https://police.gov.gh/en/index.php/publication-officials/) |
| United States | National Domestic Violence Hotline | `800-799-SAFE (7233)`; text `START` to `88788` | [TheHotline.org](https://www.thehotline.org/get-help/) |
| United States | Immediate emergency | `911` | Local emergency service |
| England | Refuge National Domestic Abuse Helpline | `0808 2000 247` | [GOV.UK](https://www.gov.uk/guidance/domestic-abuse-how-to-get-help) |
| United Kingdom | Immediate emergency | `999` | [GOV.UK](https://www.gov.uk/guidance/domestic-abuse-how-to-get-help); country-specific variants required for non-England support |

Do not use the old Ghana number `+233 302 773 718`; it is not the helpline shown
on the current official DOVVSU page. Do not label an England-only service as a
complete UK service. For an unsupported or unknown country, show a reviewed
international directory and neutral guidance to contact local emergency
services; never guess a number from device locale.

### 6.4 Calling and browsing safety

- Confirm before placing a call or opening an external site.
- Explain that calls, browser history, notifications, and internet use may be
  visible on a shared or monitored device.
- Never automatically dial, open a site, copy a number, request location, or
  clear browser history.
- Use HTTPS allowlisted URLs and the platform browser; no tracking parameters.
- Do not claim Attune can erase evidence of internet use.
- Safety planning copy must be authored/reviewed by a DV professional. Avoid
  blanket advice such as “document everything” or “leave quickly,” which may be
  unsafe in a specific situation.

### 6.5 Freshness

- Product owner verifies every resource at least quarterly and within seven
  days before each production release.
- Expired verification (over 90 days) blocks release.
- Verification records include date, reviewer, source URL, and result.
- A broken contact can be disabled through a signed content update without
  exposing which users opened it.

---

## 7. Quick exit and privacy cover

### 7.1 Product behavior

Quick exit is available through:

- triple-tap on the Attune logo within two seconds from any authenticated screen
- a plainly labeled, screen-reader-accessible `Quick exit` button on Safety Resources

Activation immediately:

1. replaces sensitive Flutter content with a bundled neutral local screen
2. clears the in-app navigation stack and transient sensitive state
3. marks the session as requiring the configured safety PIN on return
4. applies the platform behavior below

No network request, analytics event, log, animation, confirmation, haptic, or
sound may delay or reveal activation. The local decoy must contain no Attune
branding and must work offline.

### 7.2 Android contract

- Open an allowlisted neutral browser destination only after the local privacy
  cover is visible.
- Use a small audited platform channel to invoke `finishAndRemoveTask()` where
  supported.
- Verify behavior on supported Android API levels and OEM variants.
- If external browser launch fails, retain the local neutral screen and remove
  the Attune task where possible.

Android documents `finishAndRemoveTask()` for finishing the task and removing
it from Recents. This is the supported target, not a guarantee across every OEM.

### 7.3 iOS contract

iOS apps cannot promise programmatic removal from the app switcher or a clean
self-termination flow. Do not call `exit(0)`, use private APIs, or describe a
crash/forced termination as a safety feature.

On iOS:

- replace the app with the local neutral screen immediately
- show a neutral privacy image in the app-switcher snapshot whenever the app
  resigns active
- optionally open an allowlisted neutral website after the cover is rendered
- require the configured safety PIN before sensitive UI is restored

Marketing and UI copy must describe this as `Quick exit`, not `clear from recent
apps`, on iOS.

### 7.4 Safety PIN

- Quick exit setup requires the user to create and confirm a dedicated PIN.
- Store only an OS-keystore-protected, salted password hash using a reviewed
  password KDF; never store or sync the PIN in plaintext.
- Biometric unlock alone is not accepted after quick exit.
- Rate-limit attempts with increasing local delay; do not wipe safety data.
- Recovery design must receive DV-professional review because email/SMS recovery
  can expose use. Until approved, recovery returns to a generic signed-out state.
- App reinstall/device restore behavior must be documented and tested.

### 7.5 App-switcher privacy

Independently of quick exit, both platforms cover sensitive content before an
app-switcher snapshot can be captured. Restore content only after the app is
active and authentication requirements are satisfied.

---

## 8. Data model and RLS contract

### 8.1 Safety events

```sql
CREATE TABLE safety_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships(id) ON DELETE SET NULL,
  at_risk_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  source_event_key text UNIQUE NOT NULL,       -- HMAC/dedupe key, not message id
  trigger_tier smallint NOT NULL CHECK (trigger_tier BETWEEN 1 AND 3),
  trigger_family text NOT NULL,
  config_version text NOT NULL,
  first_viewed_at timestamptz,
  dismissed_at timestamptz,
  notification_status text NOT NULL DEFAULT 'pending'
    CHECK (notification_status IN ('pending', 'suppressed', 'sent', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  anonymised_at timestamptz,
  CHECK (
    (anonymised_at IS NULL AND at_risk_user_id IS NOT NULL)
    OR (anonymised_at IS NOT NULL AND at_risk_user_id IS NULL AND relationship_id IS NULL)
  )
);
```

Do not store message ID, sender ID, message content, excerpt, normalized content,
matched phrase, partner name, phone, email, IP address, device ID, or push token
in this table. `source_event_key` is an HMAC over the message ID with a
server-held rotating secret and is not reversible.

### 8.2 Pattern occurrences

```sql
CREATE TABLE safety_pattern_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES relationships(id) ON DELETE CASCADE,
  at_risk_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rule_id text NOT NULL,
  config_version text NOT NULL,
  source_event_key text NOT NULL,
  occurred_at timestamptz NOT NULL,
  UNIQUE (at_risk_user_id, rule_id, config_version, source_event_key)
);
```

Delete occurrence rows after 30 days plus a seven-day operational buffer. They
are backend-only and never readable from the client.

### 8.3 Outbox and notification work

Use dedicated restricted tables for safety jobs and notifications. Payloads
contain opaque IDs only, never message text. Service role can insert/update only
through audited functions. Push tokens remain in the existing notification
system and are not copied into safety tables.

### 8.4 User access

- Enable RLS on every safety table.
- Revoke direct client access to jobs, occurrences, rule IDs, config metadata,
  source keys, and notification state.
- Do not expose raw `safety_events` rows directly.
- Provide a user-JWT RPC/view returning only `created_at`, `first_viewed_at`, and
  `dismissed_at` for rows where `auth.uid() = at_risk_user_id`.
- Dismissal RPC derives user identity from `auth.uid()`, accepts an opaque
  single-purpose token, and updates only that user's event.
- Partner JWT, sender JWT, anonymous role, and another relationship member must
  receive zero rows and cannot infer whether an event exists.
- Dashboard/admin access is denied by default and requires a separately audited,
  time-limited incident procedure. Never build a general safety-events browser.

### 8.5 Retention

- Identifiable safety events are retained for 12 months unless legal review
  requires a shorter period.
- At 12 months, set `relationship_id` and `at_risk_user_id` to null and set
  `anonymised_at`; retain only non-identifying tier/family/version/timestamps.
- Never retain message-derived keys after anonymisation; rotate/remove the
  source key as part of the job while preserving uniqueness through a random
  archival identifier if needed.
- Account deletion removes or immediately anonymises the user's identifiable
  event data according to the legally approved policy.
- Retention/anonymisation jobs are idempotent, monitored, and tested.

### 8.6 Required indexes

```text
safety_events(at_risk_user_id, created_at desc) WHERE anonymised_at IS NULL
safety_events(source_event_key) UNIQUE
safety_pattern_occurrences(at_risk_user_id, rule_id, config_version, occurred_at desc)
safety_notification_work(at_risk_user_id, created_at desc)
```

---

## 9. Privacy, telemetry, and security

### 9.1 Prohibited telemetry

Never send message text, normalized text, matched phrase, rule ID, event token,
resource choice, phone call action, website action, quick-exit use, PIN state,
or dismissal behavior to product analytics, crash metadata, session replay, or
third-party observability tools.

### 9.2 Allowed operational metrics

Only access-controlled aggregate metrics with minimum cohort size:

- jobs processed, delayed, failed, and dead-lettered
- events by tier/family/config version
- notifications sent/suppressed/failed
- aggregate view/dismiss timing distributions
- resource content version and verification freshness

No metric labels contain user, relationship, message, rule, or device IDs.

### 9.3 Logs

Structured logs may contain correlation ID, config version, processing stage,
duration, retry count, and error category. Never log request bodies, messages,
matched data, user IDs, relationship IDs, event tokens, source keys, push
payloads, or provider responses containing personal data.

### 9.4 Secrets and least privilege

- HMAC and push-provider secrets live in the platform secret store.
- Rotate secrets under a tested runbook.
- Safety worker has only message-read, safety-function-execute, and outbox-update
  permissions required for its job.
- User clients cannot write safety events or pattern occurrences.
- CORS is restricted to approved origins for any web surface.

---

## 10. Edge-case contract

| Scenario | Required behavior |
|---|---|
| Multiple rules in one message | One event; highest tier; one notification decision |
| Same job delivered repeatedly | Same event/result; no duplicate notification |
| Concurrent Tier 3 boundary messages | Atomic count; one threshold event |
| Several events in 24 hours | Record all; at most one push |
| Push disabled/fails | No fallback channel; manual resources remain available |
| Sender deletes message quickly | Existing outbox job still processes according to approved deletion policy |
| Relationship ends before worker runs | Do not process; close job without event |
| Blocked/inactive relationship | No new safety processing; resources remain manually available |
| Unknown/unsupported locale | Run only the approved default-language rules when language eligibility is certain; otherwise no match |
| Emoji/zero-width/obfuscated text | No fuzzy inference in v1.1; record no content |
| Quoted or joking phrase | May match; neutral response and dismissal; no punishment |
| User dismisses in under 60 seconds | Quality signal only; detection remains unchanged |
| User has no active partner | This chat pipeline does not run; manual resources remain available |
| Network offline | Message/outbox sync together when reconnected; local resources remain available |
| Quick exit without network | Local neutral screen and app lock still work |
| App killed during safety screen | App-switcher cover shown; configured PIN required on return |

---

## 11. Build order

### Phase 1 - Governance and threat model

1. Record DV-professional, clinical, cultural, privacy, security, and legal owners.
2. Threat-model sender inference, lock-screen exposure, monitored devices,
   admin access, quick exit, notification timing, and false positives.
3. Finalize approved v1 phrase list, resource copy, push copy, and country data.
4. Reconcile the Master Spec schema and platform claims with Section 13.

### Phase 2 - Pure detector

5. Implement typed config loading, checksum validation, normalization, phrase
   boundaries, deterministic tier selection, and pure unit tests.
6. Add golden positive/negative fixtures supplied by reviewers; fixtures must be
   synthetic and contain no real user messages.
7. Add property/fuzz tests for Unicode, punctuation, whitespace, substrings,
   determinism, and bounded runtime.

### Phase 3 - Trusted persistence

8. Add safety outbox, minimized event schema, Tier 3 occurrences, notification
   work, constraints, indexes, retention, and RLS migrations.
9. Implement atomic idempotent processing and user-scoped view/dismiss RPCs.
10. Add cross-user, partner, anonymous, service-role, concurrency, retry, and
    deletion/anonymisation integration tests.

### Phase 4 - Message integration

11. Write the outbox record atomically with message persistence.
12. Build bounded worker retries, dead-letter handling, metrics, alerts, and runbooks.
13. Prove sender response/body/status/timing does not reveal match state.

### Phase 5 - Notifications and resources

14. Implement atomic 24-hour rate limiting and idempotent provider delivery.
15. Build offline-capable versioned resources, safe call/link confirmation,
    accessibility, generic deep links, and manual access.
16. Test notification previews on locked iOS/Android devices and with shared devices.

### Phase 6 - Quick exit

17. Build local neutral cover, global gesture, visible accessible action, safety
    PIN, app-switcher cover, Android platform channel, and iOS fallback.
18. Test supported OS/device combinations, offline behavior, app restore,
    accessibility, and failure fallbacks.

### Phase 7 - Release

19. Run algorithm, security, privacy, accessibility, load, soak, and chaos checks.
20. Complete professional/legal sign-offs and resource re-verification.
21. Canary internally with synthetic traffic only; do not experiment on safety
    thresholds or notification copy through user A/B testing.
22. Record rollback procedure, operational owner, and 24-hour post-deploy checks.

---

## 12. Acceptance criteria

### Detection

- No detector code path can call an AI or remote moderation service.
- Config schema/checksum/version validation fails closed for detection while
  message delivery remains available and operations are alerted.
- Full-token phrase matching rejects substring, URL, username, and punctuation
  false positives defined by fixtures.
- One message produces at most one event at the highest matching tier.
- Tier 3 fires once at the third distinct message inside 30 days, including under concurrency.
- Core detector branch coverage is at least 90%; mutation-test survivors are reviewed.

### Privacy and authorization

- Sender and partner JWTs return zero safety rows and cannot view/dismiss an event.
- At-risk user sees only the minimized safe view, never rules/source/notification internals.
- No content, excerpt, sender ID, message ID, reversible hash, or matched phrase is stored.
- No prohibited safety data appears in logs, analytics, crash reports, session
  replay, push payload previews, or AI prompts.
- Account deletion and 12-month anonymisation pass integration tests.

### Reliability and secrecy

- Message delivery succeeds when detector, database safety function, worker, or push provider fails.
- Every committed eligible message creates a durable job exactly once logically.
- Retries create no duplicate event, count, or notification.
- At most one push per at-risk user per rolling 24 hours under concurrent load.
- Sender-visible API response, delivery state, and latency distribution do not materially differ on match.
- Backlog, failures, zero processing traffic, and stale resources have tested alerts and runbooks.

### User experience

- Push and resource copy are neutral, non-accusatory, and professionally approved.
- Resources remain available manually and offline, with no paywall.
- Call/link actions explain monitored-device risks and require confirmation.
- Dismissal is one tap and has no punitive or suppression effect.
- Screen reader, dynamic text, contrast, keyboard, focus order, and touch targets meet WCAG 2.1 AA.
- Quick exit renders the local privacy cover within 200 ms and works offline.
- Android removal and iOS privacy-cover behavior pass real-device tests.

### Operational quality

- p95 worker processing latency and capacity targets are measured at 2x expected peak.
- A 24-hour soak shows bounded queues/resources and no sensitive telemetry.
- Rollback completes within the approved runbook target without disabling manual resources.
- Quarterly and pre-release resource verification is current.

---

## 13. Master Spec reconciliation

The following two Master Spec corrections were made with v1.1 so implementation
has one authoritative direction:

1. `triggered_by_message_id` was replaced in the Master `safety_events` schema by
   the non-reversible `source_event_key` contract in Section 8. Direct message
   linkage undermines “sender never stored” and exposes more data than needed.
2. The universal `app closes + clears from recent apps` promise was replaced by the
   platform contracts in Section 7. Android supports task removal through
   `finishAndRemoveTask()`; iOS requires a local neutral screen and app-switcher
   privacy cover and must not use private APIs or forced termination.

The Master schema and quick-exit section now reflect these contracts.

---

## 14. Resolved decisions and production gates

### Resolved decisions

| Decision | Resolution |
|---|---|
| Scope | Incoming active-relationship chat only |
| Detection | Server-authoritative deterministic phrase rules; no AI |
| Routing | Recipient only; sender never notified |
| Self-harm statements | Separate protocol required; excluded from this detector |
| Client detection | Prohibited |
| Message behavior | Never blocked; durable asynchronous processing |
| Tier 3 | Third distinct message within rolling 30 days |
| Notification | Generic, recipient-only, maximum one per 24 hours |
| Dismissal | Quality signal only; never proof or suppression input |
| Storage | Minimized event with non-reversible source key; no content/message/sender ID |
| Resources | Versioned, offline-capable, quarterly and pre-release verification |
| Quick exit | Android task removal; iOS neutral cover/app-switcher privacy behavior |
| Experiments | No A/B testing of trigger thresholds, resources, or safety copy |

### Blocking production gates

- [x] Master Spec reconciliation in Section 13 is merged into the source documents.
- [ ] DV professional approves phrase families, exact rules, resources, push
      previews, dismissal, quick exit, monitored-device guidance, and safety PIN recovery.
- [ ] Licensed clinical advisor signs the `ATTUNE_CLINICAL.md` Safety checklist.
- [ ] Ghanaian/West African cultural and language review is recorded.
- [ ] Ghana, US, England, and supported-country resources are re-verified within seven days of release.
- [ ] DV-experienced lawyer approves ToS, disclaimer, retention, deletion,
      liability, emergency wording, and admin-access process.
- [ ] Privacy/security review approves data minimization, HMAC, RLS, secrets,
      notification payload, logs, and threat model.
- [ ] Real-device Android/iOS quick-exit and lock-screen notification tests pass.
- [ ] Algorithm quality checklist, accessibility review, load/soak tests,
      incident runbooks, rollback test, and production smoke plan are complete.

This specification is ready for engineering planning and implementation. It is
not approval to release the feature or approval of a production trigger lexicon.
