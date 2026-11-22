# Attune — Law-enforcement requests: policy (draft)

**Status:** Draft 1 (2026-11-21, Spec 2 W7c). For counsel: the final text is
counsel's, signed at W10 (Spec 2 §6.6). Not published until then.

**Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.6,
§4.8 (what Attune keeps and for how long), §6.8 (the DPIA).

## What this policy says

1. **Valid legal process only.** Attune discloses user data only in response
   to valid legal process from a competent authority in the user's
   jurisdiction, reviewed by the safety owner and counsel, or in an
   emergency involving imminent risk to life. An emergency disclosure is a
   human decision, recorded in the request log.
2. **Only what Attune keeps.** Attune can disclose only what it keeps
   (`§4.8` of the design). It never holds GPS, location history, selfie
   videos, ID images or face templates. An ID photo a person emails to
   support for an age check is deleted straight after it is checked, and
   the mailbox keeps mail for the shortest time it allows. Special-category answers (gender
   identity, who someone would like to meet, faith, marital history) are
   deleted when someone leaves Dating, and moderators cannot read them at
   all.
3. **No identification by orientation or gender identity.** Attune does not
   volunteer, and will contest where the law allows, any request whose
   purpose is to identify people by sexual orientation or gender identity.
4. **Telling the person.** Users are told about a request unless the law
   forbids it or telling them would put someone in danger.
5. **Every request is logged** in `law_enforcement_requests` (received, the
   jurisdiction, the legal basis, the scope, whether it is an emergency
   request, the decision, what was disclosed by category, when the person
   was told, who decided) and counted in a quarterly transparency summary:
   requests by country and type (legal process or emergency) and by
   decision, how many were met in whole or in part, reports by category,
   actions taken (also split by where they came from: a moderator's
   decision, a report's automatic step, a CSAM match or an age check; a
   restriction carried over from a deleted account is the same decision
   and isn't counted again), appeals and how many were overturned. Small counts are
   suppressed before the summary is published.

## How a request is handled (the safety owner)

The log and the summary are the safety owner's alone: no moderator can
read them.

1. Record it in the console's Law enforcement page as received (pending),
   ticking Emergency when it is an emergency request with no legal process
   yet.
2. With counsel, check the authority, the jurisdiction and the legal basis;
   narrow the scope to what the law requires.
3. Decide: refused, contested, disclosed or partly disclosed. Record what
   was disclosed by category (account, profile, messages, reports,
   restrictions, verification): never more than the decision covers. A
   recorded disclosure can only be widened, never narrowed or undone, so
   record it only once it has happened. A disclosure recorded in error is
   corrected by a support fix (an engineer, on the safety owner's written
   request), with its own record of what was changed and why.
4. Tell the person unless the law forbids it or it would put someone in
   danger; record when.
5. The log is kept 2 years (§4.8), then deleted by the daily purge.

## Reports Attune makes (escalations)

These are not requests: they are reports Attune's people decide to make,
recorded so the record shows what was done. None is ever sent
automatically.

- Recorded on the moderation case: police in the person's country (an
  imminent threat to life); NCMEC, the IWF or Ghana's Cyber Security
  Authority (CSAM from a report); CSA 292 for sextortion, only with the
  victim's consent.
- A CSAM hash match has no moderation case: its report to NCMEC, the IWF
  or the Cyber Security Authority is recorded in Spec 1's
  `safety_escalations`.
- The UK sextortion routes (Report Fraud, the Revenge Porn Helpline) have
  no recorded kind yet; a moderator records them in a case note, with the
  victim's consent.

## Questions for counsel

- Ghana (Act 843, the Cybersecurity Act) and the UK: which authorities and
  instruments count as valid legal process; the emergency standard.
- Whether 2 years is the right retention for the log.
- The wording of the published policy and the transparency report.
- The threshold below which counts are suppressed in the published report
  (Attune's own metrics are shown only at 50 or more).
- Whether the UK sextortion referrals need their own recorded kind.
- Whether "actions taken" in the published report should count only
  people's decisions, or the automatic steps too (the summary gives
  both).
