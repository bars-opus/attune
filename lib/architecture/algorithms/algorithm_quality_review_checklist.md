# Algorithm Quality Review Checklist — v3.1

## Purpose
This checklist ensures every algorithm in this codebase achieves **10/10** across all **six dimensions**: **secure, robust, scalable, maintainable, observable, and user-aware (UX)**. Use during design, implementation review, pre-merge validation, and post-deployment verification.

---

## What "10/10" Means

| Dimension | 10/10 Standard |
|-----------|----------------|
| **Secure** | No Critical/High CVEs; OWASP Top 10 mitigated; no secrets exposed; least privilege enforced; penetration test passed |
| **Robust** | Survives dependency failure, network partition, 2x load, 24h soak; no resource leaks; graceful degradation defined |
| **Scalable** | Scales horizontally with no shared bottlenecks; cost per unit sublinear; no unbounded queues or collections |
| **Maintainable** | New team member can understand and modify within 1 day; runbook exists for each alert; intent and assumptions documented |
| **Observable** | Every failure mode has an alert; root cause identifiable within 5 minutes of alert firing; structured logs with correlation |
| **User-aware** | Error messages are actionable; p95 latency ≤ 200ms for interactive paths; no information leakage; accessible |

---

## This Checklist Is a Living Document

> **If an incident occurs and no checklist item would have caught it, a new item must be proposed within 5 business days.**
> **Last updated**: 2026-05-21
> **Owned by**: Repo maintainer (nano_embryo)
> **Change log**: Inline at bottom of file (see "Changelog" section below).

---

## Important — Scope Awareness

**Not every algorithm is a live service.** Apply checks judiciously based on the algorithm's nature:

| Tag | Meaning | Typical Algorithms |
|-----|---------|-------------------|
| `[ALL]` | Universal — never skip | All algorithms |
| `[SERVICE]` | Request-response services, APIs | REST endpoints, GraphQL, gRPC, edge functions |
| `[ASYNC]` | Background workers, scheduled jobs, queue consumers, webhook handlers | Retry queues, pg_cron jobs, webhook receivers, stream processors |
| `[BATCH]` | Batch jobs, ETL, migrations, training | Nightly pipelines, data exports, one-off scripts |
| `[MUTATION]` | Algorithms that change state | Any create/update/delete operation |
| `[UI]` | User-facing endpoints (browser or app) | HTML responses, mobile API responses |
| `[UI-WEB]` | Browser-rendered UI specifically | HTML pages, web dashboards — N/A for native mobile |
| `[MOBILE]` | Native mobile app code (iOS, Android, Flutter, RN) | Lifecycle, deep links, offline behavior, network changes |
| `[FIN]` | Financial / money-handling | Payments, payouts, ledgers, wallets, refunds — see § Financial / Money-Handling |

**Skip checks that don't apply** — but document the skip with a brief justification.

---

## Priority Definitions

| Priority | Meaning | Gate |
|----------|---------|------|
| 🔴 **P0-U (Universal Blocking)** | Never skippable; no exceptions | Code review cannot begin |
| 🔴 **P0-C (Contextual Blocking)** | Blocking if applicable; skip requires explicit justification | Code review cannot begin until resolved or skipped |
| 🟡 **P1 (High)** | Strong requirement; rare exceptions | Merge to main branch |
| 🟢 **P2 (Medium)** | Expected in all professional deployments | Production deployment |
| ⚪ **P3 (Nice to have)** | Improves quality but not blocking any gate | Backlog |

---

## Phase 1: Design & Architecture

*Complete during algorithm design, before writing code.*

### Safety & Correctness by Design

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 1.1 | Idempotency keys implemented for all mutations | 🟡 P1 | [MUTATION] | Design doc shows idempotency key flow; retry produces same outcome |
| 1.2 | Timeouts defined for ALL external calls: connect, read, total | 🟡 P1 | [ALL] | Config file or constants show distinct timeout values per dependency |
| 1.3 | Graceful degradation strategy defined for each dependency failure | 🟢 P2 | [SERVICE] | Design doc answers: "If X fails, algorithm does Y" for each dependency |
| 1.4 | Authorization checked at EVERY resource access point, not just entry | 🔴 P0-U | [SERVICE] | Code review: auth check exists before each sub-resource access |
| 1.5 | Authentication verified (token validity, session integrity, credential rotation) | 🔴 P0-U | [SERVICE] | Auth middleware or explicit check before any business logic |
| 1.6 | Concurrency risks identified and mitigation documented | 🟡 P1 | [ALL] | Design doc lists shared state and chosen strategy (lock, atomic, isolate) |
| 1.7 | Algorithm is stateless where possible; if stateful, sharding/affinity documented | 🟢 P2 | [SERVICE] | State stored externally (DB, cache) or sharding key documented |
| 1.8 | Time and space complexity documented (Big O: worst, average, amortized) | 🟢 P2 | [ALL] | Comment in code or design doc: O(n log n) time, O(n) space |
| 1.9 | Consistency model documented (strong, eventual, causal, read-your-writes) | 🟢 P2 | [MUTATION] | Design doc states model and justifies choice |
| 1.10 | Compensating transactions / rollback paths defined for multi-step failures | 🟡 P1 | [MUTATION] | Saga, undo log, or explicit cleanup documented for partial failures |
| 1.11 | Data privacy impact assessed: PII identified, minimized, retention defined | 🟡 P1 | [ALL] | Data flow diagram shows PII locations; retention policy linked |
| 1.12 | Cost/compute budget estimated (scans, API calls, memory per unit) | ⚪ P3 | [ALL] | Back-of-envelope calculation in design doc |

---

## Phase 2: Implementation Review (Code-Level Correctness)

*Complete during code review, before merging PR.*

### Input & Output Safety

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 2.1 | Input sanitization: type, length, range, format, semantics, size, encoding | 🔴 P0-U | [ALL] | Validation library used; fuzz test provides malformed inputs |
| 2.2 | Parameterized queries: no string concatenation for SQL, shell, LDAP, commands | 🔴 P0-U | [ALL] | Static analysis rule active; grep for string interpolation in queries |
| 2.3 | Constant-time comparison for secrets (passwords, tokens, API keys, signatures) | 🔴 P0-U | [ALL] | Uses `crypto.timingSafeEqual` or equivalent; not `===` or `==` |
| 2.4 | Error messages don't leak: no stack traces, internal paths, user existence, schema | 🔴 P0-U | [SERVICE] | Test: trigger errors; response contains only generic messages |
| 2.5 | Resource limits enforced per request: memory, recursion, query rows, iterations, file size | 🔴 P0-U | [ALL] | Configurable limits exist; fuzz test with extreme inputs doesn't crash |
| 2.6 | Output sanitization: prevent injection in responses (XSS, header, log injection) | 🔴 P0-C | [SERVICE] | Context-appropriate encoding (HTML entities, JSON encoding, log scrubbing) |

### Secrets & Credentials

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 2.7 | No hardcoded secrets of ANY kind: API keys, passwords, tokens, private keys, certificates, connection strings, signing secrets, webhook secrets, encryption keys | 🔴 P0-U | [ALL] | Automated secret scan (GitLeaks, truffleHog) returns zero findings |
| 2.8 | Secrets fetched from vault/secrets manager/env vars at runtime, never in source or config files | 🔴 P0-U | [ALL] | Code review: all secrets accessed via `getSecret()` or equivalent |
| 2.9 | `.env` files and config files with secrets excluded from version control (.gitignore verified) | 🔴 P0-U | [ALL] | `.gitignore` contains `.env`, `*.pem`, `credentials.*`; secret scan confirms |

### Resource Lifecycle & Leak Prevention

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 2.10 | All finite resources released in finally/defer/using blocks: connections, streams, file handles, locks, native memory | 🔴 P0-U | [ALL] | Static analysis rule for unclosed resources; manual review of resource acquisition |
| 2.11 | Connection pooling used: no ad-hoc connection creation per request | 🟡 P1 | [SERVICE] | Pool library configured with max lifetime, idle timeout, health check |
| 2.12 | Thread/task/goroutine pool bounded: no unbounded spawning | 🟡 P1 | [ALL] | Worker pool or bounded concurrency primitive used; max concurrency configurable |
| 2.13 | Cleanup on cancellation/timeout: resources freed when context is cancelled | 🟡 P1 | [ALL] | Cancellation token/timer triggers resource release; test with forced cancellation |
| 2.14 | Memory growth bounded: caches have eviction (LRU/TTL/max size); no unbounded collections | 🟡 P1 | [ALL] | Cache config shows eviction policy; no `Map` with unbounded `put` |
| 2.15 | Soft timeouts / cooperative yielding: long loops yield to event loop or check cancellation | 🟡 P1 | [ALL] | `await` or `yield` points in loops; no tight CPU-bound loops without escape |

### State & Side Effects

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 2.16 | Shared mutable state protected: locks, atomic operations, or isolated state | 🟡 P1 | [ALL] | Race detector (`-race`) passes on concurrent tests |
| 2.17 | Side effects isolated: pure logic separated from I/O | 🟢 P2 | [ALL] | Core logic testable without mocking I/O |
| 2.18 | Idempotency implemented for all mutations (same input + retry = same outcome) | 🟡 P1 | [MUTATION] | Test: send same mutation twice; verify idempotency key prevents double effect |

### Financial / Money-Handling

*Apply to any algorithm that records, moves, computes, or audits monetary value.*

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 2.19 | Money is never stored or computed as floating point. Use integers in minor units (cents, kobo, pence) or arbitrary-precision decimal. Only convert at the display boundary. | 🔴 P0-U | [FIN] | grep for `* 100`, `/ 100`, `double amount`, `Float`; verify only at I/O boundaries. Currency math test: $0.1 + $0.2 == $0.3 exactly. |
| 2.20 | Provider idempotency keys reused across retries — same key on attempt 1, 2, … N. Never regenerate. | 🔴 P0-U | [FIN][MUTATION] | Trace one withdrawal across 3 retry attempts; same `Idempotency-Key` / `reference` sent every time. Provider response shows "already exists" on attempt 2+. |
| 2.21 | Webhook handlers idempotent on event ID: receiving the same event twice produces no double-effect | 🔴 P0-U | [FIN][ASYNC] | Replay an already-processed webhook payload; verify second insert hits unique-constraint and exits cleanly, no double credit. |
| 2.22 | Append-only audit log records every state transition with actor, target, outcome, before/after; never updated or deleted after write | 🟡 P1 | [FIN][MUTATION] | Schema: no UPDATE/DELETE grants on audit table; trigger or RLS prevents modification. Spot-check sample entries have all required fields. |
| 2.23 | Periodic reconciliation: scheduled job compares our recorded state against provider state and flags discrepancies | 🟢 P2 | [FIN][ASYNC] | Reconciliation job runs at least daily; report shows zero unresolved discrepancies, or a manual review queue for any. |

---

## Phase 3: Performance & Scalability

*Complete before performance testing.*

### Efficiency

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 3.1 | Pagination for list operations: cursor-based or limit/offset; max page size enforced | 🟢 P2 | [SERVICE] | API returns pagination metadata; default and max limits configured |
| 3.2 | No N+1 queries: batch database or API calls; use joins or DataLoader pattern | 🟢 P2 | [ALL] | Query log shows batched queries; ORM eager loading configured |
| 3.3 | Database queries use appropriate indexes: EXPLAIN run on all query patterns | 🟢 P2 | [ALL] | EXPLAIN output shows index usage; no full table scans on large tables |
| 3.4 | Cache strategy defined and documented: what, TTL, invalidation, cache keys, stampede protection | 🟢 P2 | [SERVICE] | Cache config documented; invalidation triggers identified |
| 3.5 | Parallelization used where safe; not used where order or side-effect ordering matters | ⚪ P3 | [ALL] | Evidence of benchmarking before/after parallelization |
| 3.6 | I/O batching: coalesce multiple small reads/writes | ⚪ P3 | [ALL] | Buffer or batch size configured |

### Resilience Under Load

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 3.7 | Backpressure handling: bounded queues, load shedding, or rate limiting | 🟢 P2 | [SERVICE] | Queue max size configured; behavior on full queue defined (shed, block, throttle) |
| 3.8 | Rate limiting implemented and tested: per user/IP/endpoint/tenant | 🟢 P2 | [SERVICE] | Load test proves 429 returned at configured threshold |
| 3.9 | Retry logic with exponential backoff and jitter for transient failures. Concrete bounds: max attempts 3–6 for sync paths, up to 10 for async queues; base delay ≥ 250ms; max delay ≤ 60s for sync, ≤ 6h for async; jitter ≥ 25% of base delay | 🟢 P2 | [ALL] | Config values present in code; unit test asserts cadence. For async, exhausted retries land in dead-letter — see 4.14. |
| 3.10 | Retry logic does NOT retry on permanent errors (auth failures, validation errors, 4xx) | 🟡 P1 | [ALL] | Error classification logic: retryable vs non-retryable errors |
| 3.11 | Circuit breaker for flaky dependencies: open on threshold, half-open for probing | ⚪ P3 | [SERVICE] | Circuit breaker library configured; failure threshold and timeout defined |
| 3.12 | Graceful shutdown: drain in-flight requests, close resources, respect shutdown timeout | 🟡 P1 | [SERVICE] | SIGTERM handler implemented; in-flight request count reaches zero before exit |
| 3.13 | Bulkhead isolation: resource pools partitioned by operation type | ⚪ P3 | [SERVICE] | Separate thread pools or connection pools per operation category |

---

## Phase 4: Observability (Production Operations)

*Complete before deployment to production.*

### Logging & Tracing

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 4.1 | Structured logs at entry, exit, and key decision points (JSON format) | 🟢 P2 | [ALL] | Sample log output is valid JSON; includes timestamp, level, message, context |
| 4.2 | Correlation ID generated at entry and propagated to all downstream calls | 🟢 P2 | [SERVICE] | Trace one request through all services; same correlation ID appears in all logs |
| 4.3 | Distributed trace context propagated across services (W3C Trace Context or OpenTelemetry) | ⚪ P3 | [SERVICE] | Trace appears in distributed tracing tool (Jaeger, Honeycomb, etc.) |
| 4.4 | Sensitive data excluded from logs. **PII glossary** — these fields are PII and must be redacted: passwords, API tokens, OAuth tokens, webhook secrets, encryption keys, full email addresses, phone numbers, full names, government IDs, card PAN/CVV/expiry, full street address, GPS coordinates, IP addresses, session cookies, full provider response payloads containing any of the above. **Allowed in logs**: user IDs (UUIDs), short reference IDs, error categories, HTTP status codes, redacted shapes (e.g., `e***@example.com`). | 🔴 P0-U | [ALL] | Log redaction rule (`redactForLog` or equivalent) covers every glossary field; regex scan on production log sample finds zero hits for `@`, card number patterns, `Bearer `, `sk_`, `pk_`. |
| 4.5 | Log levels used correctly: ERROR for action-needed, WARN for potential issues, INFO for key events, DEBUG for investigation | 🟢 P2 | [ALL] | Review log output; no ERROR for recoverable conditions, no PII in INFO |

### Metrics & Alerting

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 4.6 | RED metrics: Rate (throughput), Errors (by type), Duration (p50/p95/p99) | 🟢 P2 | [SERVICE] | Metrics visible in dashboard (Grafana, Datadog, etc.) |
| 4.7 | Resource metrics: heap memory, GC pause time, connection pool wait, file descriptors, goroutine/thread count | 🟢 P2 | [SERVICE] | Dashboard shows resource trends over 7+ days |
| 4.8 | Business metrics: key outcomes, processing backlog depth, conversion rates | ⚪ P3 | [ALL] | Domain-specific metrics defined and emitted |
| 4.9 | Alerts defined and linked to runbooks for: error rate spike, p95 latency spike, resource exhaustion, zero traffic (dead service) | 🟢 P2 | [SERVICE] | Alert rules in monitoring system; each alert links to a runbook |
| 4.10 | Alert thresholds tested: triggering conditions verified in staging | 🟢 P2 | [SERVICE] | Load test pushes metric past threshold; alert fires within expected time window |

### Configurability & Debugging

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 4.11 | Configurable thresholds: timeouts, limits, retry counts, batch sizes; no hardcoded magic numbers | 🟢 P2 | [ALL] | All operational parameters sourced from config/env; defaults documented |
| 4.12 | Health check verifies all critical dependencies are reachable and responsive | 🟢 P2 | [SERVICE] | `/health` returns 200 only if DB, cache, queue all pass their checks |
| 4.13 | Readiness check signals ability to accept traffic; false during startup, draining, or degraded | 🟢 P2 | [SERVICE] | `/ready` returns 503 during startup; orchestrator stops routing traffic |
| 4.14 | Dead letter queue for async operations that fail after all retries exhausted | ⚪ P3 | [SERVICE] | Failed messages visible in DLQ dashboard; replay mechanism exists |

---

## Phase 5: User Experience (UX)

*Complete for user-facing algorithms; skip `[UI]` checks for backend-only.*

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 5.1 | Error responses are actionable: clear message, error code, and next-step hint | 🟢 P2 | [UI] | User testing: non-technical user understands what went wrong and what to do |
| 5.2 | p95 latency ≤ 200ms for **in-app interactive operations** (button taps, screen transitions, local list filtering). For operations bounded by external dependencies (provider redirects, third-party SDK calls), the 200ms target shifts to "first feedback rendered within 200ms" — a loading spinner, progress bar, or partial result. Document the actual p95 if outside the target. | 🟢 P2 | [UI] | Performance trace: cold tap → first paint ≤ 200ms. For external-dep operations: tap → loading indicator visible ≤ 200ms, even if full result takes seconds. |
| 5.3 | Progressive loading or streaming for operations taking >1 second | ⚪ P3 | [UI] | Partial results or loading state displayed within 200ms |
| 5.4 | Idempotent retry guidance: tell users if it's safe to retry after a failure | ⚪ P3 | [UI] | Error response includes `Retry-After` header or "safe to retry" indicator |
| 5.5 | No internal information leaked in UI: no stack traces, internal IDs, or system details | 🔴 P0-U | [UI] | Trigger errors; verify UI shows only user-friendly messages |
| 5.6 | Accessibility: error states, loading states, and content meet WCAG 2.1 AA minimum | ⚪ P3 | [UI] | Accessibility audit tool passes; screen reader can navigate error and loading states |

---

## Phase 6: Testing Evidence (Verification)

*Complete before merge; attach evidence to PR.*

### Correctness & Coverage

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 6.1 | Edge cases covered: empty, null, max, min, boundary values, Unicode, timezone, leap seconds | 🟡 P1 | [ALL] | Test file shows boundary cases; parameterized test covers each boundary |
| 6.2 | Failure scenarios tested: timeout, dependency down, invalid input, partial failure, network partition | 🟢 P2 | [ALL] | Mock/fake injects each failure; test asserts correct behavior (not crash) |
| 6.3 | Concurrency tested: race detector enabled; parallel test runs pass consistently | 🟡 P1 | [ALL] | CI runs tests with `-race` flag; no flaky failures in last 10 runs |
| 6.4 | Negative tests: verify what SHOULDN'T happen (no side effects on failure, no data loss on rollback, no duplicate on retry) | 🟡 P1 | [ALL] | Test asserts absence of effect after failure; database state unchanged |
| 6.5 | Property-based tests for invariants (e.g., "roundtrip(encode(x)) == x", "sort(a)+sort(b) == sort(a+b)") | ⚪ P3 | [ALL] | Property test framework used; at least one invariant test per core function |
| 6.6 | Deterministic behavior; or non-determinism explicitly documented, bounded, and seeded in tests | ⚪ P3 | [ALL] | Tests produce identical output given same seed; no flaky tests |
| 6.7 | Unit test coverage measured as **branch coverage** (not line). Tools: `flutter test --coverage` (Dart, produces `coverage/lcov.info`); `deno test --coverage=cov_dir` (Deno). Targets: core domain logic ≥ 90%, adapters/glue/repositories ≥ 70%, UI widgets ≥ 50%. | 🟢 P2 | [ALL] | `lcov --summary coverage/lcov.info` or `deno coverage cov_dir` output meets thresholds; uncovered branches reviewed and justified in PR. |
| 6.8 | Mutation testing passed on core logic: no surviving mutants | ⚪ P3 | [ALL] | Mutation testing report shows <5% surviving mutants in core module |

### Performance & Longevity

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 6.9 | Performance benchmark exists for critical paths; results attached to PR | 🟢 P2 | [ALL] | Benchmark output shows latency and throughput; regression threshold defined |
| 6.10 | Soak test / longevity test: run for ≥ 24 hours with stable resource usage. **Stability defined as**: heap growth ≤ +5% from t=1h to t=24h, open DB/HTTP connections ≤ +10%, file descriptors flat (±1), no monotonically-growing collections in heap dump, no leaked goroutines/isolates. | 🟢 P2 | [SERVICE][ASYNC] | Snapshot resource metrics at t=1h, 6h, 12h, 24h; compute deltas; attach to PR. |
| 6.11 | Load test: behavior at 2x expected peak load; latency degradation is graceful, not cliff | 🟢 P2 | [SERVICE] | Load test report shows p95 latency at 2x load; no error rate spike |
| 6.12 | Chaos test in staging: dependency killed mid-request; algorithm recovers within timeout | 🟢 P2 | [SERVICE] | Chaos experiment report; circuit breaker or fallback activates; no data corruption |

### Code Quality

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 6.13 | Documentation complete: intent, assumptions, failure modes, runbook link | 🟢 P2 | [SERVICE] | README or code comments answer: "What does this do? What does it assume? What breaks? How do I fix it?" |
| 6.14 | Runbook exists for each alert defined in Phase 4; includes diagnosis steps and mitigation | 🟢 P2 | [SERVICE] | Each alert rule links to a runbook; runbook has step-by-step instructions |

---

## Phase 7: Security Hardening (Final Verification)

*Complete before production deployment.*

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 7.1 | Dependency scan: all libraries free of known Critical/High CVEs | 🔴 P0-U | [ALL] | Automated in CI (Dependabot, Snyk, OWASP Dependency Check); zero Critical/High |
| 7.2 | Static analysis (SAST): passes without blocking findings | 🔴 P0-U | [ALL] | SonarQube, CodeQL, or Semgrep quality gate is green |
| 7.3 | Secret scan: no secrets in code, config, build artifacts, or commit history | 🔴 P0-U | [ALL] | GitLeaks or truffleHog runs on every commit; zero findings |
| 7.4 | Least privilege: service account has minimal required permissions; no blanket `*` IAM roles | 🟡 P1 | [SERVICE] | IAM policy reviewed; each permission justified by actual API call |
| 7.5 | Encryption in transit: all external communication uses TLS ≥ 1.2; internal uses TLS where possible | 🔴 P0-U | [SERVICE] | Certificate check; internal traffic analysis shows encrypted connections |
| 7.6 | CSRF/CORS configuration correct for browser-facing endpoints | 🔴 P0-C | [UI-WEB] | CORS headers restrict to known origins; CSRF tokens present on state-changing requests. **Skip if** project is native-mobile-only — document the skip on the PR. |
| 7.7 | Security scan runs continuously: not a one-time gate; CVEs monitored and alerted | 🟡 P1 | [ALL] | CI runs dependency scan on every PR; alert fires for new Critical CVE in production |

---

## Phase 8: Post-Deployment Verification

*Complete within 24 hours of production deployment.*

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 8.1 | Rollback procedure exists and is documented. **Tier 1 (best)**: automated canary with metric-based rollback (Spinnaker, Argo Rollouts). **Tier 2 (acceptable)**: manual rollback runbook with tested commands (e.g., `supabase functions deploy <fn>@<prev-version>` or `git revert <sha> && deploy`). **Tier 3 (not acceptable)**: "we'll figure it out." | 🟡 P1 | [SERVICE] | Tier 1 or Tier 2 runbook linked from this checklist; rollback time-to-recovery ≤ 15 min for Tier 1, ≤ 30 min for Tier 2. |
| 8.2 | Smoke tests pass in production: critical path exercised with real traffic | 🟡 P1 | [SERVICE] | Automated smoke test suite runs within 5 minutes of deploy; results in dashboard |
| 8.3 | Production metrics verified for 24 hours: error rate, latency, resource usage within baseline | 🟢 P2 | [SERVICE] | Dashboard comparison pre/post deploy; no regression beyond threshold |
| 8.4 | Checklist updated if any incident reveals a missing check (within 5 business days) | 🟢 P2 | [ALL] | Incident postmortem action item links to checklist PR |

---

## Phase 9: Continuous Improvement

*Ongoing; reviewed quarterly.*

| # | Check | Priority | Applies To | How to Verify |
|---|-------|----------|------------|---------------|
| 9.1 | Checklist reviewed and updated quarterly; stale items removed, new patterns added | ⚪ P3 | [ALL] | Last review date ≤ 90 days ago |
| 9.2 | Postmortems from incidents reference missing checklist items; those items are added | 🟢 P2 | [ALL] | Incident tracker shows checklist update action items |
| 9.3 | Team retro feedback on checklist: is it too heavy? missing patterns? false positives? | ⚪ P3 | [ALL] | Retro notes include checklist effectiveness discussion |

---

## Quick Reference: Priority Summary

| Priority | Count | Gate |
|----------|-------|------|
| 🔴 P0-U (Universal Blocking) | 17 | Code review cannot begin |
| 🔴 P0-C (Contextual Blocking) | 3 | Code review cannot begin unless skipped with justification |
| 🟡 P1 (High) | 21 | Merge to main branch |
| 🟢 P2 (Medium) | 28 | Production deployment |
| ⚪ P3 (Nice to have) | 15 | Backlog |

**Total checks: 84** — apply only what fits your context using the scope tags.

---

## PR Template Integration

Copy this into `.github/pull_request_template.md`:

```markdown
## Algorithm Quality Checklist v3.0

> **Context**: [ ] Service/API  [ ] Batch job  [ ] One-off script  [ ] UI-facing  [ ] Other: ____
> **Skip justifications**: Document any P0-C or other skipped items below.
> 
> | Check # | Reason skipped |
> |---------|-----------------|
> |         |                 |

### 🔴 P0-U (Universal Blocking — REQUIRED before review)
- [ ] 2.1 Input sanitization (type, length, range, format, encoding)
- [ ] 2.2 Parameterized queries (no string concatenation)
- [ ] 2.3 Constant-time comparison for secrets
- [ ] 2.4 Error messages don't leak internal info
- [ ] 2.5 Resource limits enforced (memory, recursion, rows, iterations)
- [ ] 2.7 No hardcoded secrets of ANY kind
- [ ] 2.8 Secrets fetched from vault/env at runtime
- [ ] 2.9 .env and config secrets in .gitignore
- [ ] 2.10 Resources released in finally/defer/using blocks
- [ ] 1.4 Authorization at EVERY resource access
- [ ] 1.5 Authentication verified
- [ ] 4.4 Sensitive data excluded from logs (see PII glossary)
- [ ] 5.5 No internal info leaked in UI (if applicable)
- [ ] 7.1 Dependency scan passed (zero Critical/High CVEs)
- [ ] 7.2 Static analysis passed
- [ ] 7.3 Secret scan passed (zero findings)
- [ ] 7.5 TLS ≥ 1.2 for external communication
- [ ] 2.19 Money never stored/computed as float (if [FIN])
- [ ] 2.20 Provider idempotency keys reused across retries (if [FIN])
- [ ] 2.21 Webhook handlers idempotent on event ID (if [FIN][ASYNC])

### 🔴 P0-C (Contextual Blocking — resolve or justify skip)
- [ ] 2.6 Output sanitization (XSS, injection prevention)
- [ ] 7.6 CSRF/CORS configured (if browser-facing)

### 🟡 P1 (Required before merge)
- [ ] 1.1 Idempotency keys (if mutation)
- [ ] 1.2 Timeouts for all external calls (connect, read, total)
- [ ] 1.6 Concurrency risks mitigated
- [ ] 1.10 Compensating transactions for multi-step failures
- [ ] 1.11 Data privacy assessed (PII identified, minimized)
- [ ] 2.11 Connection pooling used
- [ ] 2.12 Thread/task pool bounded
- [ ] 2.13 Cleanup on cancellation/timeout
- [ ] 2.14 Memory growth bounded (cache eviction)
- [ ] 2.15 Soft timeouts / cooperative yielding in loops
- [ ] 2.16 Shared mutable state protected (race detector clean)
- [ ] 2.18 Idempotency implemented (if mutation)
- [ ] 3.10 Retries don't retry on permanent errors
- [ ] 3.12 Graceful shutdown (drain in-flight, close resources)
- [ ] 6.1 Edge cases covered
- [ ] 6.3 Concurrency tested (race detector)
- [ ] 6.4 Negative tests (absence of side effects on failure)
- [ ] 7.4 Least privilege (service account permissions)
- [ ] 7.7 Security scanning is continuous, not one-time
- [ ] 8.1 Rollback procedure tested (Tier 1 canary OR Tier 2 manual runbook)
- [ ] 8.2 Smoke tests pass in production
- [ ] 2.22 Audit log append-only with actor/target/outcome/diff (if [FIN][MUTATION])

### 🟢 P2 (Required before production)
- [ ] 1.3 Graceful degradation strategy for each dependency
- [ ] 1.7 Stateless or documented state affinity
- [ ] 1.8 Complexity documented (Big O)
- [ ] 1.9 Consistency model documented
- [ ] 2.17 Side effects isolated (pure logic testable without I/O)
- [ ] 3.1 Pagination (if list operation)
- [ ] 3.2 No N+1 queries
- [ ] 3.3 Indexes verified (EXPLAIN)
- [ ] 3.4 Cache strategy defined
- [ ] 3.7 Backpressure handling
- [ ] 3.8 Rate limiting tested
- [ ] 3.9 Retry logic with exponential backoff + jitter
- [ ] 4.1 Structured logs (JSON, correlation ID)
- [ ] 4.2 Correlation ID propagated
- [ ] 4.5 Log levels used correctly
- [ ] 4.6 RED metrics (Rate, Errors, Duration)
- [ ] 4.7 Resource metrics (heap, connections, file descriptors)
- [ ] 4.9 Alerts defined + linked to runbooks
- [ ] 4.10 Alert thresholds tested
- [ ] 4.11 Configurable thresholds (no hardcoded magic numbers)
- [ ] 4.12 Health check
- [ ] 4.13 Readiness check
- [ ] 5.1 Error responses actionable (if UI)
- [ ] 5.2 p95 latency ≤ 200ms (if UI)
- [ ] 6.2 Failure scenarios tested
- [ ] 6.7 Unit test coverage ≥ 90% (core), ≥ 70% (adapters)
- [ ] 6.9 Performance benchmark exists
- [ ] 6.10 Soak test passed (24h stable resources)
- [ ] 6.11 Load test passed (2x expected peak)
- [ ] 6.12 Chaos test passed (dependency failure recovery)
- [ ] 6.13 Documentation (intent, assumptions, failure modes)
- [ ] 6.14 Runbook exists for each alert
- [ ] 8.3 Production metrics verified for 24h post-deploy
- [ ] 8.4 Checklist updated if incident reveals gap
- [ ] 9.2 Postmortem gaps fed back into checklist
- [ ] 2.23 Periodic reconciliation job exists (if [FIN][ASYNC])

### ⚪ P3 (Backlog — non-blocking)
- [ ] 1.12 Cost/compute budget estimated
- [ ] 3.5 Parallelization optimization
- [ ] 3.6 I/O batching
- [ ] 3.11 Circuit breaker
- [ ] 3.13 Bulkhead isolation
- [ ] 4.3 Distributed trace context
- [ ] 4.8 Business metrics
- [ ] 4.14 Dead letter queue
- [ ] 5.3 Progressive loading / streaming
- [ ] 5.4 Idempotent retry guidance
- [ ] 5.6 Accessibility (WCAG 2.1 AA)
- [ ] 6.5 Property-based tests
- [ ] 6.6 Deterministic behavior documented
- [ ] 6.8 Mutation testing passed
- [ ] 9.1 Checklist reviewed quarterly
- [ ] 9.3 Team retro feedback on checklist

---

## Changelog

### v3.1 — 2026-05-21
- Added Financial / Money-Handling section: 2.19 (float-free math), 2.20 (provider idempotency reuse), 2.21 (webhook idempotency), 2.22 (audit immutability), 2.23 (reconciliation).
- Added scope tags: `[ASYNC]` (background workers, scheduled jobs, webhook handlers), `[MOBILE]` (native mobile lifecycle / deep links / offline), `[UI-WEB]` (browser-rendered UI specifically), `[FIN]` (financial / money-handling).
- Sharpened vague thresholds: 3.9 (retry parameter bounds), 4.4 (PII glossary), 5.2 (latency carve-out for external hops), 6.7 (coverage tool + branch coverage), 6.10 ("stable" defined as % thresholds).
- 7.6 (CSRF/CORS) re-scoped to `[UI-WEB]` and gained an explicit "skip if native-mobile-only" note.
- 8.1 (canary deployment) gained tiered acceptance — Tier 2 manual rollback runbook is acceptable when Spinnaker/Argo isn't available.
- Process placeholders filled in: date, owner, changelog reference now inline (no separate file).

### v3.0 — initial version
- 79 checks across 9 phases, 6 dimensions, 5 priority levels.