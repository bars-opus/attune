# Dating Mode Dating Chat Safety Plan

**Purpose:** define what must exist before Dating Mode can ship a real post-match chat experience  
**Status:** planning document; current implementation intentionally avoids claiming this is production-ready

## 1. Current state

The current build exposes:

- Safety Resources entry points
- Quick Exit in guided-date flow
- block/unmatch/report backend contracts

The current build does **not** yet expose a production-ready dating chat surface because the existing Safety System spec is scoped to active-relationship chat, not post-match dating chat.

## 2. Required decision

Before chat ships, one of these must be explicitly chosen and recorded:

1. Extend Safety System scope to include Dating chat with reviewed rule families, storage rules, routing logic, and copy.
2. Create a separate Dating Chat Safety spec if the language, thresholds, or escalation procedures differ materially from couples chat.

No implementation should silently assume option 1 without written approval.

**Working decision (product owner, July 2026): option 2 — a separate Dating
Chat Safety specification.** Rationale: the threat models barely overlap. The
couples Safety System targets coercive control by an intimate partner (tiered
phrase families, at-risk-recipient routing, discreet exit). Dating chat's
dominant threats are harassment, sexual content, grooming, impersonation, and
romance scams between strangers — different rule families, different
escalation, different copy. Recipient-only asynchronous routing is retained as
a design principle. This working decision still requires safety-owner review
before the Section 5 blockers can be checked; it removes only the ambiguity
about which document to write.

## 3. Minimum implementation requirements for dating chat

### Safety scope

- define whether the current deterministic phrase-family detector applies to dating chat
- define which message families are in scope
- define whether thresholds differ for newly matched users
- define whether routing remains recipient-only and asynchronous
- define romance-scam scope as a first-class family: financial-request
  patterns (money, account details, mobile-money transfers, gift cards,
  crypto), urgency/emergency framing, and off-platform payment redirection —
  West Africa is a known scam-operation base and a trust-branded matching app
  is an attractive hunting ground
- define a dedicated scam report category and its moderation runbook entry
- pair detection with education: the guided first-date financial-safety
  reminder (DATING_MODE_SPEC.md Section 9) links directly to the scam report
  path

### User-facing controls

- block and report must remain one or two taps away from the dating chat screen
- Safety Resources must be reachable from chat
- Quick Exit availability must be confirmed for dating chat surfaces too
- no message sending delay or client-side detection may be introduced

### Operations

- moderation runbook for dating reports
- support triage ownership
- evidence retention and admin access process
- copy for generic safety notifications, if any are approved

### Privacy

- no one-sided interest leakage through chat notifications
- no prohibited dating data in push previews, traces, analytics, or support tooling
- confirmed data-minimization policy for any dating-chat safety event storage

## 4. Engineering tasks once scope is approved

- add route and UI only after reviewed scope is signed off
- connect dating match records to chat bootstrap in a way that does not reveal blocked or closed states incorrectly
- add block/report entry points directly inside the dating chat composer/header
- add tests proving blocked users cannot continue messaging through stale chat state
- verify Safety Resources and Quick Exit availability from dating chat on real devices

## 5. Release blockers

- [ ] Safety scope explicitly approved for dating chat
- [ ] Reviewed user copy approved
- [ ] Moderation and support runbook approved
- [ ] Privacy/security review approved
- [ ] Real-device validation complete

