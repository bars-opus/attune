# Dating Mode Review And Gates

**Purpose:** implementation companion for `DATING_MODE_SPEC.md` Section 16  
**Status:** engineering guardrails in place; human sign-off still required before production

## Review pack index

Use these documents together:

- `DATING_MODE_REVIEW_AND_GATES.md`
- `DATING_MODE_CLINICAL_REVIEW_PACKET.md`
- `DATING_MODE_CULTURAL_REVIEW_PACKET.md`
- `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`
- `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`

The implementation may continue behind feature flags without these approvals. Production release may not.

## What is already implemented

### Algorithm and explanation guardrails

- Alignment uses only approved aggregate dimensions and explicit values overlap.
- Love-language matching is excluded from ranking and explanations.
- Explanations are modest, source-grounded, and non-predictive.
- Alignment is presented as `limited_signal`, `some_shared_ground`, or `promising_shared_ground`.
- Regression tests cover symmetry, determinism, limited-signal fallback, and love-language exclusion.

### Consent and state

- Dating opt-in, terms acceptance, age confirmation, and profile activation are modeled separately.
- Dating state transitions are server-authoritative RPC calls rather than direct client writes.
- Consent events are append-only.
- Exit, pause, block, unmatch, and private reflections have explicit backend contracts.

### Safety foundations

- Safety Resources entry points exist in Dating dashboard, matches, and guided-date flow.
- Quick Exit is available from guided-date flow.
- Block flow ends visibility and future pairing.
- The current build avoids pretending that dating chat is already clinically and operationally approved.

## What is not honestly complete yet

### Human review

- Clinical advisor approval of included dimensions, transforms, explanations, uncertainty copy, and excluded claims
- Ghanaian/West African cultural review of language, defaults, prompts, and dating assumptions
- Legal/privacy approval of terms, age-verification path, retention, moderation, and report evidence
- Safety approval for dating chat scope, copy, operations, and escalation procedures

### Operational readiness

- Photo and bio moderation workflow
- Stronger adults-only verification beyond self-attestation
- Multi-account RLS validation in a seeded environment
- Production monitoring, canary, rollback, and incident runbooks

## Decision rule

If a question requires a licensed clinical judgment, a Ghanaian/West African cultural judgment, a legal/privacy decision, or an operational moderation commitment, the answer must be recorded by the relevant owner in the linked review packet. Engineering must not invent it.
