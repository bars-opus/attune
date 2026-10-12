# Ledger — P3/P4 deferred minors M1–M11 (user: fix all before testing)
M2 fixed — planning_minors_contracts RED (option restored under Date block) → GREEN
M4 fixed (orphan sweep in nightly purge; bucket JPEG/10MB limits when storage has the columns) — contract RED via mutation (old purge) → GREEN. Ruling: bucket limits only assertable on hosted storage (local stub lacks the columns).
M5 fixed — image_size.test.ts RED (module missing) → GREEN; deno 16/16
M6 fixed — service_role read+append only; BEFORE TRUNCATE trigger — contract GREEN
M7 fixed — is_int never NULL; cast after check — contract GREEN
M9 fixed — no version bump on server preview write — contract RED via mutation → GREEN; rich contract link versions back to 1/2
M1 fixed — minors widget test RED → GREEN. Also exposed: every Planning swipe-delete tripped the dismissed-widget assertion on failure; all 7 sites now delete inside confirmDismiss.
M3 fixed — TTL 10 min, reuse 8 min — test RED → GREEN
M8 — not reproducible (photo still attached after close in this Riverpod version); hardened anyway (notifier/picker read before awaits, _alive guards). Test passes before and after.
M10 fixed — test RED (tick flickered back) → GREEN
M11 fixed — PlanningUnavailableScreen with AppBar + Go back, used by both planning routes — test RED → GREEN
Ruling: M6 keeps service_role's table privileges — service_role_grants_test requires every public table be readable+updatable by workers; the append-only guarantee comes from the row trigger (UPDATE/DELETE) and the new TRUNCATE trigger, for every role incl. owner — cost if wrong: none (privilege without effect).
Verification: full flutter test 2361/2361; flutter analyze 0 errors, 70 pre-existing warnings, none in Planning/router/notification config; full SQL harness 68 PASS + 1 pre-existing FAIL (settings_accessor, Vault); planning concurrency PASS; deno planning-link-preview 16/16.
