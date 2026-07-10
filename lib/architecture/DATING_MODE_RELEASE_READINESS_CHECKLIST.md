# Dating Mode Release Readiness Checklist

**Source:** `DATING_MODE_SPEC.md` Section 16  
**Purpose:** make release gates executable by owner rather than implied by the spec

Mark each item with:

- `done`
- `blocked`
- `n/a`

Add owner and evidence link beside each item before release review.

## 1. Clinical and product

- [ ] Clinical advisor approves included dimensions, transforms, explanations, uncertainty copy, and excluded claims.
- [ ] Love-language matching is absent from ranking and compatibility explanations.
- [ ] No copy predicts success, health, safety, readiness, or attachment-pair destiny.
- [ ] Ghanaian/West African cultural review is recorded.
- [ ] No swipe, browsing, count, admirer, urgency, confetti, or monetized revelation mechanic exists.

## 2. Consent and privacy

- [ ] Eligibility, Dating opt-in, terms, age gate, profile activation, and historical-data consent are distinct server-authoritative states.
- [ ] Refusing historical-data consent still permits Dating Mode.
- [ ] Consent withdrawal invalidates historical snapshots and pending introductions.
- [ ] Former-partner data, Healing content, safety data, raw messages, and private reflections are absent from ranking.
- [ ] Retention schedule, export, deletion, private storage, signed URLs, EXIF stripping, analytics minimization, and privacy impact assessment are approved and tested.

## 3. Security and trust

- [ ] RLS/RPC tests with at least four accounts prove no profile enumeration, cross-user reads, one-sided-interest leakage, actor forgery, or block bypass.
- [ ] Adults-only enforcement and protected correction flow are tested; age is never a client-editable integer.
- [ ] Photo/bio moderation, appeal, block, unmatch, report, spam, impersonation, and harassment procedures are operational.
- [ ] Dating messaging Safety scope and user copy are explicitly approved and tested.
- [ ] Push, logs, analytics, traces, crash reports, and support tools contain no prohibited Dating data.

## 4. Algorithm and operations

- [ ] Golden fixtures prove symmetry, determinism, boundedness, provenance, missingness neutrality, and explanation fidelity.
- [ ] Candidate hard filters are symmetric and cannot be weakened by refresh or empty-pool behavior.
- [ ] Concurrent interest creates one mutual match; retries are idempotent.
- [ ] Batch complexity, capacity, cost, indexes, bounded queues, retries, dead-letter handling, reconciliation, and failure recovery are measured.
- [ ] Fairness/cultural evaluation, drift thresholds, monitoring, alerts, runbooks, feature flags, canary, and rollback are approved.
- [ ] Account pause, exit, relationship creation, consent withdrawal, block, suspension, and deletion invalidate the correct records within documented SLAs.

## 5. UX and accessibility

- [ ] Alignment preview appears before photos and includes the limitations note.
- [ ] One-sided interest, pass, expiry, pool size, and rejection remain private in UI, API, notification, and timing behavior.
- [ ] Every state works with screen readers, text scaling, non-color indicators, localization, reduced motion, offline/retry behavior, and privacy cover.
- [ ] Safety Resources, block, report, and unmatch are easy to reach and never paywalled.

## 6. Required evidence pack before release meeting

- [ ] Clinical review packet completed
- [ ] Cultural review packet completed
- [ ] Dating chat safety decision recorded
- [ ] RLS/RPC test results attached
- [ ] Real-device quick-exit validation attached
- [ ] Privacy/security sign-off attached
- [ ] Moderation/support runbook attached
- [ ] Rollout and rollback plan attached
