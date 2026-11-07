# Dating Mode Clinical Review Packet

**Audience:** licensed clinical advisor  
**Purpose:** approve or reject the Dating Mode alignment inputs, explanation style, confidence language, and excluded claims before production

## 1. Review scope

This review is about whether Dating Mode makes psychologically responsible use of Attune data. It is not a review of visual design, legal terms, or backend security.

Clinical reviewer is being asked to assess:

- included dimensions
- excluded dimensions
- interpretation boundaries
- explanation copy style
- uncertainty presentation
- risk of deterministic or pathologising language

## 2. Current implemented algorithm boundary

### Included

- aggregate attachment dimensions using anxiety/avoidance distance
- aggregate communication-style spectrum distance
- aggregate conflict-style spectrum distance
- explicit shared values or priorities overlap

### Excluded

- love-language matching, similarity, mismatch, or complementarity
- former-partner data
- Healing answers, outputs, or readiness score
- safety events or support usage
- raw messages
- private reflections
- photos or appearance-derived traits
- popularity, engagement, or response-speed metrics

## 3. Current explanation contract

The implementation currently allows only modest explanation styles like:

- "Some similar needs around closeness and reassurance."
- "There is some overlap in how you each tend to communicate."
- "Some conflict-style differences may be manageable with curiosity."
- "Several self-reported priorities appear to overlap."

The implementation currently forbids claims like:

- "You are highly compatible."
- "This predicts relationship success."
- "Your attachment pairing is ideal."
- "They are a safe match."
- "Your love languages complement each other."

## 4. Questions requiring explicit clinical sign-off

Record `approve`, `approve with changes`, or `reject` for each.

### Included dimensions

- [ ] Attachment aggregate distance is an acceptable v1 dating signal at this modest interpretation level.
- [ ] Communication-style aggregate distance is an acceptable v1 dating signal at this modest interpretation level.
- [ ] Conflict-style aggregate distance is an acceptable v1 dating signal at this modest interpretation level.
- [ ] Explicit values/priorities overlap is an acceptable v1 dating signal.

### Excluded dimensions

- [ ] Love-language exclusion is clinically appropriate.
- [ ] Excluding Healing, safety, raw messages, and former-partner data is clinically appropriate.

### Explanation tone

- [ ] Current explanation phrasing is sufficiently non-diagnostic and non-deterministic.
- [ ] Current limitations note is sufficiently clear that Attune cannot predict chemistry, safety, or success.
- [ ] Current confidence/band presentation does not overstate certainty.

## 5. Questions requiring written edits if not approved

- Which included dimension should be removed, narrowed, or rephrased?
- Which explanation phrases are too strong, pathologising, deterministic, or culturally mismatched?
- Are additional uncertainty disclosures required?
- Are any current bands or confidence labels misleading?

## 6. Sign-off record

Reviewer name:  
Credentials:  
Date:  
Decision:  
Required changes before production:  

## 7. The gentle wait (Spec 2 W2; a production gate)

The owner's ruling (Q12) replaces the Healing gate (a readiness score above 70, every Healing stage, eight weeks) with a gentle wait. The clinician is asked to record a note on its length and its copy, under `DATING_MODE_SPEC.md` §2.1's gate-erosion clause.

**What is built.** The wait applies only when a relationship ended on Attune. It lasts while the shared space's 30-day read-only window is open: from the ending, 30 days. It is shorter in exactly two ways: both partners close the space while both accounts still exist, or the former partner starts a new relationship (then the one left behind is no longer waiting; the one who moved on keeps the wait from the first ending). During the wait the person can set up Dating; introductions start on the open date. A private three-question reflection is offered (each answer optional, up to 500 characters, never scored, seen by nobody else, clearable at any time, deleted when the person leaves Dating or deletes the account), and Healing is offered, never required. No wait for a breakup off Attune, or none. The former-partner exclusion is mandatory regardless. Two counts are kept, aggregate only: people who open the wait screen, and accounts deleted within 7 days of opening it (a proxy for people re-registering to escape the wait). The second count undercounts: someone who leaves Dating first and then deletes the account is not counted, because leaving deletes the record of when they opened the screen. Read it as a floor.

**Rules that close ways around the wait (owner ruling 2026-11-07, W2 batch 1).**

- **The deleted former partner.** A former partner who deleted their account counts as not having closed the space. A lone close after that still waits the full window. So a victim who deletes their account gives the other person no early way out.
- **The second-account bypass.** Someone could invite a second account of their own, accept, have it deleted and close the space alone; that still waits, from the second ending. The same trick with both accounts closing the space together also fails: whoever moved on to the new relationship keeps the wait from the first ending.
- **An ending with no recorded date** refuses Dating (counted for the owner), never "no wait".

**Under the gate-erosion clause** (`DATING_MODE_SPEC.md` §2.1): shortening or removing the wait, or weakening either rule above, is never legitimate without a fresh recorded clinical sign-off. A thin pool is not a reason.

**Why not a longer or scored wait (research 03 §2.8, 09 P15).** No study supports an imposed wait after a breakup; a hard eight-week timer pushed a test persona to re-register on another SIM, which defeats the ex-exclusion. The 30-day window gives a reason ("you don't date while your former partner can still read your shared space") instead of an arbitrary number.

**The screen's copy (D0), exactly as built:**

- Title: "Before you begin"
- "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}, when your shared space closes. If you both close it sooner, Dating opens then."
- "This pause is because your relationship ended here. It isn't a judgement about you."
- "Three questions, just for you" — "Only you can see these, and nothing is scored."
- "What do you want to carry into your next relationship?"
- "What are you hoping for now?"
- "How will you know if you need more time?"
- Under each answer: "{count} of {max} characters"
- "Save my answers" — "Your answers are saved."
- When every answer is blank and answers were saved: "Clear my answers" — "Your answers are cleared."
- "Healing is here if you want it. It's there to help, and it's never required."
- "Set up Dating now"
- When the server is busy: "This is taking a little longer than usual. Your answers are still here, so try again in a moment." (saving), "This is taking a little longer than usual. Try clearing again in a moment." (clearing), "This is taking a little longer than usual. Try again in a moment." (reading)
- Offline: "You're offline. Dating needs a connection." and "Connect to save this answer."
- On a failure: "Something went wrong. Try again." with "Retry"

When closing the space together can no longer end the wait (the former partner deleted their account, or the person moved on to a relationship that also ended), the body instead reads, with no shortcut promised: "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}." (W2 final review M-4.) The body does not mention the second way the wait shortens (the former partner starting a new relationship); the screen then simply stops showing.

Healing's own readiness result now reads "Your check-in is complete. Healing stays here whenever you want it." (or, below 71, "Your answers suggest there may be more you want to explore. Go at your own pace.") and names no Dating date. The result screen's success styling (the primary-colour ring and score, and "Continue to journey completion →") appears only for a completed journey with a score above 70; a lower score gets the neutral ring and "Back to journey" (W2 final review I-1).

**Questions requiring explicit clinical sign-off** (record `approve`, `approve with changes` or `reject`):

- [ ] The length: the 30-day ending window, shorter only when both close the space (both accounts present) or the former partner starts a new relationship.
- [ ] The deleted-former-partner rule: a lone close after the other account was deleted still waits.
- [ ] The second-account closure, alone or with both closing: the wait from the first ending holds.
- [ ] Setup during the wait, with introductions only from the open date.
- [ ] The three reflection questions, optional and unscored.
- [ ] The D0 copy above, including "It isn't a judgement about you."
- [ ] D0's no-shortcut variant ("Your relationship on Attune ended on {end date}. Dating opens for you on {open date}.") when closing the space together can no longer end the wait, and whether the manual's general line ("or sooner if you both close it", `dating_mode_docs.dart`) needs the same qualification.
- [ ] Healing offered, never required, and Healing's new result message.
- [ ] No wait after a breakup off Attune.
- [ ] Optional: should D0 also show Spec 1's static "Need support now?" link (no detection, nothing stored)?

Reviewer name:  
Credentials:  
Date:  
Decision:  
Required changes before production:  

A domestic-violence specialist also reads the D0 copy (the same W2 gate) and records their read here:

DV reviewer name:  
Date:  
Decision:  

