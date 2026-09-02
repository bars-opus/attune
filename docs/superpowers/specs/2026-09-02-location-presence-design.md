# Location Presence — Design

**Status:** approved for build, expected to need refinement in use
**Date:** 2026-09-02

## 1. What this is

Two features sharing one data source:

1. **Distance** — an ambient, deliberately coarse sense of how far apart the
   couple is, on the conversation screen beside the next calendar event.
2. **Place updates** — a partner *chooses* a moment ("at the coffee shop"),
   optionally with a note or photo, which appears in the section and as a
   card in the chat.

## 2. What this is NOT, and why

No map of the partner. No pin. No "where is she right now". No request-location
button. No live tracking.

Attune ships a discreet exit (triple-tap to a decoy screen) as a permanent
constraint, and its safety system has rule categories named `isolation_control`
and `pattern_control`. The product is explicitly built with the possibility
that one partner is coercive. A location feature in that product has to be
designed so that it cannot become an instrument of the thing the rest of the
app defends against.

The design resolves this by inverting who controls disclosure:

- The app never reveals where anyone is.
- Precision only ever appears in an update a person **chose** to send.
- The ambient number is coarsened until it cannot be read as movement.

"If you are truthful you should not mind sharing" is the argument a controlling
partner uses, and it only holds where the feature is not needed: in a healthy
relationship declining costs nothing, and in a coercive one declining is the
accusation. This design removes the standing thing there is to withhold. There
is nothing to turn off, so nothing whose absence can be interrogated.

The counter-argument that decided the build: a controlling partner will demand
location from Find My or Life360 regardless. Refusing to build it protects
nobody and moves the demand to a platform with no safety detector at all. Built
here, the demands land in Attune's chat, where the coercive-control rules
already run.

## 3. Distance

### 3.1 Coarsening

Distance is **bucketed, never exact**, so watching the row cannot reveal
movement. A number that twitches is a movement sensor; a bucket that changes
once an hour is not.

| Situation | Shown |
|---|---|
| < 1 km | "Practically together" |
| Same city (< 50 km) | "About 20 minutes away" (rounded to 5 min) |
| Same country | "4h by road · 1h by air" |
| Different countries, trip in the calendar | "12 days until you're together" |
| Different countries, no trip | "5,100 km apart · 11pm there, 8pm here" |
| Moved a lot since yesterday | "1,200 km closer than yesterday" |

### 3.2 The long-distance problem

A static large number does not create closeness. Accra ↔ London is 5,100 km
today, tomorrow, and every day for a month: the row becomes a daily reminder of
absence. This is the couple the feature is FOR, and the naive version works
against them.

So the row shows what *changes* when distance does not:

- **Their local time**, which answers the actually useful question: can I call?
- **A countdown**, when the shared calendar has an upcoming event both attend.
  "12 days until 0 km" is the same data with the opposite emotional valence.
- **The delta**, when someone is travelling. The derivative is the interesting
  number, and it spikes exactly when something meaningful is happening.

### 3.3 Freshness

Location is sampled periodically, not continuously — on app foreground, at most
every 15 minutes. Distance is a slow-moving fact; live tracking would cost
battery to deliver a number that is bucketed anyway.

A stale position must never be presented as current. Positions older than 24
hours stop producing a distance entirely rather than showing a confident wrong
number, and anything over an hour is labelled ("as of this morning").

## 4. Place updates

A deliberate act: the partner taps, picks or confirms where they are, and may
attach a note or photo.

- Appears in the conversation-screen section (latest only) and as a card in the
  chat — the chat copy is where a note and photo belong, and it lets the
  existing analysis pipeline see it.
- Deletable like any message. Deleting removes the stored coordinates too: a
  photo of a bar at 1am may read differently tomorrow, and the exit has to be
  as easy as the entry.

### 4.1 No cadence, ever

**No streaks, no counters, no "you haven't shared today" nudge, no
notification when an update does not arrive.**

This is the load-bearing rule of the whole feature. If updates become an
expected rate, their absence becomes readable — "you went out and didn't share"
is the same accusation as "you turned your location off", arrived at more
gently. The app must never establish an expected frequency. Attune uses streaks
elsewhere, which makes this a live temptation rather than a hypothetical one.

## 5. Data

`partner_presence`: one row per user — coarse position, city, country,
timezone, updated_at. Read only by the other member of an active relationship,
through a SECURITY DEFINER function returning DISTANCE, not coordinates. A
client never receives its partner's raw position.

`place_updates`: the deliberate ones. Full precision, because the user chose to
send it. Linked to the chat message so deleting either removes both.

Both are opt-in. Turning presence off deletes the stored position rather than
hiding it, and does not notify the partner.

## 6. Open questions, deliberately deferred

- Whether a countdown needs an explicitly tagged "visit" event or can infer one
  from any shared calendar entry.
- Whether the ambient distance earns its place at all once place updates exist,
  or whether update-only is cleaner in practice.
- Travel-mode thresholds (when does "by road" become "by air") likely need
  tuning against real couples rather than reasoning.
