# Attune — Dating moderation runbook

**Status:** Draft 1 (2026-11-21, Spec 2 W7c; brought up to date with the W7
final fix waves, 2026-11-22). Owned by the safety owner. Not
in force until the W7 production gate is met: the safety owner, a moderator
who reads Twi, Ga and Pidgin, and out-of-hours P0 cover are named and
trained on this runbook; counsel has signed the law-enforcement policy
(`DATING_LAW_ENFORCEMENT_POLICY.md`); the report copy's review time matches
the staffed hours below.

**Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.2–§6.6.
Where this runbook and the design spec differ, the spec wins and this file
is corrected. This draft describes what Spec 2 W7a–W7c built; the known gaps
in §12 are things the console can't do yet.

## 1. Roles and hours

- **Safety owner:** the owner. Publishes country configuration, keeps the
  law-enforcement log (only the safety owner can read it), is the only
  person who lifts a CSAM hold (§5), decides appeals of their own decisions
  only 24 hours after the appeal (the console enforces this), and is the
  only person who sees cases that need sensitive routing (§8).
- **Moderator:** one contracted moderator who reads Twi, Ga and Pidgin.
- **Out-of-hours P0 cover:** a named person on call for P0 cases outside
  staffed hours.
- **Staffed hours:** 08:00–22:00 GMT, every day. A P0 report is due within
  four staffed hours and never more than 24 hours; P1 within 24 hours; P2
  within 48 hours; P3 within 72 hours. A P0 report filed outside staffed
  hours is due four hours into the next staffed day (a report at 21:00 is
  due at 11:00 the next day). An appeal shows as P2 and is due within 7
  days, the time the person is promised. The pilot's size is set so
  the measured P0 load fits this capacity. If the hours change, the review
  clock in the database changes with them (`private.dating_report_sla_due`,
  one function) and so does the report's sent line.
- **SLA alerts:** every 15 minutes the database sends one content-free line
  per priority that has a case past its time, about the oldest such case
  and timed from when it was filed ("P0 case waiting 3 h 40 m"), to the
  on-call channel (`moderation_alert_webhook`). It names no person and no
  case: open the console to see it. The line counts every open case,
  including cases only the safety owner can see (§8). So a moderator may get
  a line for a case that isn't in their queue: that case is the safety
  owner's, and the line repeats every 15 minutes until it is closed. An ID
  check (§6) has no SLA clock and never sends a line: it waits on the
  person, not on you. It stays in the queue's ID section.
- **Never on without people.** Dating is never switched on in production
  unless an active safety owner row and an active moderator row exist
  (§9). Until both exist, the report's sent line says reports go to the
  test review queue, even in production mode; deactivating every moderator
  turns the staffed line off again.
- **The health view** (`get_dating_operational_health`) is the safety
  owner's dashboard. It shows open reports by priority and those past due,
  and `id_checks_open` (how many ID checks are open and the oldest wait in
  hours). `id_checks_open` never pages anyone; look at it each staffed day.
  Its counters include `dating.sla.alert_rejected` (the on-call channel
  refused an alert line) and `dating.carry_over.relink_skipped` (§6).

## 2. Working in the console

- Sign in with your Attune phone account and your authenticator code. The
  console works only behind the access gate, on a managed device.
- **One console tab per moderator.** Your session lives in the browser tab
  you signed in from. Closing the tab signs you out, and a new tab starts
  signed out. Don't duplicate the tab: a duplicate shares the first tab's
  refresh token, and when one tab refreshes it, both can be signed out
  (sign in again to recover). The console also signs you out after 30
  minutes without use.
- **The queue** reads each kind of case separately (reports, appeals,
  signals, ID checks and so on), at most the first 200 of each;
  "More are waiting" means there are more than it shows. The ID checks come
  first, in their own **Waiting for ID / ID still needed** section (§6).
- **Claim** a case before working it, so the other person knows you have
  it. A claim stops another moderator claiming the case while you are
  working it. The safety owner can take a claim over at any time, and
  anyone can take it over once you have done nothing on the case for an
  hour; the audit log records the take-over. A claim is advice, not a lock:
  it does not stop someone else deciding the case, so talk to each other
  before deciding a case someone else has claimed.
- **Decisions can't be undone in the console.** A decision that can't be
  undone asks you to confirm and says what it will do. Read that line
  before you confirm.
- **"The server is busy"** means another write on the same person was in
  progress. Wait a moment and try again: repeating an action is safe,
  because the server recognises a repeat and doesn't do it twice.
- Every action you take (opening a case, claiming, each decision, a note,
  an escalation) is written to the audit log, which nobody can edit. It is
  kept 2 years.
- **Notes** never name someone's gender, who they want to meet, their faith
  or marital history; write what you saw and why you decided. A note is at
  most 1000 characters and every moderator who can see the case reads it.

## 3. Triage, category by category

For every report: read the reports and their text, the evidence (the last
50 messages, both sides), earlier cases on the same account or number, and
the safety families raised in the chat. All reports about one person join
one open case. If the case shows "The reporter's messages in this chat
triggered: …", weigh the report with that in mind: it took no automatic
step and did not count towards a hold. That note covers the chat's safety
events from the last 90 days only (older events are anonymised), so in a
long chat also read the evidence yourself for pressure or money asks from
the reporter.

The console's decisions: **Hold** (an interim hold, with a category),
**Lift the case's holds**, **Restrict** (suspend until a date, suspend
with no end date, or a closer look that the person never sees and that
keeps them out of new introductions; the dialog says what follows), **Ask
for ID (age check)**, **Confirm a minor** (with an open age report),
**Dismiss** (no action), **Record an escalation** and **Add a note**. An
ID check case has its own four actions (§6).

| Category | Priority | Look for | Decision options | Record |
|---|---|---|---|---|
| `underage_risk` | P0 | age cues in the evidence (school years, exams), an `age_signal` family, the profile | Ask for ID (§6); Confirm a minor (closes the whole app, Spec 1's age review); Dismiss | `underage_risk` |
| `csam` | P0 | **never view an image**; the case is the report alone | Hold with category `csam` (only the safety owner can lift it, §5); record an escalation (NCMEC, IWF or Ghana's Cyber Security Authority) once it is made through Spec 1 W7b's escalation runbook; Restrict | `csam` |
| `child_safety` | P0 | questions about children's routines or access | Hold; Restrict; escalate to police if a child is at risk now | `child_safety` |
| `threat_to_life` | P0 | a specific threat, a place, a time | Hold; escalate to police in the person's country (numbers from `support_resources`); Restrict | `threat_to_life` |
| `sextortion` | P1 | threats to share images, payment demands | Restrict; with the victim's consent only, escalate to CSA 292 (Ghana) or Report Fraud / the Revenge Porn Helpline (UK), §7 | `sextortion` |
| `romance_scam` | P1 | money, airtime or mobile-money asks; a `financial_request` family | Restrict | `romance_scam` |
| `threats` | P1 | threats short of life | Restrict; Hold if continuing | `threats` |
| `entrapment` | P1 | a profile built to lure people (photos, prompts, earlier cases) | Restrict | `entrapment` |
| `harassment` | P2 | repeated unwanted messages | Restrict until a date; Dismiss | `harassment` |
| `explicit_content` | P2 | unwanted sexual messages | Restrict until a date; Dismiss | `explicit_content` |
| `impersonation` | P2 | someone else's photos or name | Ask for ID; Restrict | `impersonation` |
| `hiding_relationship` | P2 | evidence of a current marriage | Restrict; Dismiss | `hiding_relationship` |
| `spam` | P3 | selling, links | Restrict; Dismiss | `spam` |
| `other` | P3 | read it | any | the closest category |

**What each decision does to holds.** Dismiss, Restrict and Confirm a
minor each end the case and lift the interim holds this case placed. Ask
for ID moves the age reports to a separate ID check (§6); the case keeps
its holds while other reports are open, and lifts them if it closes.
None of them lifts a hold another case placed, or a CSAM hold (§5).
**Lift the case's holds** shows on open and in-review cases: it lifts the
holds and report age checks this case placed, never an ID check's age
check or a CSAM hold, and decides nothing. It is the only hold lift on an
ordinary case (the age check's lift lives on the ID check, §6). Decided and
closed cases offer no lift.

**Signals** (dragnet, duplicate opener, money asks across matches, device
accounts): open the case, read what triggered it, and either dismiss it
(dismissing a dragnet case lifts its throttle) or restrict.

**Orphaned cases.** A case whose person deleted their account stays open
under their number's code, so a person who comes back on the same number
is still caught by it. An orphaned case always needs sensitive routing
(the console can't read the identity of a deleted person), so only the
safety owner sees it, and its SLA line repeats every 15 minutes until it is
closed. If nothing in it warrants action, Dismiss it. An orphaned **ID
check** is different: close it with No ID came, never Dismiss (§6).

**Relinked cases.** When someone comes back on the number, their first
restriction read relinks the number's orphaned cases to the new account.
A phone number can be recycled to a new holder, so a relinked case may now
point at someone who never did anything. On any case that was orphaned
before (it stood open with no account), check that the profile matches the
evidence before you Hold, Restrict or Ask for ID. If it doesn't, Dismiss
the case.

**Appeals.** Read the restriction, the original decision and the appeal.
You cannot decide an appeal of your own decision. The safety owner may,
working alone, but only 24 hours after the appeal was sent. When nobody is
recorded as having made the first decision (a hold carried over from a
deleted account, or a suspension from before W7), the console answers that
the decider is unknown: only the safety owner decides it, again 24 hours
after the appeal. Accept to lift the restriction ("Your appeal was
accepted. Dating is open again."); reject and the person reads "We looked
again and the decision stands." Each restriction has one appeal, so either
decision is final.

- The one appeal follows the person's number: if their appeal was rejected
  and they delete their account and come back on the same number, the
  carried restriction still reads as appealed.
- An appeal still open when the person deleted their account is lost with
  the account. When they come back, they can appeal once more, and that
  appeal starts a fresh 7-day clock.
- An interim hold is not appealable, but a hold carried over to a new
  account is (the old account's case may still be open). Before you accept
  an appeal of a carried hold, look for that open case: accepting ends the
  hold before the case is decided.

## 4. Never

- Never ban on one report or one phrase. A phrase never restricts anyone;
  an interim hold needs two independent P0 reports, or an `underage_risk`
  report with the person's own age cue in that chat (which places an age
  check instead).
- Never use nationality, network, name or region as a signal.
- Never act on a report whose substance is someone's gender identity:
  Dismiss it.
- Never contact police, NCMEC, the IWF or the CSA automatically. Every
  escalation is your decision, recorded in the console after you made it.
- Never view, download or describe CSAM. A hash hit holds the account and
  goes to the safety owner's reporting path without any image being shown.
- Never moderate a case you are part of (§8), and never hold a second
  Dating account of your own.

## 5. Holds

- **An interim hold** hides the person from introductions and stops them
  sending. Their conversations stay open; the other people see only
  silence. It is not a decision, and the person can't appeal it.
- **A person can have two live holds** (for example a report's hold and a
  CSAM hold). Each ends on its own path; lifting one leaves the other.
- **A CSAM hold** is any hold with category `csam`, whatever placed it: a
  hash hit, a CSAM report's corroboration, a moderator's Hold with category
  `csam`, or a hold carried over from a deleted account. A case's
  decisions and lifts never end it. Only the safety owner ends it,
  through the console's **CSAM holds** page, with a written reason that is
  kept in the audit log. A carried CSAM hold can't be appealed either.
- **When the safety owner lifts a CSAM hold:** only once review shows the
  hold's grounds were wrong. A false-positive hash hit is handled the same
  way as any other CSAM hold:
  1. Open **CSAM holds**. Each hold shows the date it was placed, where it
     came from (a hash match, or placed through a case) and whether it was
     carried over from a deleted account. No person is named.
  2. For a hash match, the review is the Spec 1 review the page lists
     beside the hold (its id, status and date): lift only once it is
     confirmed a false positive by the matcher vendor or the IWF.
  3. For a hold placed through a case (a report's or a moderator's), press
     **Open its case**: the review is that case. Decide the case first,
     then come back and lift.
  4. Press **Lift this hold**, write the reason (what the review found, at
     most 1000 characters; it is kept in the audit log), then confirm. The
     reason never describes an image and never names someone's gender,
     faith or who they want to meet.
  5. The person is back in introductions and can send again, unless
     another hold or restriction applies.
- **Spec 1's account hold is separate.** A hash hit also places Spec 1's
  `safety_review` account hold, which closes the whole app. Lifting the
  Dating hold does not touch it; it is cleared on Spec 1's own path.
- **When a suspension ends** (its date passes, it is lifted, or an appeal
  is accepted), Dating stays paused: the person taps Resume. A hold never
  pauses or closes anything, so nothing needs resuming when it lifts.

## 6. Age checks

**Ask for ID (age check)** on a case opens a separate **ID check** case for
the person (kind ID check). The case's open age reports move to it, with
an age check: Dating closes for the person until they show an ID. The ID
check is assigned to you, waits in the queue's **Waiting for ID / ID still
needed** section, and has no SLA clock: it never pages or counts as past
due. The case you asked from keeps its other reports and holds and stays
in review for them;
if nothing else is open there, it closes ("Asked for ID: moved to an ID
check") and lifts its holds, except a CSAM hold. The two cases link to
each other ("Open its ID check", "Open the case it came from"). New
reports never join an ID check: a report that arrives later goes to an
ordinary case. A person has one ID check at a time (an open one, or one
whose age check is still live after No ID came); Ask for ID is refused
while they have one.

**Corroboration after the ask (intended).** The age reports that moved to
the ID check no longer count towards a hold on the case they came from.
So a later P0 report on that case is a single report and places no hold
by itself. This is deliberate: the age check has already closed the
person's matches and Dating, and once their ID is verified, an open P0
report still keeps them out of new introductions.

**How the ID arrives.** The person's **Verify with ID** opens an email to
the support inbox with the subject "Attune ID check: " and the check's
reference code, for example "Attune ID check: AB23CD45" (8 letters and
digits; it names neither Dating nor the person). The app shows the same
code and asks the person to include it, with a photo of an official ID
that shows their date of birth. Nobody is asked for a phone number. Find
the ID check by its code: the console's **Waiting for ID / ID still needed**
section shows each ID check's code on its row (use the browser's find), and
the ID check's page shows it as "ID check code: …". Check the ID's date of
birth and that the name and face match the person's profile (on the case
it came from). Then delete the email and its attachment from the inbox and
its trash, straight away:
Attune keeps no ID images (`DATING_LAW_ENFORCEMENT_POLICY.md`, point 2).
The safety owner sets the support mailbox to the shortest retention it
allows, backups included, so a deleted email doesn't linger.
An email with no code (an older app, or an age check no case asked for)
can't be matched in the console: reply asking for the code shown on the
person's Dating screen, or pass it to the safety owner.

**On an ID check** the console offers only four actions, each with a
confirm that names its consequence. None of them changes the case the ID
check came from: decide its holds and reports there (Lift the case's
holds, Dismiss, Restrict as usual).

- **Lift the age check**: the ID shows an adult. On an open ID check it
  lifts the age check and closes it ("ID checked: an adult"; its age
  reports not upheld). On an ID check already closed with No ID came, see
  "A late ID" below.
- **Confirm a minor**: the ID shows they are under 18. It closes the ID
  check (its age reports upheld), restricts Dating for age review in place
  of the age check, and places Spec 1's account hold, which closes the
  whole app. That hold is cleared only by Spec 1's support path.
- **No ID came**: closes the ID check without an ID (its age reports
  upheld). The age check stays, so the person still can't use Dating, and
  the ID check stays in the section as **ID still needed**.
- **Dismiss (asked by mistake)**: closes an open ID check with no action
  and lifts the age check without an ID (its age reports not upheld). Use
  it only when asking was a mistake.
- Claim, Add a note and Record an escalation, as on any case. Hold,
  Restrict and Ask for ID are not offered on an ID check.

**An orphaned ID check** (the person deleted their account while it
waited; the page says "The account was deleted."): close it with **No ID
came**, never Dismiss. The console offers only No ID came, and the server
refuses Dismiss and Lift the age check on it, because either would free a
number nobody has verified. The age check then stays on their phone
number: if they return, Dating stays closed for them until they verify,
their ID check comes back to their new account with a **new code**, and a
late ID is handled from it. Ask for ID is refused for a number that has an
orphaned ID check.

**A returning person's ID.** If an ID email arrives from someone who
deleted their account and came back, ask them to open Dating once before
you look at the ID. That first read carries the age check to their new
account, shows them the new code and relinks their ID check. Until then
the ID check is orphaned: it isn't listed if it was closed, and Lift the
age check is refused if it is still open. Ask them to send the new code.

**A late ID** (after No ID came): open the ID check from the ID still
needed section. While its age check is live, **Lift the age check** frees
the person; the No ID came decision stands and its age reports stay
upheld (nothing about the reports changes, only the age check ends).
**Confirm a minor** is still there too.

**`dating.carry_over.relink_skipped`** (a health counter) means a
returning account already had its own open case of the same kind, so the
number's orphaned case was not relinked to it. The person stays checked
(their age check came back with them), but that check still points at the
orphaned case, and no console action can end it. The console can no longer
create this (Ask for ID is refused while a number has an orphaned ID
check), so it comes only from older data or a direct database change. When
the counter rises, the safety owner asks engineering for a recorded repair:
move the carried age check onto the account's own ID check, so it can be
lifted or confirmed from there once the ID is seen.

**Procedure:**

1. Ask for ID (age check) on the case. An ID check opens in the queue's
   Waiting for ID / ID still needed section.
2. When the "Attune ID check: <code>" email arrives, find the ID check by
   its code, check the ID as above, then delete the email and its
   attachment. No code: reply asking for it, or pass the email to the
   safety owner. A person who deleted and came back: ask them to open
   Dating once and send the new code.
3. ID shows an adult: **Lift the age check**. ID shows a minor: **Confirm
   a minor**. No ID after a reasonable wait: **No ID came** (the ID check
   stays in the section, so a late ID is handled from step 2).
4. Decide the case it came from as usual, if it is still open.

## 7. Escalation

Always a human decision, recorded with **Record an escalation** after you
made it: pick the kind (the console never picks one for you) and add the
other body's reference (at most 200 characters). Recording sends nothing
to anyone. The case page lists its **Escalations recorded**: the kind, the
date and whether you recorded it. Everyone who can see the case sees that
list, but only the safety owner and the person who recorded an escalation
see its reference.

- **Imminent threat to life:** police in the person's country (numbers from
  `support_resources`).
- **CSAM:** NCMEC's CyberTipline, the IWF, or Ghana's Cyber Security
  Authority, through Spec 1 W7b's escalation runbook. A hash hit has no
  Dating case: its escalation lives in Spec 1's `safety_escalations`, not
  in the console. A CSAM report has a case, so its escalation is recorded
  on the case.
- **Sextortion:** CSA 292 (Ghana) or Report Fraud / the Revenge Porn
  Helpline (UK), **only with the victim's consent**. For Ghana, the kind is
  "CSA 292, with the person's consent"; the console refuses plain "Cyber
  Security Authority" on a sextortion case. The UK routes have no kind in
  the console yet: write a note instead, naming the route, the date and
  that the person consented, but not the reference (a note is read by every
  moderator on the case).

**Requests from the police or a court** go to the safety owner, who
handles them under `DATING_LAW_ENFORCEMENT_POLICY.md` in the console's Law
enforcement page (only the safety owner can open it):

- **Record a request:** the country (two letters, like GH), the legal
  basis, what is asked for, and the day it was received if not today
  (within the log's last 2 years, and no later than tomorrow). Tick
  **Emergency request** when there is no legal process yet; the
  transparency summary counts emergencies apart.
- The console keeps one received time per request. Pressing Record again
  after "busy" or a lost answer sends the same request, so it is never
  logged twice. Changing any field (or Emergency) makes it a new request
  with a new time.
- **Deciding:** use **Decide** on the request's row. Recording the same
  request again with a different decision answers "This request is already
  in the log with another decision": press **Decide it**, which decides
  that logged request by its id.
- A recorded disclosure can only be widened (keep every category already
  disclosed). One recorded in error is corrected through support (an
  engineer, on the safety owner's written request), with its own record.
- Tick "The person was told" once they have been; it can't be unticked.

## 8. Sensitive routing and parties

A case that puts side by side two people who are not a woman and a man, or
anyone whose answer can't be read, is shown only to people with sensitive
routing (initially only the safety owner). The console decides this each
time it shows the queue or a case; nothing records it. If you are told a
case "isn't available", that is all you need to know.

You never see a case you are part of. You are a party when you are the
case's person, a reporter on it, or a member of a chat it comes from (by
account or by phone number), or a party to the case behind an appealed
restriction. You also never see your own photo or identity check. The
console treats such a case as one that doesn't exist.

Gaps the console doesn't catch, so you must:

- **A second account on another number.** The console knows you only by
  your moderator account and its number. Declare any other Dating account
  to the safety owner, and don't hold one.
- **An earlier case.** If you reported this person before, or were in a
  chat with them, in an earlier case, the console still shows you the new
  case and the earlier case's outcome. Hand it to the other moderator.
- **The safety owner as a party.** If the safety owner is a party to a
  case that needs sensitive routing, nobody can see it, and its SLA line
  repeats. The safety owner must give sensitive routing to a second,
  trained moderator (set `sensitive_routing_allowed` on that moderator's
  row) for that case, and take it back afterwards.

## 9. Moderator access

- Moderator rows (`dating_moderators`) are added by hand in the SQL editor;
  no migration names a person. Each moderator enrols an authenticator at
  first sign-in.
- **Dating needs both rows.** Dating is never on in production without an
  active safety owner row and an active moderator row (§1). Before
  deactivating the last active moderator, switch Dating off or name a
  replacement.
- **To cut someone off at once, deactivate their moderator row**
  (`active = false`): every call then answers "This account isn't a
  moderator." Removing
  their authenticator is not enough: a signed-in session stays valid for
  about an hour afterwards.
- Sensitive routing is given per moderator row and taken back the same way.
- **Repairs:** never re-apply one W7 migration on its own. W7c re-creates
  functions W7a and W7b define; re-running W7a or W7b alone puts their
  older bodies back. Re-apply from the earliest W7 file through the last,
  each with its twin.

## 10. Wellbeing

- No exposure to CSAM, ever.
- After any P0 involving violence, step off the queue for the rest of the
  shift; the out-of-hours cover or the safety owner takes over.

## 11. Retention and housekeeping

- Reports, cases, the audit log, escalations and the law-enforcement log
  are kept 2 years, and longer while a restriction or an enforcement record
  from the case still stands. Evidence is kept until the case closes plus
  180 days, or as long as a restriction from it stands.
- Enforcement records (the restrictions that survive a deletion) are kept 2
  years, keyed to the deleted person's number. They keep the user ids of
  the moderator who decided and of whoever decided an appeal.
- The daily purge deletes at most 5000 audit rows and 5000 escalations per
  run. If the audit log ever grows by more than 5000 rows a day, tell
  engineering: the backlog drains only at that rate.
- For the DPIA:
  - the SLA line counts cases that need sensitive routing by priority (§1);
  - a reporter whose own trip came more than 90 days before the report
    still counts (§3);
  - open cases stay open, without the account, after a deletion, and are
    relinked to whoever next holds the number, which can be a recycled
    number's new holder (§3);
  - the ID check code is random and identifies no one: 8 letters and
    digits, one per asked age check, unique while the check is live and
    gone once it ends; a check carried back after a deletion gets a new
    one. No phone number is asked for in the ID email;
  - ID emails are deleted straight after checking, and the support
    mailbox keeps mail for the shortest time it allows, backups included
    (the owner sets this).

## 12. Known gaps (built later; work around them as written)

- **An ID email with no code** (an older app, or an age check no case
  asked for, such as W4's own): the console can't find its case (§6).
- **A decided case can't be found again:** the queue lists only open
  cases (and ID checks whose age check is live), and the console has no
  search.
- **A skipped relink** (`dating.carry_over.relink_skipped`) needs an
  engineering repair (§6).
- **UK sextortion routes have no escalation kind** (§7).
- **Opinions:** the console's Opinions page has no "mark reviewed"; a
  priority report stays in the queue until its post is removed.
- **Photos:** text or a phone number inside a photo isn't read
  automatically; reject such a photo as `unsafe`.

## 13. Review cadence

- Weekly: overturned decisions by country (`dating.overturned.{country}`)
  and appeals accepted against rejected.
- Quarterly: the transparency summary (the console's Law enforcement page)
  for the published report: requests by country, type (legal process or
  emergency) and decision, requests met, reports by category, actions
  taken, appeals and overturned. The page gives raw counts: suppress small
  counts before anything is published (counsel sets the threshold).
