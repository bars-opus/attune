# ATTUNE — FORUM FEATURE SPECIFICATION V2
### Updated implementation spec incorporating owner decisions
**Version:** 2.0
**Created:** June 2026
**Status:** Ready for DeepSeek implementation
**Changes from V1:** Anonymity system redesigned, forum identity table removed,
follower count added to profile page, forum insight screen added,
navigation and push notifications confirmed as already configured.

---

> **HOW TO USE THIS DOCUMENT**
>
> This replaces ATTUNE_FORUM_SPEC.md V1 entirely.
> Build in the exact order defined in Section 9.
> Do not build anything not described here without review.
> If something is unclear, ask before building it.

---

## TABLE OF CONTENTS

1. [What Changed From V1](#1-what-changed-from-v1)
2. [Navigation Structure](#2-navigation-structure)
3. [Anonymity System — Simplified](#3-anonymity-system--simplified)
4. [Feature 1 — Opinions](#4-feature-1--opinions)
5. [Feature 2 — Forums](#5-feature-2--forums)
6. [Forum Insight Screen](#6-forum-insight-screen)
7. [Shared Rules](#7-shared-rules)
8. [Moderation System](#8-moderation-system)
9. [Database Schema](#9-database-schema)
10. [Notification System](#10-notification-system)
11. [Build Order](#11-build-order)
12. [Infrastructure Confirmation](#12-infrastructure-confirmation)
13. [Open Questions](#13-open-questions)

---

## 1. WHAT CHANGED FROM V1

### Removed entirely
```
- forum_identities table (no longer needed)
- Anonymous username generation (no usernames shown at all)
- Forum identity setup flow (4 screens) — not built
- Forum settings screen — not built
- Anonymous profile page replacing with follower-visible profile
```

### Changed
```
- Anonymity model: blank name + relationship_status from profile table
  instead of auto-generated anonymous username
- Follower count: shown on anonymous profile page (owner decision)
- City display: future feature, not in this implementation
- Anonymous profile page: shows follower count (see Section 4.7)
```

### Added
```
- Forum insight screen (Section 6)
  Shows: FOR vs AGAINST counts, forum start date, activity stats

- Polls (Section 7.x + Section 9 schema)
  Optional attachment on an opinion or a forum topic.
  2-4 immutable plain-text options, one poll per post, no expiry.
  Phone-verified voters only, one vote per user, changeable and
  retractable. Results hidden until you vote. Aggregate counts only.
  Distinct from topic_votes: topic voting gates a topic into
  existence, a poll asks that topic's readers a question.

- Reposts (Section 7.x + Section 9 schema + Section 10 #9)
  One-tap share-as-is on an opinion, opinions only (not forum topics).
  Reference row, not a content copy -- likes/comments/reports always
  belong to the one original opinion. No self-repost, no
  repost-of-a-repost. Surfaces in Discover/Following under the
  reposter's own author_handle, timestamped at repost time. Original
  author is notified anonymously, same as likes/comments/replies.

- Quotes (Section 7.x + Section 9 schema + Section 10 #10)
  Repost + your own opinion. Unlike a repost, a quote IS a full
  opinion -- own text, own posting-path validation, own
  like/comment/report counts, own feed placement -- that also embeds a
  reference to the opinion it quotes. Self-quote allowed. No
  quote-of-a-quote -- always re-targets the original. If the quoted
  opinion is later removed, the quote stays up and the embedded
  original shows a placeholder. Original author notified anonymously
  (not on self-quote).

- Editing (Section 7.x + Section 9 schema)
  Opinions, comments, and forum posts editable within 15 minutes of
  posting. Same content validation as posting (5000-char + keyword
  filter — limit raised from 280 by later owner decision, see Section 9).
  Shows "(edited)", no history. Independent of report state --
  an edit never resets report_count or hidden_pending_review.

- Mute / hide (Section 7.x + Section 9 schema)
  Per-post hide and per-author mute, both feed-only filters, no
  moderation implication, no effect on counts, no notification to the
  affected author. Mute keyed on author_handle (never user_id), silent,
  retroactively hides the muted author's existing posts too.

- Tags (Section 7.x + Section 9 schema)
  Fixed, app-defined 20-tag starter vocabulary (not user-editable) on
  opinions and forum topics, up to 3 per post, optional, set at
  creation. Fixed rather than freeform specifically because a
  user-invented tag is a fingerprint; browsing a tag is anonymized like
  every other feed and cannot be combined with an author filter.
```

### Confirmed as already built (do not rebuild)
```
- Navigation structure (top bar with Opinions and Chat tabs)
- Push notification service (OneSignal — already configured)
- Supabase project (configured, profile table exists with
  relationship_status column)
```

---

## 2. NAVIGATION STRUCTURE

### Already built — wire new screens into existing structure

```
TOP NAVIGATION BAR (already exists):
┌─────────────────────────────────────┐
│  Opinions  │  Chat                  │
└─────────────────────────────────────┘

Default selected tab by user mode:
- Single mode users     → Opinions tab (default on app open)
- Couples mode users    → Chat tab (default on app open)
- Personal mode users   → Opinions tab (default on app open)
```

### Opinions tab — internal navigation (build this)

```
OPINIONS TAB
├── Sub-tab 1: Opinions   ← Twitter/Threads-like feed (default)
│   ├── Following feed
│   └── Discover feed
└── Sub-tab 2: Forums     ← Topic voting and debate rooms
    ├── Contributing tab  ← Forums user has posted in or voted in
    └── Explore tab       ← All active forums to browse
```

### Bottom tab bar — unchanged

```
Pulse | Chat | Games | Insights | Profile
No changes to this bar.
```

---

## 3. ANONYMITY SYSTEM — SIMPLIFIED

### Core principle

Posts in Opinions and Forums are anonymous.
No username is shown anywhere in the forum/opinions space.
The only visible identity signals are:

```
1. Relationship status (from profile table, automatic)
2. City (future feature — NOT in this implementation)
```

### What appears on every post

```
┌─────────────────────────────────────┐
│  🟢 Single                   2h ago │  ← status icon + relationship_status · time ago
│                                     │
│  [post content here]                │
└─────────────────────────────────────┘
```

There is no name. There is no photo. There is no username placeholder.
The name field is not rendered at all — it simply does not exist in the UI.

**Owner decision (forum group-chat restructure):** the debate room's
`ForumPostBubble` (`lib/features/forums/presentation/widgets/forum_post_bubble.dart`)
carries a small `CircleAvatar` alongside each non-mine post, filled with a
status-derived color and icon (via `statusIconFor`/`statusColorFor`). This is
NOT a real avatar in the sense this section originally forbade — it encodes
no photo, no identity, nothing beyond the same `relationship_status` value
already shown as text next to it. It exists purely so the bubble reads as a
message-thread participant marker (matching the 1:1 chat bubble convention
this screen borrows), the same way the badge dot in the same bubble encodes
FOR/AGAINST. The original "no avatar" rule stands for anything that could
function as a persistent visual identity across posts (a generated
image/icon unique per user, a color keyed to `user_id`, etc.) — that remains
permanently forbidden. A status-icon glyph that any two posters with the
same `relationship_status` render identically is not an identity signal and
is allowed.

### Where relationship_status comes from

```
Source: profiles table, relationship_status column
Pulled: automatically at post creation time
Stored: on the post itself (denormalised for display performance)
        so that if a user changes their status, old posts
        show the status they had at time of posting

SQL at post creation:
INSERT INTO opinions (user_id, content, relationship_status_at_post)
SELECT auth.uid(), $content, p.relationship_status
FROM profiles p WHERE p.id = auth.uid();
```

### What relationship_status values map to display

```
'single'         → displays as "Single"
'taken'          → displays as "Taken"
'figuring_it_out'→ displays as "Figuring it out"
'open'           → displays as "Open"
NULL or empty    → displays as nothing (blank, no status shown)
```

### Linking posts to real accounts (internal only)

Every post stores `user_id` internally for:
- Moderation (admins can identify poster if needed)
- Preventing users from liking their own posts
- Posting limits enforcement
- Ban enforcement

The `user_id` is NEVER exposed in any API response to clients.
RLS policies enforce this strictly.

### City display

City is NOT shown in this implementation.
It will be a future settings feature.
Do not add any city field, city column, or city display code now.
When it is built later, it will be a settings toggle that
pulls from the user's profile location data.

---

## 4. FEATURE 1 — OPINIONS

### What it is

Text-only public feed. Works like Twitter/Threads with these rules:
- Text only. No images. No video. No audio. No links previewed.
- Maximum 5000 characters per opinion post (owner decision, raised from the
  original 280 — see the note on the canonical schema block in Section 9).
- Comments allowed. Maximum 5000 characters per comment (same raise).
- Likes and dislikes are the only reactions.
- Fully anonymous — blank name, relationship status only.

### 4.1 The feed — two tabs

#### Following tab

Shows opinions from anonymous users the current user follows.

```
- Initially empty for new users with empty state prompt:
  "You are not following anyone yet.
   Head to Discover to find voices you connect with."
- Chronological order — newest first
- Infinite scroll
- Pull to refresh
```

#### Discover tab

Shows opinions from all users with smart ordering.

```
Ordering logic (priority order):
1. Opinions from users with same relationship_status shown first
   (Single users see Single-posted opinions higher in feed)
2. Within same status: ordered by engagement score × recency weight
   Engagement score = (like_count - dislike_count) + (comment_count × 2)
   Recency weight = 1 / (hours_since_posted + 1)
3. Opinions the user already interacted with are deprioritised
4. Opinions with more dislikes than likes ranked lower but never hidden
5. No AI targeting — simple rule-based ordering only
```

### 4.2 Posting an opinion

```
Compose screen:
┌─────────────────────────────────────┐
│  Single                             │  ← their relationship_status
│                                     │
│  ┌─────────────────────────────┐   │
│  │ What's on your mind?        │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│  5000 characters remaining          │  ← owner decision, was 280
│                             [Post]  │
└─────────────────────────────────────┘

Rules:
- Text only — no media attachment option
- Character count counts down from 5000 (owner decision, was 280)
- [Post] disabled until at least 1 character entered
- [Post] disabled if over 5000 characters
- Editable within 15 minutes of posting, then permanently fixed — see
  Section 7 "Editing" (added after this section was originally written;
  the "only delete" rule below has been superseded by that)
- Deletable at any time by the owner (unchanged)
- Confirmation before posting: "Post this?" [Cancel] [Post]
- relationship_status_at_post captured at insert time from profile
```

### 4.3 Opinion card

```
┌─────────────────────────────────────┐
│                                     │  ← blank, no name rendered
│  Single                      2h ago │
│                                     │
│  Why do avoidant people always      │
│  attract anxious people? Asking     │
│  for myself honestly                │
│                                     │
│  👍 24  👎 3  💬 12  [Follow] [⋯]   │
└─────────────────────────────────────┘

Elements:
- No name field rendered
- Relationship status · time ago
- Opinion text (full, no truncation under 5000 chars — owner decision, was 280)
- 👍 like count (tappable)
- 👎 dislike count (tappable)
- 💬 comment count (tappable → opens comment thread)
- [Follow] button → follows this user anonymously
  Changes to [Following] if already followed
- [⋯] → Report / Copy text / Delete (own posts only)

Interaction rules:
- Like OR dislike, never both simultaneously
- Tapping active reaction toggles it off
- Switching from like to dislike removes like, adds dislike
- Cannot like or dislike own posts
- Own posts show [Delete] in [⋯] menu, no [Follow] button
```

### 4.4 Comments

```
Comment thread screen:

┌─────────────────────────────────────┐
│  ← Back              Comments       │
├─────────────────────────────────────┤
│  [Original opinion card at top]     │
├─────────────────────────────────────┤
│  12 comments                        │
│                                     │
│  Taken · 1h ago                     │
│  Same — the nervous system seeks    │
│  what feels familiar even if it     │
│  hurts                              │
│  👍 8  👎 1    [Reply] [⋯]          │
│                                     │
│  Single · 45m ago                   │
│  Familiarity ≠ safety but the brain │
│  does not know the difference       │
│  👍 5  👎 0    [Reply] [⋯]          │
│                                     │
├─────────────────────────────────────┤
│  ┌──────────────────────────────┐  │
│  │ Add a comment...             │  │
│  └──────────────────────────────┘  │
│                           [Post]   │
└─────────────────────────────────────┘

Rules:
- Comments are flat — no nested replies in v1
- Reply taps pre-fill comment box but do NOT use @username
  (there are no usernames). Instead prefix with "> [first 40 chars
  of the post being replied to]" as a quote prefix.
- Comment max 5000 characters (owner decision, was 280)
- Comments can be liked and disliked
- Comments cannot be edited, only deleted
- relationship_status_at_post captured at insert time
```

### 4.5 Following system

```
Follow is anonymous-to-anonymous (user_id to user_id internally).
No usernames involved.

Follow: tap [Follow] on any opinion card
Unfollow: tap [Following] to toggle

Following tab shows opinions from followed users.

Follower counts:
- NOT shown on opinion cards in the feed
- SHOWN on the anonymous profile page (see 4.6)
  Owner decision: counts are visible on profiles only

A user can see who they follow in:
Profile tab → [Forum following] (future — not in this implementation)
```

### 4.6 Anonymous profile page

Reached by tapping anywhere on a post card
(the whole card is tappable, not a username link since there is none).

```
┌─────────────────────────────────────┐
│                                     │  ← no name, no avatar
│  Single                             │  ← relationship status
│  [Follow]  ·  47 followers          │
├─────────────────────────────────────┤
│  Their opinions — newest first      │
│  [list of opinion cards]            │
└─────────────────────────────────────┘

Shows:
- Relationship status
- Follow/Unfollow button
- Follower count (shown here, not on feed cards)
- All their opinions newest first

Does NOT show:
- Name
- Avatar / photo
- Following count (how many they follow)
- Join date
- Any information linking to their real account
```

---

## 5. FEATURE 2 — FORUMS

### What it is

Forums are live debate rooms where users argue FOR or AGAINST a topic.
Topics are submitted by users and voted into existence.
Once a topic gets more than 50% upvotes from users who have seen it,
it becomes a live forum.
Inside the forum, FOR posts appear on the left, AGAINST on the right.

### 5.1 Forums tab — two sub-tabs

#### Contributing tab

Forums the user has actively participated in:

```
Each forum card:
┌─────────────────────────────────────┐
│  Should you tell your partner       │
│  everything about your past?        │
│                                     │
│  🟢 FOR 142   🔴 AGAINST 89         │
│  Your side: FOR · 3 new posts       │
└─────────────────────────────────────┘
```

#### Explore tab

All active forums sorted by most recent activity.

```
Each forum card:
┌─────────────────────────────────────┐
│  Long distance relationships        │
│  never really work                  │
│                                     │
│  🟢 FOR 98    🔴 AGAINST 74         │
│  231 contributors · 12 min ago      │
└─────────────────────────────────────┘

Sections in Explore:
1. Active forums (ordered by last_post_at descending)
2. Topics waiting for votes (voting pool)
3. Quiet forums (no posts 7-30 days)
```

### 5.2 Topic submission

```
Button: [+ Submit a topic] — on both Contributing and Explore tabs

Submission screen:
┌─────────────────────────────────────┐
│  ← Back        Submit a topic       │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Write a debatable topic...  │   │
│  └─────────────────────────────┘   │
│  120 characters remaining           │
│                                     │
│  Good topics invite two sides.      │
│  "Is jealousy ever healthy?"        │
│  "Long distance never works"        │
│                                     │
│                          [Submit]   │
└─────────────────────────────────────┘

On submit:
- Topic inserted with status = 'voting'
- submitter's vote = 'up' automatically (they count as an upvote)
- submitter's impression recorded (they count as having seen it)
- seen_count starts at 1, upvote_count starts at 1
- voting_expires_at = now() + 14 days
```

### 5.3 Topic voting cards

Shown in the "Topics waiting for votes" section of Explore tab.

```
┌─────────────────────────────────────┐
│  TOPIC UP FOR VOTE                  │
│                                     │
│  "Long distance relationships       │
│   never really work"                │
│                                     │
│  Submitted by: Single               │  ← relationship status only
│  Seen by 89 people                  │
│                                     │
│  ▲ Upvote (FOR)     ▼ Downvote (AGAINST)│
│       52                  21        │
│                                     │
│  58% upvote · needs 50% to activate │
│  ████████████░░░░  58%              │
└─────────────────────────────────────┘

Voting rules:
- Upvote OR downvote, never both
- Toggleable (tap again to remove vote)
- Can switch from upvote to downvote
- Upvote = I am FOR this topic
- Downvote = I am AGAINST this topic
- This determines which side the user is on when forum activates

Impression tracking:
- When this card is visible on screen for ≥ 2 seconds:
  INSERT into topic_impressions (topic_id, user_id)
  ON CONFLICT DO NOTHING (one impression per user per topic)
- Update topic.seen_count accordingly

Activation threshold check (run hourly via cron):
- Condition: upvote_count / seen_count > 0.50
             AND seen_count >= 20
- If met: topic status → 'active', send notifications to all voters
- If 14 days passed without activation: status → 'expired'
  No notifications sent on expiry.
```

### 5.4 Forum activation notifications

```
To all who UPVOTED:
"'[Topic title]' is now a live debate. You're on the FOR side →"

To all who DOWNVOTED:
"'[Topic title]' is now a live debate. You're on the AGAINST side →"

To users who SAW the topic but did NOT vote:
No notification. They can find it in Explore.

To users who never saw the topic:
No notification. They can find it in Explore.
```

### 5.5 Joining a forum (users who did not vote)

```
First entry screen for non-voters:

┌─────────────────────────────────────┐
│  "Long distance relationships       │
│   never really work"                │
│                                     │
│  142 FOR · 89 AGAINST               │
│                                     │
│  Pick your side to contribute.      │
│                                     │
│  [I'm FOR]       [I'm AGAINST]      │
│                                     │
│  [Just browse — I won't post]       │
└─────────────────────────────────────┘

Browse only:
- Can read all posts
- Cannot post
- Never counted as a contributor
- Not shown in forum stats
```

### 5.6 Inside the forum — debate room

**Owner decision (supersedes the original two-column layout below):**
resolves the cross-side-reply `[NEEDS DECISION]` this section originally
carried (see old Section 13 entry) as **Option B — YES, replies cross
sides.** Implemented as `DebateRoomScreen` +
`ForumPostBubble` (`lib/features/forums/presentation/screens/debate_room_screen.dart`,
`lib/features/forums/presentation/widgets/forum_post_bubble.dart`).

```
LAYOUT (current):
┌─────────────────────────────────────┐
│  ← Back                    [ⓘ] [⋯] │  ← ⓘ opens Forum Insight screen
│  Forum                              │
│  231 contributions                  │  ← exact post count, not an estimate
├─────────────────────────────────────┤
│  [ForumCard: topic + poll, pinned   │  ← scrolls away with the feed, same
│   at top of the list]               │    placement OpinionCard gets in
│                                     │    CommentThreadScreen
├─────────────────────────────────────┤
│                                     │
│  🟢 Single · 2h            ●FOR    │  ← someone else's post, left-aligned
│  I did it for 2 years and it        │
│  absolutely works with commitment   │
│  👍 34  Reply  ⋯                    │
│                                     │
│           ●AGAINST   Taken · 3h 🟠  │  ← YOUR post, right-aligned
│           Time zones will destroy   │
│           you no matter how strong  │
│           you are        👍 28  ⋯   │
│                                     │
│  [more posts ↓, single chrono list] │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐   │
│  │ Add to the FOR argument...  │   │
│  └─────────────────────────────┘   │
│                           [Post]   │
└─────────────────────────────────────┘

Layout rules (current — replaces the two-column design):
- ONE chronological feed, not two columns. Every post — FOR and AGAINST —
  appears in the single order it was written, newest at the bottom, exactly
  like a group chat thread.
- ALIGNMENT is authorship, not side: `post.isMine` puts a bubble on the
  right, everyone else's on the left. This mirrors the 1:1 chat
  `MessageBubble` convention exactly.
- SIDE (FOR/AGAINST) no longer determines column or alignment. It shows as:
  - A small badge dot on every bubble (`colorScheme.primary` for FOR,
    `colorScheme.against` for AGAINST).
  - The bubble fill color, but ONLY for your own posts (`colorScheme.primary`
    if mine, neutral `colorScheme.onBackground` otherwise) — this is
    authorship-only tinting, not a second side signal; see the code comment
    on `ForumPostBubble.bubbleColor` for the reasoning (alignment already
    says "mine," so tinting the fill by side too would be redundant).
- Because alignment is authorship, your own AGAINST post can sit on the
  right, directly beside someone else's AGAINST post on the left — this is
  the visual outcome of resolving cross-side replies as YES.
- Replies stay inline in the main feed at their own chronological position
  (never pulled out) — a real group chat doesn't hide a message just
  because it was a reply. A stacked-avatar "N replies" row under a post
  that has replies opens them in a bottom sheet as a shortcut, but the
  canonical location of every reply is always its own position in the flat
  feed.
- Tapping a reply's quoted-text preview scrolls the main feed to its parent
  post and briefly highlights it (WhatsApp-style "jump to replied
  message"), rather than expanding anything in place.
- Single scroll surface (not two independent columns). Sending a post, or
  a reply, while scrolled up in history scrolls back to the bottom to show
  what was just sent — same as WhatsApp/iMessage.
- Composer only visible if user picked a side (unchanged from original).
  Composer border/send-button color match the viewer's own side.
- Browse-only users see the full feed, no composer shown (unchanged).
- Swipe gestures: swipe past a threshold on a bubble fires Reply directly
  (non-destructive, safe to fire on release); swipe-then-tap on your own
  post's revealed pane opens Delete with a confirmation dialog; swipe-
  then-tap on someone else's opens Report.

Reactions inside forum:
- 👍 like only (no dislike inside forums) — unchanged.
  Reason: sides are already defined, dislikes would confuse the debate

Reply mechanic:
- Tap Reply, or swipe past threshold → quotes first 60 chars of post
  inline as prefix, same mechanic as originally specified.
- Quote prefix is stored as reply_to_post_id on the post — unchanged.
- Cross-side replies ARE allowed (see Owner decision above) — a FOR post
  can reply to an AGAINST post and vice versa. This is what makes it a real
  debate rather than two parallel monologues.

Post rules:
- Max 5000 characters (see "Content length" under Section 7 — raised from
  the original 280 across opinions, comments, and forum posts).
- Text only
- relationship_status_at_post captured at insert time
- Side locked — you can only post on your chosen side (unchanged)
- Deletable by the owner at any time (no time window, unlike the 15-minute
  edit window) — soft-delete via `removed_at`, decrementing the topic's
  `total_posts`/`for_posts`/`against_posts` counters. This is a newly added
  capability — the original spec had no delete path for forum posts at all.
```

### 5.7 Forum lifecycle

```
ACTIVE   → forum has had a post within the last 7 days
           shown at top of Explore tab

QUIET    → no posts for 7 days
           moved to "Quiet forums" section in Explore
           still accessible, just deprioritised
           notification sent to contributors:
           "This forum has gone quiet. Keep the debate going →"
           (sent once, not repeated)

ARCHIVED → no posts for 30 days
           read-only, no new posts allowed
           shown in Explore → Archived section
           Final counts frozen: "FINAL: FOR 142 · AGAINST 89"

REOPEN   → future feature (Section 13 open questions)
           Not built in this implementation
```

---

## 6. FORUM INSIGHT SCREEN

Accessed by tapping the ⓘ icon inside any active forum.

```
┌─────────────────────────────────────┐
│  ← Back         Forum insights      │
├─────────────────────────────────────┤
│  "Long distance relationships       │
│   never really work"                │
├─────────────────────────────────────┤
│                                     │
│  Started                            │
│  June 3, 2026 · 8 days ago          │
│                                     │
│  Contributors                       │
│  231 total · 142 FOR · 89 AGAINST   │
│                                     │
│  Total posts                        │
│  486 posts · 312 FOR · 174 AGAINST  │
│                                     │
│  Engagement                         │
│  2,341 likes on FOR posts           │
│  1,876 likes on AGAINST posts       │
│                                     │
│  Activity trend                     │
│  ████████░░  Most active Day 2      │
│  Last post: 12 minutes ago          │
│                                     │
│  Most active periods                │
│  Evenings (6pm–10pm)                │
│                                     │
├─────────────────────────────────────┤
│  No winner is declared.             │
│  This is a living debate.           │
└─────────────────────────────────────┘

Data shown:
- Forum start date + days since
- Total contributors split by side
- Total posts split by side
- Total likes split by side
- Simple activity bar showing peak activity day
- Last post timestamp
- Most active time of day (if enough data)

Data NOT shown:
- Individual user stats (no "top posters")
- Any information that could identify a contributor
- A "winning side" declaration — never
```

---

## 7. SHARED RULES

### Content rules (both features)

```
ALLOWED:
✓ Personal experiences (no real names, no identifying details)
✓ Questions about relationships, dating, communication, emotions
✓ Opinions about relationship dynamics and patterns
✓ Sharing what worked or did not work
✓ Cultural perspectives on relationships
✓ Disagreement and debate

NOT ALLOWED:
✗ Real names of identifiable people
✗ Specific identifying details about a partner or ex
✗ Explicit sexual content
✗ Hate speech, discrimination, slurs of any kind
✗ Contact information (phone numbers, handles, emails)
✗ Content encouraging self-harm or harm to others
✗ Spam or repetitive posting
✗ Anything that could identify a real person without consent
```

### Polls (both features)

A poll is an optional attachment on an opinion or a forum topic. It never
replaces the post body — the post stands on its own and the poll hangs off it.

```
SHAPE:
- 2-4 options per poll
- Each option is plain text, 1-60 characters
- Options are FIXED at creation — no adding, editing, reordering, or
  deleting after the post exists
- One poll per post, maximum
- Polls do not expire; they stay open while the post is visible

VOTING:
- Phone-verified users only (anonymous users cannot vote — Section 3)
- One vote per user per poll, enforced by UNIQUE (poll_id, user_id)
- A voter CAN change their vote — this moves the count, never adds one
- A voter CAN retract their vote, returning to the pre-vote state
- A user CAN vote on their own poll (unlike opinion reactions, where
  reacting to your own post is blocked) — a poll is a question its
  author is also entitled to answer

RESULTS:
- Hidden until you vote, then revealed
- Retracting your vote re-hides them
- Aggregate per-option counts only — who voted for what is never
  queryable by any client

CONTENT RULES:
- Option text passes the same keyword filter as post bodies
- The content rules above apply to option text in full
```

**Polls are NOT topic voting.** Both exist on the forum surface and answer
different questions:

| | Topic voting (`topic_votes`) | Poll (`post_polls`) |
|---|---|---|
| Question | Should this topic become a live debate room? | What do readers think about this topic's question? |
| Shape | Up / down | 2-4 options |
| Effect | Gates activation (>50% of seen) | Gates nothing |
| Expiry | `voting_expires_at` (14 days) | Never |

A topic can carry both: people vote it into existence, and separately answer
the poll inside it.

### Reposts (opinions only)

A repost is a one-tap "share this as-is" action on an opinion. Scoped to
opinions only -- forum topics already have topic voting as their
re-circulation mechanic, so reposts would duplicate that rather than add
anything.

```
SHAPE:
- No added commentary -- purely a share action, not a quote-post.
  Nothing new to moderate: no free-text surface is created.
- A repost is a reference (a join row pointing at the original opinion),
  never a content copy. Likes, comments, and report counts always
  belong to the ONE original opinion.
- No self-repost -- blocked the same way self-reactions already are.
- No repost-of-a-repost -- a repost always targets the original opinion
  directly. There is no chain.
- Un-repost is available any time and never touches the original.

FEED VISIBILITY:
- A repost surfaces in Discover/Following like a normal feed entry,
  timestamped at REPOST time (not the original's created_at) -- this is
  what makes it re-circulate rather than just sit on a personal list.
- Attributed to the REPOSTER's own author_handle. The original author's
  identity is never exposed by a repost, and the link between the two
  handles is never client-queryable beyond "this opinion, reposted."

PARTICIPATION:
- Requires phone-verified auth, same gate as posting/replying/voting/
  saving/following. Anonymous (unverified) users cannot repost.

MODERATION:
- If the original opinion is removed, its reposts stop appearing in
  feeds (covered by the feed query's existing removed_at IS NULL
  filter) but repost rows are not deleted -- a removal does not need a
  separate repost cleanup pass.
```

### Quotes (opinions only)

A quote is "repost, plus your own opinion." Unlike a repost it is not a
lightweight reference -- it IS a full, independent opinion that also embeds a
reference to the opinion it quotes.

```
SHAPE:
- A quote goes through the SAME posting path as any opinion: 5000-char
  limit (raised from 280 by later owner decision, see Section 9), Layer 1
  keyword filter, the anti-spam limit/cooldown below,
  the ban gate. It has its own like/comment/report counts and its own
  feed placement. Quoting adds no new moderated surface -- the quote
  text is an opinion's text, moderated exactly like one.
- The reference to the quoted opinion is a pointer (its id), not a
  copy of its content -- resolved live at render time.
- Self-quote IS allowed (unlike self-repost, which is blocked) --
  quoting your own opinion to add a follow-up thought is a distinct,
  legitimate action, not a no-op share of yourself.
- No quote-of-a-quote -- a quote always references an ORIGINAL
  opinion. Quoting a quote re-targets the original underneath, same
  rule as repost-of-a-repost. One hop, no chain.
- Because a quote IS an opinion, it can itself be reposted, quoted,
  replied to, reacted to, saved and reported like any opinion.

FEED VISIBILITY:
- Appears in Discover/Following like any new opinion -- own
  created_at, no special-casing, because it is a normal opinion row.
- Attributed to the QUOTER's own author_handle. The embedded original
  is attributed to its own (different) author_handle -- the two
  handles are never shown as linked to each other beyond "this
  opinion quotes that one."

REMOVED ORIGINAL:
- If the quoted opinion is later removed or deleted, the quote is NOT
  removed -- the quoter's own text and engagement stay untouched. The
  embedded original renders "This opinion is no longer available"
  instead of the vanished content.

PARTICIPATION:
- Requires phone-verified auth, same gate as posting -- a quote is a
  post.

MODERATION:
- The quote's own text is reportable/removable exactly like any
  opinion, independent of the quoted opinion's state.
```

### Editing (opinions, comments, forum posts)

```
- 15-minute window from created_at, identical across all three content
  types -- one number, one rule.
- Same validation as posting: 5000-char limit (owner decision, raised from
  280 -- see Section 9), Layer 1 keyword filter. Editing cannot bypass
  moderation that posting would have caught.
- Shows "(edited)" to readers. No edit history exposed.
- Purely time-based -- existing reports / report_count /
  hidden_pending_review do not block editing and are not reset by it.
- After the window closes, content is permanently fixed, same as today.
- Editing never changes created_at, never re-triggers notifications,
  never changes feed ranking/ordering.
```

### Mute / hide (opinions)

```
- HIDE is per-post: dismisses one specific opinion from the caller's
  own feeds. No effect on counts, no notification to the author, no
  effect on any other viewer.
- MUTE is per-author, keyed on author_handle (never user_id) -- stops
  surfacing that author's future posts, AND retroactively hides their
  existing posts too (otherwise muting would do nothing about the
  content that prompted it). Silent: the muted author is never told,
  same as follows already being silent.
- Both are feed-level filters only -- they change nothing about the
  underlying opinion for anyone else.
- Hiding a post from someone you have not muted, and muting someone
  whose posts you have not separately hidden, are independent actions.
- Requires phone-verified auth, same gate as follow/save/repost.
```

### Tags (opinions and forum topics)

A fixed, app-defined chip vocabulary, separate from the four broad forum
categories (Attachment, Conflict, Date ideas, General) -- categories are
coarse sections, tags are narrower topical chips, closer to how a tag
appears on a social post than a section header.

```
VOCABULARY (v1, app-controlled, not user-editable):
  relationship, dating, marriage, situationship, breakup,
  love, healing, trust, jealousy, communication,
  sex, attraction, love language,
  date, long distance, red flags, boundaries,
  vals day, anniversary,
  attachment, self-love

WHY FIXED, NOT FREEFORM:
- A user-invented tag is a fingerprint -- trackable across posts in a
  way free text is not. A fixed, app-chosen vocabulary has none of this
  risk and needs no moderation surface, since every string exists
  before anyone posts one.

SHAPE:
- Up to 3 tags per opinion or forum topic, chosen at compose time from
  the fixed list. Optional -- an untagged post is a normal post.
- Set at creation, not independently editable after posting. No retag
  action in v1.

BROWSING:
- Tapping a tag chip opens a filtered feed: every opinion/topic
  carrying that tag, most recent first, same anonymized shape as every
  other feed (author_handle only, never real identity).
- Tags are also directly searchable/browsable from the fixed
  vocabulary (not a freeform search box).
- A tag filter can NEVER be combined with an author filter -- "everyone
  who used this tag," never "this author's tagged posts." Combining
  the two would let someone narrow in on one person by topic, exactly
  what fixed tags exist to prevent.

PARTICIPATION:
- Browsing tag results follows the same anonymous-browsing rules as
  everything else. Attaching a tag when posting requires phone-verified
  auth, since tagging is part of posting.
```

### Posting limits (anti-spam)

```
Opinions:
- 5 opinion posts per user per 24 hours
- 20 comments per user per 24 hours
- 60 second cooldown between opinion posts

Forums:
- 10 forum posts per user per forum per 24 hours
- 30 second cooldown between forum posts
- User can be active in multiple forums simultaneously
  (limit is per-forum, not total)

Topic submission:
- 3 topic submissions per user per 7 days
- Cannot resubmit an expired topic for 30 days

Enforce at:
- Edge function level (server-side) — primary enforcement
- Client-side — disable the post button with countdown timer shown
```

---

## 8. MODERATION SYSTEM

### Report flow

```
[⋯] on any post, comment, or topic → [Report]

Reason options:
○ Identifies a real person
○ Harmful or dangerous content
○ Explicit sexual content
○ Hate speech or discrimination
○ Spam
○ Other

After report: "Thank you. We will review this within 24 hours."

Post is NOT hidden on single report.
Post is hidden when report_count reaches 10 (auto-hide).
Hidden posts show as "Post under review" placeholder.
```

### Auto-hide threshold

```
When report_count >= 10 on any content:
SET hidden_pending_review = true
Content shows as "Post under review"
Post is still in database, not deleted
Human review required to either:
  - Confirm removal (set removed_at = now())
  - Clear report and restore (set hidden_pending_review = false,
    report_count = 0)
```

### Posting bans

```
Three confirmed violations → 7-day posting ban
Ban stored on user record (NOT on forum identity)
Ban enforcement: edge function rejects inserts from banned users
Banned users CAN still read — they cannot post

Ban check SQL (add to all insert edge functions):
SELECT banned_until FROM profiles WHERE id = auth.uid();
IF banned_until > now() THEN REJECT;
```

### Priority reports (2-hour review SLA)

```
Trigger priority review automatically when content contains:
- Any terms from the safety trigger list in ATTUNE_MASTER_SPEC.md
- Explicit identification of a real person (name detection)
- Self-harm language

Priority flag: forum_reports.priority = true
Admin dashboard (or Supabase direct) shows priority queue separately.
```

---

## 9. DATABASE SCHEMA

```sql
-- No forum_identities table in v2.
-- Posts link directly to user_id from auth.
-- relationship_status_at_post is denormalised from profiles
-- at insert time for display performance.
--
-- Owner decision: the 280-char cap below on opinions/opinion_comments/
-- forum_posts was raised to 5000 (migration
-- 20260807120000_raise_content_length_to_5000.sql), across the table
-- CHECK constraints and every posting/editing RPC. 280 read as a "tweet"
-- limit that fought the actual use case -- these are often reflective,
-- multi-paragraph posts about a relationship, not one-liners. This schema
-- block is left showing 280 for historical/diff clarity against the
-- original spec; treat 5000 as the current live limit everywhere content
-- length is checked.

-- Opinions
CREATE TABLE opinions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  content text NOT NULL CHECK (char_length(content) <= 280),  -- see note above: live limit is 5000
  relationship_status_at_post text CHECK (
    relationship_status_at_post IN (
      'single', 'taken', 'figuring_it_out', 'open'
    )
  ),
  -- NULL for a normal opinion. Set for a quote -- a quote IS an opinion
  -- (own content, own counts, own posting-path validation), this column
  -- is only the pointer to what it quotes. Self-referencing FK, always
  -- points at an ORIGINAL opinion: quote-of-a-quote re-targets the
  -- original at insert time, so this can never chain.
  quoted_opinion_id uuid REFERENCES opinions,
  like_count int DEFAULT 0,
  dislike_count int DEFAULT 0,
  comment_count int DEFAULT 0,
  repost_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  -- NULL until edited. Editing sets this to now() and never resets
  -- report_count/hidden_pending_review -- the edit window is purely
  -- time-based (created_at + 15 minutes), moderation state is untouched.
  edited_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Opinion reactions
CREATE TABLE opinion_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  reaction_type text CHECK (reaction_type IN ('like', 'dislike')) NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (opinion_id, user_id)
);

-- Opinion comments
CREATE TABLE opinion_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  content text NOT NULL CHECK (char_length(content) <= 280),  -- see note above: live limit is 5000
  relationship_status_at_post text,
  quoted_text text,                        -- first 60 chars of replied-to post
  reply_to_comment_id uuid REFERENCES opinion_comments,
  like_count int DEFAULT 0,
  dislike_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  edited_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Anonymous follows (user_id to user_id, no usernames)
CREATE TABLE opinion_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid REFERENCES auth.users NOT NULL,
  following_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (follower_id, following_id)
);

-- Saved opinions (bookmarks). Mirrors opinion_follows' shape.
CREATE TABLE opinion_saves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  opinion_id uuid REFERENCES opinions NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

-- Reposts. A reference row, never a content copy -- likes/comments/reports
-- always belong to the one original opinion. No self-repost (user_id !=
-- opinions.user_id, enforced in the RPC). No repost-of-a-repost: opinion_id
-- always points at an original opinion, there is no chain to resolve.
CREATE TABLE opinion_reposts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  opinion_id uuid REFERENCES opinions NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

-- Per-post hide. Feed-only filter, no effect on counts, no notification.
CREATE TABLE opinion_hides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  opinion_id uuid REFERENCES opinions NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

-- Per-author mute, keyed on the opaque author_handle (never user_id, per
-- FORUM.md §3) -- storing a real user_id here directly would defeat the
-- anonymity model the moment a mute list was ever queried. Retroactively
-- hides the muted author's existing posts too (see "Muting and hiding"
-- above), enforced at feed-query time by resolving the handle back to a
-- user_id server-side, same one-directional resolution follow already does.
CREATE TABLE opinion_mutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  muted_author_handle text NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, muted_author_handle)
);

-- Fixed, app-controlled tag vocabulary. NOT user-editable -- a user-invented
-- tag would be a fingerprint (see "Tags" above), so every row here is seeded
-- by a migration, never inserted by a client.
CREATE TABLE tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);

-- Two join tables rather than one polymorphic (post_type, post_id) table --
-- keeps each FK a real REFERENCES constraint instead of an unenforced
-- discriminator column, matching how post_polls uses two nullable FKs rather
-- than a generic content-type system.
CREATE TABLE opinion_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions NOT NULL,
  tag_id uuid REFERENCES tags NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (opinion_id, tag_id)
);

CREATE TABLE forum_topic_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics NOT NULL,
  tag_id uuid REFERENCES tags NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (topic_id, tag_id)
);

-- Forum topics
CREATE TABLE forum_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submitted_by uuid REFERENCES auth.users NOT NULL,
  relationship_status_at_submit text,
  content text NOT NULL CHECK (char_length(content) <= 120),
  status text CHECK (status IN (
    'voting', 'active', 'quiet', 'archived', 'expired'
  )) DEFAULT 'voting',
  upvote_count int DEFAULT 1,              -- starts at 1 (submitter)
  downvote_count int DEFAULT 0,
  seen_count int DEFAULT 1,               -- starts at 1 (submitter)
  total_posts int DEFAULT 0,
  for_posts int DEFAULT 0,
  against_posts int DEFAULT 0,
  last_post_at timestamptz,
  activated_at timestamptz,
  voting_expires_at timestamptz
    DEFAULT (now() + interval '14 days'),
  created_at timestamptz DEFAULT now()
);

-- Topic votes
CREATE TABLE topic_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  vote_type text CHECK (vote_type IN ('up', 'down')) NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

-- Topic impressions (for seen_count)
CREATE TABLE topic_impressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  seen_at timestamptz DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

-- Forum posts (inside debate rooms)
CREATE TABLE forum_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  side text CHECK (side IN ('for', 'against')) NOT NULL,
  -- browse-only users have no posts so no 'browse' value needed
  content text NOT NULL CHECK (char_length(content) <= 280),  -- see note above: live limit is 5000
  relationship_status_at_post text,
  reply_to_post_id uuid REFERENCES forum_posts,
  quoted_text text,                        -- first 60 chars of quoted post
  like_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  edited_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Forum post likes
CREATE TABLE forum_post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  forum_post_id uuid REFERENCES forum_posts NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (forum_post_id, user_id)
);

-- Moderation reports
CREATE TABLE forum_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reported_by uuid REFERENCES auth.users NOT NULL,
  opinion_id uuid REFERENCES opinions,
  comment_id uuid REFERENCES opinion_comments,
  forum_post_id uuid REFERENCES forum_posts,
  topic_id uuid REFERENCES forum_topics,
  reason text NOT NULL,
  priority boolean DEFAULT false,
  status text CHECK (status IN (
    'pending', 'reviewed_removed', 'reviewed_kept', 'escalated'
  )) DEFAULT 'pending',
  reviewed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Follower counts view (for anonymous profile page)
CREATE VIEW opinion_follower_counts AS
SELECT
  following_id AS user_id,
  COUNT(*) AS follower_count
FROM opinion_follows
GROUP BY following_id;
```

### RLS Policies

```sql
-- Opinions: readable by all authenticated users
CREATE POLICY "opinions_public_read"
ON opinions FOR SELECT
USING (
  auth.uid() IS NOT NULL
  AND removed_at IS NULL
  AND hidden_pending_review = false
);

-- Opinions: user_id NEVER exposed in SELECT responses
-- Enforce via a view that strips user_id:
CREATE VIEW public_opinions AS
SELECT
  id, content, relationship_status_at_post,
  like_count, dislike_count, comment_count,
  report_count, created_at
  -- user_id intentionally excluded
FROM opinions
WHERE removed_at IS NULL AND hidden_pending_review = false;

-- Opinions: writable by authenticated users only
CREATE POLICY "opinions_authenticated_insert"
ON opinions FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Opinions: deletable by owner only
CREATE POLICY "opinions_owner_delete"
ON opinions FOR DELETE
USING (auth.uid() = user_id);

-- Opinion reactions: one per user, cannot react to own post
-- Enforced by UNIQUE constraint + application logic

-- Opinion follows: readable and writable by follower
CREATE POLICY "follows_owner"
ON opinion_follows FOR ALL
USING (auth.uid() = follower_id);

-- Forum topics: readable by all authenticated users
CREATE POLICY "topics_public_read"
ON forum_topics FOR SELECT
USING (auth.uid() IS NOT NULL);

-- Forum topics: submitted_by never exposed
-- Use a view:
CREATE VIEW public_forum_topics AS
SELECT
  id, content, relationship_status_at_submit, status,
  upvote_count, downvote_count, seen_count,
  total_posts, for_posts, against_posts,
  last_post_at, activated_at, voting_expires_at, created_at
  -- submitted_by intentionally excluded
FROM forum_topics;

-- Forum posts: readable by all authenticated users
CREATE VIEW public_forum_posts AS
SELECT
  id, topic_id, side, content, relationship_status_at_post,
  reply_to_post_id, quoted_text, like_count, created_at
  -- user_id intentionally excluded
FROM forum_posts
WHERE removed_at IS NULL AND hidden_pending_review = false;

-- Reports: insert-only for authenticated users
CREATE POLICY "reports_insert_only"
ON forum_reports FOR INSERT
WITH CHECK (auth.uid() = reported_by);

-- Reports: no SELECT for regular users (admin only)
CREATE POLICY "reports_no_read"
ON forum_reports FOR SELECT
USING (false);
-- Admin access via Supabase service role only
```

---

## 10. NOTIFICATION SYSTEM

OneSignal is already configured. All notifications use
existing OneSignal integration.

```
OPINION NOTIFICATIONS:

1. Someone likes your opinion
   Title: "New like"
   Body: "Someone liked your opinion"
   Grouping: after 5 likes in 1 hour →
             "5 people liked your opinion"
   Triggered: on INSERT to opinion_reactions WHERE reaction_type='like'
   Send to: opinion.user_id

2. Someone comments on your opinion
   Title: "New comment"
   Body: first 60 chars of comment + "..."
   Triggered: on INSERT to opinion_comments
   Send to: opinion.user_id (not to commenter themselves)

3. Someone replies to your comment
   Title: "New reply"
   Body: first 60 chars of reply
   Triggered: on INSERT where reply_to_comment_id IS NOT NULL
   Send to: parent comment's user_id

9. Someone reposts your opinion
   Title: "New repost"
   Body: "Someone reposted your opinion"
   Triggered: on INSERT to opinion_reposts
   Send to: opinion.user_id (not to reposter themselves)

10. Someone quotes your opinion
    Title: "New quote"
    Body: "Someone quoted your opinion"
    Triggered: on INSERT to opinions WHERE quoted_opinion_id IS NOT NULL
    Send to: quoted_opinion.user_id (not on self-quote)

FORUM NOTIFICATIONS:

4. Topic activated (to voters only)
   FOR voters:
   Title: "Your topic is live"
   Body: "'[first 50 chars]...' is now a debate. You're FOR →"

   AGAINST voters:
   Title: "Your topic is live"
   Body: "'[first 50 chars]...' is now a debate. You're AGAINST →"

   Triggered: when cron sets topic.status = 'active'
   Send to: all user_ids in topic_votes for this topic_id

5. New activity in forums you contribute to
   Title: "[Topic short title]"
   Body: "3 new posts in the debate"
   Triggered: when forum_posts count for a topic increases by 3
              since the user's last visit
   Send to: users who have posted in that forum
   Rate limit: maximum once per 2 hours per forum per user

6. Forum going quiet
   Title: "Debate going quiet"
   Body: "'[topic]' has gone quiet. Keep it going →"
   Triggered: when status changes to 'quiet'
   Send to: users who posted in this forum
   Sent once only, not repeated

MODERATION NOTIFICATIONS:

7. Post removed
   Title: "Post removed"
   Body: "One of your posts was removed for violating guidelines."
   Send to: real user account (user_id, not anonymous)

8. Posting ban applied
   Title: "Posting paused"
   Body: "Your posting access is paused for 7 days."
   Send to: real user account

NEVER NOTIFIED:
- When someone follows you (follows are silent)
- When someone dislikes your opinion
- Activity in forums you only browsed (not contributed to)
- When your topic expires without activating
```

---

## 11. BUILD ORDER

Build in this exact order. Do not advance until each step is
working and tested end-to-end.

```
PHASE 1 — DATA LAYER
Step 1:  Run all migrations from Section 9
         Create all tables, views, RLS policies, indexes
         Test: verify RLS blocks user_id exposure in all public views
Step 2:  Add ban enforcement to profiles table
         ADD COLUMN banned_until timestamptz to profiles if not exists
         Test: banned user insert is rejected

PHASE 2 — OPINIONS FEED
Step 3:  Post compose screen
         280-char limit, character counter, confirmation dialog
         relationship_status captured from profiles at insert
Step 4:  Opinion card component (reusable widget)
         Blank name field (not rendered), status, time, content,
         like/dislike/comment counts, follow button, menu
Step 5:  Discover feed screen
         Query public_opinions view, ordering logic implemented
Step 6:  Like / dislike interaction
         Toggle logic, mutual exclusion, cannot react to own posts
         Optimistic UI update + server confirmation
Step 7:  Comment thread screen
         Flat comments, quote-reply mechanic, like/dislike on comments

PHASE 3 — OPINIONS SOCIAL
Step 8:  opinion_follows table operations
         Follow/unfollow edge functions
Step 9:  Follow/unfollow button on opinion card
Step 10: Following feed screen
         Query public_opinions filtered to followed user_ids
Step 11: Anonymous profile page
         Status, follow button, follower count, their opinions list

PHASE 4 — TOPIC VOTING
Step 12: Topic submission screen
         120-char limit, auto-upvote, auto-impression for submitter
Step 13: Topic voting card component
         Up/down vote buttons, counts, progress bar to 50%
Step 14: Impression tracking
         2-second visibility trigger → INSERT topic_impressions
         ON CONFLICT DO NOTHING
Step 15: Voting pool display in Explore tab
         "Topics waiting for votes" section
Step 16: Activation cron job
         Runs hourly
         Condition: upvote_count / seen_count > 0.50
                    AND seen_count >= 20
         Action: UPDATE status = 'active', SET activated_at = now()
         Then: fire activation notifications via OneSignal

PHASE 5 — FORUM DEBATE ROOM
Step 17: Side selection screen
         FOR / AGAINST / Browse only
         Store user's side in topic_votes or new user_forum_sides table
         (See note below)
Step 18: Two-column debate room layout
         Left FOR, right AGAINST, independent scroll
         Newest at bottom, pull to refresh
Step 19: Post composer (side-locked)
         Only shown if user picked a side
         Composer placeholder text reflects their side
Step 20: Forum post card component
         FOR left-aligned in left column
         AGAINST right-aligned in right column
Step 21: Reply mechanic
         Tap reply → quote first 60 chars → composer prefilled
         reply_to_post_id stored on insert
Step 22: Forum lifecycle cron jobs
         Every hour: check last_post_at
         7 days no posts → status = 'quiet'
         30 days no posts → status = 'archived'
         On quiet: fire going-quiet notifications

PHASE 6 — FORUM INSIGHT SCREEN
Step 23: Forum insight screen
         All stats from forum_topics row
         Activity trend (simple bar from daily post counts)
         Accessible via ⓘ icon in forum header

PHASE 7 — NAVIGATION WIRING
Step 24: Wire Opinions sub-tabs (Opinions feed | Forums)
Step 25: Wire Forums sub-tabs (Contributing | Explore)
Step 26: Contributing tab query
         Forums where user has a topic_vote or forum_post
Step 27: Default tab logic by user mode
         Single/personal → Opinions; Couples → Chat

PHASE 8 — MODERATION
Step 28: Report flow (all content types from ⋯ menu)
Step 29: Auto-hide trigger at 10 reports
Step 30: Posting limits + cooldown enforcement (edge function)
Step 31: Ban enforcement (check banned_until on all inserts)

PHASE 9 — NOTIFICATIONS
Step 32: Like notifications with grouping (5 in 1hr = single grouped)
Step 33: Comment and reply notifications
Step 34: Forum activation notifications (FOR/AGAINST personalised)
Step 35: Forum activity notifications (3 new posts, 2hr rate limit)
Step 36: Forum quiet notifications (sent once only)
Step 37: Moderation notifications (removal + ban)
```

**Note on Step 17 — storing user's forum side:**

For users who did not vote (they pick side on entry), their side
needs to be stored. Options:

Option A: Insert a synthetic topic_vote record when they pick a side
on entry (even though they did not vote in the voting pool).
Simple, one table.

Option B: Create a separate user_forum_sides table:
```sql
CREATE TABLE user_forum_sides (
  user_id uuid REFERENCES auth.users,
  topic_id uuid REFERENCES forum_topics,
  side text CHECK (side IN ('for', 'against', 'browse')),
  PRIMARY KEY (user_id, topic_id)
);
```

**Recommendation: Option B.** Keeps voting data clean.
A vote in topic_votes means "I voted to activate this topic."
A side in user_forum_sides means "I am participating on this side."
These are different actions and should be different tables.

---

## 12. INFRASTRUCTURE CONFIRMATION

```
✓ Supabase project configured
✓ profiles table exists with:
  - id (user_id)
  - relationship_status column (values: single/taken/
    figuring_it_out/open)
✓ OneSignal push notifications configured
✓ Navigation top bar (Opinions | Chat) already built
✓ User authentication working

NEEDS CONFIRMATION BEFORE PHASE 1:
□ Does profiles table have banned_until column?
  If not: add it in Step 2 migration.
□ What is the exact relationship_status column name
  and its possible values in the existing profiles table?
  (Confirm they match: single/taken/figuring_it_out/open)
□ Is there an existing edge functions setup?
  (For posting limits and ban enforcement in Phase 8)
□ Share the OneSignal config reference for Phase 9.
```

---

## 13. OPEN QUESTIONS

```
[RESOLVED] Cross-side replies in forum debate room
  Question: Can a FOR user reply directly to an AGAINST post?
  Decision: Option B — YES. The debate room was restructured from two
  independent-scrolling columns into a single chronological group-chat
  feed (alignment = authorship via `post.isMine`, not side) specifically
  to make cross-side replies possible. Full design recorded in
  Section 5.6 above.

[OPEN] Discover feed algorithm tuning
  Current ordering is rule-based (same status first, then
  engagement × recency). May need adjustment after first
  4 weeks of usage data.

[OPEN] Posting limits tuning
  5 opinions/day and 10 forum posts/day are starting estimates.
  Adjust after seeing real usage patterns.

[OPEN] City display
  Future feature. Not in this spec.
  When built: settings toggle in Profile tab, pulls from
  profile location, shown after relationship_status on posts.

[OPEN] Forum reopen mechanic for archived forums
  Not built in this implementation.
  Future: "Request reopen" button on archived forums,
  requires 5 user requests to trigger admin review.

[OPEN] Admin moderation dashboard
  For v1 launch: moderation queue reviewed directly via
  Supabase dashboard (service role access).
  Build a proper admin UI in a future sprint.
```

---

*This spec is complete and ready for DeepSeek implementation.*
*Build in the order defined in Section 11.*
*Review against ATTUNE_SOUL.md before shipping.*
*The user_id is never exposed in any client-facing API response.*
*Last reviewed: June 2026*




<!-- 
-- ============================================================
-- ATTUNE FORUM FEATURE V2 – PHASE 1 MIGRATION (CORRECTED)
-- Creates profiles table first, then forum tables
-- Run in Supabase SQL editor
-- ============================================================

-- ============================================================
-- PART 0: Create profiles table (if not exists)
-- ============================================================

CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  avatar_url text,
  relationship_status text DEFAULT 'single' CHECK (
    relationship_status IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  banned_until timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- RLS: users can read any profile (for follower counts, status display)
CREATE POLICY "profiles_readable_all" ON profiles
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- RLS: users can update their own profile
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- RLS: insert only during signup (service role or trigger)
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Auto-create profile on user signup (Supabase Auth trigger)
-- This function runs when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, relationship_status)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)), 'single');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists, then recreate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- PART 1: Forum tables
--
-- NOTE: this block predates repost_count/quoted_opinion_id/edited_at (added
-- to the canonical schema earlier in this document) and has not been kept in
-- lockstep with it. Treat the first schema block in this document, and the
-- actual applied supabase/migrations/*.sql files, as authoritative over this
-- one for current columns -- this block is retained for its RLS/grant/index
-- shape, not as a live column reference.
-- ============================================================

-- Opinions
CREATE TABLE IF NOT EXISTS opinions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text CHECK (
    relationship_status_at_post IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  like_count int DEFAULT 0,
  dislike_count int DEFAULT 0,
  comment_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Opinion reactions (likes/dislikes)
CREATE TABLE IF NOT EXISTS opinion_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  reaction_type text CHECK (reaction_type IN ('like', 'dislike')) NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (opinion_id, user_id)
);

-- Opinion comments
CREATE TABLE IF NOT EXISTS opinion_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text,
  quoted_text text,
  reply_to_comment_id uuid REFERENCES opinion_comments ON DELETE SET NULL,
  like_count int DEFAULT 0,
  dislike_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Anonymous follows
CREATE TABLE IF NOT EXISTS opinion_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid REFERENCES auth.users NOT NULL,
  following_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (follower_id, following_id)
);

-- Forum topics
CREATE TABLE IF NOT EXISTS forum_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submitted_by uuid REFERENCES auth.users NOT NULL,
  relationship_status_at_submit text,
  content text NOT NULL CHECK (char_length(content) <= 120),
  status text CHECK (status IN ('voting', 'active', 'quiet', 'archived', 'expired')) DEFAULT 'voting',
  upvote_count int DEFAULT 1,
  downvote_count int DEFAULT 0,
  seen_count int DEFAULT 1,
  total_posts int DEFAULT 0,
  for_posts int DEFAULT 0,
  against_posts int DEFAULT 0,
  last_post_at timestamptz,
  activated_at timestamptz,
  voting_expires_at timestamptz DEFAULT (now() + interval '14 days'),
  created_at timestamptz DEFAULT now()
);

-- Topic votes
CREATE TABLE IF NOT EXISTS topic_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  vote_type text CHECK (vote_type IN ('up', 'down')) NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

-- Topic impressions
CREATE TABLE IF NOT EXISTS topic_impressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  seen_at timestamptz DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

-- Forum posts
CREATE TABLE IF NOT EXISTS forum_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  side text CHECK (side IN ('for', 'against')) NOT NULL,
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text,
  reply_to_post_id uuid REFERENCES forum_posts ON DELETE SET NULL,
  quoted_text text,
  like_count int DEFAULT 0,
  report_count int DEFAULT 0,
  hidden_pending_review boolean DEFAULT false,
  removed_at timestamptz,
  edited_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Forum post likes
CREATE TABLE IF NOT EXISTS forum_post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  forum_post_id uuid REFERENCES forum_posts ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (forum_post_id, user_id)
);

-- User's chosen side for forums they joined after activation
CREATE TABLE IF NOT EXISTS user_forum_sides (
  user_id uuid REFERENCES auth.users NOT NULL,
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE NOT NULL,
  side text CHECK (side IN ('for', 'against', 'browse')) NOT NULL,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, topic_id)
);

-- Moderation reports
-- Polls (attached to an opinion OR a forum topic, never both)
-- Distinct from topic_votes: topic voting gates a topic into existence,
-- a poll asks that post's readers a question and gates nothing.
CREATE TABLE IF NOT EXISTS post_polls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES opinions ON DELETE CASCADE,
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE,
  created_by uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  -- exactly one parent
  CHECK (num_nonnulls(opinion_id, topic_id) = 1),
  -- one poll per post
  UNIQUE (opinion_id),
  UNIQUE (topic_id)
);

-- Poll options: plain text, fixed at creation, 2-4 per poll
CREATE TABLE IF NOT EXISTS poll_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id uuid REFERENCES post_polls ON DELETE CASCADE NOT NULL,
  option_position int NOT NULL CHECK (option_position BETWEEN 0 AND 3),
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
  vote_count int DEFAULT 0,
  UNIQUE (poll_id, option_position)
);

-- Poll votes. user_id exists for dedup enforcement ONLY and is never
-- exposed to clients -- see the RLS policies in Part 3.
CREATE TABLE IF NOT EXISTS poll_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id uuid REFERENCES post_polls ON DELETE CASCADE NOT NULL,
  option_id uuid REFERENCES poll_options ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (poll_id, user_id)
);

CREATE TABLE IF NOT EXISTS forum_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reported_by uuid REFERENCES auth.users NOT NULL,
  opinion_id uuid REFERENCES opinions ON DELETE CASCADE,
  comment_id uuid REFERENCES opinion_comments ON DELETE CASCADE,
  forum_post_id uuid REFERENCES forum_posts ON DELETE CASCADE,
  topic_id uuid REFERENCES forum_topics ON DELETE CASCADE,
  reason text NOT NULL,
  priority boolean DEFAULT false,
  status text CHECK (status IN ('pending', 'reviewed_removed', 'reviewed_kept', 'escalated')) DEFAULT 'pending',
  reviewed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- PART 2: Public views (user_id stripped)
-- ============================================================

CREATE OR REPLACE VIEW public_opinions AS
SELECT
  id, content, relationship_status_at_post,
  like_count, dislike_count, comment_count,
  created_at
FROM opinions
WHERE removed_at IS NULL AND hidden_pending_review = false;

CREATE OR REPLACE VIEW public_forum_topics AS
SELECT
  id, content, relationship_status_at_submit, status,
  upvote_count, downvote_count, seen_count,
  total_posts, for_posts, against_posts,
  last_post_at, activated_at, voting_expires_at, created_at
FROM forum_topics;

CREATE OR REPLACE VIEW public_forum_posts AS
SELECT
  id, topic_id, side, content, relationship_status_at_post,
  reply_to_post_id, quoted_text, like_count, created_at
FROM forum_posts
WHERE removed_at IS NULL AND hidden_pending_review = false;

CREATE OR REPLACE VIEW opinion_follower_counts AS
SELECT
  following_id AS user_id,
  COUNT(*) AS follower_count
FROM opinion_follows
GROUP BY following_id;

-- ============================================================
-- PART 3: RLS Policies
-- ============================================================

-- Grant SELECT on views to authenticated users
GRANT SELECT ON public_opinions TO authenticated;
GRANT SELECT ON public_forum_topics TO authenticated;
GRANT SELECT ON public_forum_posts TO authenticated;
GRANT SELECT ON opinion_follower_counts TO authenticated;

-- Insert policies
CREATE POLICY "opinions_insert_own" ON opinions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "opinion_reactions_insert_own" ON opinion_reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "opinion_comments_insert_own" ON opinion_comments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "opinion_follows_manage_own" ON opinion_follows
  FOR ALL USING (auth.uid() = follower_id);

CREATE POLICY "forum_topics_insert_own" ON forum_topics
  FOR INSERT WITH CHECK (auth.uid() = submitted_by);

CREATE POLICY "topic_votes_insert_own" ON topic_votes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "topic_impressions_insert_own" ON topic_impressions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "forum_posts_insert_own" ON forum_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "forum_post_likes_insert_own" ON forum_post_likes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_forum_sides_manage_own" ON user_forum_sides
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "forum_reports_insert_own" ON forum_reports
  FOR INSERT WITH CHECK (auth.uid() = reported_by);

-- Polls: anyone signed in reads the poll and its options (option rows carry
-- the aggregate vote_count, which is public by design).
CREATE POLICY "post_polls_select_all" ON post_polls
  FOR SELECT USING (true);

CREATE POLICY "poll_options_select_all" ON poll_options
  FOR SELECT USING (true);

-- A poll is created with its parent post, by that post's author.
CREATE POLICY "post_polls_insert_own" ON post_polls
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Options are immutable after creation: insert only, no UPDATE/DELETE policy.
-- Changing an option after votes land would misrepresent what people voted for.
CREATE POLICY "poll_options_insert_own" ON poll_options
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM post_polls p
      WHERE p.id = poll_id AND p.created_by = auth.uid()
    )
  );

CREATE POLICY "poll_options_no_user_update" ON poll_options
  FOR UPDATE USING (false);

-- CRITICAL: a voter may read ONLY their own vote row. Without the USING
-- clause scoped to auth.uid(), any client could read the whole table and
-- deanonymise every voter on the platform. Aggregate results reach clients
-- through poll_options.vote_count, never through this table.
CREATE POLICY "poll_votes_select_own" ON poll_votes
  FOR SELECT USING (auth.uid() = user_id);

-- One vote per user is enforced by UNIQUE (poll_id, user_id); a voter may
-- change their vote (UPDATE) or retract it entirely (DELETE).
CREATE POLICY "poll_votes_insert_own" ON poll_votes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "poll_votes_update_own" ON poll_votes
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "poll_votes_delete_own" ON poll_votes
  FOR DELETE USING (auth.uid() = user_id);

-- Delete own content
CREATE POLICY "opinions_delete_own" ON opinions
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "opinion_comments_delete_own" ON opinion_comments
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "forum_posts_delete_own" ON forum_posts
  FOR DELETE USING (auth.uid() = user_id);

-- No user updates to count columns (service role only)
CREATE POLICY "opinions_no_user_update" ON opinions
  FOR UPDATE USING (false);

CREATE POLICY "forum_posts_no_user_update" ON forum_posts
  FOR UPDATE USING (false);

-- Reports: no SELECT for regular users
CREATE POLICY "forum_reports_no_select" ON forum_reports
  FOR SELECT USING (false);

-- ============================================================
-- PART 4: Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_opinions_created_at ON opinions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_opinions_relationship_status ON opinions(relationship_status_at_post);
CREATE INDEX IF NOT EXISTS idx_opinion_reactions_opinion_id ON opinion_reactions(opinion_id);
CREATE INDEX IF NOT EXISTS idx_opinion_follows_follower ON opinion_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_opinion_follows_following ON opinion_follows(following_id);
CREATE INDEX IF NOT EXISTS idx_forum_topics_status ON forum_topics(status);
CREATE INDEX IF NOT EXISTS idx_forum_topics_last_post ON forum_topics(last_post_at DESC);
CREATE INDEX IF NOT EXISTS idx_topic_votes_topic ON topic_votes(topic_id);
CREATE INDEX IF NOT EXISTS idx_topic_impressions_topic ON topic_impressions(topic_id);
CREATE INDEX IF NOT EXISTS idx_forum_posts_topic_id ON forum_posts(topic_id);
CREATE INDEX IF NOT EXISTS idx_forum_posts_created_at ON forum_posts(created_at ASC);
CREATE INDEX IF NOT EXISTS idx_forum_post_likes_post_id ON forum_post_likes(forum_post_id);
CREATE INDEX IF NOT EXISTS idx_post_polls_opinion ON post_polls(opinion_id);
CREATE INDEX IF NOT EXISTS idx_post_polls_topic ON post_polls(topic_id);
CREATE INDEX IF NOT EXISTS idx_poll_options_poll ON poll_options(poll_id, option_position);
CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_user ON poll_votes(poll_id, user_id); -->
