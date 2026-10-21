# 07 — Server side, security/privacy and push notifications (chat)

Source of truth used: the scratch DB `attune_spec3a` (pg_policies, pg_proc, pg_trigger, grants, cron.job, pg_publication_tables). It carries every chat migration up to `20261018160000_sync_fixes` (checked: `messages_pause_guard`, `relationship_one_open_chapter_guard`, `relationship_chat_open_for`, `mark_conversation_read` quiet-skip all present), so the definitions below are the real ones, not reconstructions.

## Summary

The database side is in good shape and close to best practice: RLS on `messages` is read-only for clients except a column-restricted INSERT with `sender_id = auth.uid()`, every mutation goes through a SECURITY DEFINER RPC that re-checks membership/ownership/time windows, every SECURITY DEFINER function pins `search_path`, `anon` has no reach into any chat table, and outbox work is idempotent and lease-based. I found no way for a user to read another couple's messages, forge `sender_id`, or edit protected columns. The push pipeline is where it falls short of WhatsApp/iMessage: (1) the iOS app is built without the `aps-environment` entitlement, so iOS push is most likely dead; (2) chat pushes are only ever sent by a once-a-minute cron, so a push lands 0–60 s after the message; (3) OneSignal targeting by bare `external_id` is only safe if Identity Verification is on in the dashboard; (4) a worker crash can strand a push forever because the stale-lease recovery function is never scheduled. Also expect: no app-icon badge, no per-chat grouping, and ~5 full refetch cycles per client per message from realtime churn. Note for the manual test: between 22:00 and 08:00 (recipient's local time, if `users.timezone` is known) chat pushes are deliberately collapsed into one neutral push at 08:00 (Spec 1b) — that is by design, not a bug.

## Findings

### H-1: iOS push cannot register — `aps-environment` entitlement is missing
- Severity: High (no push at all on iOS; core flow)
- Confidence: Likely (needs one device check; everything in the repo says it is absent)
- Evidence: `ios/Runner/Runner.entitlements` contains only `application-groups` and `associated-domains`; `ios/Runner.xcodeproj/project.pbxproj` points every Runner config at that file (`CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`, lines 776/1044/1070) and has no `SystemCapabilities`/push entry; `grep -rn aps-environment ios/` → nothing; `ios/Runner/Info.plist` has no `UIBackgroundModes`; no `OneSignalNotificationServiceExtension` target exists (Podfile targets: Runner, RunnerTests, Share Extension). `git status ios/` is clean, so there is no uncommitted local fix.
- Failure scenario: fresh install on an iPhone → OneSignal SDK calls `registerForRemoteNotifications`, iOS refuses with "no valid 'aps-environment' entitlement string found", no APNs token is ever obtained → partner sends a message while the app is backgrounded → nothing arrives on the lock screen, ever. Android is unaffected.
- WhatsApp/iMessage expectation: every message arrives as a push within seconds, app closed.
- Fix: in Xcode, Runner target → Signing & Capabilities → add **Push Notifications** (writes `<key>aps-environment</key><string>development</string>` into `Runner/Runner.entitlements`; release signing switches it to `production`) and **Background Modes → Remote notifications** (`UIBackgroundModes: [remote-notification]` in Info.plist). Commit both files. Optional but recommended for OneSignal: add the Notification Service Extension target (confirmed delivery, badge increments, rich media).

### H-2: Chat pushes wait for a once-a-minute cron — 0–60 s latency on every message
- Severity: High (core flow feels broken next to any messenger)
- Confidence: Confirmed
- Evidence: `enqueue_message_downstream_work()` (trigger on `messages`) does kick `process-chat-notification-outbox` immediately via `net.http_post`, and that worker runs within ~1 s — but all it does is `INSERT INTO scheduled_notifications (status='pending', scheduled_for=now())` (`supabase/functions/process-chat-notification-outbox/index.ts:244-262`). Nothing then wakes the sender: `supabase/functions/_shared/push_queue.ts` header ("A function that wants to notify someone enqueues; it never sends"), `push_transport.test.ts:27` enforces that only `process-scheduled-notifications` calls OneSignal, and that worker is only ever invoked by `cron.job 'process-scheduled-notifications' '* * * * *'` (DB cron list; `20260907120000_register_scheduled_jobs.sql:129-131`). Triggers on `scheduled_notifications` are only `copy_guard` and `quiet_guard` — no `net.http_post`. The worker also caps at 50 rows per run, sequentially, shared with every other push type in the app.
- Failure scenario: A sends "are you there?" at 12:00:05 → outbox row done at 12:00:06 → scheduled row sits until the 12:01:00 cron tick (+ edge cold start) → B's phone buzzes at ~12:01:02. Average 30 s, worst case >60 s; if more than 50 pushes of any type are due in a minute, longer.
- WhatsApp/iMessage expectation: push within 1–3 s of send.
- Fix (minimal, keeps the "only the worker calls OneSignal" invariant): in `process-chat-notification-outbox/index.ts` right after the successful `scheduled_notifications` insert, fire-and-forget `fetch(`${SUPABASE_URL}/functions/v1/process-scheduled-notifications`, {headers: service-role})` (do not await the body; errors ignored — the cron remains the sweeper). Equivalent DB alternative: an `AFTER INSERT` trigger on `scheduled_notifications` `WHEN (NEW.status='pending' AND NEW.scheduled_for <= now())` that calls `public.invoke_edge_function('process-scheduled-notifications')` wrapped in `EXCEPTION WHEN OTHERS THEN NULL`. Claims are already atomic (`.eq("status","pending")` update), so an extra concurrent run is safe.

### H-3: OneSignal targets a bare `external_id`; without Identity Verification a partner can subscribe their own phone to the other's pushes
- Severity: High (privacy; this app's threat model is the partner)
- Confidence: Possible (depends on a OneSignal dashboard setting I cannot see; the code side is confirmed)
- Evidence: `lib/core/notifications/services/onesignal_service.dart:86,129` → `OneSignal.login(user.id)` with no identity JWT; `supabase/functions/_shared/onesignal_push.ts:22` → `include_aliases: { external_id: [userId] }`. The partner's user id is readable by design (`relationships.user_a/user_b`, policy `relationship members read`). The OneSignal app id ships in the binary (`Environment.oneSignalAppId`).
- Failure scenario: after a break-up (or during coercive control) the ex installs any OneSignal-SDK app with Attune's app id (or a resigned Attune) and calls `login(<victim uuid>)` → every push for the victim (new-message pushes from a new partner; `safety_resources` pushes, which bypass quiet hours; weekly check-ins) is delivered to the ex's phone as well. With preview on, message text too.
- WhatsApp/iMessage expectation: only the account holder's devices receive the account's pushes.
- Fix: turn on **Identity Verification** for the OneSignal app and mint the identity JWT server-side (an edge function signing `{sub: user.id}` with the OneSignal identity key, called after Supabase sign-in), then `OneSignal.login(userId, jwt)` in `onesignal_service.dart`. Until then, keep the preview default off (it is) and treat `safety_resources` copy as potentially read by the wrong person.

### M-1: Stale `processing` leases are never recovered — a crashed worker loses the push silently
- Severity: Medium (rare, but a lost notification with no retry)
- Confidence: Likely
- Evidence: `recover_stale_chat_worker_leases()` exists in the DB and resets `message_notification_outbox`, `message_safety_outbox`, `message_media_processing_outbox` and `scheduled_notifications` rows stuck in `processing` > 5 min — but nothing calls it: `cron.job 'recover-stale-chat-workers'` runs `invoke_edge_function('process-chat-media')` (DB cron list; `20260907120000_register_scheduled_jobs.sql:157-161`), `grep -rn recover_stale supabase/functions` → no edge function calls it, and the only caller is the unapplied ad-hoc file `supabase/sql/schedule_process_chat_media.sql:20`. Workers go `pending → processing` before any side effect (`process-chat-notification-outbox/index.ts:69-96`, `process-scheduled-notifications/index.ts:24-30`), so an edge-function timeout/OOM/redeploy between claim and finalize strands the row.
- Failure scenario: the outbox worker is killed after claiming (cold-start timeout, deploy mid-run) → row stays `processing` forever → B never gets a push for that message; nothing in logs. Same for a `scheduled_notifications` row claimed just before a worker death.
- WhatsApp/iMessage expectation: at-least-once push with retry.
- Fix: change the cron job body to `SELECT * FROM public.recover_stale_chat_worker_leases();` (new migration re-scheduling `recover-stale-chat-workers`), or call the RPC at the top of `process-chat-notification-outbox` / `process-scheduled-notifications` on cron-triggered runs (no `outbox_id` in the body).

### M-2: Each message causes 4–6 realtime events and as many full refetch cycles on both phones
- Severity: Medium (jank/battery/data; grows with chat length)
- Confidence: Confirmed
- Evidence: per message the server emits, on tables in `supabase_realtime`: `messages` INSERT; `relationships` UPDATE from `UPDATE relationships SET message_count = message_count + 1` in `enqueue_message_downstream_work()`; `messages` UPDATE from `mark_delivered`/`mark_delivered_for_recipient`; `messages` UPDATE from the safety worker (`process-chat-safety-outbox/index.ts:333-357` writes `safety_processed_at`); `messages` UPDATE from analyse-message (`analyse-message/index.ts:373`); `messages` UPDATE from `mark_conversation_read` (`read_receipt_at`). The client ignores payloads (`supabase_chat_repository.dart:560-607`, `callback: (_) => events.add(null)`), and every event — after a 250 ms debounce (`chat_config.dart:21`) — runs `_refreshConversation + _catchUpFromCursor + loadMessages(50 rows) + _markPartnerMessagesDelivered + _refreshPinnedMessages + markAsReadDebounced + conversationsRefresh++` (`chat_state.dart:508-534`). The inbox channel refetches `getConversations()` (+ `count_unread_messages` per relationship) on the same events (`chat_state.dart:205-237`). The events arrive seconds apart (worker, analysis), so the debounce does not coalesce them.
- Failure scenario: B sends one message → A's phone performs ~5 × (6 queries) over the next ~10 s; on a slow link the list visibly re-sorts/flickers ("Reconnecting…"-style jank) and the conversations list re-renders repeatedly. A burst of 10 messages → ~300 queries per phone.
- WhatsApp/iMessage expectation: one delta per message; receipts update in place.
- Fix: (a) drop the hot-path `message_count` increment from `enqueue_message_downstream_work()` — nothing in the app reads it, `cancel_chat_imports_on_relationship_change` already recomputes it from `count(*)`, and the only server reader is the Ask-2 eligibility path, which can `count(*)` on demand; that removes the `relationships` UPDATE event entirely. (b) In the `messages` handler, look at `payload.newRecord` and ignore UPDATEs whose user-visible fields (`content, deleted_at, edited_at, delivered_at, read_receipt_at, viewed_at, media_*`) match the cached row — safety/analysis column changes are stripped by column grants anyway, so they arrive as "nothing changed". (c) Longer term, move `safety_*`/analysis columns to a side table so those writes never touch the replicated `messages` row.

### M-3: Worker retry can push the same message twice (no idempotency key on the queued push)
- Severity: Medium
- Confidence: Possible (needs a transient failure between insert and finalize)
- Evidence: `process-chat-notification-outbox/index.ts:208-262` inserts `in_app_notifications` and `scheduled_notifications` with `source_key` unset, then `finalizeJob(... "done")` at line 276. The `catch` (line 279-283) puts the job back to `pending` on *any* error, including a failed `finalizeJob` UPDATE after both inserts succeeded; the retry inserts a second scheduled row with a new `id`, so the OneSignal `Idempotency-Key` (`process-scheduled-notifications/index.ts:46`, keyed on `job.id`) does not help. Spec §9.1 requires idempotency per `(recipient_id, message_id, type)`; the outbox unique key gives it only up to the outbox row, not past it.
- Failure scenario: transient PostgREST error on the final UPDATE → next cron tick reprocesses → B receives two "New message in Attune" banners for one message.
- WhatsApp/iMessage expectation: at most one notification per message.
- Fix: pass `source_key: 'chat_outbox:' + outboxId` on the scheduled insert and treat `23505` as success (exactly what `push_queue.ts:enqueuePush` already does — use it); the quiet guard already preserves a caller's own `source_key`. Same for `in_app_notifications` (unique on `(user_id, data->>'outbox_id')` or check-before-insert).

### M-4: No app-icon badge, no per-conversation grouping/collapse in the push payload
- Severity: Medium (visible polish gap)
- Confidence: Confirmed
- Evidence: `onesignal_push.ts:19-28` sends only `headings/contents/data`; no `ios_badgeType`/`ios_badgeCount`, no `thread_id`/`android_group`/`collapse_id`, no `ios_sound`/`android_channel_id`. Nothing in the app clears a badge (`grep clearAll` → none).
- Failure scenario: 8 messages from the partner → 8 separate identical "New message in Attune / Open Attune to read it." banners that do not stack as a conversation; the app icon never shows a badge; iMessage-style "N new messages" summary absent.
- WhatsApp/iMessage expectation: grouped per chat, badge count, one collapsed summary.
- Fix: add `thread_id`/`android_group: relationship_id`, `ios_badgeType: "Increase", ios_badgeCount: 1`, `collapse_id: relationship_id` for the generic (no-preview) copy so repeated generic pushes replace each other; call `OneSignal.Notifications.clearAll()` when the chat screen becomes active (clears iOS badge and the stacked banners).

### M-5: Android 13+ is never asked for notification permission
- Severity: Medium (no pushes on Android 13+ until the user digs into settings)
- Confidence: Possible (OneSignal 5.x does not auto-prompt in my understanding; verify on one Android 13+ device — if no system dialog appears on first launch this is it)
- Evidence: `onesignal_service.dart:29-31` calls `OneSignal.Notifications.requestPermission(true)` only inside `if (Platform.isIOS)`. `AndroidManifest.xml:45-48` declares `POST_NOTIFICATIONS` with a comment assuming the service requests it "on startup". The OneSignal 5.5.1 plugin exposes `requestPermission` as the only prompt path (`onesignal_flutter-5.5.1/lib/src/notifications.dart:88`).
- Failure scenario: fresh install on Pixel/Android 14 → no permission dialog → OS treats the app as notifications-off → partner's messages never show.
- Fix: call `requestPermission(true)` on both platforms (ideally after sign-in, gated by `OneSignal.Notifications.permission == false`).

### M-6: A client can insert `is_system_notice = true` — a partner can forge app notices
- Severity: Medium (spoofing in a safety-sensitive chat; also bypasses push + unread)
- Confidence: Confirmed
- Evidence: `information_schema.column_privileges` grants `authenticated` INSERT on `messages.is_system_notice` (migration `20261017130100_messages_column_grants.sql`); the only guard triggers are for `pause`/`appreciation` media types, not for notices; the client already uses the path (`ephemeral_video_viewer_screen.dart:130`, `supabase_chat_repository.dart:317`). Server treats notices specially: never pushed (`messagePushable`), never unread (`count_unread_messages` `NOT m.is_system_notice`), rendered without a bubble (`message_bubble.dart:1421`).
- Failure scenario: a partner using the REST API inserts `{is_system_notice: true, content: "Attune: your partner has reported this conversation to Safety"}` → it renders as an official centred notice, triggers no push and no unread badge, so it looks like it came from the app.
- WhatsApp/iMessage expectation: system lines cannot be authored by a participant.
- Fix: revoke INSERT on `is_system_notice` from `authenticated` and move the screenshot notice behind a SECURITY DEFINER RPC (same `set_config('attune.send_…','on')` pattern as `send_pause`), with a BEFORE INSERT guard raising unless the GUC is set.

### M-7: Signed-URL creation for chat media scans the whole `messages` table
- Severity: Medium (latency grows with history; every thumbnail/image/voice load)
- Confidence: Likely (schema confirmed; cost is linear in message count)
- Evidence: storage policy `message_media_select_relationship_members` → `EXISTS (SELECT 1 FROM messages m WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name) AND relationship_chat_open(m.relationship_id))`; `pg_indexes` on `messages` has no index on `media_url` or `media_thumbnail_url`; the client creates signed URLs itself (`supabase_chat_repository.dart:431 createSignedUrl`), so this policy runs per media item per page.
- Failure scenario: a year-old chat with 40k rows → opening a page with 20 images runs 20 sequential scans of `messages` in storage's RLS check → photos pop in late.
- Fix: `CREATE INDEX messages_media_url_idx ON public.messages (media_url) WHERE media_url IS NOT NULL;` and the same for `media_thumbnail_url` (the planner will BitmapOr the two).

### M-8: The "Relationship Updates" toggle silently switches off message pushes
- Severity: Medium (user-visible, undocumented)
- Confidence: Confirmed
- Evidence: `process-chat-notification-outbox/index.ts:163-176` suppresses the chat push when `booking_reminders_enabled === false`; that column is the settings toggle labelled "Relationship Updates — Notifications about shared Attune activity" (`notification_config.dart:232-237`). Chat is not mentioned.
- Failure scenario: B turns off "Relationship Updates" to stop moment/plan pings → B stops receiving any message pushes and does not know why.
- Fix: gate chat pushes on `push_enabled` only, or add a dedicated `chat_messages_enabled` column and toggle.

### L-1: Every partner message writes an `in_app_notifications` row, even while the recipient is viewing the chat
- Severity: Low (the bell widget is not mounted anywhere; table grows unbounded and would flood the inbox if it is)
- Confidence: Confirmed
- Evidence: insert at `process-chat-notification-outbox/index.ts:208-220` happens before the `suppressPush` branch; `NotificationBellIcon` has no call sites; inbox fetch has no type filter (`notification_repository_impl.dart:165`).
- Fix: insert only when not actively viewing (or not at all for `new_message`); add a purge.

### L-2: `relationships.message_count` drifts
- Severity: Low (unused by the app)
- Confidence: Confirmed
- Evidence: incremented for every row incl. system notices, pause/pause_reply, game cards, place updates, imports; never decremented on `delete_message` (soft) or purge; recomputed as `count(*)` only on status/archive changes (`20261018160000_sync_fixes.sql:56`). Different definitions in the two places. See M-2 for the recommendation to drop it from the hot path.

### L-3: `message_stars` lets a user star any message id
- Severity: Low (existence probe only; UUIDs are unguessable)
- Confidence: Confirmed
- Evidence: policy `message_stars_owner` (`ALL`, `user_id = auth.uid()`) with no relationship check; FK to `messages`.
- Fix: add `AND EXISTS (SELECT 1 FROM messages m WHERE m.id = message_id AND relationship_chat_open(m.relationship_id))` to `WITH CHECK`.

### L-4: Residual `anon` SELECT grants on `in_app_notifications`, `notification_settings`, `push_tokens`
- Severity: Low (RLS has no anon policy, so zero rows; hygiene)
- Confidence: Confirmed
- Evidence: `has_table_privilege('anon', …, 'SELECT') = true` for the three tables; their policies are `TO authenticated` only.
- Fix: `REVOKE SELECT ON … FROM anon;`

### L-5: Reply quote text is client-supplied
- Severity: Low (same trust model as WhatsApp's E2E quotes, but here the server could enforce it)
- Confidence: Confirmed
- Evidence: `quoted_text` is in the INSERT column grant; `validate_message_reply_before_insert()` checks only same-relationship. A partner can attribute invented words to the other in a reply header.
- Fix: derive `quoted_text` server-side in the trigger from `left(parent.content, 200)` (as `validate_message_story_reply_before_insert` already does for stories).

## Done well

- `messages`: `authenticated` has no UPDATE/DELETE grant and a column-restricted INSERT (`sender_id`, `relationship_id`, content/media/reply columns only); `created_at`, `sort_at`, `deleted_at`, `delivered_at`, `tone_score`, analysis and safety columns are not writable; SELECT grant excludes `tone_score`, `nvc_violations`, `bid_type`, `sentiment`, `safety_*` (so Realtime's column filter strips them too).
- `messages_insert_sender_active` forces `sender_id = auth.uid()` and an `active`, unarchived relationship; `messages_select_members` → `relationship_chat_open()` (member, not archived, active/paused or ended < 30 days, not sealed by me). Previous chapters are unreadable once archived (chapter scoping), and `relationship_one_open_chapter_guard` keeps one open chapter per person.
- Every mutation is an RPC that re-checks membership and ownership with `FOR UPDATE` locking and a 5-minute window (`edit_message`, `delete_message`), relationship + message checks (`pin_message`, `react_to_message`), partner-only receipts (`mark_delivered*`, `mark_conversation_read`). `message_reads`/`message_read_marks`/outbox tables have no client grants at all.
- All SECURITY DEFINER functions in `public` set `search_path` (query returned zero offenders); `anon` can execute only forum read functions; trigger functions granted to PUBLIC cannot be called directly.
- Media: upload intents + object metadata validated in `validate_message_media_before_insert`; storage SELECT tied to a visible message row; `message-media` bucket private.
- Realtime publication is versioned in a migration; `REPLICA IDENTITY DEFAULT` keeps content out of DELETE payloads; policy evaluation per subscriber works for both partners.
- Push privacy: generic copy by default, preview opt-in (`chat_message_preview_enabled` default false), `privacySafeData` whitelist of ids only, deleted/system messages never pushed, suppressed while actively viewing (20 s heartbeat vs 30 s window), relationship lifecycle (`pause/end/archive`) cancels pending outbox + scheduled pushes, `mark_conversation_read` cancels unsent pushes, quiet-hours collapse with advisory lock, workers require the service-role key, trigger's `net.http_post` wrapped in `EXCEPTION WHEN OTHERS` so safety/analysis can never block a send.
- Outbox: unique `(recipient_id, message_id, notification_type)`, atomic conditional claim, 5-attempt dead-letter, immediate pg_net kick + cron sweeper, OneSignal `Idempotency-Key` per scheduled row.
- App: `OneSignal.logout()` on sign-out and `login` on sign-in; tap deep-links into the right chat (`notification_config.dart:98-108`); taps deferred under the Safety PIN / quick-exit decoy and replayed on unlock.

## Not verified

- Whether the production project has the vault secrets `supabase_url`/`service_role_key` (needed for the immediate pg_net kick; without them the outbox falls back to the 1-minute cron on top of H-2) and whether prod's `cron.job` matches the scratch DB.
- OneSignal dashboard settings (Identity Verification, APNs/FCM credentials) — H-3 depends on it.
- Realtime's column-privilege filtering (`realtime` schema is not present in the scratch DB).
- Actual device behaviour: iOS registration (H-1), Android 13 prompt (M-5), background delivery-tick (the recipient's phone only marks `delivered_at` once the app runs; with no NSE/background handler a closed app shows one tick until opened — accepted by Spec §9.1).
- `process-chat-safety-outbox` / `analyse-message` internals beyond their `messages` writes (another reviewer's area); I only confirmed they cannot block or delay a send.
