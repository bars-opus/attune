# ATTUNE — PRINCIPLES CHECKLIST
### Fast daily reference for every coding, design, and copy decision
**Version:** 1.0
**Created:** June 2026
**Read time:** 4-6 minutes
**Full reasoning:** See ATTUNE_SOUL.md
**Technical spec:** See ATTUNE_MASTER_SPEC.md

---

> **HOW TO USE THIS**
>
> Before shipping any feature, screen, notification, or line of copy —
> run through the relevant section below.
> Every question is answerable in one word.
> If any answer is wrong, stop and fix it before shipping.
>
> This is not a substitute for reading the soul document.
> It is a fast check for decisions you make twenty times a day.

---

## SECTION A — THE TEN PERMANENT NOs

These are absolute. No exceptions. No edge cases. No "just this once."
If a feature does any of these things, it does not ship.

```
□ Does this tell the user what to decide about their relationship?
  Correct answer: NO

□ Does this show one partner's individual behaviour data to the other?
  Correct answer: NO
  (Shared patterns: yes. Individual attribution: never.)

□ Does this use streak mechanics designed to create obligation?
  Correct answer: NO

□ Does this make the free experience deliberately worse to sell relief?
  Correct answer: NO

□ Does this use a Claude API call to make safety determinations?
  Correct answer: NO
  (Safety triggers are hard-coded keyword detection only.)

□ Does this notify both partners when a safety trigger fires?
  Correct answer: NO
  (At-risk user only. Always. No exceptions.)

□ Does this use coin-based or obscured pricing?
  Correct answer: NO

□ Does this use a partner's past relationship data in dating
  matching without their explicit separate opt-in?
  Correct answer: NO

□ Does this create a combined report showing both users'
  personal insights together?
  Correct answer: NO

□ Does the recipient know a message was rewritten by the translator?
  Correct answer: NO
```

---

## SECTION B — EVERY FEATURE BEFORE SHIPPING

Run this for every new feature or significant change.

### B1 — Foundation check (Layer 1)
```
□ What is the single primary action on this screen?
  If there are two competing primary actions: simplify.

□ How many taps from app open to the moment of value?
  Target: Chat = 1 tap. Translator = 2 taps. Check-in = 3 taps.
  If more than the target: redesign the flow.

□ Does this work when the user is emotionally activated —
  mid-conflict, exhausted, stressed?
  If it only works when they feel good: it does not work.

□ Is the primary action button in the thumb zone,
  large enough to tap without precision?
  If not: move it or resize it.
```

### B2 — Trust check (Layer 2)
```
□ Does this screen communicate its purpose in under 3 seconds?
  If not: simplify.

□ Is every claim on this screen sourced?
  (e.g. "based on your chat analysis" not "it seems like")
  If not: add the source or remove the claim.

□ Is the pricing for this feature stated in real currency,
  clearly, before the user taps to purchase?
  If not: fix the pricing screen.

□ Does this screen feel trustworthy with sensitive
  relationship data on it?
  If not: more whitespace, clearer hierarchy, quieter colours.
```

### B3 — Soul check (Layer 3)
```
□ Is this a gift or a receipt?
  Significant intelligence moments should be gifts.
  (Anticipation → reveal → afterglow)
  If it is a receipt when it should be a gift: add ceremony.

□ Does this incomplete loop close inside the relationship
  or inside the app?
  Prefer: the relationship.

□ Does this feature get smarter about this specific user
  over time, or is the experience the same for everyone?
  Prefer: compounding intelligence.

□ Does this make the product more worth returning to,
  or does it make leaving more painful?
  Only the first is acceptable.
```

---

## SECTION C — EVERY NOTIFICATION BEFORE SENDING

```
□ Is this notification triggered by a genuine user need
  or by a DAU/retention metric?
  Only genuine user need is acceptable.

□ Is this notification respecting quiet hours?
  Never send between 10pm and 8am local time.

□ Is this the minimum number of notifications for this event?
  One notification per event. Never a sequence of reminders
  for the same thing.

□ If this is a safety notification: does it go only to the
  at-risk user, with no ceremony, no reveal sequence?
  Safety notifications are always direct receipts.
```

---

## SECTION D — EVERY LINE OF COPY BEFORE PUBLISHING

Read every piece of copy the product generates — notifications,
insights, verdicts, onboarding, error states — against this list.

```
□ Does this sound like the same voice as every other
  line in the product?
  Honest. Specific. Warm. Respectful. Grounded.

□ Does this tell the user what they should feel or decide?
  Correct answer: NO.
  Attune observes. The user decides.

□ Does this contain any of these banned words?
  toxic / narcissist / codependent / disorder / broken
  Correct answer: NONE OF THESE.

□ Is this observation specific to this user's data,
  or could it apply to anyone?
  Generic observations have no value. Rewrite until specific.

□ Does this verdict/insight sound like a judge or a wise friend?
  Correct answer: WISE FRIEND.

□ Does this end on the highest emotionally appropriate note
  available given the content?
  Dead stops and disclaimer endings are wrong.
  Agency, forward motion, or honest acknowledgment: correct.
```

### Copy voice quick test

Read the copy aloud. Ask:

> "Would a wise, honest friend who has been paying close
> attention say this — or does it sound like a checklist?"

If it sounds like a checklist: rewrite it.

---

## SECTION E — AI PROMPT REVIEW

Before deploying any new Claude prompt or changing an existing one:

```
□ Does the prompt include the global constraint header?
  (Never attribute negative behaviour to a named partner.
   Never use banned words. Never tell users what to decide.)

□ Does the prompt instruct the model to return ONLY valid JSON?
  No preamble. No markdown fences.

□ Is the output parsed inside a try/catch with a fallback?

□ Does the prompt avoid sending more than the last 20 messages
  as raw context?
  For older context, use structured summaries, not raw message text.

□ Is this prompt versioned in /prompts/v1/?
  Never edit a deployed prompt — create a new version.

□ Does this prompt avoid sending raw message content
  to any logging system?
```

---

## SECTION F — DATA AND PRIVACY

Before any new data is collected, stored, or used:

```
□ Is this data collection necessary for a specific feature,
  or is it "nice to have"?
  Collect only what is necessary.

□ Does this data have an RLS policy that enforces access
  at the database level, not the application level?

□ Is this data deletable by the user on request?

□ If this is personal insight data: is it readable only
  by the user it describes — never by their partner?

□ If this is safety event data: is it readable only
  by the at-risk user — never by anyone else?

□ If this is cycle data: is sharing with partner off by default,
  requiring explicit opt-in?

□ If this data will be used for dating compatibility:
  does it have its own explicit separate consent,
  distinct from general terms of service?
```

---

## SECTION G — GAMIFICATION REVIEW

Before adding any engagement mechanic:

```
□ Is the variable reward genuine (real intelligence, real discovery)
  or manufactured (random timer, artificial surprise)?
  Only genuine variability is acceptable.

□ Is this a streak? 
  Correct answer: NO streaks. Ever.

□ Is this a badge for using a feature?
  Correct answer: NO. No decorative badges. Recognition exists
  only as measured growth, never as collectible status.

□ Is this a leaderboard of any kind?
  Correct answer: NO leaderboards. Ever.

□ Does this mechanic make the user engage with the app
  or engage with their relationship?
  Prefer: the relationship.

□ Is this measuring real skill development or superficial activity?
  Only real skill development earns recognition.
```

---

## SECTION H — MONETISATION REVIEW

Before any pricing, paywall, or upgrade prompt:

```
□ Is the free tier genuinely valuable, not artificially limited?

□ Is the upgrade prompt appearing at a moment of genuine value
  (user wants something real) rather than manufactured friction?

□ Is the price stated in real currency before the tap to purchase?

□ Is cancellation as frictionless as signup?

□ Are safety resources, abuse detection alerts, and crisis
  hotlines accessible to all users regardless of tier?
  Correct answer: ALWAYS FREE. No exceptions. Ever.
```

---

## SECTION I — DATING MODE REVIEW

Before any dating mode feature:

```
□ Does this feature move users toward real connection
  or toward collecting matches?
  Only the first is acceptable.

□ Does this feature involve a swipe interface?
  Correct answer: NO swipe interfaces. Ever.

□ Does this feature show match counts or view counts?
  Correct answer: NO.

□ Is the matching profile compatibility-first, photo-secondary?

□ Is double-blind matching preserved?
  (Users only see mutual interest, never one-sided rejection.)

□ Is any past relationship data used here?
  If yes: does the user have explicit separate consent
  for this specific use?
```

---

## SECTION J — CHAT LIFECYCLE REVIEW

Before any feature touching the chat section states:

```
□ When a relationship unlinks, does write access cut
  symmetrically for both users immediately?

□ After soft lock: can each user read only their own
  messages, not their partner's?
  (Enforced at RLS level, not application level.)

□ Does the hard lock fire when either user enters healing mode?
  And is it one-way — permanent, no reversal?

□ Are cross-notifications suppressed at every state transition?
  Neither partner is ever notified about what the other is doing.
```

---

## THE ONE-LINE SUMMARY

> Attune earns its place in people's lives by genuinely
> understanding them better over time.
> Every decision either serves that sentence or it does not.

---

## QUICK REFERENCE — BANNED WORDS

Never appear in any Attune-generated content:

```
toxic · narcissist · codependent · disorder · broken ·
you should · you must · you need to · your relationship is ·
stay · leave · healthy · unhealthy (as verdict language)
```

Note: "healthy" and "unhealthy" are banned as verdict judgments.
Neutral uses such as "relationship health" in clinical, safety, or
measurement contexts are allowed when they do not tell the user what
to decide.

## QUICK REFERENCE — FRAMEWORK CONFIDENCE LEVELS

Affects how strongly the AI can state observations:

```
HIGH confidence   → state directly
  Gottman bids for connection
  Response latency patterns
  Repair attempt detection

MEDIUM confidence → "some signals suggest..."
  Attachment quiz results
  NVC violation detection
  Pursue-withdraw pattern

LOWER confidence  → "this may or may not apply to you..."
  Contempt detection
  Love language matching effects
```

## QUICK REFERENCE — PERMANENT CONSTRAINTS

These five constraints are architectural. They cannot be changed
by a feature request, a business decision, or a growth target:

```
1. No couple report combining both users' personal insights. Ever.
2. No safety notifications to both partners. At-risk user only.
3. No swipe interface in dating mode. Ever.
4. Translator recipient never knows the message was rewritten.
5. Safety system never routes through an AI model.
```

---

*For full reasoning behind any item on this checklist: ATTUNE_SOUL.md*
*For technical implementation: ATTUNE_MASTER_SPEC.md*
*Future Month 2 task: create a 20-30 line pre-commit checklist for daily scans.*
*Last reviewed: June 2026*
