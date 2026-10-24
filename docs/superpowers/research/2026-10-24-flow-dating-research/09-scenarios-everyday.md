# 09 — Everyday scenarios: 19 people from the store page to first value, then weeks 1–4

**Researcher:** 09 (everyday-scenario simulator) · **Date:** 2026-10-24 · **Programme:** Flow + Dating research (see `BRIEF.md`)
**Inputs:** research files 01–07 in this folder; the simulation format of `2026-10-16-couples-research/04-scenarios-everyday.md`; a few read-only code checks (listed in §1). Read-only: no app files changed.

**Short answer.**
- **The sign-in wall is still the most likely place to lose people.** Late SMS, WhatsApp codes sent to the wrong SIM, an older user who can't hold six digits in his head, and form state lost when the app closes affect 7 of 19 people. Voice fallback, autofill, confirming which number WhatsApp is on, and keeping A1–A3 on the device fix most of it.
- **Dating takes 3–4 days to its first introduction.** That is 12–14 setup screens, a liveness check, a 72-hour cool-off, then the next daily drop. The best fixes are to start the cool-off at sign-up rather than at activation, merge four screens, show the exact day, and give the person something to do while they wait.
- **The invite is fragile at both ends.** On iOS the invite is lost when the app installs. The invitee then creates their own invite. A code expires while the partner is still deciding. Simple fixes: put the code inside the message, add "My partner already invited me", and let the server withdraw the acceptor's own invite.
- **Dating shows up where it causes harm.** Today, a married woman whose husband ignored the invite, and someone inside the 30-day window after an ending, are both shown "Meet someone in Dating mode" (code check below). The strawman's quiet "Turn on Dating" row would put the same risk on the phone of a partnered person using Just for me.
- **Accessibility blocks whole groups.** The app ignores the phone's text size (`maxScaleFactor: 1.0` at the root). The code is six unlabelled boxes. The liveness check is visual only. Together these shut out the 63-year-old husband, the 52-year-old widow and the blind user.
- **A strict post-breakup timer encourages evasion.** An amicable ender who is ready can get round an 8-week wait by re-registering with another SIM. That defeats the phone-HMAC ex-exclusion, the protection that matters most.

---

## 1. How this was researched

**Method**
1. **Strawman.** I built one flow (§2.1) from the recommendations in 01, 03, 04, 05, 06 and 07. Each step cites the research it came from. Where two research files disagree, the strawman picks one and the simulations test the choice.
2. **Simulation.** I simulated 19 people:
   - the 15 the brief asked for;
   - 4 that the research says matter: a same-gender seeker in Ghana (04 §2.1.8), a 17-year-old (04 §2.2), a romance-scam crew (04 §2.4; C2), and a partnered person using Just for me in private (05 §3.3).

   Each walk goes screen by screen from the store page to first value, then through weeks 1–4.
3. **Code grounding.** Technical failures are tied to code read this session or to the audit in 06.
4. **Synthesis.** I counted each friction across the 19 people and weighted it by severity (§2.4). Steps, fields, motion moments and metrics follow from that (§3).

**Evidence tags used here**
- A citation such as `05 §4.0` or `04 Impl 21` points to a research file in this folder. The grade of the underlying evidence is the one given there. `CR-06` means `2026-10-16-couples-research/06-synthesis-roadmap.md`.
- **[Code]**: read in the repo this session.
- **[Sim]**: a simulated behaviour, feeling or timing. **This is not evidence.** It is a hypothesis to test in usability and device sessions, and at best it counts as Anecdote.
- **[Unverified]**: a platform or vendor behaviour from background knowledge that was not re-checked this session.

**Code checks made this session** [Code]
- `lib/app/app_shell.dart:34` wraps every route in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`, so the phone's font-size setting is ignored app-wide. This contradicts CR-06 F16 and 05 §3.8 ("onboarding screens must pass at 200%").
- `lib/features/auth/log_in/presentation/widgets/verification_code_field.dart:161-172`: the code is six separate `TextField`s with one-time-code autofill and no `Semantics` label.
- `lib/features/onboarding/presentation/widgets/pending_invite_guide.dart`: at 48 h the person is offered a reflection space; at 7 days, "Keep waiting / Use Attune on my own for now / **Invite someone else**".
- `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`:
  - Outside the pending and paused states (`:310-329`), the screen shows "Invite your partner" and, when no invite exists, **"Meet someone in Dating mode"** (`:371-384`).
  - `_useAttuneAlone` (`:137-144`) withdraws the invite, which lands the person on exactly that variant.
  - Only `paused` is excluded (`:255-258`), so an ended relationship still inside its 30-day window shows the Dating button.
  - The Healing card reads "Healing from a breakup?" (`:587`).
- `lib/main.dart:46,123-128`: `Supabase.initialize(...).timeout(30 s)` is awaited before `runApp`.
- `supabase/migrations/20260705210000_dating_mode_v1_2_hardening.sql:209`: an 8-week wait from the breakup is built into the Healing gate.

**Limits**
- No real users, interviews or device tests. Every timing is an estimate.
- The people are composites. Ghanaian, Nigerian, Indian and UK details need the cultural reviewer (05 §3.4; 03 Q11).
- I assume Dating is enabled in Ghana, Nigeria, the UK (age assurance done) and Canada. Only the Dubai simulation tests a country where it is off.
- I did no new web research. External facts come from 01–07 and keep their grades from there.

---

## 2. Findings

### 2.1 The strawman flow (built from 01–07)

```
SHARED START (everyone)
S0  Store page: subtitle and first 3 screenshots show the three paths; listing states 18+, phone sign-in,
    and "Dating available in: …".                                        (05 §3.1, Impl 3–4; 04 Impl 31)
W0  Native splash, at most 1 s.                                                            (05 §4.0 W0)
W1  Welcome: three equal path cards, each with a static preview sheet; Get started / I already have an
    account / I have an invite; text link "Read Opinions first".                           (05 §4.0 W1)
G1  Guest Opinions: one-tap 18+ self-declaration, then read-only Discover, threads, tags. (07 Impl 14)
A1  Name, any script, 1–40 characters, held on the device.                            (05 A1, Impl 7)
A2  Date of birth: three numeric fields in locale order, no defaults, "That makes you 29"; under 18 →
    calm stop on the device, 30-day local block.                              (05 §5.1; 02 Impl 11)
A3  Phone: country from SIM/region, national format accepted; SMS by default, "Send by WhatsApp
    instead".                                                                    (05 A3, Impl 11)
A4  Code: autofill; resend at 30/60/120 s; after the 2nd resend "Try WhatsApp" / "Call me with the
    code"; valid 10 minutes.                                         (05 A4, Impl 8–10; 02 Impl 9)
A5  Before you start: 18+, data and AI disclosure, delete anything; the server writes DOB (protected,
    write-once), name and consent.                                            (05 A5; 06 Impl 1)
A6  What brings you to Attune? In a relationship / Single and open to dating / Just for me;
    changeable any time.                                                             (05 A6)
    [Conflict: 06 Q1 orders OTP → EULA → DOB → name → path. Strawman takes 05's order; see Q1.]

PATH R — In a relationship
R1  Invite your partner: share sheet (WhatsApp first), QR, code; preview of what they'll see; message
    in several registers.                                       (05 R1; MASTER_SPEC §8.8)
R2  Inline "Get a heads-up when {name} joins" → the only notification ask on this path. (05 R2, Impl 15)
R3  Your space while you wait (Home, not a wall): first note, quiz about you, About-us card (stage,
    together since, married year(s), living, children; one per screen, all skippable); 48 h
    reflection; day-7 pivot.                       (05 R3, §5.4–5.8; [Code] pending_invite_guide.dart)
R4  Linked: one "You're both here" settle, at most 600 ms, no confetti; chat opens; read receipts off
    by default.                                                       (05 §6; CR-06 F4)
RI  Invitee: link or typed code → "You've been invited" → A1–A5 → path preset to Relationship with
    "Choose another way" → server-side age check on accept.          (05 §4.0, Q4; 06 Impl 1)

PATH D — Single and open to dating
D0  Gentle-wait check (server): only if a relationship ended inside Attune; Healing offered, never
    required.                                                (05 D0; 03 Impl 13; 06 Impl 7, Q12)
D1  How Dating works: up to 3 a day, "Interested" is private, mutual only, a separate chat; every gate
    disclosed (verification, photos, cool-off, country); "Not in your area yet" if the country is
    off.                                                           (05 D1, Q13; 04 Impl 31)
D2  Explicit consent for sensitive answers: what they're used for, who sees them, how to withdraw.
                                                                        (04 Impl 13; 01 §3.4)
D3  Intention (fixed): Marriage / A committed relationship / Long-term, taking it slowly / Not sure
    yet; a timeline if Marriage; "I'm not married or in a relationship" attestation.
                                                                          (01 Impl 1–2, 12, Q1)
D4  Who would you like to meet? Men / Women / Everyone; a country note shown on the device when
    relevant, never logged.                                              (05 §5.3; 04 Impl 3)
D5  Which best describes you? Woman / Man / Non-binary, plus more specific options; private by
    default.                                                              (05 §5.2; 01 Q2)
D6  Where: country (ISO) plus city/region from a list; "Also open to people in…" off by default.
                                                                (04 Impl 2, 20; 02 Q6)
D7  Children: have / want, can be a dealbreaker.                                     (01 Impl 10)
D8  Faith (optional): mine, plus how much sharing it matters.            (01 Impl 9; 03 Impl 16)
D9  Photos: 2 or more through the system picker, EXIF stripped, moderated; optional "show after we're
    both interested".                                                (01 §3.1, Impl 8)
D10 Prompts: 2–3.                                                                     (01 §3.1)
D11 Liveness selfie plus facial age estimation (challenge age 25, ID fallback); decision target under
    24 h.                                                       (01 Impl 4; 04 Impl 9; 02 Impl 10)
D12 This is what others see: age, never DOB; gender only if chosen; never who-you-want-to-meet.
                                                                                     (05 D7)
D13 Inline "Tell me about matches, at most once a day" → notification ask.               (05 D8)
D14 Cool-off of about 72 h, then a daily drop of up to 3 at a time the person picks; at most 6 waiting;
    new introductions pause at 3 open pre-date chats; never padded.
                                                     (04 Impl 19; 03 Impl 3; 02 Impl 15)
M1–6 After a match: "Why you two were introduced" (explicit overlaps plus "Attune can't predict
    chemistry"); guided first conversation; contact masking for 72 h or until "Swap contacts";
    in-app voice; "Plan a meet?" around day 7–10 with Share my plan; "Close kindly".
                                                       (03 (c); 04 Impl 21, 28; 02 Impl 6)

PATH J — Just for me
J1  Me home straight away, with one first-action card: write a first note / take a 3-minute quiz.
                                                                                     (05 J1)
J2  Quiz and anchors are optional, self-facing, with the F9 caveat.                   (05 J2, Q3)
J3  Notification ask only when the person sets a reminder.                               (05 J3)
J4  Quiet rows: "Invite a partner" and "Turn on Dating"; Opinions is a peer tab, not the landing.
                                                                           (06 Q16; 07 Q1)

SWITCHING: Settings → How you use Attune. The personal layer is always on underneath; Relationship and
Dating are never both active; every switch is silent to everyone else.                  (05 §4.3)
```

### 2.2 How to read each simulation

Each person has:
- a one-line profile: age, place, device, network, path;
- a **store → first value** table (Step · what they see · what they do · data collected · feeling or friction · drop-off risk);
- a **weeks 1–4** table;
- **what breaks technically**;
- **fixes**, each tagged with the strawman step it changes and a priority:
  - **P0**: blocker or harm;
  - **P1**: high value across several people;
  - **P2**: valuable;
  - **P3**: nice to have.

Drop-off risk reads **none / low / med / HIGH**. Everything in the feeling column is [Sim] unless it cites a source.

---

### P1. Akosua and Yaw: Accra, dating 2 years, Yaw joins 5 days late

**Akosua Owusu, 27**, marketing assistant in East Legon. Samsung Galaxy A15 (Android 14), MTN prepaid, home Wi-Fi.
**Yaw Boateng, 30**, bank officer. iPhone 13 (iOS 26), Telecel.
They live apart for family and church reasons. Akosua heard about Attune from a friend's Instagram story. **Path: In a relationship.**

**Akosua, day 0**

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| S0 | Play listing. Screenshot 1: "A private space for the two of you" | Installs on Wi-Fi | — | "Not a dating app? Good." Screenshot 2 shows introductions, and for a moment she wonders what Yaw will think. | low |
| W1 | Three path cards; opens the Relationship preview | Reads, then Get started | — | Her first worry is whether he can read her journal. The preview should answer that. | low |
| A1 | "What should we call you?" | "Akosua" | name (device) | — | none |
| A2 | Day · Month · Year | 14 · 3 · 1999 → "That makes you 27." | DOB (device) | A brief "why?"; the hint answers it | low |
| A3 | +233 from the SIM | 024 123 4567 (leading 0 accepted) | phone | — | none |
| A4 | Code screen | SMS arrives in about 10 s; autofills if the Hook adds the app hash (05 Impl 10) | — | Relief | none |
| A5 | Three bullets | Continue | consent; server writes DOB and name | Reads the AI line twice | low |
| A6 | Three paths | In a relationship; the card grows into the next screen | path | — | none |
| R1 | Preview of what Yaw will see; WhatsApp first | Sends the plain-spoken version | pending invite | Quick | none |
| R2 | "Get a heads-up when Yaw joins" | Turn on → Android dialog → Allow | push permission | Makes sense at this moment | none |
| R3 | Your space: first note / quiz / About us | About us: Dating · Oct 2024 · Apart, nearby · No children | `couple_profiles` (pending) | "Apart, nearby" doesn't read as second-best. **First value at about 3.5 min.** | none |

**Yaw, days 0–5**

| Day | What happens | Data | Feels / friction | Drop |
|---|---|---|---|---|
| 0, 21:40 | The WhatsApp message arrives during football | — | "Later." | — |
| 2 | Taps the link → App Store → installs → opens. **The invite context is gone**: iOS has no deferred deep link without an attribution SDK (05 §4.0). He sees the generic Welcome and taps Get started, not "I have an invite". | — | Doesn't notice the invite button | med |
| 2 | Goes through A1–A3. The Telecel SMS takes more than 2 minutes; the 30 s resend sends a second code; he closes the app. | held on device only | "Another app that doesn't send codes." | **HIGH** |
| 5 | Akosua sits with him. The app reopens at Welcome because A1–A3 were not kept, so he re-enters everything. The code arrives. A6 → In a relationship → R1 "Invite your partner". | — | "She invited **me**." He creates his own invite. | med |
| 5 | Akosua points to the code in her WhatsApp message, but he can't see anywhere to type it | his own pending row | Confusion | med |
| 5 | Backs out, finds "I have an invite", types K7P2QM → "You've been invited by Akosua" → linked | link | Both phones play "You're both here" while they sit together. A good moment. | — |

**Weeks 1–4**

| Wk | What they do | Where it lands |
|---|---|---|
| 1 | Yaw sees "Together since Oct 2024" and changes it to Dec 2024, the month he asked her out. Akosua sees "Edited", with no name. | Leaving the edit unattributed doesn't hide anything when there are only two people. She knows it was him and asks why he "hid" it. A small spat, then laughter. |
| 1 | Read receipts are off by default (CR-06 F4). Akosua expected ticks. Turning them on needs both of them; Yaw agrees. | Works as designed. A one-line explanation at linking would avoid the "is it broken?" moment. |
| 2 | Ask 2 arrives; each completes it on a different evening. | Fine. |
| 3–4 | Plan a trip to Aburi; This or That in chat (Games are not touched). | Value holds. |

**What breaks technically**
- iOS loses the invite during install, so the code has to be typed (05 §4.0). The WhatsApp message must carry the code as plain text.
- The SMS is late. A second request issues a new code, and the first may stop working [Unverified: Supabase's handling of concurrent OTPs; test].
- A1–A3 are lost when the app closes. 05 §3.8 extends offline tolerance to DOB and path; it should also cover the name and phone.
- Yaw ends up with a dangling pending invite. `create-relationship-invite` refuses only while an active or paused relationship exists, and `accept-invite` refuses only if the invitee has an active or paused one (06 §2.1.5). Yaw's own pending row therefore survives. [Code via 06; inference]

**Fixes**
1. The R1 message carries the code in plain text plus one line: "Open Attune → I have an invite → K7P2QM". (R1, **P0**)
2. A6 and R1 both show "My partner already invited me — enter the code". (A6/R1, **P0**)
3. `accept-invite` withdraws the acceptor's own pending outbound invite in the same transaction. (RI, P1)
4. Keep A1–A3 on the device until verified. Reopening resumes at A4 with "Send a new code". Accept either of the last two codes within the 10-minute window. (A1–A4, P1)
5. Shared fields show a quiet "Changed by Yaw · 12 Nov" line, with no push and no feed (see Q2). (R3/R4, P1)

---

### P2. Agnes and Kwadwo Asante: customary marriage plus church wedding, the older partner less tech-confident

**Agnes Asante, 49**, headteacher in Ahodwo, Kumasi. iPhone 12, MTN.
**Kwadwo Asante, 63**, retired civil servant. Tecno Spark 8 (Android 11) with font size set to largest; reading glasses; uses WhatsApp mostly for voice notes.
They married customarily in 1999 (knocking and head rites) and had a Methodist church wedding in 2004. Children aged 24, 20 and 16. Their daughter suggested Attune. **Path: In a relationship.**

**Agnes, day 0** (abridged; her sign-in matches Akosua's)

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| S0 / W1 | Every screenshot shows couples in their twenties | Installs anyway | — | "Is this for people like us?" | med |
| R3 stage | "How would you describe where you two are?" | Married ("any kind of marriage: customary, religious or civil") | stage | Relieved that customary counts | none |
| R3 year | "What year did you marry?" → "Had more than one ceremony? Add another" | Customary 1999 · Church 2004 | married years | **Delighted**: "They understand Ghana." (05 §5.6) | none |
| R3 rest | Living; children | Together · Yes, 13–17 and 18+ | household | — | none |

**Kwadwo, day 0** (Agnes sends the invite across the sitting room)

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| RI | Taps the link → Play Store → installs. The Play Install Referrer passes the code (05 §4.0, not re-fetched) → "You've been invited by Agnes" | Continue | — | Pleased that it knows | low |
| all screens | **All text is small.** The app ignores his largest-font setting (`app_shell.dart:34`, clamp at 1.0) [Code] | Squints, takes off his glasses, puts them back | — | Hands the phone to Agnes | **HIGH if alone** |
| A2 | Day · Month · Year | He knows the year. His Ghana Card says 1 July 1963, so he types that (05 §5.1: accept the best-known date; cultural reviewer to confirm) | DOB | "Why do they want my birthday?" | low |
| A4 | Code | The SMS arrives. He leaves the app to read it, comes back, and has forgotten three digits. There's no autofill without the app hash. | — | Frustrated | **HIGH** |
| A4 | After the second resend: "Call me with the code" | Takes the call; a voice reads the digits; Agnes types them | — | "This one is better." Voice suits him. | — |
| A5 | The AI line | "Is it reading our messages?" Agnes reads the "More about this" sheet aloud | consent | Wary, but carries on | med |
| RI → R4 | Path preset; age check; "You're both here" | — | link | Smiles | — |

**Weeks 1–4**

| Wk | What they do | Where it lands |
|---|---|---|
| 1 | Kwadwo sends voice notes and can't comfortably read Agnes's long texts. | The text clamp again. |
| 2 | Ask 2 has 26 questions. He stops at question 9 and nothing is saved (06 §2.1.2 #15: no retry layer). | He never goes back. |
| 3 | Agnes taps Together's "Add your anniversary", which is a separate reminder from the profile's married years (06 Impl 5). | Two sources of truth. The reminder fires on the church date; Kwadwo counts from the customary one. |
| 4 | He tells a friend "it's for young people". | Store imagery is a barrier to married couples over 50. |

**What breaks technically**
- The text clamp at the root shell [Code].
- Voice OTP is a written launch requirement but isn't in the code (05 §2; 06 §2.1.7).
- There's no SMS Retriever hash, so no Android autofill (05 Impl 10).
- Ask 2 doesn't save as it goes.
- There are two anniversary sources.

**Fixes**
1. **Remove the 1.0 text clamp, or raise it to at least 2.0,** after auditing layouts at 200%. Start with onboarding, chat and Dating (CR-06 F16; 05 §3.8). ⚠ **Regression risk:** the root shell wraps every route, so every screen reflows. Ship behind a layout pass with golden tests. (all, **P0**)
2. Voice OTP through the Send SMS Hook (05 Impl 8). (A4, **P0**)
3. SMS Retriever app hash on Android and an origin-bound code on iOS (05 Impl 10). (A4, P1)
4. Ask 2 saves each answer and resumes where the person left off. (later, P1)
5. "Add your anniversary" reads from and writes to the couple profile. With two ceremonies, the couple chooses which one to remember, or both. (R3, P1; 06 Impl 5)
6. Screenshots and W1 previews show couples of different ages, including married couples with grown children. (S0/W1, P2)
7. The A5 AI line says plainly what the AI reads and when, in words a 63-year-old could repeat back. Check the wording against decision 29 and what the AI actually does. (A5, P1)

---

### P3. Efua and Kwame: long distance, London ↔ Kumasi

**Efua Mensah, 29**, nurse in Croydon. iPhone 15 on an EE (+44) number; her old MTN SIM sits in a drawer.
**Kwame Darko, 31**, teacher in Kumasi. Infinix Hot 30 (Android 13) with two SIMs: MTN for calls and data, and WhatsApp registered on his Telecel number.
Together 3 years, apart for 18 months. The knocking took place in August 2025; the church wedding has no date yet. **Path: In a relationship.**

**Store → linked**

| Step | Who | Sees / does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| A3 | Efua | Country comes from the SIM: UK +44. Today's code defaults to Ghana (05 §2; 06 §2.1.2 #3), so she would have had to change it. | phone | Smooth with the fix | none |
| R3 | Efua | Stage: Engaged or Married? Kwame's mother says knocking plus head rites means married; Efua says not until church. She picks **Engaged**. Living: **Long distance**. | stage, living | A cultural fork the app can't settle (05 §3.4) | none |
| RI | Kwame | Link → Install Referrer → "You've been invited by Efua" | — | — | none |
| A3–A4 | Kwame | Types his MTN number and, out of habit, taps "Send by WhatsApp instead". **The code goes to WhatsApp on the MTN number, where he has no account.** Nothing arrives. Resend at 30 s, again by WhatsApp. After the second resend he picks "Call me with the code", which works. | — | Four minutes lost; on the phone with Efua: "Nothing is coming." | **HIGH** without voice |
| R4 | both | Linked the same evening; the settle plays on both phones; Efua's heads-up arrives at 21:05 London time | link | Warm | — |
| R4+ | Kwame | Changes "Engaged" to "Married". Efua changes it back. | shared field | Ping-pong | — |

**Weeks 1–4**

| Wk | What they do | Where it lands |
|---|---|---|
| 1 | Map, dual clock and a "Next visit" plan for December. | First value. |
| 2 | Efua replaces her iPhone and restores from iCloud. Whether the session survives depends on how the Supabase session is stored [Unverified]. If she's signed out, the UK SMS works. | Fine, but untested. |
| 3 | Ask 2. Kwame's data runs out mid-flow. | It needs to resume. |
| 4 | Efua flies to Kumasi for Christmas on a roaming UK SIM. If she's signed out there (for example by clearing storage), the roaming SMS may be slow or cost money. WhatsApp on hotel Wi-Fi would work. A passkey would avoid both problems (05 Impl 13). | A sign-in risk for the diaspora. |

**What breaks technically**
- The WhatsApp code goes to a number with no WhatsApp. This is 05's dual-SIM hypothesis, to be tested in Ghana.
- The country defaults to Ghana in today's code.
- It's unknown whether a session survives an iOS restore.
- Re-signing in while roaming.

**Fixes**
1. The WhatsApp option says: "We'll send it to WhatsApp on +233 24 … — is WhatsApp on this number?" If WhatsApp reports the message undeliverable [Unverified: Cloud API error behaviour], fall back to SMS automatically. (A3/A4, **P0**; 05 §3.2.1, Meta advice)
2. Default the country from the SIM or region (05 Impl 11). (A3, **P0** for the diaspora)
3. After week 1, offer a passkey: "Sign in without a code next time" (05 Impl 13, Q9). (week 2, P1)
4. Stage helper text: "Engaged: including after the knocking, before the wedding". If partners flip a field back and forth twice, show once: "You two see this differently, and that's fine. 'Something else' lets you use your own words." (R3, P2; cultural reviewer)

---

### P4. Comfort: the partner who never joins (inviter's view at day 1, 7 and 30)

**Comfort Asamoah, 34**, pharmacist in Tema. iPhone 13. Married 6 years to **Fiifi, 38**, an engineer who "doesn't do apps like that". Two children, aged 5 and 2. She found Attune through a women's WhatsApp group. **Path: In a relationship.**

| Day | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| 0 | R1 → R3 | Invites Fiifi (straight English). About us: Married 2020 (customary and church the same weekend) · Together · Yes, under 2 and 2–5. Writes a first note: "We feel like flatmates." | invite, couple profile, note | Hopeful, a little relieved to have written it down | none |
| 1 | WhatsApp shows Fiifi has read the message; no reply. The waiting card says "We'll suggest a private reflection space if this takes a little while." [Code] | Nothing | — | Stung | low |
| 2 | "A private space while you wait" → Open reflection mode [Code] | Writes again | journal | It helps | low |
| 7 | "It's been a week. Your invite has run its week." **Keep waiting / Use Attune on my own for now / Invite someone else** [Code] | — | — | "Invite someone **else**? I'm married." | med |
| 7 | Picks "Use Attune on my own for now". The invite is withdrawn and the Chat tab now shows "Invite your partner" **and "Meet someone in Dating mode"** [Code `_useAttuneAlone` → personal variant] | — | invite withdrawn; the couple-profile answers go with it (they live on the relationship row, 06 §2.2.4 #3) | **Insulted, and worried Fiifi will see a dating button on her phone** | **HIGH (harm)** |
| 8–29 | Journals twice a week and reads Opinions. Couples features stay locked (no AI before linking, decision 29). | — | — | "Nothing here for a married woman on her own." | **HIGH** |
| 30 | — | Likely uninstall | — | — | — |

**Fiifi, day 45:** he finally taps the old link and sees "This invite has expired", with no next step. He gives up.

**What breaks technically**
- `_useAttuneAlone` withdraws the invite, the mode resyncs to `personal`, and the Dating button appears [Code].
- The answers she typed into the couple profile are lost with the withdrawn row (06 §2.2.4 #3: the profile lives and dies with `relationships`).

**Fixes**
1. **The Dating entry never appears on the Relationship path.** That includes "on my own for now" and the 30-day window after an ending (see P15). (R3, **P0**; `chat_couples_locked_screen.dart:371-384`)
2. Rename "Invite someone else" to **"Send a new invite"**, with a quiet "to a different number" option. (R3 day 7, **P0** copy)
3. "On my own for now" keeps the path as Relationship with link state *none* (06 §2.3). (R3, P1)
4. **Day-30 value: "Working on us, on my own".** This is solo content that never interprets the absent partner:
   - a private "what I know about him" Love map;
   - conversation starters to use in person;
   - the one-person parts of the conflict toolkit;
   - private appreciation notes.

   Show one "Want to send Fiifi a new invite?" line at day 30, never again unless she asks. Grounds: couples apps must work alone (05 §3.4; Lasting, Relish); refusal to participate is a named churn reason (05 §3.4 **A**). (R3, P1)
5. The invitee's expired screen: "This invite has expired. Ask Comfort to send a new one", with a one-tap WhatsApp message to her. (RI, P1)
6. Keep the 7-day expiry; don't renew codes silently. A long-lived code sitting in a chat can be accepted by whoever holds it, and accepting links immediately (06 §2.1.5). Renewal should stay the inviter's deliberate act. (R1, P1)
7. About-us answers are kept as the inviter's draft until the couple links, so a withdrawn invite doesn't wipe them. (R3, P2)

---

### P5. Chiamaka: 29, single and faith-centred, Lagos, joining Dating

**Chiamaka (Chi) Okafor, 29**, accountant in Lekki. Pentecostal (RCCG). iPhone 11 on iOS 26, MTN Nigeria plus Airtel. She has watched friends get "games" from men on Bumble. **Path: Single and open to dating.**

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| A3–A4 | +234 from the SIM; picks WhatsApp; iOS 26 autofills from the WhatsApp notification (05 §3.2.1) | — | phone | Smooth; she avoided the SMS route | none |
| A6 | Three paths | Single and open to dating | path | — | none |
| D1 | Up to 3 a day; Interested is private; video selfie; 2+ photos; **"first introductions about 3 days after sign-up"** | Reads all of it | — | "Three days — serious. I like that." (Effort reads as seriousness, 02 §2.6.) | low |
| D2 | Consent for sensitive answers | Agree | consent events | Reads it | none |
| D3 | Intention, timeline, attestation | Marriage · "In the next year or two" · ticks the attestation | intention, timeline, attestation | Exactly her language | none |
| D4 | Who would you like to meet? | Men | preference | No country note: it appears on the device only when the choice includes her own gender (05 §5.3 "not logged") | none |
| D5 | Which best describes you? | Woman | gender | — | none |
| D6 | Country and city | Nigeria · Lagos | location | "Lagos is huge. Ikeja to Lekki is two hours." | low |
| D7 | Children | None · wants: Yes | children | — | none |
| D8 | Faith | Christian · "Must share" · no denomination offered | faith | "Catholic and Pentecostal are not the same to me." | low |
| D9 | Photos | Three from the gallery through the system picker; leaves "show after we're both interested" off | photos | — | low |
| D10 | Prompts | Writes 2 of 3 in about 6 minutes | prompts | The slowest step | med |
| D11 | Liveness and age check | Told to take her glasses off, retries, passes | pass and timestamp; video deleted | "Good. No fakes." | med |
| D12–D13 | Preview; notifications | Allow | — | — | none |
| D14 | "Your first introductions arrive Thursday at 7 pm." | Waits | — | A long wait after 11 minutes of setup | med |

Setup took **13 screens and about 11 minutes** [Sim], beyond 01 Impl 3's target of 8 screens and under 5 minutes. After activation, because Nigeria is a Tier 1 country (04 §2.1.6), she is offered: "Make Attune look like a plain notes app on your phone?" She's puzzled but not offended, because the copy is neutral.

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 (day 4) | Three introductions at 19:00: Tunde (32, Pentecostal, marriage), Emeka (30, Catholic) and Bayo (34, faith "nice if we share"). "Why you two were introduced: you both said marriage, in the next year or two. Faith matters a lot to you both. Attune can't predict chemistry." She taps Interested on Tunde and Not for me on the others, with a 5-second undo. | Calm, and the reason she can see is the product (02 §2.4). |
| 1 (day 6) | Mutual with Tunde → a quiet, warm screen → guided first conversation with reciprocal reveal. On day 2 he asks for her WhatsApp; his number shows as "•••" with "Swap contacts". She doesn't tap it yet. | She feels protected (04 Impl 21). |
| 2 | A second match, Chidi: "Can you send me 5k for transport so I can come and see you?" She alone sees a card: "Asking for money early is the most common scam pattern. You don't owe anyone money to meet." She reports it (`romance_scam`). | Deterministic, with no LLM (03 Impl 11). |
| 2 | A third man pushes for sex before marriage. She declines, and he reports her as a "fake profile". One report triggers no action [Sim, per 02 Impl 4]. | The West African "banned for saying no" pattern is avoided (02 §2.2 P4). |
| 3 | In-app voice call with Tunde. On day 10: "Plan a first meet?" → a café in Lekki, Saturday 14:00 → Share my plan with her sister (time and place, no photo by default). Afterwards: "Home safe?" → I'm OK. | 03 (c) 3–5; 04 Impl 28. |
| 4 | Second date. She pauses new introductions, which silently hides her (03 Impl 12). | A healthy exit signal. |

**What breaks technically**
- Nigerian SMS delivery: 12 of 22 "code never arrives" reviews are Nigerian (02 §2.3). DND filtering may delay transactional SMS [Unverified]. She avoided it with WhatsApp.
- Liveness with glasses needed a retry.
- The masking rules must recognise Nigerian formats: 080…, +234… and 10-digit bank account numbers (NUBAN), not only Ghanaian mobile money (04 Impl 21–22 extended) [Sim].

**Fixes**
1. An optional denomination under Christian (02 Q4). It's on the faith screen only and never required. (D8, P2; cultural reviewer)
2. Mega-city "sides" (Lagos Island / Mainland; Accra / Tema) as an optional split that is still coarser than a neighbourhood. (D6, P2; owner question on data minimisation, 04 §2.1.5)
3. Show the exact first-introduction day at D1 and again at activation. (D1/D14, P1)
4. Weight reports by credibility, and add a "reported after declining" safeguard, before any automated restriction (02 Impl 4). (M, **P0** for West Africa)
5. Nigerian money scripts ("transport", "recharge card", "urgent 2k") and NUBAN and phone formats in the deterministic rules (04 Impl 22). (M, P1)
6. The discreet-icon offer is worded for everyone: "Some people like their apps to look plain." (D14, P2; 04 Q11)

---

### P6. Kofi: 34, divorced with children, Toronto, joining Dating

**Kofi Mensah, 34**, IT analyst in Brampton, Ontario. Ghanaian-Canadian; moved at 12. Divorced in 2024. Two children, aged 6 and 9, on alternating weeks. iPhone 15 Pro on Rogers. He has used Hinge and is "tired of swiping". **Path: Single and open to dating.**

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| A2 | Three labelled fields in en-CA order | Types 08 · 11 · 1991, meaning 8 November, into a Month · Day · Year layout. It's stored as **11 August**, and "That makes you 34" is true either way. | **wrong DOB** | Doesn't notice | silent error |
| A3–A4 | +1 from the SIM; SMS in seconds | — | phone | — | none |
| D3 | Intention and attestation | A committed relationship · ticks "not married" (his divorce is final) · optional "Married before?" set to Divorced, hidden | intention, attestation, history | "Fair questions." | none |
| D4–D5 | Who / you | Women · Man | prefs | — | none |
| D6 | Canada · Toronto (GTA) · "Also open to people in…" off | Thinks about Ghana; leaves it off | location | — | none |
| D7 | Children | Have: Yes · Want more: Open to it | children | "Yes or no is enough. My kids aren't going on here." (03 (a)) | none |
| D9 | Photos | His best photo has his kids in it → "Photos with children can't be used on Dating. Crop to just you?" | photos | Fine once he knows why (03 (d)) | med |
| D11 | Liveness | Passes first time | pass | — | none |
| D14 | Drop time | 21:30, after the kids sleep | time | — | none |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | Day 4, 21:30: "No good fit today. Attune is still small in Toronto. We'll introduce you when there's a good fit." Day 5: one introduction (Ama, 31, Mississauga). Day 6: none. Two all week. | Honest, and calmer than Hinge, but he wonders if anyone is there (02 §2.4 "are there more than 2 people on here?"). Drop risk **HIGH** in week 2. |
| 2 | Turns on "Also open to people in Ghana" → one cross-border scam card → introductions from Accra. One match asks early about Canadian visas. He's uneasy and uses Close kindly. | A visa-seeking fear is named on Muzz (02 §2.3). Cross-border has to be a deliberate choice, and it is. |
| 3 | Mutual with Ama from week 1 → in-app voice → coffee on his free Saturday. | First real value at about day 18. |
| 4 | It's his kids' week. He pauses manually, then forgets to unpause for 9 days. | No nag is right, but he needs a scheduled pause. |
| later | In August Attune shows him as 35, three months early. Dating is on, so correcting it needs support (05 Q14). | The A2 error comes back to bite. |

**Fixes**
1. **The A2 confirmation names the month in words:** "8 November 1991 — that makes you 34." It removes day/month ambiguity in any locale. (A2, **P0**, cheap)
2. A child-photo rejection gives the reason and offers a crop. (D9, P1)
3. Be honest about a thin pool, and suggest widening that the person chooses (age range, region, abroad), never automatic (02 Impl 15). (D14, P1)
4. A scheduled pause, for example "Pause on alternate weeks", for co-parents. (Settings, P2)
5. Cross-border: one education card, and both people verified (04 Impl 20). (D6, P1)

---
### P7. Helen: 52, widowed, UK, trying dating again

**Helen Barnes, 52**, teaching assistant in Leeds. Widowed 3 years ago, when her husband Mark died of cancer. Two adult children and a young grandson. Samsung Galaxy A54 with font size set two steps larger and bold text, on Vodafone UK. Her daughter suggested dating; Helen distrusts Tinder. **Path: Single and open to dating.** The UK has the stricter age assurance (HEAA), which is assumed done (04 Q2).

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| W1 | The Dating preview: "A few introductions a day. Only when it's mutual." | Get started | — | "That's what I want. Not a slot machine." | none |
| all screens | **Text is smaller than everywhere else on her phone** (the clamp) [Code] | Holds the phone closer | — | Tiring | med |
| A4 | Android's one-tap consent sheet: "Allow Attune to read the below message and enter the code?" (SMS User Consent, 05 §3.2.1) | Denies ("read my messages?") and types the code | — | Suspicious of the wording | low |
| D1 | Discloses a "video selfie that checks your age" | Reads twice | — | "At 52? Fine, if everyone does it." | low |
| D3 | Marriage / committed / long-term, taking it slowly / not sure yet | Wants *companionship, not remarriage, not living together*; picks "Long-term, taking it slowly" as the nearest | intention | "None of these is quite me." (03 Q7, Impl 17) | low |
| D3 | Optional "Married before?" Never / Divorced / **Widowed**, hidden by default | Picks Widowed and **turns it on for her profile** | history | "I want them to know." The per-field visibility pattern helps (01 §3.4). | none |
| D6 | UK · Leeds | — | location | Harrogate is 15 miles away, outside "Leeds" | low |
| D7 | Children | Have: Yes · Want: No | children | — | none |
| D9 | Photos | Most good recent photos include Mark or her grandson. She crops one and uses one from her daughter's wedding. | photos | An emotional moment, with no prompt to rush | med |
| D10 | Prompts | Suggested prompts help: "A perfect Sunday…" | prompts | Writing about herself is hard | med |
| D11 | Liveness plus age estimation (challenge age 25) | Glare from the window makes the first attempt fail; the second passes | pass | "It told me *move closer* but not *turn away from the window*." | med |
| D12 | Preview: "Helen, 52, Leeds · Widowed" | — | — | Moved | none |

On the Just-for-me part of Home she sees **"Healing from a breakup?"** [Code `:587`] and thinks: "This isn't a breakup."

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | Day 4: one introduction (Paul, 56, Wakefield). Her age range is 50–62, and the pool is thin. | Honest copy keeps her. |
| 2 | Introduction: "Richard, 54, engineer, contract offshore in Aberdeen". Mutual. By day 3: "I can't video call from the rig… my bank card is blocked, could you help with the supplier?" She sees the money card. She reports, then feels foolish. | The rig script is a textbook case (03 §2.9; FTC 2023). Same-country matching didn't stop it (Aberdeen is in the UK); the nudge did. Losses peak among 50–59-year-olds (04 §2.4.1, Action Fraud). |
| 3 | The optional monthly check-in asks "Is dating here making you feel better, the same, worse?" → Worse. It suggests a pause. It does **not** offer grief resources, because Healing is framed around breakups. | 03 Impl 12; CR-06 F10 has a `grief` category, but nothing routes to it here. |
| 4 | She resumes. Introduction: Graham, 58, Leeds, also widowed. Mutual → voice call → coffee at a garden centre; Share my plan with her daughter. | First real value at about day 25. |

**What breaks technically**
- The text clamp.
- The SMS User Consent wording sounds invasive.
- Liveness guidance ignores lighting.
- There's no grief routing.

**Fixes**
1. Add **"Companionship"** to the intention set. This resolves the 01/03 difference (see Q4). (D3, P1)
2. Healing's entry reads "After a breakup or a loss" and routes bereavement to grief resources (CR-06 F10). (J/Home, P1)
3. After a scam report, show a warm card: "You did the right thing. Scammers are skilled; this isn't on you." Offer a pause. (M, P1)
4. Liveness guidance covers light, glasses and distance, in plain words, with no countdown pressure. (D11, P1)
5. Remove the text clamp (the same shared fix as P2, **P0**).
6. Keep the per-field "show on my profile" toggle for marital history (01 Impl 12). (D3, keep)

---

### P8. Arjun: Indian, living in Dubai, marriage intent

**Arjun Nair, 31**, software engineer in Dubai Marina, from Kochi. Hindu. His parents want him married within two years, and they run his Shaadi profile. iPhone 14 on du (+971). A Ghanaian colleague mentioned Attune. **Path: Single and open to dating.**

**Branch A: what launch looks like.** The UAE is Tier 1 (death penalty in law, 04 §2.1.6), and Dating is enabled country by country starting with Ghana and some diaspora hubs (04 Impl 31, Q3).

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| S0 / W1 | "Dating, worldwide" in the listing; the W1 preview doesn't say where Dating is available | Get started | — | — | — |
| A1–A6 | Sign-up takes about 2 minutes (DD/MM/YYYY suits him) | Picks Dating | name, DOB, phone, path | — | none |
| D1 | **"Dating isn't available in the UAE yet."** "Just for me" is suggested | Taps a quiz | — | "Then why did it say worldwide?" | **HIGH** |
| day 2 | — | Uninstalls; considers a 1★ review | an account with no use | Exactly what 02 §2.3 recorded: "better to clearly state that the service isn't available" | — |

**Branch B: the UAE and India enabled later.**

| Step | Sees | Does | Data | Feels / friction |
|---|---|---|---|---|
| D3 | Marriage → "In the next year or two" | Picks both | intention, timeline | Fits (01 Impl 2) |
| D6 | UAE · Dubai · "Also open to people in…" → India | Turns it on | location, abroad | Both people verified; cross-border scam card (04 Impl 20) |
| D8 | Faith: Christian, Muslim, Traditional, Other, None, Prefer not to say | **"Other"** | faith | "Hindu is 'Other'?" A list written for Ghana (01 Impl 9) fails a worldwide product |
| D8 | No caste or community question; a line says "Attune doesn't filter by caste, community or tribe" | — | — | Relieved himself; his parents wouldn't be. Keeping it out is right (01 Impl 11, Q9). |
| optional | "How involved do you want family to be?" | "Very; they'll meet early" | value | Becomes shared ground (03 Impl 15) |

In weeks 1–4 most days say "No good fit today". He widens to all of the UAE. In week 3 he matches Priya (29, Abu Dhabi, Tamil Hindu). She wants video to check he's real, but in-app calls are voice only (03 Q5). They meet at a café in Dubai Mall in week 4, and he shares his plan with his sister.

**Fixes**
1. **Show where Dating is available before any investment.** Put it on the store listing and in the W1 Dating preview ("Dating is open in: Ghana, UK, Canada, … More countries coming"). Offer "Tell me when it reaches the UAE" as a single in-app opt-in: no queue position, no waitlist (02 Impl 13). (S0/W1/D1, **P0**; 05 Q13)
2. Region-aware faith lists (Hindu, Sikh, Buddhist, Jewish and others), each with "Other" and "Prefer not to say". (D8, P1; owner/cultural)
3. Count "not in your area" by country, as an aggregate with n ≥ 50, to decide which country to enable next. (metrics, P1)
4. Keep caste, community and tribe out, and say so kindly. (D8, keep)

---

### P9. Nana Ama: Just for me after a hard week, then turns on Dating

**Nana Ama Boakye, 26**, nurse at Korle Bu, Accra, working night shifts. Tecno Camon 20 (Android 13), MTN. An 8-month situationship ended when he got engaged to someone else. After four night shifts she cried in the car park. She searched "private journal app". **Path: Just for me.**

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| W1 | Just for me: "Your journal, quizzes and Healing. Single, partnered or in between." | Get started | — | "In between. That's me." | none |
| A1–A6 | About 90 s; SMS autofill | Just for me | path | — | none |
| J1 | One card: "Write your first note" | Writes 600 words at 03:10 in the underground car park (no signal) | journal (local first?) | Relief | low, **if it saves offline** [Unverified] |
| J1 | The journal-lock offer at the first entry (CR-06 F11 (7)) | Sets a lock | — | Safer | none |
| J1 | The deterministic disclosure check runs on save (CR-06 F11). She wrote "I just want to disappear for a while", which may match | A private card with resources | nothing stored | Either "they think I'm suicidal" or "someone noticed". The wording decides which. | med |
| J3 | "Remind me to write on Sundays" → notification ask now | Allow | reminder | Makes sense | none |
| Home | "Healing from a breakup?" | Yes → Healing journey (self-reported, outside Attune) | Healing stage | No gate, correct | none |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1–2 | Journals 5 times; Healing stage 1; reads Opinions from an "Attune asks" card. | J1 value lands (07 Q1: her own space first, Opinions one tap away). |
| 2 | Comments on an Opinions post. Someone **dislikes** her comment. | Hurts. 07 Impl 2 says to remove dislikes. |
| 4 | Taps the quiet "Turn on Dating" row → D0: no wait, since the breakup was outside Attune → D1 … D14. | D2 must say plainly that nothing from her journal, quizzes or Healing is used. Today's consent screen has an optional historical-data checkbox that brings quiz answers into scoring (06 §2.4). 03 Impl 1 removes quiz traits from ranking, so the checkbox should go. |
| 4 | Her second tab changes from **Me** to **Dating**. | "Where's my journal?" The personal layer must stay one tap away on the Dating home (05 §4.3). Introductions arrive at 08:30, after her shift (a chosen time; quiet hours respected). |

**Fixes**
1. Moving from Just for me to Dating keeps a permanent "Your space" entry (journal, quizzes, Healing) on the Dating home. (J→D, P1)
2. D2 says: "Nothing from your journal, quizzes or Healing is used to introduce you." Remove the historical-data checkbox. (D2, P1)
3. Journal saves work offline and sync later. Verify the current behaviour. (J1, P1)
4. The crisis card offers support "in case" and never asserts anything ("We noticed you might be…"). Clinically reviewed (CR-06 F11). (J1, **P0** wording)
5. Remove dislikes from Opinions (07 Impl 2). (Opinions, P1)

---

### P10. Efua and Nii: met through Attune Dating, then link into Relationship Mode

**Efua Adjei, 28**, architect, Airport Residential, Accra. **Nii Armah, 31**, logistics manager, Spintex. Both active in Dating and introduced in their first week.

| When | What happens | Data | Feels / friction |
|---|---|---|---|
| Wk 1 | "Why you two were introduced: you both said marriage; both want children; faith matters to you both. Attune can't predict chemistry; meeting is how you find out." Both tap Interested → mutual → a quiet, warm screen. | match | Grounded (03 Impl 1) |
| Wk 1 | Guided first conversation: three reciprocal pairs, each revealed after both answer. | chat | "Easier than 'hey'." (03 (c) 1) |
| Wk 1, day 5 | Masking ends; both tap "Swap contacts"; most chat moves to WhatsApp. | — | Normal. Attune's safety coverage ends there, by their choice. |
| Wk 2 | First meet at a café in Osu; Share my plan; after-date check-in; either taps "we met". | we-met flag | — |
| Wk 3 | The day-21 "Keep chatting, or close kindly?" card appears **even though they've met three times**. | — | Jarring. It should be suppressed after "we met". |
| Wk 6 | "Talk about what we are" prompt pack (03 Impl 14) → they decide. Nii taps "Become a couple on Attune". | — | — |
| Wk 6 | If built on the invite code exchange (06 Impl 11), Nii is sent to a share sheet to send Efua a code she can already see in the chat. **His own Dating pauses at once**, because the pending row trips the relationship guard (06 §2.4), while hers keeps running. | pending relationship | Clunky, and asymmetric. If she says "not yet", he is paused and it shows. |
| Wk 6 | Better: an **in-chat request** → each sees a private "What are we agreeing to?" step: "Your Dating profiles pause for both of you; you'll share a private space; either of you can end it at any time." → Efua confirms → both Dating profiles pause at confirmation. | relationship active | "We decided." This is the most meaningful moment in the product (03 §2.7). |
| Wk 6 | Efua still had an open dating chat with someone else. What happens to it? | — | Undefined today. The other person should see a neutral "This conversation has ended", with no reason. |
| Wk 6 | About us: "When did you two get together?" The day they matched (3 Nov)? The first meet (14 Nov)? Today? | together since | 05 §5.0 forbids pre-filling from app data. A chip showing the match date would be helpful but needs a ruling (Q11). |
| Wk 6 | Their first dating-chat messages are due for deletion at match close plus an evidence window (04 Impl 8). | — | Sentimental loss: "That was our first conversation." |
| Wk 7–8 | Opinions status label silently re-syncs from Single to In a relationship (06 Q7). Read receipts are off by default in the couple chat. Ask 2 arrives. | — | Fine. |

**Fixes**
1. An in-chat "Become a couple" request with a private "what are we agreeing to" step. Dating pauses for both only when both have confirmed (03 Impl 14). (link, P1)
2. Other open dating chats close neutrally when a couple links. (link, P1)
3. "Keep our first messages": a joint opt-in that copies them into the couple space as a read-only "How we met" card. Otherwise they are deleted on the retention schedule. (link, P2; Q10)
4. Suppress the day-21 card after "we met". (M, P2)
5. 30 days after linking, offer: "Delete your Dating profile and preferences?" (special-category minimisation, 04 Impl 8). (later, P1)

---

### P11. Kwabena: very low data, old Android, rural Ghana, joining Dating

**Kwabena Asare, 27**, agricultural extension officer near Kintampo (Bono East). An itel phone running Android Go with 2 GB RAM and 32 GB storage, of which 1.1 GB is free. MTN prepaid; he buys small bundles of roughly 500 MB to 1 GB. 3G in town, 2G/EDGE on farms. He charges the phone at the office. Tinder once ate his data. **Path: Single and open to dating.**

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| S0 | Play listing; app size unknown (**not measured for this research**) | Downloads over 3G in about 10+ minutes; "Not enough storage" → deletes WhatsApp videos | — | Annoyed before he starts. Install conversion falls about 1% per 6 MB (05 §3.1, **M**). | **HIGH** |
| W0 | Native splash | Waits | — | On first install there's no session, so it's quick. On a **later cold start with an expired token on 2G**, `Supabase.initialize` (awaited, 30 s timeout) may hold the first frame while it refreshes [Code `main.dart:46,123-128`; network refresh is an inference, verify] | med (later) |
| W1–A2 | Animations skipped on low-RAM devices (05 §6) | — | — | Fast, which is good | none |
| A3–A4 | SMS by default; **SMS needs no data** | Code by SMS on 2G | phone | Works | none |
| A5 | Server write on EDGE: "Saving…" after 400 ms | Waits 6 s | consent, DOB | Fine with honest text | low |
| D1 | Discloses photos and a video selfie; **no word on data use** | — | — | "How many MB is this video?" | med |
| D6 | Ghana → a region list | Bono East; "Open to: anywhere in Ghana" (the local pool is thin) | location | Today's list has 6 hard-coded cities (06 §2.4), and his town isn't one | **HIGH today**, low with regions |
| D9 | System photo picker (backported to Android 4.4+, 05 §3.6) | 2 photos of 3–4 MB each | photos | Upload stalls at 60% on 2G | med |
| D11 | Liveness: the camera preview plus a streamed check | **Android kills the app for low memory** mid-capture → reopens at… where? | — | If setup isn't saved, he starts over | **HIGH** |
| D11 | Tries again at 06:00 when the network is better; passes on the third attempt | pass | — | Determined, but most people wouldn't be | — |
| D14 | Drop at 19:00 | — | — | — | — |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | Introductions (Techiman, Kumasi, Accra) each load 2–3 photos, which uses data. **The push often doesn't arrive**: Transsion phones are reported to kill background apps aggressively [Unverified; test on device]. He opens the app two days later. | If introductions last only 2–3 days (06 Q11), he misses them. |
| 2 | Mutual with Akua (25, teacher, Techiman). Text-only dating chat works on 2G (04 Q5). The in-app voice call keeps breaking up. | Text-first suits low data. |
| 3 | They meet on Techiman market day. Share my plan sends a web link; his brother has no data. | An SMS-text version of the plan would work. |
| 4 | Storage fills up and he taps "Clear data" → signed out → SMS sign-in works. | Fine. Only cache-only data is lost. |

**Fixes**
1. **Measure and budget the app size.** Ship split ABIs and an app bundle; load heavy modules (Mapbox and the like) on demand; set an install-size target for Android Go. (S0, P1; 05 Impl 24)
2. The first frame never waits on the network. Verify whether `Supabase.initialize` can block on a token refresh; if it can, start the app from the local session and refresh in the background. (W0, P1) ⚠ Shared file `main.dart`.
3. **A data-saver mode**: text-first introduction cards (person before photo, 03 Impl 5), photos on tap; D1 states the approximate data use. (D1/D14, P1)
4. Resize photos on the device before upload, to a few hundred KB [target is a Sim estimate]. (D9, P1)
5. **Liveness is resumable**: save setup at every step. After two failed captures, offer a fallback: a photo with a gesture, reviewed by a person within 24 hours (02 Impl 10). (D11, **P0** for Ghana)
6. Introductions last at least 5–7 days (01 Impl 14) and always show when the app opens. Never rely on push. (D14, P1)
7. A region list covering all 16 Ghana regions, plus "anywhere in Ghana" (04 Impl 2). (D6, **P0**)
8. Share my plan also as SMS text. (M, P2)

---

### P12. Esi: screen-reader user (TalkBack), joining Dating

**Esi Quaye, 33**, customer-service lead at a telco in Dansoman, Accra. Blind since age 10. Samsung Galaxy A14 with TalkBack; fast speech rate; WhatsApp all day. Friends' photo-first swiping apps were unusable for her. **Path: Single and open to dating.**

| Step | TalkBack says / she does | Data | Feels / friction | Drop |
|---|---|---|---|---|
| W1 | If the path cards are custom widgets without semantics: "Button. Button. Button." If labelled: "In a relationship. A private space for you and your partner. Double-tap to preview." The preview's sample images need text. | — | Decides whether she trusts the app | med |
| A2 | "Day, edit box", "Month, edit box", "Year, edit box"; the confirmation is read out | DOB | Good if labelled; errors must be announced | low |
| A3 | Country already set from the SIM, so she doesn't have to swipe through 200 countries | phone | Good | none |
| A4 | **"Edit box. Edit box. Edit box. Edit box. Edit box. Edit box."** Focus jumps to the next box as each digit lands; the countdown may be read every second [Code: six `TextField`s, no `Semantics`] | — | Disorienting. SMS User Consent ("Allow") rescues it in one tap. | **HIGH** without autofill |
| D3–D8 | Radio groups read well if they use real semantics | answers | Fine | low |
| D9 | The photo picker reads photos by date only; she asks her sister to choose. One photo, in sunglasses, is rejected ("We couldn't see your face clearly"), but **which one?** | photos | She depends on someone else and can't fix it alone | med |
| D10 | Prompts | Writes that she's blind, by choice (no disability field; health is special-category, 01 §3.3) | Her choice, her words | none |
| D11 | **Liveness: "Fit your face in the oval."** Visual-only guidance. Rekognition Face Liveness also uses a flashing colour sequence [Unverified: vendor UI; check for a photosensitivity warning] | — | Impossible without audio and haptic cues | **HIGH (blocker)** |
| D12 | "Esi, 33, Accra…" read in full | — | Good | none |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | Introduction cards read person-first: name, age, area, intention, "why you two", prompts, then "3 photos" with no descriptions. | Person-first order (03 Impl 5) suits her very well. |
| 1 | She taps "Not for me" by mistake. The 5-second undo toast has gone before TalkBack reaches it. | WCAG 2.2.1 says timing must be adjustable; a 5-second undo fails it. |
| 2 | Mutual match. The text-only dating chat (04 Q5) is accessible, but she'd rather send voice notes. | In-app voice calls (03 Impl 7) help. |
| 3 | She tells her match before meeting, by choice. Share my plan with a friend; she goes by Bolt. | Works. |

**Fixes**
1. **Code field: one field with drawn boxes,** labelled "Verification code, 6 digits". The countdown is announced only when resend unlocks (05 §3.8, Impl 10). (A4, **P0**)
2. Semantic labels on every onboarding and Dating control, enforced in widget tests with Flutter's accessibility guidelines (`labeledTapTargetGuideline`, `androidTapTargetGuideline`, `textContrastGuideline`). (all, **P0**)
3. **Accessible liveness**: audio and haptic guidance ("move the phone up a little"), a photosensitivity warning if light challenges are used, and a human-reviewed fallback within 24 hours. (D11, **P0**)
4. A photo rejection names the photo ("the second photo you added") and gives the reason. (D9, P1)
5. Undo lasts until the next action, or at least 20 seconds when a screen reader is on. (M, P1)
6. Optional captions the person writes for their own photos, which also give conversations a starting point. Never AI-generated (spec §4.3 forbids photo-derived attributes). (D9, P2)

---

### P13. Adwoa: a guest who reads Opinions for a week before signing up

**Adwoa Mensah, 23**, doing national service in Accra. Redmi Note 12, MTN. In a situationship: "we're not dating, but we're dating". A friend said: "Read what people write on Attune." **Path: guest, then Just for me.**

| Day | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| 1 | W1 → "Read Opinions first" → G1 "I'm 18 or older" (07 Impl 14) | One tap | local flag | Taps without thinking. **A 16-year-old would too**: 05 §5.1 (FTC) says never use a yes/no age gate. | — |
| 1–3 | Discover (read only); a post about situationships | Reads 40 posts | — | "These are my people." | low |
| 3 | Wants to react "I relate" → "Sign in to react" | Not yet | — | A small push | low |
| 5 | Wants to comment → "Sign in to write" | Not yet | — | — | low |
| 7 | Writes a draft post as a guest → "Sign in to post" → A1 | Signs up | name, DOB, phone | Will her draft survive? | med |
| 7 | A6 | "Just for me" ("in between") | path | Fine | none |
| 7 | Lands on the **Me** home (07 Q1), not on her draft | Hunts for Opinions | — | "Where did my post go?" | med |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | Posts three times. "I relate" reactions are visible only to her (07 Impl 3). One harsh comment ("you're a side chick") gets through. She removes it and turns on "Just listening". | The author controls work (07 Impl 6). |
| 2 | Uses "Keep this private (save to my journal)" in compose and finds the journal. | Opinions leads into J1 value (07 Impl 9). |
| 4 | He asks to "make it official". She taps "Invite a partner" → path changes to Relationship → he joins. He reads Opinions too and **recognises her old story**. | Per-post handles stop the posts being linked, but not someone recognising the story (07 Impl 11). The warning copy matters. |

**Fixes**
1. Signing up from a guest action returns her to it: the draft is kept locally, and she lands back on the post or compose screen once. (G1→A1, P1)
2. **The guest age gate asks for a birth year** (no default, stored on the device) instead of a yes/no tap. The year can fill A2's year field later. This reconciles 05 §5.1 and 07 Impl 14 (Q12). (G1, P1)
3. The first landing after sign-up is where the person came from; after that, their path home. (A6, P2)
4. Before an invite is sent, show once: "Your Opinions posts stay unlinked to you, but people who know you could recognise a story." (R1, P2)

---
### P14. Selasi: picks the wrong path, then switches

**Selasi Agbeko, 25**, graphic designer in Accra (originally from Ho). iPhone XR. A three-year relationship ended two weeks ago, outside Attune. She wanted journaling and Healing, but tapped **"Single and open to dating"** because "single" was the word she had been saying all week.

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| A6 | Three paths | Single and open to dating | path = dating | — | — |
| D1 | "A few introductions a day…, video selfie…" | Freezes: "I'm not ready for this." | — | Embarrassed | med |
| D1 | "Set up later" | Taps it → personal Home with a Dating card, but her second tab is labelled **Dating**, with a "Finish setting up" banner | — | Feels nagged | med |
| Settings | Finds "How you use Attune" after about a minute → Just for me | Switches silently | path = just_me | Relief | low |

**Weeks 1–4**

| Wk | What happens | Where it lands |
|---|---|---|
| 1–2 | Healing (self-reported breakup), journal, quizzes. | J value. |
| 3 | Her ex wants to try again. She taps "Invite a partner" from Me → the path changes to Relationship (pending). He doesn't install. | Fine. |
| 4 | She withdraws the invite. **Which path is she on now?** The rules don't say. She lands on the Relationship home in its "on my own" state. | It should return her to Just for me. |
| variant | Her friend Kafui has Dating **active** and taps "Invite a partner" to try the feature. Dating pauses silently (the relationship guard, 06 §2.4: "a Just-for-me user who taps Invite gets Dating paused"). | "Why have my introductions stopped?" |

**Fixes**
1. D1 gains a second action: **"Not ready for Dating? Use Attune just for me."** One tap switches the path. (D1, P1)
2. "Set up later" leaves one quiet card and no banner. (D1, P2)
3. Path switches can be undone: withdrawing an invite returns the person to the path they were on before. (X, P1)
4. Before any action that pauses Dating, confirm: "Inviting a partner pauses Dating. Continue?" (X, P1)
5. Measure "path switched within 7 days" by from→to pair (05 Impl 22). (metrics, P1)

---

### P15. Abena and Kojo: an amicable breakup inside Attune; Abena wants to date again

**Abena Darkwa, 30**, product manager in Osu, Accra. **Kojo Antwi, 31.** Together 14 months, linked in Attune for 10. They ended amicably on 2 October 2026: he is leaving for a master's in Germany in January, and neither wants long distance. Abena taps End. Under CR-06 F1, Kojo gets no notification; he sees a warm ending screen next time he opens the app, and both get a 30-day read-only window and an export.

| Day | Sees | Does | Data | Feels / friction | Drop / harm |
|---|---|---|---|---|---|
| 0 | The ending card (ended, 30-day window), **plus "Invite your partner" and "Meet someone in Dating mode"** below it [Code: only `paused` is excluded] | — | `ended_at`; exclusion HMAC written by `end_relationship` (06 §2.4) | "The day I ended it, it suggests dating." | **harm** |
| 0 | Kojo, on his next open: the warm ending screen, with the same buttons underneath | — | — | "Already?" | **harm** |
| 1–20 | Journals; downloads their shared memories | — | export | Steady | — |
| 21 | Settings → How you use Attune → Single and open to dating → D0: "Before you begin" (3 private reflection questions), "Healing is here if you want it", **"Dating opens for you on 27 Nov"** (8 weeks) [Code: `interval '8 weeks'`] | — | — | "I ended it. We're fine. I'm an adult." Feels patronised. | **HIGH** |
| 22 | Considers deleting her account and signing up again with her second SIM | — | — | **A new number escapes the phone-HMAC ex-exclusion** (04 §2.3; the Fable C4 residual). Kojo is still in Accra until January and also dating, so they could be introduced to each other. The timer creates the risk that the exclusion exists to prevent. | **HIGH (harm)** |
| 21 (alternative, 03 Impl 13) | The readiness reflection (2 minutes), then "Start now" or "Pick a date". Ex-exclusion always applies. | Starts | — | "Fair. It asked; it didn't tell me." | low |

**Weeks 4–7 (alternative flow).** D1–D14, the cool-off, then introductions. Her Opinions status label silently re-syncs from Taken to Single (06 Q7; 07 Impl 15). Kojo never sees a signal. If both of them date, the exclusion keeps them apart.

**Fixes**
1. **Tie the gentle wait to the shared space's 30-day window** (or less, if both seal it), with the readiness reflection, Healing offered and no readiness score. This gives a reasoned minimum, "you don't date while your ex can still read your shared space", rather than an arbitrary 8 weeks. Owner decision (Q6); clinical note required (04 Q10; 06 Q12). (D0, **P0**)
2. Show no Dating prompts on the home screen during the ending window. Dating stays reachable in Settings. (post-ending home, **P0**; same code fix as P4)
3. D0 copy: "This pause is because your relationship ended here. It isn't a judgement about you." (D0, P1)
4. Measure account deletions within 7 days of seeing the gentle-wait screen, as an aggregate proxy for evasion. (metrics, P1)

---

### P16. Elikem: a same-gender seeker in Accra (Tier 1)

**Elikem, 27**, bank teller in Accra. Gay, not out to his family, lives with his parents in Adenta. A second-hand iPhone 12 on MTN; the SIM is registered to his Ghana Card, so the number is tied to his legal identity. He has used Grindr over a VPN and knows the Kasoa entrapment stories (01 §2.6). **Path: Single and open to dating.** The research disagrees here: 03 Q3 says no same-gender introductions in Ghana until counsel clears it; 04 Q1 says offer them, with Tier 1 protections and a kill switch.

| Step | Sees | Does | Data | Feels / friction | Drop |
|---|---|---|---|---|---|
| S0 | Checks the screenshots for any sign of inclusion | — | — | Wary | med |
| A1 | Name | "Eli" | name | Avoids his full name | — |
| D2 | Explicit consent: purpose, who sees what, how to withdraw, "deleted when you leave" | Reads every word | consent | Needs it | low |
| D4 | Men → **a note on the device** (country taken from the SIM): "In Ghana, relationships between men can carry legal risk, and people have been targeted through dating apps. Here's what Attune does… What you can do…" Not logged (05 §5.3) | Reads it twice | preference | Seen, and scared | med |
| **Branch B** (03 Q3) | "Introductions between men aren't available in Ghana right now because of the legal situation. Your choice stays private and is deleted if you leave. Support: …" (`lgbtq_legal`, CR-06 F10) | Leaves | — | Goes back to Grindr over a VPN, which is riskier. This is the WhosHere trade-off (04 Q1). | **HIGH** |
| **Branch A** D9 | Photos are **withheld until mutual interest** for same-gender introductions in Tier 1 (04 Impl 3b) | Uses photos with no recognisable background | photos | "Good." | low |
| D11 | "Where does my face video go?" → "Deleted the same moment; we keep only pass or fail" (04 §2.7 #6) | Passes | pass | Reassured | med |
| after | Discreet icon and a separate Dating PIN offered (04 Impl 5) | Sets both | — | iOS shows a system alert when the icon changes [Unverified], and the name under the icon stays "Attune", which is neutral (04 §2.1.7) | — |

**Variant: his friend Edem**, a returnee living in Accra on a UK SIM. At D4 the SIM country is the UK, so no note appears. At D6 he picks Ghana. **The note is never shown** unless the tier is re-checked after D6. The fix is to ask D6 first (§3.1).

**Weeks 1–4 (Branch A)**

| Wk | What happens | Where it lands |
|---|---|---|
| 1 | The weekly cap for new accounts allows one same-gender introduction (04 Impl 3d). The card shows first name, age, region and "why you two"; photos come after mutual interest. | Slow, but safe. |
| 2 | Mutual. Photos are revealed; chat uses `FLAG_SECURE`. The match pushes: "Come to my place tonight, I'm alone." Elikem alone sees the LGBTQ meeting-safety card: never a private address first, beware of urgency (04 Impl 29). He declines and reports a "suspected fake or entrapment profile" (02 Impl 19). Moderation finds the account said Interested to every introduction: a dragnet flag (04 Impl 3e). | The protections work as a set. |
| 3 | His mother picks up his phone: a Notes-style icon, then the Safety PIN; she sees nothing. He also learns the triple-tap quick exit. **Today, quick exit does not wipe dating caches** (04 G10). | This must be fixed before any Tier 1 launch. |
| 4 | He meets a verified match at a mall food court in daylight. Share my plan to a friend leaves out the match's name and photo (04 Impl 28). | Correct. |

**Fixes**
1. Get Ghanaian counsel before offering same-gender introductions in Ghana. Pre-build the per-country kill switch. If counsel hasn't cleared it at launch, use Branch B's honest copy and resources (Q5). (D4, **P0**)
2. **Ask D6 before D4**, and set the tier to the highest of SIM country, dating country and session IP country (04 Impl 1). (D4/D6, **P0**)
3. All Tier 1 protections are enforced on the server before any Tier 1 country enables same-gender matching (04 Impl 3). (**P0**)
4. Quick exit wipes dating caches; `FLAG_SECURE`; a Dating PIN (04 Impl 5). (**P0**)
5. Hard-delete preferences on exit, plus a law-enforcement request policy (04 Impl 8, Q12). (**P0**)

---

### P17. Esinam: 17, tries to sign up

**Esinam, 17**, final-year senior high school student in Ho. Her sister's old Tecno Spark 10. She saw a TikTok about Attune Dating.

| Step | Sees | Does | Data | Outcome |
|---|---|---|---|---|
| G1 | "I'm 18 or older" (07 Impl 14) | Taps it | local flag | The yes/no gate lets her through to Opinions (05 §5.1 warns against exactly this). |
| A2 | Enters her real DOB (2009) → "Attune is for adults (18 and over). We haven't saved anything you entered." plus a youth-support link; a 30-day local block (05 §5.1) | — | nothing on the server | She stops, embarrassed. **No phone number was ever collected.** This is the reason to ask DOB before the phone (Q1). |
| day 2 | Uninstalls and reinstalls. Whether the block survives depends on backup: Android Auto Backup restores SharedPreferences by default unless it's excluded [Unverified for this app]. | — | — | Probably gone. |
| day 2 | Enters 2005 → "That makes you 21" → phone → code → Dating | a false declared DOB | — | Through the first layer. |
| D11 | Facial age estimation with challenge age 25 → estimated under 25 → ID fallback (Ghana Card or passport, for example through Smile ID, 04 §2.2.3) → she has none → "We couldn't confirm your age for Dating." | — | pass/fail only | **Dating blocked.** Just for me and Opinions stay open under the false DOB. |
| day 9 | Her 22-year-old boyfriend sends a couples invite. `accept-invite` checks the declared DOB, which passes. | — | link | The two-layer model protects Dating, not couple linking. This is an accepted limit (04 §2.2.1, bottom line). |

**Side effect.** With a challenge age of 25, most real 18–24-year-olds go to the ID fallback. In Ghana that is a large share of new users.

**Fixes**
1. Store the under-18 block where it survives a reinstall: a backed-up preference plus the iOS Keychain. (A2, P2)
2. A birth-year gate for guests (Q12). (G1, P1)
3. A fast Ghana Card path for the ID fallback, a decision within 24 hours, and the fallback rate measured by age band (aggregate). (D11, P1)
4. For 18–20-year-olds, default the age range to at most 7 years older (03 Q6). (D14, P2)
5. An `underage_risk` report closes the person's matches (04 Impl 12). (M, **P0**)

---

### P18. The scam crew: the account the flow has to stop

**A crew of four in Kasoa.** The setting is the December 2025 romance-scam hub raid (01 §2.6). They have five used Android phones and SIMs registered with other people's Ghana Cards [Unverified]. They use stolen photos of a UK-based model and target diaspora men in the UK and US.

| Step | What they try | How the flow responds | Cost to them | Cost to honest users |
|---|---|---|---|---|
| A1–A6 | 5 accounts | OTP works (real SIMs) | low | — |
| D6 | Ghana, plus "open to people in the UK and US" | Cross-border needs both people verified; targets see an education card (04 Impl 20) | — | one card |
| D9 | Stolen photos | Vision face check passes | — | — |
| D11 | The live face doesn't match the photos → CompareFaces fails. A deepfake injection → Face Liveness claims to detect injection (04 §2.2.3, vendor **W**) → fails. Human fallback: photos and live face differ → rejected | **4 of 5 accounts blocked** | high | the same check everyone does |
| D11 retry | One member uses his own face and his own photos | Passes | — | — |
| D14 | 72 h cool-off; at most 3 introductions a day; the cross-border pool is only verified diaspora users who opted in | Reach is a handful of introductions a week | high | 72 h wait |
| M | A copy-pasted opener to 3 matches → same-message hash (04 §2.4.2) → moderation. "Transport fare" or "data bundle" → money card to the target (04 Impl 22). A WhatsApp request → masked for 72 h (04 Impl 21). The target reports → interim hold (04 Q7) | **Account held on day 6** | high | — |
| new SIM | A new account on the same phone | Device and IP clustering → moderation (04 Impl 22) | — | — |

**What this shows.**
- The curated, capped design makes Attune a poor target next to Facebook. Capping introductions is "the strongest limit available" (04 §2.4.2).
- Honest users pay with liveness, the 72-hour wait and masking. That is why each of these needs to be explained at D1 and never feel punitive (02 §2.6).
- Fairness rule: never use country, network or name as a risk signal; use behaviour only (02 Impl 5).

**Fixes**
1. Cross-border introductions also need an account at least 14 days old (a Sim proposal), as well as both people verified. (D6/D14, P1)
2. The same-opener hash and device/IP clustering go to moderation. A single signal never triggers an automatic ban (02 Impl 4). (M, P1)
3. Interim holds on P0 reports (04 Q7). (M, P1)
4. Behaviour-only risk signals, written down as a rule (02 Impl 5). (M, **P0**)

---

### P19. Abigail: partnered, using Just for me in private

**Abigail, 38**, trader in Kumasi. Married. Her husband checks her phone. She wants somewhere private to write. **Path: Just for me.**

| Step | Sees | Does | Feels / friction | Risk |
|---|---|---|---|---|
| A6 | "Just for me … Single, partnered or in between." | Picks it | "So it's allowed." | none |
| J1 | First note; journal-lock offer (CR-06 F11 (7)) | Sets a lock | Safer | none |
| J4 | Two quiet rows on Me: "Invite a partner" and **"Turn on Dating"** (06 Q16) | — | If her husband sees "Turn on Dating" on her phone: "Why is there dating on your phone?" | **harm** |
| Settings | Discreet icon (CR-06 F8), Safety PIN (F2), quick exit (F3) | Sets a PIN | — | — |
| Reminders | "Time to write" | — | The push text must be neutral | low |

**Fixes**
1. **Replace the two quiet rows with one neutral row, "More ways to use Attune",** which opens a sheet offering Relationship or Dating. (J4, **P0**)
2. Neutral push text; the journal lock screen says only "Notes" (CR-06 F11 (7)). (J3, P1)

---

### 2.4 Recurring frictions, ranked

Ranked by how many people hit each friction and how bad it is. "Severity" is the worst outcome seen in the simulations.

| Rank | Friction | People | Where | Severity | Fix in short |
|---|---|---|---|---|---|
| 1 | **The sign-in wall**: late SMS, WhatsApp code sent to the wrong SIM, no voice option, older users who can't hold the code, form lost on close, consent-sheet wording, roaming | P1, P2, P3, P5, P7, P11, P12 (7) | A3–A4 | Blocker | Send SMS Hook with voice fallback; autofill (app hash, origin-bound code); "Is WhatsApp on this number?"; keep A1–A3 on the device; passkey after week 1 |
| 2 | **Dating takes 3–4 days and 12–14 screens to the first introduction** | P5, P6, P7, P8 (Branch B), P9, P11, P12, P16 (8) | D1–D14 | High drop | Start the cool-off at A5; merge screens; show the exact day at D1; one "get ready" activity while waiting |
| 3 | **Invite plumbing**: lost on iOS install, invitee creates their own invite, expiry, "Invite someone else", the link flow for matched pairs | P1, P2, P3, P4, P10 (5) | R1, RI, link | High (the couple path's whole value) | Code in the message; "My partner already invited me"; accept withdraws the acceptor's own invite; expired-code screen; "Send a new invite"; in-chat link request |
| 4 | **Dating shown where it harms**: a married person "on my own", the ending window, a partnered Just-for-me user | P4, P15, P19 (+ P14 pause surprise) (4) | R3, post-ending, J4 | **Harm** | Path-aware visibility; one neutral "More ways to use Attune" row; confirm before Dating pauses |
| 5 | **Accessibility and text size**: 1.0 clamp, six unlabelled boxes, visual-only liveness, 5-second undo | P2, P7, P12 (+ P11) (4) | every screen; A4; D11 | Blocker for those groups | Remove or raise the clamp; one labelled code field; accessible liveness; adjustable undo; accessibility tests in CI |
| 6 | **Liveness failures**: low memory, glare, glasses, blindness, ID fallback for 18–24-year-olds | P5, P7, P11, P12, P17 (+ P18, deliberately) (5) | D11 | High | Resumable; guidance on light and distance; human fallback within 24 h; fast Ghana Card path |
| 7 | **Thin pool, "not in your area", the "worldwide" promise** | P6, P7, P8, P11, P16 (5) | S0, W1, D1, D14 | High churn | Show availability before sign-up; honest empty days; widening the person chooses; cross-border opt-in |
| 8 | **The gentle wait as a timer** invites evasion that defeats ex-exclusion | P15 (1, structural) | D0 | **Harm** | Tie it to the 30-day window plus a readiness reflection |
| 9 | **Answer sets that don't fit people's lives** | P2, P3, P5, P7, P8 (5) | R3, D3, D6, D8, Healing | Moderate | Keep the second ceremony; stage helper text; optional denomination; regional faith lists; "Companionship"; bereavement-aware Healing; city sides |
| 10 | **Reports used as a weapon; fairness** | P5, P18 (2) | M | High in West Africa | Credibility weighting; "reported after declining" safeguard; behaviour-only signals |
| 11 | **Side effects of switching path** | P9, P10, P13, P14 (4) | X | Moderate | A permanent "Your space"; switches that can be undone; confirm before pausing; return to the guest's intent |
| 12 | **Low-end device and data** | P11 (+ P3) (2) | S0, W0, D9, D11 | Severe for rural users | Size budget; data-saver; resize photos on the device; resumable steps; first frame independent of the network |
| 13 | **Shared fields: unattributed edits, flip-flops** | P1, P2, P3, P10 (4) | R3/R4 | Low–moderate | A quiet "Changed by …" line; a "you see this differently" hint |
| 14 | **DOB ambiguity and correction** | P2, P6, P17 (3) | A2 | Silent error | Month in words; accept the best-known date; a correction path |
| 15 | **Guest gate and continuity** | P13, P17 (2) | G1 | Low | Birth-year gate; return to the post or compose screen after sign-up |

---

## 3. Implications for Attune

### 3.1 Strawman steps to cut, reorder or merge

1. **Reorder Dating setup** to D1 → D3 → **D6 → D2 → D4** → D5 → D7 → D8 → D9 → D10 → D11 → D12.
   - **D6 (where) before D4 (who):** the country note must use the dating country, not just the SIM. In P16's variant, a returnee on a UK SIM never saw the note.
   - **D2 consent immediately before the first sensitive question:** consent is understood best in context (P5, P9). It is still a separate explicit act, as Art. 9(2)(a) requires (04 §2.3).
2. **Merge D3** (intention, timeline revealed inline when Marriage is chosen, attestation as a required line underneath) **into one screen.** These are parts of one answer, the case where 05 §3.5.1 allows grouping (P5, P6, P7).
3. **Merge D12 and D13.** The notification ask sits inline on the preview (05 D8 is already inline). **Merge D8's** tradition, importance and optional denomination onto one screen.
4. **Result: 12 Dating screens, one of them optional (D8).** That is still above 01 Impl 3's target of 8. Accept it, on the condition that every step saves, and the effort is explained and pays off (02 §2.6, Impl 12; P5 read the effort as seriousness).
5. **Start the cool-off at A5 (account creation), not at activation,** and **show the exact first-introduction day at D1.**
   - It costs a scammer the same per account (04 C2).
   - Someone who takes two days to finish setup waits nothing extra.
   - People affected: P5, P6, P7, P9, P11.
6. **While waiting, D14 offers one "get ready" activity:** the first-date guide, the journal or a quiz. **No fake "building your matches" screen** (05 §3.7).
7. **D1 gains a second action: "Not ready? Use Attune just for me"** (P14).
8. **A6 and R1 gain "My partner already invited me"** (P1).
9. **The A2 confirmation names the month in words** (P6).
10. **The W1 Dating preview and the store listing say where Dating is open** (P8; 05 Q13).
11. **G1 becomes a birth-year entry** (P13, P17; reconciles 05 §5.1 and 07 Impl 14).
12. **J4's two quiet rows become one neutral "More ways to use Attune" row** (P19).
13. **On the Relationship path:**
    - "Send a new invite" replaces "Invite someone else";
    - "On my own for now" keeps the path as Relationship;
    - **Dating is never shown on the Relationship path or in the ending window** (P4, P15).
14. **D0 ties the wait to the 30-day window, with a readiness reflection** (P15; Q6).
15. **Cut from the Dating consent screen** the "I am 18 or older" checkbox (now redundant, 06 §2.4) and the historical-data checkbox (P9; 03 Impl 1).
16. **Keep 05's A1–A6 order.** An under-18 never hands over a number (P17), and returning users skip A1–A2 (Q1).
17. **Keep the About-us card after the invite** (05 Q7). P1, P2 and P4 all filled it in while waiting, and it was their day-0 value.

### 3.2 Which data fields are worth their friction

| Field | Path | Friction seen | Value seen | Verdict |
|---|---|---|---|---|
| Name (any script) | all | none | Needed everywhere; names-not-pronouns copy (05 Impl 20) | **Required** |
| Date of birth | all | Low: day/month order (P6), unknown exact date (P2), "why?" | 18+ gate; age only ever shown | **Required.** Month in words; accept the best-known date |
| Phone | all | **High**: OTP delivery (rank 1) | Identity anchor; ex-exclusion HMAC (06 Impl 12) | **Required** |
| Path | all | Low, but wrong choices happen (P14) | Decides home and steps | **Required**, easy to undo |
| Together since | R | Moderate: partners disagree (P1, P10) | Anniversary reminder only (05 §5.5) | **Optional**; one source shared with reminders |
| Stage and married year(s) | R | Low; the knocking makes it ambiguous (P3) | Relevance; the second ceremony delighted P2 | **Optional**; keep "Add another ceremony" |
| Living arrangement | R | none | Turns on long-distance features (P3) | **Optional** |
| Children (couple) | R | none | Relevance | **Optional**; age bands optional |
| Intention | D | Low; "companionship" was missing (P7) | Hard filter; the basis of "why you two" | **Required**; 4 options (Q4) |
| Marriage timeline | D | none | Shared ground for marriage-minded people (P5, P8) | **Optional**, shown only for Marriage |
| Not-married attestation | D | none | Safety; the polygamy policy (02 Q5) | **Required**, on the intention screen |
| Who you want to meet | D | Very sensitive (P16) | Symmetric hard filter | **Required**; special category; never shown |
| Own gender | D | Low | Hard filter | **Required**; private by default |
| Country and region | D | Low with a full list; **HIGH with today's 6 cities** (P11) | Filters, risk tier, same-country default | **Required**; all regions; optional city "sides" (Q8) |
| Open to people abroad | D | Low | Diaspora (P6, P8); scam exposure if on by default | **Optional**, off by default |
| Children have/want | D | none | Dealbreaker (P6); never child details | **Required** |
| Faith and importance | D | Low; lists didn't fit (P5, P8) | Decisive for faith users (P5) | **Optional**; regional lists; denomination optional |
| Marital history | D | none | P7 wanted it visible | **Optional**; per-field visibility |
| Photos (2+) | D | Moderate (P7, P11, P12) | Humanises; needed for liveness matching | **Required**; "after mutual interest" option; resized on the device |
| Prompts (2–3) | D | Moderate (writing) | Conversation fuel; person before photo | **2 required**, with suggestions |
| Liveness and age estimate | D | **High** (rank 6) | Fraud (P18), age (P17) | **Required**, with fallbacks |
| Family involvement | D | none | Shared ground (P8) | **Optional; ask after the first introduction** |
| Photo captions | D | none | Accessibility (P12) | **Optional**, later |
| Ethnicity, tribe, caste, income, health, body type | D | — | P8's parents would want caste; nothing else asked for these | **Never** (01 Impl 11) |

### 3.3 Where motion and celebration belong

Values follow 05 §6. Every moment has a reduced-motion fallback (an opacity cross-fade) and skips Lottie on low-RAM devices.

| Moment | Treatment | Why (from the simulations) |
|---|---|---|
| Code accepted (A4) | Check fades in, 400 ms hold, auto-advance | P2: relief after a hard step |
| Path chosen (A6) | Container transform at 400 ms, the single "arrival" flourish | Marks a decision without fanfare |
| **Partner linked (R4)** | Two avatars settle, at most 600 ms, one light haptic, **once on each phone**, even if one opens later | P1 and P3 shared the moment in person or on a call |
| Liveness passed (D11) | A calm "You're verified" check | P5: a trust moment |
| First mutual match | A quiet, warm screen; no burst, no "It's a match" (01 Impl 16) | P5, P10 |
| **Dating → Relationship link** | The same settle, after both confirm; copy: "You decided together" | P10: the most meaningful moment in the product (03 §2.7) |
| Introductions arrive | Calm cross-fade; no counters | 03 (d): no counts |
| First note saved (J1) | Text only: "Saved, just for you" | P9 at 03:10: calm, nothing playful |
| **Never animate** | Under-18 stop, consent, safety and country notes, ending, gentle wait, Healing, empty "no good fit" days, reports and scam cards, "Close kindly", "not in your area", expired invite | P15, P16, P17, P7, P8: a painful or frightening moment met with motion would feel careless (05 §6; motion spec §1.1) |

### 3.4 Metrics to watch

All are server-side aggregates in daily buckets: no user or device IDs, no answers, no gender or preference values, and cells shown only at n ≥ 50 (05 Impl 22; 01 Impl 17).

| Area | Metric | Why (people) |
|---|---|---|
| Sign-in | Code requested → verified, by **carrier, channel and country**; use of voice fallback; median seconds to code | Rank 1 (P1, P2, P3, P11) |
| Sign-in | Get started → A6, median (target ≤ 90 s) | 05 §4.0 |
| Invite | Sent → accepted within 24 h and 7 days; median hours; **share typed by code vs opened from a link**; invitee-created duplicate invites; expired-code hits | P1, P4 |
| Couples | Partner not joined at day 7 and day 30; "Send a new invite" use; "on my own" retention at day 30 | P4 |
| Dating funnel | Completion per D step; time from A6 to D11 pass; **time from A5 to first introduction** (target ≤ 72 h); uninstalls before the first introduction | Rank 2 |
| Verification | First-try pass rate; fallback rate **by age band and device RAM class**; time to decision (target < 24 h) | P11, P12, P17 |
| Pool | "No good fit today" rate by city per week; introductions per active person per week; "not in your area" counts by country | P6, P8 |
| Outcomes | Mutual interest per introduction; "we met" conversion; time to meet; share of chats ended with Close kindly; Dating → Relationship links | 03 (e); P10 |
| Safety | Reports per 1,000 matches; money-card and masking events; dragnet flags; interim holds; **enforcement overturned, by country** | P5, P16, P18; 02 Impl 4 |
| Path | Path switched within 7 and 30 days, by from→to | P14 |
| Gentle wait | Share who start on the earliest date; **account deletions within 7 days of the wait screen** | P15 |
| Accessibility | **Not measured per user.** Use a test matrix instead (TalkBack, VoiceOver, 200% text, Android Go) | P2, P12; accessibility settings are sensitive signals |
| Anti-metrics | Sessions a day, time in app, introductions viewed: watched, never optimised | 03 (e) |

---

## 4. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | Ask DOB before the phone (05) or after the code (06 Q1)? | **Before the phone**, held on the device and written after the code. P17 shows a minor never hands over a number; returning users skip it. |
| Q2 | Shared couple-profile edits: unattributed (05 §5.3) or "Last edited by …" (06 Q4)? | **Attributed, as a quiet line with no push.** With two people, anonymity is a fiction and caused a spat (P1). |
| Q3 | When does the Dating cool-off start, and how long is it? | **72 h from account creation (A5)**, overlapping verification, with the exact first-introduction day shown at D1. Pilot 48 h against 72 h. |
| Q4 | Intention set: 01's four or 03's set (which includes companionship)? | **Marriage · A committed relationship · Companionship, at my own pace · Not sure yet.** P7 and the 50+ research need companionship (03 §2.10); four options keep the pool together (01 §3.5). |
| Q5 | Same-gender introductions for accounts in Ghana (03 Q3 vs 04 Q1)? | **Counsel decides.** Build every Tier 1 protection plus the kill switch now. If counsel hasn't cleared it at launch, show Branch B's honest copy with resources rather than filtering silently (P16). |
| Q6 | Length of the gentle wait after an Attune ending? | **The shared space's 30-day window (shorter if both seal it), plus the readiness reflection and Healing offered; no 8-week timer and no score.** A hard timer pushed P15 towards re-registering, which defeats ex-exclusion. Needs a clinical note (04 Q10). |
| Q7 | Which countries open Dating at launch, and how is that shown? | Ghana plus selected diaspora countries (04 Q3): for example the UK once age assurance is done, Canada, and the US once biometric consent is in place (04 Impl 15). **State it on the store listing and in W1's preview**, with a single "Tell me when it's here" opt-in (P8). |
| Q8 | Mega-city sides (Lagos Island/Mainland, Accra/Tema) as a location option? | **Yes, optional, and never finer than a "side".** Two-hour cross-city trips are real (P5), and a side doesn't reveal a neighbourhood (04 §2.1.5). |
| Q9 | Remove the 1.0 text-scale clamp in the shared root shell? | **Yes, raised to at least 2.0 behind a layout and golden-test pass**, onboarding, chat and Dating first. ⚠ Every screen reflows (P2, P7). |
| Q10 | A matched pair's first dating messages when they link: delete or keep? | **A joint "Keep our first messages" opt-in** that copies them into a read-only "How we met" card; otherwise delete on schedule (04 Impl 8) (P10). |
| Q11 | May "Together since" offer the match date as a suggestion chip? | **Yes, as a chip the couple taps**, never pre-filled. It is a date, not content inferred from messages. This is a narrow exception to 05 §5.0 (P10). |
| Q12 | Guest age gate: one-tap 18+ (07) or neutral (05)? | **Birth year, no default, kept on the device**, which later fills A2's year (P13, P17). |
| Q13 | Liveness fallback when capture fails (low-end phones, blind users)? | **A photo with a gesture, reviewed by a person within 24 hours**, plus audio and haptic guidance in the main capture (P11, P12). |
| Q14 | Faith lists for a worldwide product? | **Region-aware lists** with "Other" and "Prefer not to say"; optional denomination for Christians (P5, P8; cultural reviewer). |
| Q15 | Healing for bereavement? | **"After a breakup or a loss"**, with grief resources routed through F10 (P7). Full grief content later, with clinical review. |
| Q16 | Couples content for someone whose partner never joins? | **Yes: a solo "Working on us, on my own" set** that never interprets the absent partner (P4). Without it, day-30 retention on this path is close to nothing. |
| Q17 | Is a 14-day minimum account age for cross-border introductions worth the delay for honest diaspora users? | **Yes, for cross-border only.** Same-country introductions stay at 72 h. Cross-border is where the classic scam script lives (04 §2.4.1) (P18). |
