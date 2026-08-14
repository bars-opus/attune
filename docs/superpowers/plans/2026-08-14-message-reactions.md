# Message Reactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let either partner react to any chat message with an emoji (a quick row of 6 plus a full picker), shown as a small pill overlapping the bubble's bottom-outer corner, picked from the existing focused-message-menu overlay, with a lightweight notification to the partner.

**Architecture:** A new `message_reactions` table (one row per `(message, user)`, upsert-on-repeat, RLS-visible to both relationship members) is written through a new `react_to_message` RPC (mirrors `pin_message`'s validation shape: active relationship, message exists and not deleted, belongs to this relationship). Reactions ride on `Message.reactions` (`Map<String, Set<String>>`, emoji → reactor user ids), hydrated in the repository's existing per-page batch fetch. `ChatController` patches the affected message in `state.messages` in place, matching `editMessage`/`deleteMessage`'s existing pattern. The focused action menu (`focused_action_menu.dart`) gains a new reaction row parameter, docked above the existing action list inside the same overlay. `MessageBubble` wraps `UniversalBubble` in a `Stack` to paint the reaction pill(s) without touching `UniversalBubble`'s internals (shared with `ForumPostBubble`, which does not get reactions). A new outbox row type + edge-function branch delivers the partner notification, following `message_notification_outbox`'s existing "new_message" pipeline shape.

**Tech Stack:** Flutter/Riverpod/Supabase (Postgres + RLS + Realtime + Edge Functions/Deno), `emoji_picker_flutter` (new dependency, pure Dart, no native code) for the full picker.

## Global Constraints

- One reaction per person per message — reacting again overwrites (upsert), never adds a second row. Enforced by `PRIMARY KEY (message_id, user_id)`.
- Either partner may react to any message, including their own.
- Quick row: ❤️ 👍 👎 😂 ‼️ ❓ (in that order) plus a "+" that opens `emoji_picker_flutter`.
- Same emoji from both partners collapses into ONE pill with a small ×2 badge — never two separate pills for the same emoji.
- Pill placement: overlapping the bubble's bottom-outer corner (opposite side from the bubble's own alignment corner is NOT required — bottom-outer means bottom-left for a partner bubble, bottom-right for your own, matching where WhatsApp/iMessage anchor it).
- `ForumPostBubble`/forums is explicitly OUT of scope — nothing about `UniversalBubble`'s own file changes, only `MessageBubble`'s wrapping.
- **Critical, session-learned lesson: `chatControllerProvider` is a Riverpod `.family<Conversation>` keyed by OBJECT IDENTITY** (`Conversation` has no `==` override). `_refreshConversation()` replaces `state.conversation` with a freshly-fetched, different-identity object almost immediately after the screen opens. Every new callsite that reads `chatControllerProvider(...)` inside `chat_screen.dart`'s `_MessageList` MUST key off the `conversation` field (sourced from `widget.conversation`), exactly like the existing `onStar`/`onPin`/`onEdit`/`onDelete` closures already do — NEVER `state.conversation`. This was a real, shipped bug fixed earlier in this same file; do not reintroduce it.
- Every repository write method that can be rejected server-side must propagate the exception uncaught (no silent `catch (_)`) — the UI layer (`chat_screen.dart`) is responsible for catching, logging via `debugPrint`, and showing a snackbar, matching the existing `onStar`/`onPin` pattern exactly.
- `dart analyze` must report zero new issues on every touched file after each task.
- `flutter test` must show zero new failures against the project's current baseline (13 pre-existing unrelated failures in intro/routing/settings/opinions tests + 2 in `chat_couples_locked_screen_healing_entry_test.dart` — confirm this exact count/set at Task 1 and re-confirm at the final task).

---

### Task 1: `message_reactions` table, RLS, and `react_to_message`/`remove_reaction` RPCs

**Files:**
- Create: `supabase/migrations/20260901130000_message_reactions.sql`

**Interfaces:**
- Produces: table `public.message_reactions(message_id uuid, relationship_id uuid, user_id uuid, emoji text, reacted_at timestamptz, PRIMARY KEY (message_id, user_id))`; RPC `react_to_message(p_relationship_id uuid, p_message_id uuid, p_emoji text) RETURNS void`; RPC `remove_reaction(p_message_id uuid) RETURNS void`.

This task has no Dart code — it is pure SQL, verified by applying it to the linked Supabase project and running manual RPC calls via the CLI. There is no local Postgres/Docker in this environment (confirmed earlier this session — `supabase db diff --linked` failed with "Cannot connect to the Docker daemon"), so verification is against the real linked project, the same way the `20260901120000_message_stars_upsert_grant.sql` fix was verified earlier in this session.

- [ ] **Step 1: Write the migration**

```sql
-- Message reactions: either partner may react to any message (including
-- their own) with one emoji at a time. Reacting again overwrites via
-- react_to_message's upsert — one row per (message, user), never two.
--
-- relationship_id is denormalized onto this table (not derivable-only via
-- a join through messages) for the same reason message_pins carries it
-- (20260831120000_message_actions.sql:142-143): it lets the realtime
-- channel filter Postgres changes on relationship_id directly, matching
-- the existing message_pins subscription in
-- SupabaseChatRepository._channelFor (supabase_chat_repository.dart:492).

CREATE TABLE IF NOT EXISTS public.message_reactions (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  reacted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_relationship
  ON public.message_reactions (relationship_id);

-- The PRIMARY KEY (message_id, user_id) already serves lookups by
-- message_id alone (it's the leading column), so no extra index is
-- needed there — matching message_stars' single index, not message_pins'
-- two (message_pins' PK leads with relationship_id, message_reactions'
-- leads with message_id).

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
-- Visible to BOTH relationship members (unlike message_stars, which is
-- owner-only) — you need to see your partner's reaction, not just your
-- own. Archived-chat guard matches message_pins_select exactly.
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = message_reactions.relationship_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
-- Only your OWN reaction may be removed (unlike message_pins, where
-- either partner may unpin) — matches message_stars_owner's "yours only"
-- shape for DELETE.
CREATE POLICY message_reactions_delete ON public.message_reactions
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- SELECT/DELETE only, no direct INSERT/UPDATE grant — reacting always
-- goes through react_to_message so the relationship-active and
-- message-not-deleted business rules are enforced server-side (same
-- rationale as message_pins' INSERT-only-via-RPC comment,
-- 20260831120000_message_actions.sql:187-188). Direct DELETE is safe to
-- grant broadly since the RLS policy above already restricts it to your
-- own row.
REVOKE ALL ON public.message_reactions FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.message_reactions TO authenticated;

CREATE OR REPLACE FUNCTION public.react_to_message(
  p_relationship_id uuid,
  p_message_id uuid,
  p_emoji text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_emoji IS NULL OR char_length(p_emoji) = 0 OR char_length(p_emoji) > 16 THEN
    RAISE EXCEPTION 'invalid_emoji' USING ERRCODE = '22023';
  END IF;

  -- Same "active, not archived" condition pin_message enforces
  -- (20260831120000_message_actions.sql:363-376): reacting is a write
  -- into a live conversation.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND (r.user_a = v_uid OR r.user_b = v_uid)
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- Message must exist, belong to this relationship, and not be
  -- tombstoned — matches pin_message's message check exactly
  -- (20260831120000_message_actions.sql:381-388).
  IF NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id
      AND m.relationship_id = p_relationship_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_reactable' USING ERRCODE = '42501';
  END IF;

  -- Upsert: one row per (message_id, user_id) — reacting again overwrites
  -- the emoji rather than erroring or adding a second row.
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES (p_message_id, p_relationship_id, v_uid, p_emoji)
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET emoji = EXCLUDED.emoji, reacted_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.react_to_message(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.react_to_message(uuid, uuid, text) TO authenticated;

-- remove_reaction is a thin RPC (not a direct DELETE from the client)
-- purely for symmetry/simplicity with react_to_message's call shape in
-- the repository — the RLS DELETE policy above already makes a direct
-- delete equally safe, but going through one RPC per mutation keeps the
-- repository's two methods structurally identical to
-- starMessage/unstarMessage's own pair.
CREATE OR REPLACE FUNCTION public.remove_reaction(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.message_reactions
  WHERE message_id = p_message_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_reaction(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_reaction(uuid) TO authenticated;
```

- [ ] **Step 2: Apply to the linked project**

Run: `npx supabase db push --linked`
Expected: prompts to apply `20260901130000_message_reactions.sql`, confirm, "Finished supabase db push."

- [ ] **Step 3: Verify via `npx supabase migration list --linked`**

Run: `npx supabase migration list --linked`
Expected: `20260901130000` appears with both a local and remote timestamp (applied).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260901130000_message_reactions.sql
git commit -m "feat(chat): add message_reactions table and react_to_message/remove_reaction RPCs"
```

---

### Task 2: `Message.reactions` field, repository methods, `_hydrateMessages` join

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`
- Test: `test/features/chat/domain/entities/message_reactions_test.dart` (new file)
- Test: `test/features/chat/support/chat_test_harness.dart` (extend `FakeChatRepository`)

**Interfaces:**
- Produces: `Message.reactions` field, type `Map<String, Set<String>>` (emoji → set of reactor user ids), default `const {}`. `ChatRepository.addReaction({required String relationshipId, required String messageId, required String emoji})` and `ChatRepository.removeReaction(String messageId)`, both `Future<void>`, both throwing uncaught on any rejection (no internal catch) — matches `starMessage`/`pinMessage`'s existing contract.
- Consumes: `SupabaseChatRepository._messageColumns`, `_hydrateMessages` (existing batch-hydration chokepoint at `supabase_chat_repository.dart:702`).

- [ ] **Step 1: Add `reactions` to `Message`**

In `lib/features/chat/domain/entities/message.dart`, add the field, constructor param, `copyWith` param, and `fromRow`/`optimistic`/`toJson`/`fromJson` wiring. `reactions` is intentionally NOT parsed inside `Message.fromRow` from the row map itself (unlike every other field) — it is populated by the repository AFTER `fromRow` runs, via `copyWith`, because it comes from a separate table joined in a batch, not a column on `messages`. `fromJson`/`toJson` DO serialize it (for the local cache round-trip, same as every other field) using a plain `Map<String, List<String>>` shape (JSON has no `Set`).

```dart
  final Map<String, Set<String>> reactions;
```

Add to the constructor:

```dart
    this.reactions = const {},
```

Add to `copyWith`'s parameter list and body:

```dart
    Map<String, Set<String>>? reactions,
```
```dart
      reactions: reactions ?? this.reactions,
```

Add to `toJson`:

```dart
      'reactions': reactions.map((emoji, ids) => MapEntry(emoji, ids.toList())),
```

Add to `fromJson`:

```dart
      reactions: (json['reactions'] as Map<String, dynamic>?)?.map(
            (emoji, ids) => MapEntry(
              emoji,
              (ids as List<dynamic>).map((e) => e as String).toSet(),
            ),
          ) ??
          const {},
```

Do NOT add anything to `Message.fromRow` or `Message.optimistic` — a freshly-sent/loaded-from-row message always starts with `reactions: const {}` (the constructor default), matching how `Message.fromRow` never reads star/pin state either (that also lives in a separate table, joined separately).

- [ ] **Step 2: Write the failing test for `Message.reactions`**

```dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message baseMessage() => Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hello',
        createdAt: DateTime(2026, 1, 1),
        status: MessageStatus.sent,
        isMine: true,
      );

  test('reactions defaults to empty', () {
    expect(baseMessage().reactions, isEmpty);
  });

  test('copyWith replaces reactions wholesale', () {
    final withReaction = baseMessage().copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
      },
    );
    expect(withReaction.reactions['❤️'], {'u1', 'u2'});
  });

  test('toJson/fromJson round-trips reactions', () {
    final withReaction = baseMessage().copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
        '👍': {'u1'},
      },
    );
    final restored = Message.fromJson(withReaction.toJson());
    expect(restored.reactions['❤️'], {'u1', 'u2'});
    expect(restored.reactions['👍'], {'u1'});
  });

  test('fromJson defaults reactions to empty when the key is absent', () {
    final json = baseMessage().toJson()..remove('reactions');
    final restored = Message.fromJson(json);
    expect(restored.reactions, isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/chat/domain/entities/message_reactions_test.dart`
Expected: FAIL — `reactions` is not a defined getter on `Message`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/domain/entities/message_reactions_test.dart`
Expected: PASS — 4 tests green.

- [ ] **Step 5: Add repository interface methods**

In `lib/features/chat/data/repositories/chat_repository.dart`, add near `starMessage`/`unstarMessage` (after the `getPinnedMessages` doc block, before `createRelationshipAvatarUploadIntent`):

```dart
  /// Reacts to [messageId] with [emoji] (server enforces active
  /// relationship + message-not-deleted — see react_to_message RPC).
  /// Reacting again with a different emoji overwrites the caller's prior
  /// reaction on this message; it never adds a second row. Throws on any
  /// rejection.
  Future<void> addReaction({
    required String relationshipId,
    required String messageId,
    required String emoji,
  });

  /// Removes the caller's own reaction from [messageId], if any. A no-op
  /// (does not throw) if the caller had no reaction on this message.
  Future<void> removeReaction(String messageId);
```

- [ ] **Step 6: Implement in `SupabaseChatRepository`**

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`, add after `unpinMessage` (before the closing `}` of the class, matching the existing method ordering — reactions come after pins, same as pins came after stars):

```dart
  @override
  Future<void> addReaction({
    required String relationshipId,
    required String messageId,
    required String emoji,
  }) async {
    await _supabase.rpc(
      'react_to_message',
      params: {
        'p_relationship_id': relationshipId,
        'p_message_id': messageId,
        'p_emoji': emoji,
      },
    );
  }

  @override
  Future<void> removeReaction(String messageId) async {
    await _supabase.rpc(
      'remove_reaction',
      params: {'p_message_id': messageId},
    );
  }
```

- [ ] **Step 7: Wire the reactions join into `_hydrateMessages`**

`_hydrateMessages` (`supabase_chat_repository.dart:702`) currently maps rows one at a time via `Future.wait`, resolving signed image URLs per row. Reactions need a SEPARATE batch query (one `IN` query for the whole page, not one query per row) because `message_reactions` is a different table with no join clause available on the plain `messages` select used by `getMessages`/`getMessagesAfter`. Replace the method body:

```dart
  Future<List<Message>> _hydrateMessages(
    List<Map<String, dynamic>> rows,
    String currentUserId,
  ) async {
    final messageIds = rows.map((row) => row['id'] as String).toList();
    final reactionsByMessageId = await _fetchReactionsFor(messageIds);

    return Future.wait(
      rows.map((row) async {
        var base = Message.fromRow(row, currentUserId: currentUserId);
        final reactions = reactionsByMessageId[base.id];
        if (reactions != null) {
          base = base.copyWith(reactions: reactions);
        }
        if (base.mediaKey == null || base.mediaType != 'image') {
          return base;
        }
        final signedUrl = await createSignedMediaUrl(
          base.mediaThumbnailKey ?? base.mediaKey!,
        );
        return base.copyWith(signedMediaUrl: signedUrl);
      }),
    );
  }

  /// Batch-fetches reactions for a page of messages in ONE query (an `IN`
  /// filter over [messageIds]) rather than one query per message — a page
  /// is capped at chatConfigProvider's messagePageSize (50 by default), so
  /// this is a single round trip per page, not N.
  Future<Map<String, Map<String, Set<String>>>> _fetchReactionsFor(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return const {};

    final rows = await _supabase
        .from('message_reactions')
        .select('message_id,user_id,emoji')
        .inFilter('message_id', messageIds);

    final result = <String, Map<String, Set<String>>>{};
    for (final row in rows) {
      final messageId = row['message_id'] as String;
      final userId = row['user_id'] as String;
      final emoji = row['emoji'] as String;
      final byEmoji = result.putIfAbsent(messageId, () => {});
      byEmoji.putIfAbsent(emoji, () => {}).add(userId);
    }
    return result;
  }
```

- [ ] **Step 8: Extend `FakeChatRepository` for tests**

In `test/features/chat/support/chat_test_harness.dart`, add reaction storage and the two new methods. Add near the existing `starredMessageIds`/`pinnedMessageIds` fields:

```dart
  /// messageId -> (userId -> emoji). Mirrors the real schema's
  /// PRIMARY KEY (message_id, user_id) shape: at most one emoji per user
  /// per message.
  final Map<String, Map<String, String>> reactionsByMessage = {};
```

Add near `starMessage`/`unstarMessage`:

```dart
  @override
  Future<void> addReaction({
    required String relationshipId,
    required String messageId,
    required String emoji,
  }) async {
    final byUser = reactionsByMessage.putIfAbsent(messageId, () => {});
    byUser[currentUserId] = emoji;
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        reactions: _reactionsMapFor(messageId),
      );
    }
  }

  @override
  Future<void> removeReaction(String messageId) async {
    reactionsByMessage[messageId]?.remove(currentUserId);
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        reactions: _reactionsMapFor(messageId),
      );
    }
  }

  Map<String, Set<String>> _reactionsMapFor(String messageId) {
    final byUser = reactionsByMessage[messageId] ?? const {};
    final byEmoji = <String, Set<String>>{};
    for (final entry in byUser.entries) {
      byEmoji.putIfAbsent(entry.value, () => {}).add(entry.key);
    }
    return byEmoji;
  }
```

- [ ] **Step 9: Subscribe the realtime channel to `message_reactions` changes**

Without this step, a partner's reaction never syncs live — `_MessageList`'s existing refresh only fires on `messages`/`relationships`/`message_pins` Postgres changes (`supabase_chat_repository.dart`'s `_channelFor`, `.onPostgresChanges` calls). Task 1's migration denormalized `relationship_id` onto `message_reactions` specifically so this same filter shape applies. In `lib/features/chat/data/repositories/supabase_chat_repository.dart`, inside `_channelFor`, add a new `.onPostgresChanges(...)` call to the existing builder chain, immediately after the existing `message_pins` one (same file, same method — do not create a second channel):

```dart
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'relationship_id',
            value: relationshipId,
          ),
          callback: (_) => events.add(null),
        )
```

This feeds into the SAME `events` stream `watchConversationEvents` already returns, so `ChatController._subscribeToRealtime`'s existing debounced handler (`chat_state.dart:213-244`, which already calls `loadMessages(silent: true)` on any event) picks up reaction changes automatically — no changes needed in `chat_state.dart` for this. `loadMessages(silent: true)` re-fetches the visible window through `_hydrateMessages` (Step 7 of this task), which re-joins reactions, so the partner's pill appears within one debounce window (`chatConfigProvider().realtimeRefreshDebounce`, 250ms by default) of them reacting — no app restart needed.

- [ ] **Step 10: Run tests to verify no regression**

Run: `flutter test test/features/chat/domain/entities/message_reactions_test.dart test/features/chat/chat_controller_test.dart`
Expected: all PASS — the harness change must not break any existing test that constructs `FakeChatRepository`.

Run: `dart analyze lib/features/chat/domain/entities/message.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/features/chat/support/chat_test_harness.dart`
Expected: `No issues found!`

- [ ] **Step 11: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/features/chat/domain/entities/message_reactions_test.dart test/features/chat/support/chat_test_harness.dart
git commit -m "feat(chat): add Message.reactions, addReaction/removeReaction repository methods"
```

---

### Task 3: `ChatController.reactToMessage`/`removeReactionFrom` — in-place state patch

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart`
- Test: `test/features/chat/chat_controller_test.dart`

**Interfaces:**
- Consumes: `Message.reactions` (Task 2), `ChatRepository.addReaction`/`removeReaction` (Task 2).
- Produces: `ChatController.reactToMessage(Message message, String emoji)` and `ChatController.removeReactionFrom(Message message)`, both `Future<void>`, both patching `state.messages` in place — same shape as `editMessage`/`deleteMessage` (`chat_state.dart:554-583`).

- [ ] **Step 1: Write the failing test**

Find `ChatController`'s test setup pattern first by reading the existing star/pin tests in `test/features/chat/chat_controller_test.dart`, then add tests following that exact setup shape (container via `buildChatContainer`, `FakeChatRepository`, `container.read(chatControllerProvider(conversation).notifier)`):

```dart
  test('reactToMessage patches the message in state with the new reaction', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final conversation = activeConversation('rel-1');
    repo.conversationOverride = conversation;
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final notifier = container.read(chatControllerProvider(conversation).notifier);
    await notifier.loadMessages();

    final message = container.read(chatControllerProvider(conversation)).messages.first;
    await notifier.reactToMessage(message, '❤️');

    final updated = container.read(chatControllerProvider(conversation)).messages.first;
    expect(updated.reactions['❤️'], contains('user-a'));
  });

  test('removeReactionFrom clears the caller\'s reaction from state', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final conversation = activeConversation('rel-1');
    repo.conversationOverride = conversation;
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final notifier = container.read(chatControllerProvider(conversation).notifier);
    await notifier.loadMessages();

    final message = container.read(chatControllerProvider(conversation)).messages.first;
    await notifier.reactToMessage(message, '👍');
    final reacted = container.read(chatControllerProvider(conversation)).messages.first;
    await notifier.removeReactionFrom(reacted);

    final cleared = container.read(chatControllerProvider(conversation)).messages.first;
    expect(cleared.reactions['👍'] ?? {}, isNot(contains('user-a')));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_controller_test.dart --plain-name "reactToMessage patches"`
Expected: FAIL — `reactToMessage` is not defined on `ChatController`.

- [ ] **Step 3: Implement `reactToMessage`/`removeReactionFrom`**

In `lib/features/chat/presentation/state/chat_state.dart`, add immediately after `unpinMessage` (`chat_state.dart:614-623`), following `editMessage`'s exact in-place-patch shape:

```dart
  Future<void> reactToMessage(Message message, String emoji) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await _repository.addReaction(
      relationshipId: message.relationshipId,
      messageId: message.id,
      emoji: emoji,
    );
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map((entry) => entry.id == message.id
              ? entry.copyWith(reactions: _withReaction(entry.reactions, user.id, emoji))
              : entry)
          .toList(),
    );
  }

  Future<void> removeReactionFrom(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await _repository.removeReaction(message.id);
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map((entry) => entry.id == message.id
              ? entry.copyWith(reactions: _withoutReaction(entry.reactions, user.id))
              : entry)
          .toList(),
    );
  }

  /// Removes [userId] from every emoji bucket first (a reaction is
  /// one-per-user, so switching emoji must clear the old bucket, not just
  /// add to the new one), then adds it to [emoji]'s bucket. Empty buckets
  /// are dropped so a pill never renders with a zero count.
  Map<String, Set<String>> _withReaction(
    Map<String, Set<String>> reactions,
    String userId,
    String emoji,
  ) {
    final next = _withoutReaction(reactions, userId);
    final updated = Map<String, Set<String>>.from(next);
    updated[emoji] = {...(updated[emoji] ?? {}), userId};
    return updated;
  }

  Map<String, Set<String>> _withoutReaction(
    Map<String, Set<String>> reactions,
    String userId,
  ) {
    final updated = <String, Set<String>>{};
    for (final entry in reactions.entries) {
      final without = entry.value.where((id) => id != userId).toSet();
      if (without.isNotEmpty) updated[entry.key] = without;
    }
    return updated;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_controller_test.dart`
Expected: all PASS, including the 2 new tests.

- [ ] **Step 5: `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/state/chat_state.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart test/features/chat/chat_controller_test.dart
git commit -m "feat(chat): add ChatController.reactToMessage/removeReactionFrom"
```

---

### Task 4: `emoji_picker_flutter` dependency + reaction row in `focused_action_menu.dart`

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/widgets/focused_action_menu.dart`
- Test: `test/core/widgets/focused_action_menu_test.dart`

**Interfaces:**
- Produces: `showFocusedActionMenu`'s signature gains one new required parameter: `required List<ReactionQuickOption> quickReactions` and `required void Function(String emoji) onReact` — a new public class `ReactionQuickOption` (a single `emoji` field; no selected-state tracking is built in this plan, see Task 4 Step 4's implementation for the exact shape) lives in this same file. `showFocusedActionMenu` ALSO needs a way to open the full picker — add `required VoidCallback onOpenFullPicker`.
- Consumes: `emoji_picker_flutter` package (added this task).

This task builds the reaction ROW inside the overlay only — wiring it to real `reactToMessage`/`removeReactionFrom` calls and opening the actual `emoji_picker_flutter` sheet happens in Task 5, where `MessageBubble`/`chat_screen.dart` supply real callbacks. This task's own test uses fake callbacks (`VoidCallback`/recorded calls), same as `focused_action_menu_test.dart`'s existing tests use fake `actions`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add emoji_picker_flutter` — this resolves and pins the actual current published version automatically (do NOT hand-write a version constraint into `pubspec.yaml`; the version above is illustrative only and may not match what's actually published by the time this task runs).
Expected: `pubspec.yaml` gains an `emoji_picker_flutter: ^X.Y.Z` line under `dependencies:` with whatever version `pub` resolved, `pubspec.lock` updates, command exits 0.

If `flutter pub add` reports a version conflict against this project's other dependencies, stop and report it rather than forcing a resolution — this is exactly the kind of `BLOCKED` case the fix-loop process exists for.

- [ ] **Step 2: Write the failing test for the reaction row**

Read `test/core/widgets/focused_action_menu_test.dart` first to match its existing `showFocusedActionMenu` call shape exactly (it currently passes `context`, `anchorRect`, `anchorSnapshot`, `actions` — every existing test in this file needs its call site updated to also pass the three new required params, or the file will not compile). Add these new params to EVERY existing `showFocusedActionMenu(...)` call in this test file:

```dart
                quickReactions: const [],
                onReact: (_) {},
                onOpenFullPicker: () {},
```

Then add a new test:

```dart
  testWidgets('tapping a quick reaction calls onReact with that emoji and dismisses',
      (tester) async {
    String? reacted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [
                  ReactionQuickOption(emoji: '❤️'),
                  ReactionQuickOption(emoji: '👍'),
                ],
                onReact: (emoji) => reacted = emoji,
                onOpenFullPicker: () {},
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(reacted, '❤️');
    // Dismissed: the action list from this call is no longer in the tree.
    expect(find.text('Action A'), findsNothing);
  });

  testWidgets('tapping the "+" calls onOpenFullPicker and dismisses',
      (tester) async {
    var openedPicker = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFocusedActionMenu(
                context: context,
                anchorRect: const Rect.fromLTWH(20, 100, 200, 60),
                anchorSnapshot: const Text('bubble snapshot'),
                actions: [ListTile(title: const Text('Action A'), onTap: () {})],
                quickReactions: const [ReactionQuickOption(emoji: '❤️')],
                onReact: (_) {},
                onOpenFullPicker: () => openedPicker = true,
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(openedPicker, isTrue);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/widgets/focused_action_menu_test.dart`
Expected: FAIL to compile — `quickReactions`/`onReact`/`onOpenFullPicker`/`ReactionQuickOption` don't exist yet.

- [ ] **Step 4: Implement the reaction row**

In `lib/core/widgets/focused_action_menu.dart`, add the new public class near the top (after the imports, before `showFocusedActionMenu`):

```dart
/// One emoji in the focused menu's quick-reaction row.
class ReactionQuickOption {
  const ReactionQuickOption({required this.emoji});
  final String emoji;
}
```

Change `showFocusedActionMenu`'s signature to add the three new required params:

```dart
Future<void> showFocusedActionMenu({
  required BuildContext context,
  required Rect anchorRect,
  required Widget anchorSnapshot,
  required List<Widget> actions,
  required List<ReactionQuickOption> quickReactions,
  required void Function(String emoji) onReact,
  required VoidCallback onOpenFullPicker,
}) {
```

Pass them through to `_FocusedActionMenuOverlay`:

```dart
      return _FocusedActionMenuOverlay(
        anchorRect: anchorRect,
        anchorSnapshot: anchorSnapshot,
        actions: actions,
        quickReactions: quickReactions,
        onReact: onReact,
        onOpenFullPicker: onOpenFullPicker,
        animation: animation,
      );
```

Update `_FocusedActionMenuOverlay`'s constructor and fields:

```dart
class _FocusedActionMenuOverlay extends StatelessWidget {
  const _FocusedActionMenuOverlay({
    required this.anchorRect,
    required this.anchorSnapshot,
    required this.actions,
    required this.quickReactions,
    required this.onReact,
    required this.onOpenFullPicker,
    required this.animation,
  });

  final Rect anchorRect;
  final Widget anchorSnapshot;
  final List<Widget> actions;
  final List<ReactionQuickOption> quickReactions;
  final void Function(String emoji) onReact;
  final VoidCallback onOpenFullPicker;
  final Animation<double> animation;
```

The reaction row needs its own estimated height added to the flip-above/below math (`_estimatedItemHeight`/`estimatedMenuHeight` at the top of `build()`), since it now sits ABOVE the action list and adds real height to what must fit on screen:

```dart
  static const double _reactionRowHeight = 48;
```

In `build()`, change:

```dart
    final estimatedMenuHeight = actions.length * _estimatedItemHeight;
```
to:

```dart
    final estimatedMenuHeight =
        actions.length * _estimatedItemHeight + _reactionRowHeight + _gap;
```

Build the reaction row widget as a local inside `build()`, right before the `return GestureDetector(...)`:

```dart
    final reactionRow = Material(
      borderRadius: BorderRadius.circular(24),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in quickReactions)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onReact(option.emoji);
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(option.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                onOpenFullPicker();
              },
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
```

Note this uses `Navigator.of(context)` where `context` is `_FocusedActionMenuOverlay.build`'s OWN context (the dialog route's context, obtained fresh in that build call) — NOT a context captured from outside the overlay. This is safe for the same reason the outer scrim's `onTap: () => Navigator.of(context).pop()` (a few lines below, already in this file) is safe: it is read fresh inside this widget's own `build()`, which only runs while this route is live. This differs from `message_actions_sheet.dart`'s `Builder`-per-tile pattern, which exists specifically because THAT file's context comes from `MessageBubble`'s call site outside the dialog route — not the case here.

Now dock `reactionRow` above the action list. Find the existing menu `Positioned` block (the one with `left: clampedLeft, top: fitsBelow ? ... , child: FadeTransition(...)`) and wrap its child in a `Column` with the reaction row first:

```dart
              Positioned(
                left: clampedLeft,
                top: fitsBelow ? anchorRect.bottom + _gap : null,
                bottom: fitsBelow
                    ? null
                    : screenSize.height - anchorRect.top + _gap,
                child: FadeTransition(
                  opacity: animation,
                  child: GestureDetector(
                    onTap: () {},
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        reactionRow,
                        const SizedBox(height: _gap),
                        Material(
                          borderRadius: BorderRadius.circular(14),
                          elevation: 8,
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: menuWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
```

This replaces the PREVIOUS single `Material(...)` child of that `GestureDetector` — the reaction row `Material` and the actions-list `Material` are now two separate elevated cards stacked in a `Column`, matching iMessage's own two-tier layout (reaction row on top, action list below).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/focused_action_menu_test.dart`
Expected: all PASS, including the 2 new tests and every pre-existing test (now compiling with the 3 added params).

- [ ] **Step 6: `dart analyze`**

Run: `dart analyze lib/core/widgets/focused_action_menu.dart test/core/widgets/focused_action_menu_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/widgets/focused_action_menu.dart test/core/widgets/focused_action_menu_test.dart
git commit -m "feat(chat): add quick-reaction row to the focused action menu overlay"
```

---

### Task 5: Wire `MessageBubble` — real reaction callbacks, bubble pill(s), full picker sheet

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Test: `test/features/chat/presentation/widgets/message_bubble_test.dart`

**Interfaces:**
- Consumes: `showFocusedActionMenu`'s new `quickReactions`/`onReact`/`onOpenFullPicker` params (Task 4), `Message.reactions` (Task 2).
- Produces: `MessageBubble` gains new params `currentUserId` (already exists), `onReact: void Function(String emoji)?`, `onRemoveReaction: VoidCallback?` — both nullable, null disables the affordance, matching this file's established null-disables-gesture convention (`onReply`/`onLongPress` already work this way).

This task does NOT touch `chat_screen.dart` yet — `MessageBubble` gains the capability and renders correctly when driven by fake callbacks in its own widget test, exactly like `onStar`/`onCopy` etc. were built in the original message-actions-sheet feature before `chat_screen.dart` wired them to the real controller in a later task.

- [ ] **Step 1: Write the failing test for the reaction pill**

Read the existing `message_bubble_test.dart` tests for the isStarred-icon pattern added earlier this session (search for `'shows a star icon'`) to match its exact `pumpWidget`/`Message.fromRow` setup shape. Add:

```dart
  testWidgets('shows a reaction pill with the emoji and count when the message has reactions',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-react',
        'client_message_id': 'c-react',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    ).copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows one pill per distinct emoji, no count badge when only one reactor',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-react2',
        'client_message_id': 'c-react2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    ).copyWith(
      reactions: {
        '❤️': {'u1'},
        '👍': {'u2'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('no reaction pill renders when the message has no reactions',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-noreact',
        'client_message_id': 'c-noreact',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.textContaining('❤'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/presentation/widgets/message_bubble_test.dart --plain-name "reaction pill"`
Expected: FAIL — no reaction pill renders anywhere yet.

- [ ] **Step 3: Add `onReact`/`onRemoveReaction` params and the pill Stack**

In `lib/features/chat/presentation/widgets/message_bubble.dart`, add to the constructor and fields (near `onStar`/`onUnstar`):

```dart
    this.onReact,
    this.onRemoveReaction,
```
```dart
  final void Function(String emoji)? onReact;
  final VoidCallback? onRemoveReaction;
```

Wire the quick-reaction row and full-picker callback into the existing `showFocusedActionMenu` call inside `onLongPress`:

```dart
      onLongPress: canOpenActions
          ? (bubbleRect, bubbleSnapshot) => showFocusedActionMenu(
                context: context,
                anchorRect: bubbleRect,
                anchorSnapshot: bubbleSnapshot,
                quickReactions: const [
                  ReactionQuickOption(emoji: '❤️'),
                  ReactionQuickOption(emoji: '👍'),
                  ReactionQuickOption(emoji: '👎'),
                  ReactionQuickOption(emoji: '😂'),
                  ReactionQuickOption(emoji: '‼️'),
                  ReactionQuickOption(emoji: '❓'),
                ],
                onReact: (emoji) => onReact?.call(emoji),
                onOpenFullPicker: () => _openFullEmojiPicker(context, onReact),
                actions: buildMessageActionItems(
```

(The rest of the `actions: buildMessageActionItems(...)` call is UNCHANGED — only the three new named args are added above it, and the trailing `)` that used to close `showFocusedActionMenu(` directly after `actions: ...)` now needs the extra params accounted for; keep the existing `actions:` block exactly as-is. `onReact` inside the `_openFullEmojiPicker(context, onReact)` call refers to `MessageBubble.onReact`, the widget's own field, in scope inside `build()`.)

Now build the pill row and wrap `UniversalBubble` in a `Stack`. Read the current full `build()` method first (it currently `return`s `UniversalBubble(...)` directly) and change the return statement's shape from `return UniversalBubble(...)` to:

```dart
    final reactionPills = _buildReactionPills(context, message);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        UniversalBubble(
          // ...every existing named argument, UNCHANGED...
        ),
        if (reactionPills != null)
          Positioned(
            bottom: -10,
            left: isMine ? null : 12,
            right: isMine ? 12 : null,
            child: reactionPills,
          ),
      ],
    );
```

Add the pill-building helper as a private top-level function:

```dart
/// One small pill per distinct emoji on [message], or null if there are
/// none. Same emoji from multiple reactors collapses into ONE pill with a
/// small count badge (never multiple pills for the same emoji). Display
/// only — tapping a pill to toggle your own reaction is explicitly out of
/// scope for this plan (see Task 6's manual smoke-test note).
Widget? _buildReactionPills(BuildContext context, Message message) {
  if (message.reactions.isEmpty) return null;
  final colorScheme = Theme.of(context).colorScheme;

  return Wrap(
    spacing: 4,
    children: [
      for (final entry in message.reactions.entries)
        if (entry.value.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                if (entry.value.length > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${entry.value.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
    ],
  );
}
```

- [ ] **Step 4: Wire the real `emoji_picker_flutter` sheet**

Add the import at the top of the file:

```dart
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
```

Add `_openFullEmojiPicker`, the full-picker sheet (not a method on `MessageBubble`, since it needs no widget state — mirrors `_showEditDialog`'s free-function shape in `chat_screen.dart`):

```dart
void _openFullEmojiPicker(BuildContext context, void Function(String emoji)? onReact) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onReact?.call(emoji.emoji);
          Navigator.of(sheetContext).pop();
        },
      ),
    ),
  );
}
```

Update the call site from Step 3 to pass `onReact` through:

```dart
                onOpenFullPicker: () => _openFullEmojiPicker(context, onReact),
```

(`onReact` here refers to `MessageBubble.onReact`, the widget's own field, in scope inside `build()`.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/chat/presentation/widgets/message_bubble_test.dart`
Expected: all PASS, including the 3 new tests and every pre-existing test in this file (the `Stack` wrapping must not change any existing assertion's `find` results — `UniversalBubble` is still in the tree, just no longer the direct return value).

- [ ] **Step 6: `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/presentation/widgets/message_bubble_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/presentation/widgets/message_bubble_test.dart
git commit -m "feat(chat): wire reaction picking and pill display into MessageBubble"
```

---

### Task 6: Wire `chat_screen.dart` — real `onReact`/`onRemoveReaction` handlers

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Test: `test/features/chat/chat_screen_message_actions_test.dart`

**Interfaces:**
- Consumes: `MessageBubble.onReact`/`onRemoveReaction` (Task 5), `ChatController.reactToMessage`/`removeReactionFrom` (Task 3).

**CRITICAL — read the Global Constraints section's `chatControllerProvider` identity warning before starting this task.** The closure you write here MUST key `chatControllerProvider(...)` off the `conversation` field already present on `_MessageList` (added in an earlier, already-shipped fix to this exact file) — NEVER `state.conversation`. Every other action handler in this same `MessageBubble(...)` construction (`onStar`, `onUnstar`, `onPin`, `onUnpin`) already does this correctly; copy their exact shape.

- [ ] **Step 1: Write the failing test**

Read `test/features/chat/chat_screen_message_actions_test.dart`'s existing `'Star from the sheet reaches the repository'` test for the setup pattern (it uses `pumpChat`, long-presses a bubble, taps the sheet). This feature's picking UI is different (a reaction ROW inside the same overlay, not a `ListTile`), so the tap target is the emoji glyph itself, not `find.text('Star')`. Add:

```dart
  testWidgets('tapping a quick reaction in the focused menu reaches the repository', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(repo.reactionsByMessage['m1']?['user-a'], '❤️');
    await tearDownChat(tester, container);
  });

  testWidgets('reacted message shows the pill immediately (no restart needed)', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(find.text('👍'), findsOneWidget);
    await tearDownChat(tester, container);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_screen_message_actions_test.dart --plain-name "quick reaction"`
Expected: FAIL — no `onReact` wired yet, so nothing calls the repository and no pill renders.

- [ ] **Step 3: Wire `onReact`/`onRemoveReaction` in `_MessageList`**

In `lib/features/chat/presentation/screens/chat_screen.dart`, inside `_MessageList.build`'s `MessageBubble(...)` construction (the same block containing `onStar`/`onUnstar`/`onPin`/`onUnpin`), add two new named arguments following those four's EXACT shape (same `try`/`catch`/`debugPrint`/`context.showErrorSnackbar` pattern, same `chatControllerProvider(conversation)` — NOT `state.conversation` — keying):

```dart
            onReact: (emoji) async {
              try {
                await ref
                    .read(chatControllerProvider(conversation).notifier)
                    .reactToMessage(message, emoji);
              } catch (e, st) {
                debugPrint('reactToMessage failed: $e\n$st');
                if (context.mounted) {
                  context.showErrorSnackbar("Couldn't react — try again.");
                }
              }
            },
            onRemoveReaction: () async {
              try {
                await ref
                    .read(chatControllerProvider(conversation).notifier)
                    .removeReactionFrom(message);
              } catch (e, st) {
                debugPrint('removeReactionFrom failed: $e\n$st');
                if (context.mounted) {
                  context.showErrorSnackbar("Couldn't remove reaction — try again.");
                }
              }
            },
```

Place these two new arguments immediately after `onUnpin:` and before `onEdit:` in the existing `MessageBubble(...)` call, matching this file's existing action-then-edit/delete ordering.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/chat_screen_message_actions_test.dart`
Expected: all PASS, including the 2 new tests and every pre-existing test in this file (7 prior + 2 new = 9).

- [ ] **Step 5: `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/chat_screen_message_actions_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Full chat suite regression check**

Run: `flutter test test/features/chat/ test/features/forums/ test/core/widgets/`
Expected: same 2 pre-existing failures as the project baseline (`chat_couples_locked_screen_healing_entry_test.dart`), zero new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/chat_screen_message_actions_test.dart
git commit -m "feat(chat): wire message reactions into ChatScreen's message list"
```

---

### Task 7: Notification outbox extension — `message_reaction` type

**Files:**
- Create: `supabase/migrations/20260901140000_message_reaction_notifications.sql`
- Modify: `supabase/functions/process-chat-notification-outbox/index.ts`

**Interfaces:**
- Produces: `message_notification_outbox.notification_type` CHECK extended to allow `'message_reaction'`; new columns `reaction_emoji text` and `reactor_id uuid` (nullable, only populated for reaction-type rows); a new trigger `enqueue_reaction_notification` on `message_reactions` AFTER INSERT OR UPDATE.

This task has no Dart code — pure SQL + a Deno edge function change, verified against the linked project the same way Task 1 was.

- [ ] **Step 1: Write the migration**

```sql
-- Extends the existing message_notification_outbox pipeline
-- (20260705120000_chat_system_v1_2.sql) to also carry reaction
-- notifications, alongside the existing 'new_message' type.

ALTER TABLE public.message_notification_outbox
  DROP CONSTRAINT IF EXISTS message_notification_outbox_notification_type_check;

ALTER TABLE public.message_notification_outbox
  ADD CONSTRAINT message_notification_outbox_notification_type_check
  CHECK (notification_type IN ('new_message', 'message_reaction'));

-- Only meaningful for notification_type = 'message_reaction' — NULL for
-- 'new_message' rows, which don't need them (the message content itself
-- carries the notification body via previewBody() in the edge function).
ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS reaction_emoji text;
ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS reactor_id uuid REFERENCES public.users(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.enqueue_reaction_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_recipient_id uuid;
BEGIN
  SELECT * INTO v_message FROM public.messages WHERE id = NEW.message_id;
  IF NOT FOUND OR v_message.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Notify the MESSAGE'S SENDER (whoever wrote the message being reacted
  -- to), not "the other relationship member" generically — if you react
  -- to your OWN message, sender_id = NEW.user_id and there is nothing to
  -- notify (self-notification is meaningless and would leak your own
  -- action back to yourself as a push).
  v_recipient_id := v_message.sender_id;
  IF v_recipient_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Same UNIQUE-conflict-do-nothing shape as
  -- enqueue_message_downstream_work's message_notification_outbox insert
  -- (20260705120000_chat_system_v1_2.sql:211-223) — a rapid re-react
  -- (emoji A then emoji B within the same debounce window) collapses to
  -- one outbox row via the UPDATE below rather than piling up duplicates,
  -- since (recipient_id, message_id, notification_type) is UNIQUE and
  -- covers 'message_reaction' rows exactly as it already covers
  -- 'new_message' rows.
  INSERT INTO public.message_notification_outbox (
    message_id, relationship_id, recipient_id, sender_id,
    notification_type, reaction_emoji, reactor_id
  )
  VALUES (
    NEW.message_id, NEW.relationship_id, v_recipient_id, NEW.user_id,
    'message_reaction', NEW.emoji, NEW.user_id
  )
  ON CONFLICT (recipient_id, message_id, notification_type)
  DO UPDATE SET
    reaction_emoji = EXCLUDED.reaction_emoji,
    reactor_id = EXCLUDED.reactor_id,
    state = 'pending',
    attempts = 0,
    created_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enqueue_reaction_notification_trigger ON public.message_reactions;
CREATE TRIGGER enqueue_reaction_notification_trigger
AFTER INSERT OR UPDATE ON public.message_reactions
FOR EACH ROW EXECUTE FUNCTION public.enqueue_reaction_notification();
```

- [ ] **Step 2: Apply to the linked project**

Run: `npx supabase db push --linked`
Expected: prompts to apply `20260901140000_message_reaction_notifications.sql`, confirm, "Finished supabase db push."

- [ ] **Step 3: Verify the CHECK constraint and trigger exist**

Run: `npx supabase migration list --linked`
Expected: `20260901140000` appears applied both locally and remotely.

- [ ] **Step 4: Extend the edge function**

In `supabase/functions/process-chat-notification-outbox/index.ts`, add new constants near the top:

```typescript
const REACTION_PUSH_TITLE = "New reaction";
```

In `processJob`, after the existing `const relationship = unwrapRelationship(...)` line and its existing suppression check block (lines ~131-149 in the current file), branch the title/body construction on `job.notification_type`. Find the existing:

```typescript
    const previewEnabled = settings?.chat_message_preview_enabled === true;
    const title = CHAT_PUSH_TITLE;
    const body = previewEnabled ? previewBody(message) : CHAT_PUSH_BODY;
```

Replace with:

```typescript
    const isReaction = job.notification_type === "message_reaction";
    const previewEnabled = settings?.chat_message_preview_enabled === true;
    const title = isReaction ? REACTION_PUSH_TITLE : CHAT_PUSH_TITLE;
    const body = isReaction
      ? reactionBody(job, previewEnabled ? previewBody(message) : null)
      : (previewEnabled ? previewBody(message) : CHAT_PUSH_BODY);
```

Find the two places `type: "new_message"` appears (the `in_app_notifications` insert and the `scheduled_notifications` insert, both in the existing `processJob` body) and change each to:

```typescript
        type: isReaction ? "message_reaction" : "new_message",
```

Add the new formatting helper near `previewBody`:

```typescript
function reactionBody(job: Record<string, unknown>, messagePreview: string | null) {
  const emoji = typeof job.reaction_emoji === "string" ? job.reaction_emoji : "❤️";
  if (messagePreview) {
    return `${emoji} reacted to "${messagePreview.slice(0, 60)}"`;
  }
  return `${emoji} reacted to your message`;
}
```

- [ ] **Step 5: Verify the edge function still type-checks**

Run: `cd supabase/functions/process-chat-notification-outbox && deno check index.ts`
(If `deno` is not available locally, skip this step and rely on the deployed function's own error surface — note this explicitly in the task report rather than silently skipping.)
Expected: no type errors.

- [ ] **Step 6: Deploy the updated function**

Run: `npx supabase functions deploy process-chat-notification-outbox`
Expected: deploys successfully.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260901140000_message_reaction_notifications.sql supabase/functions/process-chat-notification-outbox/index.ts
git commit -m "feat(chat): notify on message reactions via the existing outbox pipeline"
```

---

### Task 8: Full regression pass + Algorithm Quality Review Checklist verification

**Files:** None modified — verification only.

**Interfaces:** None — this task consumes everything from Tasks 1-7 and verifies the whole feature together.

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: same failure count/set as this branch's documented baseline (13 pre-existing unrelated intro/routing/settings/opinions failures + 2 `chat_couples_locked_screen_healing_entry_test.dart` failures), zero new failures anywhere, including every reaction-specific test added across Tasks 2-6.

- [ ] **Step 2: Full analyzer pass**

Run: `dart analyze lib/ test/`
Expected: zero new issues versus this branch's fork-point baseline (confirm by comparing the total issue count to the count on `main` before this plan's first commit).

- [ ] **Step 3: Manual empirical check — realtime sync across the identity-bug fix**

This is the SAME class of bug fixed earlier in this session (`chatControllerProvider` keyed on `state.conversation` vs `widget.conversation`) — re-verify by reading, not just trusting the code: grep for every `chatControllerProvider(` call added by this plan and confirm each one uses `conversation` (the `_MessageList` field), never `state.conversation`.

Run: `grep -n "chatControllerProvider(" lib/features/chat/presentation/screens/chat_screen.dart`
Expected: every occurrence inside `_MessageList` or the free-standing helper functions uses `conversation`, not `state.conversation`; every occurrence inside `_ChatScreenState` uses `widget.conversation`.

- [ ] **Step 4: Algorithm Quality Review Checklist v3.1, `[MOBILE][UI]` scope**

Read `lib/architecture/algorithms/algorithm_quality_review_checklist.md`. Confirm and record findings for at minimum:
- 5.2 (interactive p95 ≤200ms / ≤250ms transition target): the focused menu's `transitionDuration` is unchanged at 220ms (Task 4 did not touch this value) — confirm by reading `focused_action_menu.dart`'s `showGeneralDialog` call.
- 2.10/2.16 (resource lifecycle/concurrency): confirm zero new `AnimationController` anywhere across Tasks 4-6's diffs — the reaction row reuses the dialog route's own existing `animation` parameter, same as the rest of the overlay.
- 5.6 (accessibility): the reaction row's tap targets (`InkWell` around each emoji `Text`) should be checked against a minimum touch-target size; if the 6px padding used in Task 4's `reactionRow` code produces a target smaller than 44x44 logical pixels once rendered, note this as a finding for a follow-up fix (do not silently accept an inaccessible target).

- [ ] **Step 5: Manual smoke-test note**

Record in the final task summary: a human should manually test on a real device — long-press a message, tap each of the 6 quick reactions plus "+", confirm the picker sheet opens and a selected emoji lands as a pill, confirm the partner's device (or a second test account) sees the pill appear via realtime without restarting the app, and confirm a push/in-app notification arrives for a reaction on the partner's own message (not on your own).

- [ ] **Step 6: No commit for this task** — verification only. If any check in Steps 1-4 fails, that is a real finding: fix it in the file it belongs to (matching whichever earlier task's file it is) and re-run this task's checks from Step 1, do not silently patch and skip re-verification.
