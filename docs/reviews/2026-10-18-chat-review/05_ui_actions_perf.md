# 05 — Chat screen UI, message actions, fluidity/performance

Reviewer scope: `chat_screen.dart`, `message_bubble.dart`, `universal_bubble.dart`, `focused_action_menu.dart`, `message_actions_sheet.dart`, `chat_text_field.dart`, `attune_chat_wallpaper.dart`, `live_message_motion.dart`, `emoji_message_content.dart`, `chat_date_chip.dart`, `conversations_screen.dart`, search/starred/info screens, and the action paths in `chat_state.dart` + `supabase_chat_repository.dart`. Read-only; nothing executed on device.

## Summary

The message list, composer, swipe-to-reply, reactions, long-press menu and the optimistic send path are built to a high standard (keyed rows, play-once arrival animations, scoped typing/presence rebuilds, reaction optimistic+rollback, realtime fan-out for edits/deletes/pins/reactions). Three things will visibly fail on the two-phone test: **jumping to a message that is not already built** (reply quotes, pinned banner, Starred/Search/Media "go to message") silently does nothing or lands in the wrong place; **edited messages carry no "edited" marker in the chat**, so the edit-history sheet is unreachable and the partner cannot tell a message changed; and the **Starred screen is cached forever** after its first open. Below that, the list lacks WhatsApp/iMessage staples — no scroll-to-bottom / unread pill / "new messages" divider, delivery state visible only on the newest bubble, URLs not tappable — plus two real performance costs (full-resolution image decodes for 220px tiles; a full-screen `Opacity` gradient repainted every scroll frame in dark mode).

## Findings

### H-1: Jump-to-message fails for any target not currently built (reply quote, pinned banner, Starred/Search/Media "Go to message")
- Severity: High
- Confidence: Confirmed (code path traced; heuristic cannot converge by construction)
- Evidence:
  - `lib/features/chat/presentation/screens/chat_screen.dart:605-660` — `_tryEnsureMessageVisible` only works when `_messageKeys[id].currentContext != null` (row inside cacheExtent). Fallback `_jumpToMessage` (629-660): `averageExtent = viewportDimension / _messageKeys.length` (639), one `animateTo(index * averageExtent)`, one 50 ms wait, one retry, then gives up silently.
  - `_messageKeys` is only pruned to ids still in `state.messages` (3259); it accumulates every row ever built, so after any scrolling `averageExtent` collapses (e.g. viewport 800 / 120 built rows = 6.7 px per message) and the estimate lands thousands of pixels short. On a fresh open it uses ~15 rows, so a 10% error in average bubble height already misses a 400-message-old target by ~40 messages, outside the 250 px cacheExtent.
  - Reply-quote tap and pinned-banner tap use `_jumpToMessage` directly (1389-1396, 3560-3565); if the parent/pinned message is older than the loaded 50-message page, `indexWhere == -1` → returns with no feedback. Only `initialJumpToMessageId` pages back (`_jumpToMessageAcrossPages`, 664), and after paging it still hands off to the same estimate.
- Failure scenario: Partner replies to something you said 60 messages ago; you tap the quote → list scrolls somewhere unrelated (or not at all), nothing flashes. Open Starred → tap a message from last week → chat opens, pages back for a few seconds, scrolls to the wrong place, no highlight. Pinned banner → tap a pin from last month → nothing happens.
- WhatsApp/iMessage expectation: tapping a quote/pin/search result always lands on and flashes the message, loading history if needed.
- Fix: (a) make `_jumpToMessage` page back like `_jumpToMessageAcrossPages` when `index == -1` (one shared entry point for quote/pin/initial jump). (b) Replace the single estimate with a convergence loop: find the built row whose index is nearest the target (iterate `_rowKeys`, read `RenderBox` offset + index), extrapolate from its measured offset using the mean height of *currently built* rows, `jumpTo`, pump a frame, repeat until `_messageKeys[target].currentContext != null` (cap ~12 iterations), then `ensureVisible` + flash. (c) Show a brief "Loading older messages…" affordance while paging.

### H-2: Edited messages show no "edited" marker in the chat; edit history is unreachable
- Severity: High (transparency in a couples app is the whole point of spec decision 2)
- Confidence: Confirmed
- Evidence:
  - `lib/features/chat/presentation/widgets/message_bubble.dart:690-700` — the only `_MessageMeta` instance is built with `showEdited: false`; `_RevealTimestamp` (775) renders time only. No other call site renders `editedAt` in the list (grep: only `message_info_screen.dart:128`).
  - `chat_screen.dart:3993` `_showEditHistorySheet` is wired exclusively through `onShowEditHistory`, which is only invoked from the hidden "edited" label (`message_bubble.dart:1963-1972`) → dead UI.
  - `test/features/chat/chat_screen_message_actions_test.dart:608` asserts `find.text('edited'), findsNothing` — the regression was encoded as expected behaviour when the footer moved outside the bubble (commit f29007b6).
  - Spec: `docs/superpowers/specs/2026-08-13-message-actions-design.md` "Edited label + history view" requires the label + tap-to-history.
- Failure scenario: You send "I'll be home at 7", edit to "at 9" within 5 minutes. Partner's bubble silently changes to "at 9"; no "edited" tag anywhere in the list; the only trace is long-press → Info. The edit-history sheet (prior versions) can never be opened.
- WhatsApp/iMessage expectation: an "Edited" label on the bubble; tapping it shows history.
- Fix: in `message_bubble.dart` render a small "edited" label when `message.editedAt != null && !message.isDeleted` regardless of footer visibility — e.g. append it as the last inline span of the text block or as a trailing label in the footer with `showEdited: true` when edited (and force `hasVisibleFooter` true for edited messages). Keep `onShowEditHistory` on it. Update the test at line 608 to `findsOneWidget`.

### H-3: Starred messages screen never refreshes after first open
- Severity: High (stuck state for the rest of the app session)
- Confidence: Confirmed
- Evidence: `lib/features/chat/presentation/screens/starred_messages_screen.dart:8` — `starredMessagesProvider` is a non-autoDispose `FutureProvider`; grep across `lib/` shows no `invalidate`/`refresh` of it, and `ChatController.starMessage/unstarMessage` (`chat_state.dart:1606-1620`) only update `state.starredMessageIds`.
- Failure scenario: Open Chat settings → Starred (list cached). Back to chat, star two more messages, unstar one. Reopen Starred → old list; stays wrong until app restart.
- WhatsApp/iMessage expectation: Starred is always current.
- Fix: make it `FutureProvider.autoDispose`, and `ref.invalidate(starredMessagesProvider)` in `starMessage`/`unstarMessage` (or derive the screen from `chatControllerProvider(...).starredMessageIds` + a repository fetch keyed on that set).

### M-1: No scroll-to-bottom button, unread pill or "new messages" divider; list shifts under the reader when a message arrives while scrolled up
- Severity: Medium
- Confidence: Likely (Flutter behaviour of a reverse `ListView.builder` without `findChildIndexCallback`/center anchoring; not run on device)
- Evidence: `chat_screen.dart:3297-3312` — plain `ListView.builder(reverse: true)`; no `findChildIndexCallback`, no `CustomScrollView(center:)`. Grep for any jump-to-latest affordance in `lib/features/chat` finds none. `_scrollToLatest` (1230) is only called after the user's own sends. New partner rows are inserted at index 0 with `_mergeMessages`; rows are keyed (`KeyedSubtree(key: messageKey)`, 3784) but the sliver still matches by index, so the row at each attached index receives a different message while keeping that index's layout offset.
- Failure scenario: Scroll up to re-read yesterday; partner sends three messages → the text under your finger hops by one bubble each time; nothing tells you there are new messages; you have to fling back down manually. Opening a chat with 40 unread: lands at the bottom, no "40 unread messages" divider to scroll up to.
- WhatsApp/iMessage expectation: viewport stays put, a "↓ 3" pill appears; opening a chat shows an unread divider.
- Fix: (1) add a floating "↓" pill (visible when `pixels > ~1.5 viewports`, with a count of partner messages arrived since the user left the bottom); (2) anchor the list — either pass `findChildIndexCallback` keyed on `clientMessageId` or move to `CustomScrollView` with two `SliverList`s around a `center` key; (3) a one-shot "N unread messages" `ChatDateSeparator`-style row computed from `conversation.unreadCount` at open.

### M-2: Delivery status (queued/sent/delivered/read) is only visible on the newest bubble
- Severity: Medium
- Confidence: Confirmed
- Evidence: `chat_screen.dart:3434-3435` — `showStatus: index == 0 && message.isMine`, `showLatestTimestamp: index == 0`. `_RevealTimestamp` (`message_bubble.dart:775-800`) shows the clock only, no status. Failed messages still show Retry/Remove (`hasVisibleFooter`, 392), but queued/sending ones further up show nothing.
- Failure scenario: Offline, send four messages, then partner's earlier message gets merged above them → only the last of yours shows the clock icon; you cannot tell which of the other three are queued vs sent, nor later which were read. The Offline banner's "4 messages queued" is the only hint.
- WhatsApp/iMessage expectation: WhatsApp ticks on every own bubble; iMessage shows "Delivered/Read" under your most recent own message and clocks/"Not delivered" on any pending/failed one.
- Fix: show the status chip on the newest *own* message (`index == firstOwnIndex`) and always on `isQueued`/`isSending`/`isFailed` rows; include the status icon next to the time inside `_RevealTimestamp` for own messages.

### M-3: URLs / phone numbers in messages are plain text
- Severity: Medium
- Confidence: Confirmed
- Evidence: `message_bubble.dart:1856-1870` renders `Text(message.content)`; grep `linkify|launchUrl|SelectableText|SelectionArea` across `lib/features/chat` and `universal_bubble.dart` → nothing.
- Failure scenario: Partner sends a Maps link or "call me 024…" → nothing tappable; the person has to Copy then paste into a browser.
- WhatsApp/iMessage expectation: links/phones/emails tappable (with a preview in WhatsApp).
- Fix: wrap the text block in a lightweight linkifier (`Text.rich` with `TapGestureRecognizer` spans from a URL/phone regex; `url_launcher` is already a transitive dependency via existing features — verify in pubspec) and keep long-press routing to the focused menu.

### M-4: Image thumbnails decode at full resolution (no `memCacheWidth`/`cacheWidth`)
- Severity: Medium (memory + scroll jank)
- Confidence: Confirmed
- Evidence: `message_bubble.dart:1477-1520` `Image(FileImage)` and `CachedNetworkImage(... width: 220, height: 220)` with no `cacheWidth`/`memCacheWidth`; same in `chat_media_group.dart:250`. Grep for `memCacheWidth|cacheWidth|ResizeImage` in `lib/features/chat` → none. `ChatImagePreparer.maxDimension = 1600` (`chat_image_preparer.dart:52`) so each tile decodes a ~1600×1200 bitmap (~7–8 MB) to paint 220 px.
- Failure scenario: A chat with 30 photos: scrolling through decodes ~200 MB of bitmaps; Flutter's 100 MB image cache thrashes, so scrolling back re-decodes (visible shimmer/jank), and low-end Androids risk OOM.
- WhatsApp/iMessage expectation: thumbnails are tiny decodes; full-res only in the viewer.
- Fix: pass `memCacheWidth: (220 * devicePixelRatio).round()` (and `maxWidthDiskCache`) to the chat `CachedNetworkImage`s, `cacheWidth` on the `FileImage` path; keep the viewer at full size. The `Hero` still flies between the two.

### M-5: Dark mode: full-screen `Opacity` gradient rebuilt and repainted on every scroll frame
- Severity: Medium (perf)
- Confidence: Likely
- Evidence: `attune_chat_wallpaper.dart:30-35` — `AnimatedBuilder(animation: scrollController)` rebuilds `_buildWallpaper` per scroll tick in dark mode; `_WallpaperGradientLayer` (279-310) wraps a full-screen `DecoratedBox` in `Opacity(opacity: scrollProgress)` → a full-screen `saveLayer` every frame while scrolling (the pattern tile is behind its own `RepaintBoundary`, but the gradient layer is not). Progress saturates at 620 px (`_scrollGradientProgress`), so after that the work is pure waste.
- Failure scenario: Dark-mode scroll on an older phone → dropped frames, especially combined with M-4 decodes.
- WhatsApp/iMessage expectation: wallpaper is a static raster.
- Fix: remove `Opacity`; lerp the gradient colours by `scrollProgress` into a single `DecoratedBox` (no saveLayer), and only notify when the quantised progress actually changes (or stop listening once progress hits 1).

### M-6: Timestamp-reveal drag rebuilds every visible bubble subtree per pointer event
- Severity: Medium (jank during the iMessage-style left swipe)
- Confidence: Likely
- Evidence: `chat_screen.dart:3412-3420` — each row's `MessageBubble` is built inside `ValueListenableBuilder(_timestampRevealOffset)`; every drag delta rebuilds the whole `MessageBubble` (reaction adornments, `_BubbleBody` with `CachedNetworkImage`/`VideoMessageThumbnail`/`VoiceMessagePlayer` consumers, nested `IntrinsicWidth` layouts at 445 and 1876) for all ~15 visible rows.
- Failure scenario: swipe left to see times on a screen with a few photos/voice notes → stutter.
- Fix: pass the offset down as a `ValueListenable<double>` and apply it in `UniversalBubble` via a `Transform.translate` inside an `AnimatedBuilder`/`ValueListenableBuilder` that wraps only the bubble shell, leaving the content subtree as a prebuilt `child`.

### L-1: Header pill ignores system text scaling
- Severity: Low (accessibility)
- Confidence: Confirmed
- Evidence: `chat_screen.dart:2097` `RichText(...)` for name + status (and `reply_composer_preview.dart:73`). `RichText` defaults to `TextScaler.noScaling`.
- Fix: `Text.rich(...)` or pass `textScaler: MediaQuery.textScalerOf(context)`.

### L-2: Read-only reason shown twice; media rejection shown as "Could not sync" with a Retry that reloads messages
- Severity: Low
- Confidence: Confirmed
- Evidence: `_ConversationStateBanner` (`chat_screen.dart:1746-1800`) shows "Read-only: <reason>" and the composer slot shows the same `readOnlyReason` (1711); `state.error` is also set by `sendImageMessage`/`sendVideoMessage*` rejections (`chat_state.dart:748, 1037, 1118`) and rendered under the "Could not sync" title with a Retry → `loadMessages()`.
- Fix: suppress the banner when `!canSend` (composer slot already explains), and route send rejections to a snackbar / separate `sendError` field.

### L-3: Pinned banner is blank for media pins; Copy offered on media/game bubbles; quick-reaction row has no "current" state and re-tapping does not un-react
- Severity: Low
- Confidence: Confirmed
- Evidence: `_PinnedMessagesBanner` renders `message.content` only (`chat_screen.dart:4113`); `onCopy` copies `message.content` unconditionally (3597); `buildMessageActionItems` always lists Copy (`message_actions_sheet.dart`); quick reactions are plain `ReactionQuickOption(emoji)` with no selected flag (`message_bubble.dart:~560`), and `reactToMessage` with the same emoji just re-adds (`chat_state.dart:1645`).
- Fix: use `conversationPreviewText`-style labels ("Photo", "Voice message") for pins; hide Copy when `content.trim().isEmpty`; mark the user's current emoji in the quick row and treat a re-tap as remove.

### L-4: Composer focus hops the list 56 px before the keyboard animates; no keyboard image/GIF insertion
- Severity: Low
- Confidence: Possible
- Evidence: `_onComposerFocusChanged` → `setState` (chat_screen.dart:208) flips `keyboardIsOpen` (3266) → bottom padding 120→64 instantly (3007), while `viewInsets.bottom` animates afterwards. No `contentInsertionConfiguration` on the `TextField` (`chat_text_field.dart:1554`).
- Fix: drive the reserve from `viewInsets.bottom` only (or animate the padding with `AnimatedPadding`), and add `contentInsertionConfiguration` to route pasted images into `_attachImage`.

### L-5: Per-scroll-frame and per-build O(n) work over all loaded messages
- Severity: Low (fine at 50–200 messages, grows after paging)
- Confidence: Confirmed
- Evidence: `_topmostVisibleDateLabel` iterates every loaded message on each `ScrollUpdateNotification` (`chat_screen.dart:3090-3115, 3291`); three key maps pruned per build (3259-3263); `_syncArrivals` iterates all ids on every `didUpdateWidget`; `_ConversationStateBanner` counts queued messages per build; reply-parent lookup is a linear scan per visible reply (3395-3405).
- Fix: iterate `_rowKeys` (built rows only) in the date-chip scan; index messages by id once per state change; store queued count on `ChatState`.

### L-6: Secondary screens: raw `DateFormat`, no sender/match highlight in search, Search only reachable via settings
- Severity: Low
- Confidence: Confirmed
- Evidence: `chat_message_search_screen.dart:160`, `starred_messages_screen.dart:58` use `DateFormat.yMMMd()` (project standard is `MyDateFormat`); search rows show content + date only; no search entry in the chat header/drawer (`_ConversationHeaderOverlay` offers Pulse/Insights only).
- Fix: `MyDateFormat.join`, show "You/Partner" + highlighted match, add Search/Starred/Media to the header drawer.

### L-7: Conversations list tile has no typing indicator or last-message time
- Severity: Low
- Confidence: Confirmed
- Evidence: `conversations_screen.dart:273-360` `_ConversationCard` renders name, preview, unread badge, lock icon only; `typingControllerProvider` is not watched there.
- Fix: subtitle swaps to "typing…" via `typingControllerProvider(relationshipId).partnerTyping`; trailing shows `MyDateFormat` relative time of `lastMessage.createdAt`.

### L-8: Accessibility: bubbles have no row-level semantics; reaction pill overflows at large text scale
- Severity: Low
- Confidence: Likely
- Evidence: `universal_bubble.dart` has no `Semantics` label for sender/time (only `alwaysIncludeSemantics` at 927); `_ReactionAdornment` is a fixed `SizedBox(width: 46/54, height: 44)` around a 20 px emoji `Text` (`message_bubble.dart:891-930`) — at 200% text scale the pill paints outside its box over the bubble.
- Fix: wrap each row in `Semantics(label: '<You|Partner>, <time>, <status>')` with `MergeSemantics`; use `TextScaler.noScaling` for the pill emoji (as `EmojiMessageContent` already does) or size the box from the scaled text.

## Done well (keep these)
- Optimistic send with in-place optimistic→canonical swap (`_replaceOptimistic`), `presentationSortAt` so the sent bubble never jumps; `MakeRoom`+`SettleIn` arrival with a screen-lifetime play-once ledger and identity-based `MessageArrivalTracker` (clock-skew safe).
- Reactions are optimistic with correct rollback to the previous emoji (`reactToMessage`), one-per-user semantics, flight + landing effect; partner reactions/pins/edits/deletes all arrive via the single `chat:$relationshipId` channel (messages all events, message_pins, message_reactions).
- Typing indicator and partner presence are scoped `Consumer`/provider watches, so they do not rebuild the list; presence is polled (15 s) rather than realtime.
- Long-press menu resolves `NavigatorState` eagerly, pops via tile-local contexts (recycled-element safe); Edit/Delete omitted outside the 5-minute sender window; menu disabled on local/deleted/preparing rows and in read-only conversations.
- Reply flight / cancel flight with epoch guards, reduce-motion respected everywhere (`reduceMotionOf`), emoji animations gated by visibility, foreground and route (`EmojiMessageContent`), sparkles only while `t < 1`.
- Grouping (same sender, same day) with squared inner corners; date separators placed above the first message of the day; pinned date chip measured from real row boxes; Today/Yesterday/weekday labels compared by local day.
- Composer: grows 1→5 lines with animated pill radius, send/mic swap, draft restore per relationship, focus retained after send, `TextFieldTapRegion` so satellites don't drop focus; `enabled` never toggled during send.
- `deactivate()` clears view-active so read receipts stop when the screen is covered; `setViewActive` gates `markAsRead`; `_scrollToLatest` only for own sends.
- Header taps no longer contested by the unfocus `GestureDetector` (scoped to the list layer).

## Not verified
- Actual device frame timings for M-4/M-5/M-6 and the reverse-list shift in M-1 (reasoned from Flutter's `SliverMultiBoxAdaptorElement`/`RenderSliverList` behaviour; no run).
- RTL: the app ships de/en/es/fr/it/pt only, so physical left/right in bubbles/adornments was not treated as a defect.
- Android keyboard resize timing (L-4) and iPad split-view behaviour of `AppContentWidth`.
- `focused_action_menu` layout at 200% text scale (it budgets widths; heights are estimated — not exercised).
- Video thumbnail decode sizing inside `video_message_thumbnail.dart` (poster is generated client-side at unknown size; not traced).
- Game cards inside the list (out of scope) and the Attune Assist bubble.
