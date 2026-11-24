# Dating Mode review and gates

**Status:** replaced in Spec 2 W10 (2026-11-24). The gates are now those of
`docs/superpowers/specs/2026-10-24-dating-mode-design.md` §8: each wave's
"Gate before production switch-on" line, and W10's. Where this file and the
design spec differ, the spec wins.

## How a gate is kept

- **Machine-checkable gates** are read by `get_dating_launch_readiness()`
  (the owner, from the SQL editor, or the console's Launch readiness page;
  the safety owner's). It is red while the project reads development, and
  green only when every gate is (R-6). See
  `DATING_MODE_RELEASE_READINESS_CHECKLIST.md` for the list.
- **Human gates** (legal opinions, registrations, assessments, sign-offs,
  the pen test, drills, the device matrix) are recorded as evidence
  references: per country in `country_safety_config.legal_checklist`
  (published from the console's Countries page) and per flag in
  `private.flag_production_gates` (`record_flag_gate_evidence`). A
  reference is the place the signed document lives, never `DEV-…` and
  never blank: in production a `DEV-` reference is refused and neither a
  `DEV-` nor a blank one ever counts.
- **What reads as `DEV-`:** `private.is_dev_reference` matches `DEV-` in
  any case after trimming spaces, tabs, line breaks, the no-break and
  narrow no-break spaces, the zero-width space and the byte-order mark, and
  reads any Unicode hyphen or dash (U+2010–2015, U+2212, U+FE63, U+FF0D)
  as `-`. `private.is_real_reference` is "not blank (after the same
  trimming) and not `DEV-`". Every W10 check uses these two.
- **Production mode is the owner's alone** (`attune_environment`, set in
  Vault, never by `ALTER DATABASE`, which reaches only new sessions). No
  migration, script or edge function sets it; CI fails one that names it.

## Production-mode guards (Spec 2 W10)

While the project reads production:

- `publish_country_config` refuses a checklist with a `DEV-` reference at
  any level, the same-gender reconsideration's too (`dev_reference`); a
  reduction is still published, with the check reported.
- It refuses an **opening** while any launch gate for that country is red
  (`config:launch_not_ready`, with the red gates in `gates`). An opening is
  a publish that leaves Dating on and opens the country or a region newly
  open, turns same-gender matching on, or loosens the tier (1 is the
  strictest; a missing tier reads as loosened). A publish with Dating off
  is never an opening: a closed country exposes nobody, and the publish
  that later opens it runs every gate. Closing, narrowing, tightening the
  tier and switching same-gender off are never refused by this guard.
- **Setting production mode opens nothing and runs no gate.** A country
  left open in development stays open, with everything that stood there
  (sandbox passes, `DEV-` configs), so the switch-on route requires every
  country closed and Dating off before the flip, and the console's Launch
  readiness says in red when a country is open in production while a gate
  is red.
- A gated flag whose evidence is a `DEV-` or blank reference can't be
  turned on, and `production_flag_violations()` lists it (it lists one in
  development too, as a report); `record_flag_gate_evidence` refuses a
  `DEV-` reference (`flag:dev_reference`).
- The introductions and chat configs can't be activated with a `DEV-`
  reference (W5a, W6b). Their own triggers keep an ASCII-only rule, so a
  `DEV-` written with a Unicode dash or a no-break space passes them; the
  readiness reads every active config with the full rule, so such a config
  still reads red (`introductions_config`, `chat_config`) and blocks every
  opening. Verification refuses the fake and sandbox providers (W4a); the
  CSAM matcher refuses its stub (Spec 1 W7b).

## Development mode (until launch)

The owner launches on the current hosted project (2026-11-23), so there is
no separate production project. Until launch it stays in development mode
with every Dating and traveller flag on, for testing and demos to advisors.
There the guards don't refuse anything, but the readiness and the console
still say what is red: `environment`, `flag_evidence` and
`no_flag_violations` read red (the last for every spec's gated flags,
Spec 1's development flags too), a `DEV-` checklist shows `dev_reference`,
and the Launch readiness page carries a calm note that this is expected
before launch. The clean-up before production mode is in
`DATING_MODE_RELEASE_READINESS_CHECKLIST.md` §3.

## Decision rule

If a question needs a licensed clinical judgment, a Ghanaian or West
African cultural judgment, an LGBTQ+ or DV safety judgment, a legal or
privacy decision, or a moderation commitment, the answer is recorded by the
relevant reviewer and its reference entered as above. Engineering never
invents it.
