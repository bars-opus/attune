# Chat robustness review (2026-10-18)

Goal: WhatsApp / iMessage-level chat (robust, fast, persistent, fluid)
before two-phone manual testing. Seven Fable reviewers (send, receive/sync,
cache, media, UI/actions, motion/sound/streaks/games-in-chat,
server/security/push) found the issues, and two Fable verifiers tried to
refute each one. None of the High findings was refuted.

**Where the system is solid:**
- Database security: no cross-couple read, no forging `sender_id`, no
  writable protected columns, every SECURITY DEFINER function pins its
  search_path, and anon has no access.
- Idempotent sends: unique `client_message_id`.
- Soft deletes reach the partner.
- Night pushes collapse into one at 08:00, by design (Spec 1b).

Severity means the effect on a person using the app. "Owner" marks a
step only the owner can do (Xcode, OneSignal dashboard).

## Wave 1: delivery, sync and push (must fix before manual testing)

| # | Issue | Sev | Root cause / evidence |
|---|---|---|---|
| 1 | Messages sent offline are never sent automatically when the connection returns; offline cold start drops the previous session's queue | Critical | Nothing flushes the outbox on connectivity, resume or reconnect; an offline `_init` throws before `flushOutbox` (chat_state.dart) |
| 2 | An offline send turns "Failed" after ~15–30 s | High | Offline attempts count toward the 5-attempt cap |
| 3 | An earlier queued message can sit at "Queued" forever | High | One retry timer; `flushOutbox` never re-arms items that aren't due yet |
| 4 | A message can get stuck on "sending" | High | An exception in the 23505 reconcile path escapes `_attemptSend` |
| 5 | New sends skip the queue, so order can differ between phones | Medium | Sends bypass the FIFO outbox |
| 6 | Messages deleted on the server stay on phones as ghosts (seen after the wipe) | High | Cache merge adds rows but never trims against the server |
| 7 | Edits, deletes, reactions and receipts on messages older than the newest 50 never reach the partner | High | Updates are only picked up for the first page |
| 8 | Unpin and un-react don't arrive live | Medium | Filtered realtime DELETEs are dropped under REPLICA IDENTITY DEFAULT (pins, reactions) |
| 9 | Each incoming message causes ~30 HTTP requests and several refetches; new messages wait behind ~5 unrelated requests; one exception aborts the gap fill | High | Realtime handler runs metadata first, unguarded and serially; refresh bump re-subscribes the inbox; message_count UPDATE echoes |
| 10 | Partner messages are marked Read while you're in a game or the media screen, and the push is suppressed | High | `deactivate()` doesn't fire on route push, so `_isViewActive` stays true |
| 11 | Restoring a draft shows "typing…" to the partner | Medium | Typing is sent on programmatic text set |
| 12 | Corrupt or locked local DB means the app never starts | High (rare) | Cache init isn't guarded in main() |
| 13 | iPhones can't receive pushes | High | No `aps-environment` entitlement, no background modes (Owner: enable the Push capability in Xcode) |
| 14 | Every chat push waits up to 60 s | High | Only the once-a-minute cron dispatches; nothing wakes the sender |
| 15 | Android 13+ never asks for notification permission | High (device) | Prompt is on an iOS-only branch |
| 16 | "Relationship Updates" off also kills message pushes | Medium | Wrong preference gate |
| 17 | The same push can be sent twice when a worker retries | Medium | No source key on the scheduled notification |
| 18 | A partner or ex can subscribe their phone to your pushes | High (security) | OneSignal targets a bare external_id with no Identity Verification (Owner: enable IV in the dashboard; app needs a JWT from an edge function) |
| 19 | The client can insert `is_system_notice=true`, forging app notices | Medium (security) | Insert grant with no guard |

## Wave 2: media

| # | Issue | Sev |
|---|---|---|
| 20 | Photos shrunk to ~500 px before the preparer (1600 never reached) | High |
| 21 | A voice note stops when its bubble scrolls off screen (player owned by the bubble) | High |
| 22 | One failed signed-URL load leaves an image broken for the whole session (non-autoDispose cache) | High |
| 23 | "Delete for everyone" never deletes the storage objects | High |
| 24 | Stale-lease recovery and expired-intent cleanup crons call `process-chat-media` instead of their SQL functions (migration 20260907120000) | Medium |
| 25 | Upload "stop" button does nothing; no progress, cancel or resume | Medium |
| 26 | Any StorageException (incl. 5xx) is treated as a permanent rejection | Medium |
| 27 | A permanent copy of every picked photo is left in Documents/shop_images | Medium |
| 28 | Voice and video are never cached locally | Medium |
| 29 | Strict MP4 brand allowlist | Low |

## Wave 3: chat screen

| # | Issue | Sev |
|---|---|---|
| 30 | "Go to message" (reply quote, pinned, starred, search, media) fails unless the message is already loaded | High |
| 31 | No "edited" label or history. Regression from f29007b6; the spec requires it | High |
| 32 | No scroll-to-bottom button, unread pill or "new messages" divider | Medium |
| 33 | Typing, staged-game and reply strips cover the newest message | Medium |
| 34 | Starred screen never refreshes | Medium |
| 35 | A paste over 10k characters silently destroys the draft | Medium |
| 36 | Delivery status only on the newest bubble; "delivered" only when the app is open | Medium |
| 37 | Links aren't tappable | Medium |
| 38 | Images decode at full size; dark wallpaper repaints every scroll frame; timestamp drag rebuilds every bubble | Medium |

## Wave 4: sounds and streaks

| # | Issue | Sev |
|---|---|---|
| 39 | Android: every chirp takes audio focus, so music pauses and doesn't resume | High |
| 40 | iOS: after a voice note, chirps ignore the silent switch and interrupt music | Medium |
| 41 | Streak: tapping or going back while it loads burns the only view | High |
| 42 | Failed streak upload keeps spinning "Sending…" under Failed/Retry | Medium |
| 43 | Partner's game move gives no feedback in chat (card jumps) | Medium |

Full evidence, file:line references and per-item fix designs:
[2026-10-18-chat-review/](2026-10-18-chat-review/) (reviewer reports 01–07,
verifier reports V1 and V2). Each wave is built
test-first, with a Fable review at the end.
