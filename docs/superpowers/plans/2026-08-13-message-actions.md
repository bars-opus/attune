# Message Actions (Long-Press Menu) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WhatsApp-style long-press context menu on chat message bubbles with Reply, Copy, Star, Pin, Edit, Delete — building the retention/audit contract (soft delete + tombstone, kept edit history, no analysis retraction) that resolves `CHAT_SYSTEM_SPEC.md`'s Month-4 edit/delete gate.

**Architecture:** Three new `SECURITY DEFINER` RPCs (`delete_message`, `edit_message`, `pin_message`) enforce the 5-minute window and 3-pin cap server-side, since `messages` has no `UPDATE`/`DELETE` grant for `authenticated` today and this plan keeps it that way. Two new tables (`message_stars` — private, grant-based; `message_pins` — shared, RPC-gated insert) plus two new columns on `messages` (`deleted_at`, `edited_at`) and one new table (`message_edit_history`, append-only, no client UPDATE/DELETE grant). Client wraps the existing `MessageBubble`/`UniversalBubble` shell with a new long-press-triggered action sheet, following the same optional-callback-injection pattern `onReply`/`onRetry` already use.

**Tech Stack:** Flutter/Riverpod (StateNotifier `ChatController`), Supabase Postgres (RLS, `plpgsql SECURITY DEFINER` RPCs), Supabase Realtime (`postgresChanges` on `messages`, already firing on UPDATE; new subscription needed for `message_pins`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-13-message-actions-design.md` — every RPC signature, table schema, and decision below must match it exactly unless a task explicitly notes a correction discovered while reading the live schema.
- Edit/delete window: **5 minutes** from `messages.created_at`, enforced server-side in the RPC, never client-only.
- Pin cap: **3** per relationship, enforced server-side in `pin_message`.
- Delete model: soft delete. `deleted_at` set, `content`/`media_url`/`media_type`/`media_thumbnail_url` set to `NULL`. Row and `id` persist.
- Edit model: history kept. Every RPC-driven edit inserts the **prior** content into `message_edit_history` before overwriting `messages.content`.
- No analysis retraction: `edit_message`/`delete_message` never touch `tone_score`, `nvc_violations`, `bid_type`, `message_analysis_done`, `included_in_session_id`.
- Star: private per-user (`message_stars`, RLS `user_id = auth.uid()`). Pin: shared relationship-wide (`message_pins`, RLS both relationship members).
- Only the sender may edit/delete their own message. Either partner may pin/unpin (matches the existing chat-name "no per-partner override" precedent) or star/unstar (their own star only).
- Codebase RPC conventions (confirmed against `supabase/migrations/20260730120000_edit_window_opinions_comments_forum_posts.sql`, the direct precedent): `SECURITY DEFINER`, `SET search_path = public` (this feature has no `private` schema dependency, so `public` alone is correct — the precedent's `public, private` is for opinion-specific helpers this feature doesn't use), errors raised as `RAISE EXCEPTION 'error_code' USING ERRCODE = 'xxxxx'` (never a free-text message — matches Checklist 2.4, "error messages don't leak internal detail"), `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated` on every RPC.
- `messages` row-mapping: `Message.fromRow` in `lib/features/chat/domain/entities/message.dart` and `_messageColumns` in `lib/features/chat/data/repositories/supabase_chat_repository.dart:34-37` are the two places a new column must be threaded through together — missing either one is a silent bug (column fetched but not parsed, or parsed but never fetched).
- `UniversalBubble` (`lib/core/widgets/universal_bubble.dart`) is shared with `ForumPostBubble` (debate rooms) — no change in this plan may alter its behavior for a caller that doesn't opt in to the new long-press parameter (must default to `null`/no-op).
- Algorithm Quality Review Checklist v3.1 gate: this feature is scoped `[MOBILE][MUTATION]`. Every task that adds an RPC must satisfy 2.1 (server-side input validation, not client-only), 2.16 (concurrency — `SELECT ... FOR UPDATE` before the window/ownership check in `delete_message`/`edit_message`), 2.18 (idempotency — `delete_message` and `pin_message` must be safely retriable; `edit_message` is deliberately NOT idempotent, see spec), 2.22 (append-only audit — `message_edit_history` must have zero `UPDATE`/`DELETE` grant for `authenticated`).

---

### Task 1: Database migration — schema, RPCs, RLS

**Files:**
- Create: `supabase/migrations/20260813120000_message_actions.sql`

**Interfaces:**
- Consumes: nothing from earlier tasks (first task).
- Produces: for Task 2 onward —
  - `messages.deleted_at timestamptz`, `messages.edited_at timestamptz` columns.
  - `message_edit_history(id uuid, message_id uuid, previous_content text, edited_at timestamptz)`.
  - `message_stars(message_id uuid, user_id uuid, starred_at timestamptz)`, composite PK `(message_id, user_id)`.
  - `message_pins(id uuid, relationship_id uuid, message_id uuid, pinned_by uuid, pinned_at timestamptz)`, unique `(relationship_id, message_id)`.
  - RPC `delete_message(p_message_id uuid) RETURNS void`.
  - RPC `edit_message(p_message_id uuid, p_new_content text) RETURNS void`.
  - RPC `pin_message(p_relationship_id uuid, p_message_id uuid) RETURNS void`.
  - Plain grants: `message_stars` (SELECT/INSERT/DELETE, owner-only RLS), `message_pins` (SELECT/DELETE, relationship-member RLS; no INSERT grant — insert only via `pin_message`).

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/20260813120000_message_actions.sql
--
-- Message actions: reply (already shipped), copy (client-only, no schema),
-- star, pin, edit, delete. Resolves CHAT_SYSTEM_SPEC.md's Month-4
-- "separate retention and audit contract" gate on edit/delete — see
-- docs/superpowers/specs/2026-08-13-message-actions-design.md for the
-- full decision record (soft-delete tombstone, kept edit history, no
-- analysis retraction, 5-minute window, star=private/pin=shared).

-- ---------------------------------------------------------------------
-- 1. messages: soft-delete + edit tombstone columns
-- ---------------------------------------------------------------------

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;

-- ---------------------------------------------------------------------
-- 2. message_edit_history: append-only audit trail
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_edit_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  previous_content text NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_edit_history_message
  ON public.message_edit_history (message_id, edited_at);

ALTER TABLE public.message_edit_history ENABLE ROW LEVEL SECURITY;

-- Both relationship members may read edit history (either partner can see
-- what the other edited — matches decision 2's evidentiary-value rationale
-- in the design spec). No INSERT/UPDATE/DELETE grant for authenticated —
-- rows are written only via edit_message's internal INSERT (SECURITY
-- DEFINER bypasses RLS/grants). This satisfies Checklist 2.22's
-- append-only requirement structurally, not via a trigger.
CREATE POLICY message_edit_history_select ON public.message_edit_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.relationships r ON r.id = m.relationship_id
      WHERE m.id = message_edit_history.message_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

GRANT SELECT ON public.message_edit_history TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.message_edit_history FROM authenticated;

-- ---------------------------------------------------------------------
-- 3. message_stars: private per-user bookmarks
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_stars (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_stars_user
  ON public.message_stars (user_id, starred_at DESC);

ALTER TABLE public.message_stars ENABLE ROW LEVEL SECURITY;

CREATE POLICY message_stars_owner ON public.message_stars
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.message_stars TO authenticated;

-- ---------------------------------------------------------------------
-- 4. message_pins: shared, relationship-wide, capped at 3 (via RPC)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.message_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  pinned_by uuid NOT NULL REFERENCES auth.users(id),
  pinned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (relationship_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_message_pins_relationship
  ON public.message_pins (relationship_id, pinned_at DESC);

ALTER TABLE public.message_pins ENABLE ROW LEVEL SECURITY;

CREATE POLICY message_pins_select ON public.message_pins
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.relationships
      WHERE id = relationship_id AND (user_a = auth.uid() OR user_b = auth.uid()))
  );

CREATE POLICY message_pins_delete ON public.message_pins
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.relationships
      WHERE id = relationship_id AND (user_a = auth.uid() OR user_b = auth.uid()))
  );

-- SELECT/DELETE only — no INSERT grant. Inserting a pin always goes through
-- pin_message so the 3-pin cap is enforced server-side (Checklist 2.5).
GRANT SELECT, DELETE ON public.message_pins TO authenticated;

-- ---------------------------------------------------------------------
-- 5. delete_message: soft delete, sender-only, 5-minute window
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- FOR UPDATE locks the row before the window/ownership check so two
  -- near-simultaneous calls (e.g. a double-tap) can't both read a
  -- pre-delete state and both attempt the UPDATE (Checklist 2.16).
  PERFORM 1 FROM public.messages
  WHERE id = p_message_id AND deleted_at IS NULL
  FOR UPDATE;

  UPDATE public.messages
  SET content = NULL,
      media_url = NULL,
      media_type = NULL,
      media_thumbnail_url = NULL,
      deleted_at = now()
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
  RETURNING id INTO v_updated_id;

  -- One error for "not found", "already deleted", "not yours", and
  -- "window expired" — deliberately, matching edit_opinion's precedent:
  -- distinguishing these would let a caller probe whether a message ID
  -- exists or who sent it (Checklist 2.4).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_deletable' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. edit_message: append history, overwrite content, sender-only,
--    5-minute window
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_new_content text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_current_content text;
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_new_content IS NULL OR char_length(btrim(p_new_content)) = 0
     OR char_length(p_new_content) > 10000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  SELECT content INTO v_current_content
  FROM public.messages
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
  FOR UPDATE;

  IF v_current_content IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.message_edit_history (message_id, previous_content)
  VALUES (p_message_id, v_current_content);

  UPDATE public.messages
  SET content = p_new_content, edited_at = now()
  WHERE id = p_message_id
  RETURNING id INTO v_updated_id;
END;
$$;

REVOKE ALL ON FUNCTION public.edit_message(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 7. pin_message: enforce 3-pin cap server-side
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pin_message(p_relationship_id uuid, p_message_id uuid)
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

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id AND (user_a = v_uid OR user_b = v_uid)
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = p_message_id AND relationship_id = p_relationship_id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'message_not_found' USING ERRCODE = '42501';
  END IF;

  IF (SELECT count(*) FROM public.message_pins WHERE relationship_id = p_relationship_id) >= 3 THEN
    RAISE EXCEPTION 'pin_limit_reached' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.message_pins (relationship_id, message_id, pinned_by)
  VALUES (p_relationship_id, p_message_id, v_uid)
  ON CONFLICT (relationship_id, message_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.pin_message(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_message(uuid, uuid) TO authenticated;
```

- [ ] **Step 2: Verify the migration's SQL is syntactically valid**

Run: `npx supabase db lint --local 2>&1 || true` if a local Postgres is
available (Docker running); if not, visually re-check every `CREATE`/
`ALTER`/`GRANT` statement above against the exact column and table names
used elsewhere in this file for typos — there is no CI-time SQL syntax
check in this sandboxed environment otherwise. Do NOT attempt `supabase db
push --linked` in this task — the migration is applied by a human with
dashboard access later, same deferral pattern as
`20260830120000_chat_pulse_signals.sql`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260813120000_message_actions.sql
git commit -m "feat(chat): add message actions schema — delete/edit/star/pin tables and RPCs"
```

---

### Task 2: `Message` entity + repository interface — thread `deleted_at`/`edited_at` through

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`
- Test: `test/features/chat/domain/entities/message_test.dart`

**Interfaces:**
- Consumes: `messages.deleted_at`, `messages.edited_at` columns from Task 1.
- Produces: `Message.deletedAt DateTime?`, `Message.editedAt DateTime?`, `Message.isDeleted bool` getter, for Task 3 (repository impl) and Task 5 (UI) to consume. `ChatRepository` abstract methods `deleteMessage`, `editMessage`, `starMessage`, `unstarMessage`, `pinMessage`, `unpinMessage`, `getStarredMessages`, `getPinnedMessages`, `watchPinnedMessages`, `getMessageEditHistory` — exact signatures below, for Task 3 to implement and Task 6 (controller) to call.

- [ ] **Step 1: Write the failing test for the new `Message` fields**

```dart
// test/features/chat/domain/entities/message_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message deleted/edited state', () {
    test('fromRow parses deleted_at and edited_at when present', () {
      final row = {
        'id': 'm1',
        'client_message_id': 'c1',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': '2026-08-13T10:00:00Z',
        'deleted_at': '2026-08-13T10:02:00Z',
        'edited_at': null,
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(message.deletedAt, DateTime.parse('2026-08-13T10:02:00Z').toLocal());
      expect(message.editedAt, isNull);
      expect(message.isDeleted, isTrue);
    });

    test('fromRow parses edited_at when present, isDeleted false', () {
      final row = {
        'id': 'm2',
        'client_message_id': 'c2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'updated text',
        'created_at': '2026-08-13T10:00:00Z',
        'deleted_at': null,
        'edited_at': '2026-08-13T10:01:00Z',
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(message.editedAt, DateTime.parse('2026-08-13T10:01:00Z').toLocal());
      expect(message.isDeleted, isFalse);
    });

    test('fromRow defaults both to null when absent from the row', () {
      final row = {
        'id': 'm3',
        'client_message_id': 'c3',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hi',
        'created_at': '2026-08-13T10:00:00Z',
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(message.deletedAt, isNull);
      expect(message.editedAt, isNull);
      expect(message.isDeleted, isFalse);
    });

    test('canEditOrDelete is true for own message within 5 minutes', () {
      final message = Message.optimistic(
        id: 'm4',
        clientMessageId: 'c4',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      expect(message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()), isTrue);
    });

    test('canEditOrDelete is false past the 5-minute window', () {
      final message = Message.optimistic(
        id: 'm5',
        clientMessageId: 'c5',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );
      expect(message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()), isFalse);
    });

    test('canEditOrDelete is false for a message from the other sender', () {
      final message = Message.optimistic(
        id: 'm6',
        clientMessageId: 'c6',
        relationshipId: 'r1',
        senderId: 'partner',
        content: 'hi',
        createdAt: DateTime.now(),
      );
      expect(message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()), isFalse);
    });

    test('canEditOrDelete is false for an already-deleted message', () {
      final row = {
        'id': 'm7',
        'client_message_id': 'c7',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/domain/entities/message_test.dart`
Expected: FAIL — `deletedAt`/`editedAt`/`isDeleted`/`canEditOrDelete` don't exist yet on `Message`.

- [ ] **Step 3: Add the fields to `Message`**

In `lib/features/chat/domain/entities/message.dart`, add two fields to the
class body (after `quotedText`):

```dart
  final DateTime? deletedAt;
  final DateTime? editedAt;
```

Add both as optional named params to the main constructor (after
`this.quotedText`):

```dart
    this.deletedAt,
    this.editedAt,
```

In `Message.fromRow`, add after the existing `quotedText: row['quoted_text'] as String?,` line:

```dart
      deletedAt: _parseDateTime(row['deleted_at']),
      editedAt: _parseDateTime(row['edited_at']),
```

In `copyWith`, add params and body lines following the exact existing
pattern for every other nullable `DateTime?` field (e.g. `deliveredAt`):

```dart
    DateTime? deletedAt,
    DateTime? editedAt,
```
and in the returned `Message(...)`:
```dart
      deletedAt: deletedAt ?? this.deletedAt,
      editedAt: editedAt ?? this.editedAt,
```

In `toJson`/`fromJson`, add the same pair following the existing
`deliveredAt`/`readAt` pattern (ISO string round-trip via
`_parseDateTime`).

Add two new getters after the existing `isImported` getter:

```dart
  bool get isDeleted => deletedAt != null;

  /// True only for the sender's own message, not yet deleted, sent within
  /// the last 5 minutes. [now] is injectable for testing; callers pass
  /// DateTime.now() in production.
  bool canEditOrDelete({required String currentUserId, required DateTime now}) {
    if (senderId != currentUserId) return false;
    if (isDeleted) return false;
    return now.difference(createdAt) < const Duration(minutes: 5);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/domain/entities/message_test.dart`
Expected: PASS — all 6 tests green.

- [ ] **Step 5: Add the new abstract methods to `ChatRepository`**

In `lib/features/chat/data/repositories/chat_repository.dart`, add after
the existing `setRelationshipChatName` method:

```dart
  /// Soft-deletes a message (server enforces sender-only, 5-minute window
  /// — see delete_message RPC). Throws on any rejection (not found, not
  /// yours, already deleted, window expired — the server intentionally
  /// does not distinguish which).
  Future<void> deleteMessage(String messageId);

  /// Edits a message's content, appending the prior content to
  /// message_edit_history (server enforces sender-only, 5-minute window —
  /// see edit_message RPC). Throws on any rejection.
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  });

  /// Prior versions of this message's content, oldest first. Does not
  /// include the current (latest) content — callers already have that via
  /// Message.content.
  Future<List<MessageEditHistoryEntry>> getMessageEditHistory(String messageId);

  Future<void> starMessage(String messageId);
  Future<void> unstarMessage(String messageId);

  /// This user's starred messages across all their relationships,
  /// newest-starred first.
  Future<List<Message>> getStarredMessages();

  /// True if the current user has starred this message.
  Future<bool> isMessageStarred(String messageId);

  /// Pins a message to the top of the relationship's chat (server enforces
  /// the 3-pin cap — see pin_message RPC). Throws 'pin_limit_reached' when
  /// full.
  Future<void> pinMessage({
    required String relationshipId,
    required String messageId,
  });
  Future<void> unpinMessage({
    required String relationshipId,
    required String messageId,
  });

  /// Currently pinned messages for this relationship, newest-pinned first
  /// (max 3, enforced server-side).
  Future<List<Message>> getPinnedMessages(String relationshipId);

  /// Live updates when a pin is added/removed for this relationship.
  Stream<void> watchPinnedMessages(String relationshipId);
```

Add the small value type at the bottom of the file, alongside
`ChatMessageCursor`:

```dart
class MessageEditHistoryEntry {
  final String previousContent;
  final DateTime editedAt;

  const MessageEditHistoryEntry({
    required this.previousContent,
    required this.editedAt,
  });
}
```

- [ ] **Step 6: Run the full chat domain test suite**

Run: `flutter test test/features/chat/`
Expected: PASS (existing tests unaffected; `ChatRepository` is an abstract
class so adding new abstract methods doesn't break anything until Task 3
implements them — but any existing mock/fake implementing `ChatRepository`
in test code WILL now fail to compile until it implements the new
methods too; if `flutter test test/features/chat/` reports a compile
error naming a fake repository class, add `UnimplementedError()`-throwing
stubs for the new methods to that fake in this same task so the suite
compiles, and note this in your report — implementing real behavior in
a test fake is Task 3/6's job, not this one's).

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart lib/features/chat/data/repositories/chat_repository.dart test/features/chat/domain/entities/message_test.dart
git commit -m "feat(chat): add deleted/edited fields to Message, new ChatRepository methods for message actions"
```

---

### Task 3: `SupabaseChatRepository` implementation

**Files:**
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`

**Interfaces:**
- Consumes: `ChatRepository`'s new abstract methods from Task 2; RPCs `delete_message`, `edit_message`, `pin_message` and tables `message_edit_history`, `message_stars`, `message_pins` from Task 1.
- Produces: working implementations for Task 6 (controller) to call.

- [ ] **Step 1: Update `_messageColumns` to fetch the new columns**

In `lib/features/chat/data/repositories/supabase_chat_repository.dart:34-37`,
change:

```dart
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,source,'
      'reply_to_message_id,quoted_text';
```

to:

```dart
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,source,'
      'reply_to_message_id,quoted_text,deleted_at,edited_at';
```

This is the ONLY place the fetched column list is defined — every existing
call site using `.select(_messageColumns)` (lines 182, 189, 219, 226, 280,
295, 647 as of Task 1's baseline) picks up the new columns automatically.

- [ ] **Step 2: Add the RPC-backed mutation methods**

Add after the existing `setRelationshipChatName` method (follow its exact
`_supabase.rpc(...)` pattern):

```dart
  @override
  Future<void> deleteMessage(String messageId) async {
    await _supabase.rpc('delete_message', params: {'p_message_id': messageId});
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    await _supabase.rpc(
      'edit_message',
      params: {'p_message_id': messageId, 'p_new_content': newContent},
    );
  }

  @override
  Future<List<MessageEditHistoryEntry>> getMessageEditHistory(
    String messageId,
  ) async {
    final rows = await _supabase
        .from('message_edit_history')
        .select('previous_content,edited_at')
        .eq('message_id', messageId)
        .order('edited_at', ascending: true);

    return rows
        .map(
          (row) => MessageEditHistoryEntry(
            previousContent: row['previous_content'] as String,
            editedAt: DateTime.parse(row['edited_at'] as String).toLocal(),
          ),
        )
        .toList();
  }

  @override
  Future<void> starMessage(String messageId) async {
    final user = _currentUser;
    await _supabase.from('message_stars').upsert({
      'message_id': messageId,
      'user_id': user.id,
    });
  }

  @override
  Future<void> unstarMessage(String messageId) async {
    final user = _currentUser;
    await _supabase
        .from('message_stars')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', user.id);
  }

  @override
  Future<bool> isMessageStarred(String messageId) async {
    final user = _currentUser;
    final rows = await _supabase
        .from('message_stars')
        .select('message_id')
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<List<Message>> getStarredMessages() async {
    final user = _currentUser;
    final rows = await _supabase
        .from('message_stars')
        .select('starred_at,messages!inner($_messageColumns)')
        .eq('user_id', user.id)
        .order('starred_at', ascending: false);

    return rows
        .map(
          (row) => Message.fromRow(
            row['messages'] as Map<String, dynamic>,
            currentUserId: user.id,
          ),
        )
        .toList();
  }

  @override
  Future<void> pinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    await _supabase.rpc(
      'pin_message',
      params: {'p_relationship_id': relationshipId, 'p_message_id': messageId},
    );
  }

  @override
  Future<void> unpinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    await _supabase
        .from('message_pins')
        .delete()
        .eq('relationship_id', relationshipId)
        .eq('message_id', messageId);
  }

  @override
  Future<List<Message>> getPinnedMessages(String relationshipId) async {
    final user = _currentUser;
    final rows = await _supabase
        .from('message_pins')
        .select('pinned_at,messages!inner($_messageColumns)')
        .eq('relationship_id', relationshipId)
        .order('pinned_at', ascending: false);

    return rows
        .map(
          (row) => Message.fromRow(
            row['messages'] as Map<String, dynamic>,
            currentUserId: user.id,
          ),
        )
        .toList();
  }

  @override
  Stream<void> watchPinnedMessages(String relationshipId) {
    // Reuses the same shared per-relationship event stream as
    // watchConversationEvents — message_pins changes are subscribed
    // alongside messages/relationships inside _channelFor so callers get
    // one unified invalidation signal per relationship, matching the
    // existing pattern instead of opening a second channel.
    _channelFor(relationshipId);
    return _eventControllers[relationshipId]!.stream;
  }
```

- [ ] **Step 3: Subscribe `message_pins` changes on the shared channel**

In `_channelFor` (around line 465-505), add a third `.onPostgresChanges`
call to the existing chain, mirroring the `relationships` one already
there:

```dart
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_pins',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'relationship_id',
            value: relationshipId,
          ),
          callback: (_) => events.add(null),
        )
```

Insert it between the existing `relationships` and `.onBroadcast` calls
(order among `.onPostgresChanges` calls doesn't matter functionally, but
keep it visually grouped with the other `postgresChanges` subscriptions
before the broadcast one, for readability).

- [ ] **Step 4: Run the chat data-layer test suite**

Run: `flutter test test/features/chat/`
Expected: PASS. If a fake/mock `ChatRepository` from Task 2 Step 6 still
throws `UnimplementedError()` for these methods, that's fine as long as
no test in this suite currently exercises star/pin/edit/delete paths yet
(Task 6 adds controller-level tests that will need real fake behavior —
if any test written in Task 2 already calls a fake's star/pin method,
implement real in-memory behavior in that fake now instead of leaving the
stub, and note it in your report).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/repositories/supabase_chat_repository.dart
git commit -m "feat(chat): implement message actions in SupabaseChatRepository"
```

---

### Task 4: `UniversalBubble` long-press support (shared widget, opt-in only)

**Files:**
- Modify: `lib/core/widgets/universal_bubble.dart`
- Test: `test/core/widgets/universal_bubble_test.dart` (create if it doesn't exist; check first)

**Interfaces:**
- Consumes: nothing from earlier tasks — this widget has no dependency on
  the schema/repository work.
- Produces: `UniversalBubble.onLongPress VoidCallback?` param for Task 5
  (`MessageBubble`) to wire. `ForumPostBubble` (the other consumer) is
  unaffected since the param defaults to `null`.

- [ ] **Step 1: Check for an existing test file**

Run: `find test/core/widgets -iname "*universal_bubble*"`. If a file
exists, read it fully before writing new tests so you extend rather than
duplicate its setup.

- [ ] **Step 2: Write the failing test**

```dart
// test/core/widgets/universal_bubble_test.dart (add to existing file, or
// create with this content if none exists)
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onLongPress fires when the bubble is long-pressed', (tester) async {
    var longPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UniversalBubble(
            isMine: true,
            bubbleColor: Colors.blue,
            onBubbleColor: Colors.white,
            content: const Text('hello'),
            footer: const SizedBox.shrink(),
            onLongPress: () => longPressed = true,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(longPressed, isTrue);
  });

  testWidgets('omitting onLongPress renders with no long-press handler', (tester) async {
    // Regression guard for ForumPostBubble, the other UniversalBubble
    // caller, which does not pass onLongPress — must keep rendering with
    // zero behavior change when the param is omitted.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UniversalBubble(
            isMine: true,
            bubbleColor: Colors.blue,
            onBubbleColor: Colors.white,
            content: const Text('hello'),
            footer: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    // No assertion needed beyond "did not throw" — absence of a handler
    // must be a true no-op, not an error.
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: FAIL — `onLongPress` is not a parameter of `UniversalBubble` yet.

- [ ] **Step 4: Add the parameter and wire it**

In `lib/core/widgets/universal_bubble.dart`, add to the constructor's
named params (after `this.groupTag,`):

```dart
    this.onLongPress,
```

Add the field declaration (after `final Object? groupTag;`):

```dart
  /// Long-press handler on the bubble's fill (not the quote block, which
  /// has its own tap-to-jump gesture). Null (the default) means no
  /// long-press behavior — ForumPostBubble, this widget's other caller,
  /// does not pass this and must see zero behavior change.
  final VoidCallback? onLongPress;
```

Wrap the `DecoratedBox` that renders the bubble fill (the one containing
the quote block + `content`, currently starting at line 173 `child:
DecoratedBox(`) with a `GestureDetector`:

```dart
                          child: GestureDetector(
                            onLongPress: onLongPress,
                            behavior: HitTestBehavior.opaque,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (quotedText != null) ...[
                                      GestureDetector(
                                        onTap: onJumpToParent,
                                        behavior: HitTestBehavior.opaque,
                                        child: Container(
                                          // ...existing quote block unchanged...
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    content,
                                  ],
                                ),
                              ),
                            ),
                          ),
```

(Only the outer wrapper is new — the `DecoratedBox` and everything inside
it is unchanged, just re-indented one level under the new
`GestureDetector`. The inner quote-block `GestureDetector.onTap` for
`onJumpToParent` is untouched and still fires independently — Flutter's
gesture arena lets a nested tap-only detector win over the outer
long-press-only detector for a quick tap, and the outer one wins for a
long-press since the inner one doesn't compete for that gesture type.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: PASS — both tests green.

- [ ] **Step 6: Run the forum bubble's existing tests to confirm no regression**

Run: `find test -iname "*forum_post_bubble*"` then run that test file if
it exists (e.g. `flutter test test/features/forums/.../forum_post_bubble_test.dart`).
Expected: PASS, unchanged — confirms the opt-in default truly changes
nothing for the other caller.

- [ ] **Step 7: Commit**

```bash
git add lib/core/widgets/universal_bubble.dart test/core/widgets/universal_bubble_test.dart
git commit -m "feat(chat): add opt-in long-press support to UniversalBubble"
```

---

### Task 5: Message actions sheet — the long-press menu widget

**Files:**
- Create: `lib/features/chat/presentation/widgets/message_actions_sheet.dart`
- Test: `test/features/chat/presentation/widgets/message_actions_sheet_test.dart`

**Interfaces:**
- Consumes: `Message.canEditOrDelete`/`Message.isDeleted` from Task 2.
  Does NOT consume the repository directly — this widget is pure UI,
  taking callbacks as params (matches `MessageBubble`'s existing
  `onReply`/`onRetry` pattern) so it has no Riverpod/repository
  dependency and is trivially widget-testable in isolation.
- Produces: `showMessageActionsSheet(...)` top-level function, for Task 7
  (`ChatScreen` wiring) to call from the new `onLongPress` callback.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/presentation/widgets/message_actions_sheet_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool starred = false, bool canEditOrDelete = true}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt: canEditOrDelete
        ? DateTime.now()
        : DateTime.now().subtract(const Duration(minutes: 10)),
  );
}

void main() {
  testWidgets('shows Reply, Copy, Star, Pin, Edit, Delete for an own recent message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('omits Edit and Delete when the 5-minute window has passed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(canEditOrDelete: false),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('omits Edit and Delete for a message from the other partner', (tester) async {
    final theirMessage = Message.optimistic(
      id: 'm2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: theirMessage,
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('shows Unstar instead of Star when isStarred is true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: true,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Unstar'), findsOneWidget);
    expect(find.text('Star'), findsNothing);
  });

  testWidgets('tapping Delete calls onDelete and closes the sheet', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () => deleted = true,
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing); // sheet closed
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/presentation/widgets/message_actions_sheet_test.dart`
Expected: FAIL — `message_actions_sheet.dart` doesn't exist yet.

- [ ] **Step 3: Write the widget**

```dart
// lib/features/chat/presentation/widgets/message_actions_sheet.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';

/// WhatsApp-style long-press action sheet for a chat message bubble.
/// Pure UI — takes callbacks, has no repository/Riverpod dependency, so
/// it's trivially testable and the caller (ChatScreen) owns all mutation
/// logic and error handling. Edit/Delete are omitted (not shown-disabled)
/// once [Message.canEditOrDelete] is false, matching the design spec's
/// "no dead menu item that invites a confused tap" decision.
Future<void> showMessageActionsSheet({
  required BuildContext context,
  required Message message,
  required String currentUserId,
  required bool isStarred,
  required bool isPinned,
  required VoidCallback onReply,
  required VoidCallback onCopy,
  required VoidCallback onStar,
  required VoidCallback onUnstar,
  required VoidCallback onPin,
  required VoidCallback onUnpin,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final canEditOrDelete = message.canEditOrDelete(
    currentUserId: currentUserId,
    now: DateTime.now(),
  );

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onReply();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onCopy();
              },
            ),
            ListTile(
              leading: Icon(isStarred ? Icons.star : Icons.star_border),
              title: Text(isStarred ? 'Unstar' : 'Star'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                isStarred ? onUnstar() : onStar();
              },
            ),
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                isPinned ? onUnpin() : onPin();
              },
            ),
            if (canEditOrDelete) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onEdit();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Theme.of(sheetContext).colorScheme.error),
                title: Text(
                  'Delete',
                  style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/presentation/widgets/message_actions_sheet_test.dart`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_actions_sheet.dart test/features/chat/presentation/widgets/message_actions_sheet_test.dart
git commit -m "feat(chat): add message actions long-press sheet widget"
```

---

### Task 6: `ChatController` mutation methods + optimistic state updates

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart`
- Test: `test/features/chat/presentation/state/chat_controller_test.dart` (check if it exists first; extend if so)

**Interfaces:**
- Consumes: `ChatRepository`'s new methods from Task 2/3.
- Produces: `ChatController.deleteMessage`, `editMessage`, `starMessage`,
  `unstarMessage`, `pinMessage`, `unpinMessage` methods, plus
  `ChatState.starredMessageIds Set<String>` and `ChatState.pinnedMessages
  List<Message>` fields, for Task 7 (`ChatScreen` wiring) to read/call.

- [ ] **Step 1: Check for an existing controller test file and read `ChatState`'s current shape**

Run: `find test/features/chat -iname "*chat_controller*" -o -iname "*chat_state*"`.
Read `ChatState`'s class definition in `lib/features/chat/presentation/state/chat_state.dart`
(search for `class ChatState`) to find its exact `copyWith` signature
before writing new fields — match its existing null-handling convention
(sentinel-based vs `??`-based) exactly; do not guess.

- [ ] **Step 2: Add `starredMessageIds` and `pinnedMessages` to `ChatState`**

Add two fields to `ChatState` (exact insertion point depends on the
class's real current field list — read it first per Step 1):

```dart
  final Set<String> starredMessageIds;
  final List<Message> pinnedMessages;
```

Default both to empty in `ChatState.initial(...)` (`const {}`/`const []`)
and thread them through `copyWith` following the exact pattern the class
already uses for its other collection fields (e.g. `messages`).

- [ ] **Step 3: Write the failing test for `deleteMessage`**

```dart
// Add to test/features/chat/presentation/state/chat_controller_test.dart
// (create if it doesn't exist — check Step 1's findings first, and if a
// fake ChatRepository already exists in this test file or a shared test
// helper, extend that fake's deleteMessage/editMessage/star*/pin*
// methods to real in-memory behavior rather than creating a second fake).

test('deleteMessage removes the message content from state optimistically', () async {
  // Arrange: seed the controller's state with one message from the
  // current user, using the test's existing fake ChatRepository/provider
  // container setup (mirror however retryMessage/removeFailedMessage are
  // already tested in this file, if present — same container wiring,
  // same fake injection point).
  //
  // Act: await controller.deleteMessage(message);
  //
  // Assert: the message in state.messages with the matching id now has
  // isDeleted == true (fetch it back out of state.messages and check).
});
```

Note: the exact fake/container setup for this test depends entirely on
what Task 6's implementer finds already in this test file or in a shared
`test/features/chat/` helper — if no controller test infrastructure
exists yet, write a minimal fake `ChatRepository` implementing every
abstract method (throwing `UnimplementedError` for ones this test doesn't
exercise) plus a `ProviderContainer` wired the same way any existing
provider test in this codebase does it (grep an existing
`ProviderContainer(overrides: [...])` usage in `test/features/chat/` for
the pattern to copy).

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/chat/presentation/state/chat_controller_test.dart`
Expected: FAIL — `deleteMessage` doesn't exist on `ChatController` yet.

- [ ] **Step 5: Add the six mutation methods to `ChatController`**

Add after the existing `removeFailedMessage` method, following its exact
structure (read current user, call repository, update `state` if
`mounted`):

```dart
  Future<void> deleteMessage(Message message) async {
    await _repository.deleteMessage(message.id);
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map(
            (entry) => entry.id == message.id
                ? entry.copyWith(
                    deletedAt: DateTime.now(),
                    content: '',
                  )
                : entry,
          )
          .toList(),
    );
  }

  Future<void> editMessage(Message message, String newContent) async {
    await _repository.editMessage(messageId: message.id, newContent: newContent);
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map(
            (entry) => entry.id == message.id
                ? entry.copyWith(content: newContent, editedAt: DateTime.now())
                : entry,
          )
          .toList(),
    );
  }

  Future<void> starMessage(String messageId) async {
    await _repository.starMessage(messageId);
    if (!mounted) return;
    state = state.copyWith(
      starredMessageIds: {...state.starredMessageIds, messageId},
    );
  }

  Future<void> unstarMessage(String messageId) async {
    await _repository.unstarMessage(messageId);
    if (!mounted) return;
    state = state.copyWith(
      starredMessageIds: state.starredMessageIds
          .where((id) => id != messageId)
          .toSet(),
    );
  }

  Future<void> pinMessage(Message message) async {
    await _repository.pinMessage(
      relationshipId: message.relationshipId,
      messageId: message.id,
    );
    if (!mounted) return;
    final pins = await _repository.getPinnedMessages(message.relationshipId);
    if (!mounted) return;
    state = state.copyWith(pinnedMessages: pins);
  }

  Future<void> unpinMessage(Message message) async {
    await _repository.unpinMessage(
      relationshipId: message.relationshipId,
      messageId: message.id,
    );
    if (!mounted) return;
    final pins = await _repository.getPinnedMessages(message.relationshipId);
    if (!mounted) return;
    state = state.copyWith(pinnedMessages: pins);
  }
```

Note on `deleteMessage`'s optimistic update: `Message.content` is `final
String` (non-nullable) per `message.dart`'s existing constructor, so the
tombstone state is represented as `deletedAt != null` (checked via
`isDeleted`) with `content` set to an empty string — Task 7's rendering
must check `message.isDeleted` FIRST and never render `message.content`
directly without that check, since an empty string and "no content yet"
are otherwise indistinguishable. Do not change `content` to nullable —
that would ripple into every other read site in this file and
`message_bubble.dart` for no benefit; the `isDeleted` getter is the single
source of truth for tombstone rendering.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/chat/presentation/state/chat_controller_test.dart`
Expected: PASS.

- [ ] **Step 7: Run the full chat presentation test suite**

Run: `flutter test test/features/chat/`
Expected: PASS, no regressions.

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart test/features/chat/presentation/state/chat_controller_test.dart
git commit -m "feat(chat): add delete/edit/star/pin methods to ChatController"
```

---

### Task 7: Wire long-press menu, tombstone, edited label, reply-parent placeholder into `MessageBubble`/`UniversalBubble` rendering

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/core/widgets/universal_bubble.dart` (reply-parent placeholder only — see Step 4)
- Test: `test/features/chat/presentation/widgets/message_bubble_test.dart` (check if it exists first; extend if so)

**Interfaces:**
- Consumes: `Message.isDeleted`/`editedAt` (Task 2), `UniversalBubble.onLongPress`
  (Task 4), `showMessageActionsSheet` (Task 5).
- Produces: fully-wired `MessageBubble` with an `onLongPress`-style
  callback surface, for Task 8 (`ChatScreen`) to inject real controller
  calls into.

- [ ] **Step 1: Check for an existing widget test file**

Run: `find test/features/chat/presentation/widgets -iname "*message_bubble*"`.
Read it fully if present.

- [ ] **Step 2: Write the failing test for tombstone rendering**

```dart
// Add to test/features/chat/presentation/widgets/message_bubble_test.dart
// (create if none exists, following whatever MaterialApp/Scaffold
// wrapping convention this codebase's other widget tests use — check
// message_actions_sheet_test.dart from Task 5 for the pattern).

testWidgets('renders tombstone text when message is deleted', (tester) async {
  final deleted = Message.fromRow(
    {
      'id': 'm1',
      'client_message_id': 'c1',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': null,
      'created_at': DateTime.now().toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    },
    currentUserId: 'u1',
  );

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: MessageBubble(message: deleted))),
  );

  expect(find.text('This message was deleted'), findsOneWidget);
});

testWidgets('renders edited label when message has been edited', (tester) async {
  final edited = Message.fromRow(
    {
      'id': 'm2',
      'client_message_id': 'c2',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'updated text',
      'created_at': DateTime.now().toIso8601String(),
      'edited_at': DateTime.now().toIso8601String(),
    },
    currentUserId: 'u1',
  );

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: MessageBubble(message: edited))),
  );

  expect(find.textContaining('edited'), findsOneWidget);
});

testWidgets('tapping the edited label calls onShowEditHistory with the message', (tester) async {
  Message? tapped;
  final edited = Message.fromRow(
    {
      'id': 'm2b',
      'client_message_id': 'c2b',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'updated text',
      'created_at': DateTime.now().toIso8601String(),
      'edited_at': DateTime.now().toIso8601String(),
    },
    currentUserId: 'u1',
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: edited,
          onShowEditHistory: (message) => tapped = message,
        ),
      ),
    ),
  );

  await tester.tap(find.text('edited'));
  await tester.pumpAndSettle();

  expect(tapped?.id, 'm2b');
});

testWidgets('long-press opens the actions sheet for a non-deleted message', (tester) async {
  final message = Message.optimistic(
    id: 'm3',
    clientMessageId: 'c3',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hi',
    createdAt: DateTime.now(),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: 'u1',
          onDelete: () {},
        ),
      ),
    ),
  );

  await tester.longPress(find.text('hi'));
  await tester.pumpAndSettle();

  expect(find.text('Delete'), findsOneWidget);
});

testWidgets('long-press does nothing for a deleted message (no menu, nothing to act on)', (tester) async {
  final deleted = Message.fromRow(
    {
      'id': 'm4',
      'client_message_id': 'c4',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': null,
      'created_at': DateTime.now().toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    },
    currentUserId: 'u1',
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessageBubble(message: deleted, currentUserId: 'u1', onDelete: () {}),
      ),
    ),
  );

  await tester.longPress(find.text('This message was deleted'));
  await tester.pumpAndSettle();

  expect(find.text('Delete'), findsNothing);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/chat/presentation/widgets/message_bubble_test.dart`
Expected: FAIL — tombstone text, edited label, and long-press wiring
don't exist yet.

- [ ] **Step 4: Add the reply-parent placeholder logic**

This is a client-side decision, not a schema change: `Message.quotedText`
is already denormalized onto the reply row (Task 1 doesn't touch this).
The placeholder needs to know whether the PARENT is deleted, which the
reply row itself doesn't carry. Add a new optional field to `Message`
threaded the same way as Task 2's fields — but sourced differently: add
`parentDeleted` as a param `MessageBubble` itself receives from
`ChatScreen` (Task 8), NOT stored on `Message`, because computing it
requires cross-referencing `state.messages` for the parent's current
`isDeleted` (the parent may be off-screen/paginated-out, in which case
`ChatScreen` cannot know — treat "parent not found in loaded state" as
"assume not deleted," i.e. show the existing `quotedText` unchanged; this
is a acceptable known limitation, not a bug, since the common case is the
parent is nearby in the same loaded page).

In `MessageBubble`'s constructor, add:

```dart
    this.parentDeleted = false,
```
and field:
```dart
  /// True when this message's replied-to parent has been deleted (Task 8
  /// looks this up from ChatScreen's loaded message list by
  /// message.replyToMessageId). Only meaningful when message.quotedText
  /// is non-null. Defaults to false — an off-screen/unloaded parent is
  /// assumed not deleted rather than guessed at.
  final bool parentDeleted;
```

In `MessageBubble.build`, change the `quotedText` passed to
`UniversalBubble`:

```dart
      quotedText: parentDeleted ? 'Original message deleted' : message.quotedText,
```

(No change needed inside `UniversalBubble` itself for this — it already
renders whatever string `quotedText` is given. The "Modify" line for
`universal_bubble.dart` in this task's file list is ONLY Task 4's
long-press wrapper, already done; if Task 4 landed cleanly, this task
does NOT need to touch `universal_bubble.dart` again — remove that file
from your working set once you've confirmed Task 4's change already
covers the long-press surface this task needs.)

- [ ] **Step 5: Add tombstone rendering, edited label, and long-press wiring to `MessageBubble`**

Add new optional params to `MessageBubble`'s constructor (alongside the
existing `onReply`/`onJumpToParent`):

```dart
    this.currentUserId,
    this.isStarred = false,
    this.isPinned = false,
    this.onCopy,
    this.onStar,
    this.onUnstar,
    this.onPin,
    this.onUnpin,
    this.onEdit,
    this.onDelete,
```

and fields:

```dart
  /// Needed to compute Message.canEditOrDelete inside the long-press
  /// sheet. Null disables the long-press menu entirely (e.g. a read-only
  /// archived conversation has nothing sensible to act on) — matches the
  /// existing null-disables-gesture convention onReply already uses.
  final String? currentUserId;
  final bool isStarred;
  final bool isPinned;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final VoidCallback? onUnstar;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
```

In `build`, compute the long-press handler and pass it to
`UniversalBubble`:

```dart
    final canOpenActions = currentUserId != null && !message.isDeleted;

    return UniversalBubble(
      isMine: isMine,
      bubbleColor: /* unchanged */,
      onBubbleColor: /* unchanged */,
      quotedText: parentDeleted ? 'Original message deleted' : message.quotedText,
      onJumpToParent: /* unchanged */,
      isHighlighted: isHighlighted,
      slidableKey: /* unchanged */,
      startActionPane: /* unchanged */,
      onLongPress: canOpenActions
          ? () => showMessageActionsSheet(
                context: context,
                message: message,
                currentUserId: currentUserId!,
                isStarred: isStarred,
                isPinned: isPinned,
                onReply: onReply ?? () {},
                onCopy: onCopy ?? () {},
                onStar: onStar ?? () {},
                onUnstar: onUnstar ?? () {},
                onPin: onPin ?? () {},
                onUnpin: onUnpin ?? () {},
                onEdit: onEdit ?? () {},
                onDelete: onDelete ?? () {},
              )
          : null,
      content: /* unchanged Column, see below for _BubbleBody change */,
      footer: /* unchanged, but see edited-label addition below */,
    );
```

(`build` needs `context` — it already has it as the method parameter, no
change needed there.)

Change `_BubbleBody` to render the tombstone first, before anything else:

```dart
class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color = isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(color: color, fontStyle: FontStyle.italic),
      );
    }

    // ...rest of the method body is UNCHANGED from before (hasImage /
    // content / "Unsupported message" branches)...
  }
}
```

Add the "edited" label to the footer `Wrap`'s children, right after the
time `Text` (inside `MessageBubble.build`'s `footer:` param). The spec
requires this label to be tappable, opening a history view (design spec
"Edited label + history view" section) — wrap it in a `GestureDetector`
calling a new `onShowEditHistory` param (added alongside the other new
callback params in this same step):

```dart
          if (message.editedAt != null && !message.isDeleted)
            GestureDetector(
              onTap: onShowEditHistory == null
                  ? null
                  : () => onShowEditHistory!(message),
              child: Text(
                'edited',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
```

Add the new param and field alongside the others introduced in this step:

```dart
    this.onShowEditHistory,
```
```dart
  /// Tapping the "edited" label calls this with the message, to open a
  /// history view. Null disables the tap affordance (label still renders,
  /// just not interactive) — matches this file's existing null-disables
  /// convention.
  final void Function(Message)? onShowEditHistory;
```

- [ ] **Step 6: Add the import for `showMessageActionsSheet`**

At the top of `message_bubble.dart`:

```dart
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/features/chat/presentation/widgets/message_bubble_test.dart`
Expected: PASS — all 4 new tests green.

- [ ] **Step 8: Run the full widget test suite for chat**

Run: `flutter test test/features/chat/`
Expected: PASS, no regressions (existing `MessageBubble` tests, if any,
must still pass since every new param defaults to `null`/`false`).

- [ ] **Step 9: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/presentation/widgets/message_bubble_test.dart
git commit -m "feat(chat): wire tombstone, edited label, reply-parent placeholder, long-press menu into MessageBubble"
```

---

### Task 8: `ChatScreen` wiring — connect controller methods to `MessageBubble`, add edit mode, pinned banner

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`

**Interfaces:**
- Consumes: everything from Tasks 5-7.
- Produces: fully working end-to-end feature.

- [ ] **Step 1: Read the current `MessageBubble(...)` call site fully**

Read `lib/features/chat/presentation/screens/chat_screen.dart` around
line 1140 (the `MessageBubble(...)` construction inside `itemBuilder`)
completely, including how `onReply`/`onJumpToParent` are wired, to match
the exact style (inline closures reading `ref.read(...)`) before adding
new params.

- [ ] **Step 2: Wire the new `MessageBubble` params**

Extend the existing `MessageBubble(...)` call (around line 1140) with:

```dart
            currentUserId: ref.read(currentUserProvider)?.id,
            isStarred: state.starredMessageIds.contains(message.id),
            isPinned: state.pinnedMessages.any((p) => p.id == message.id),
            parentDeleted: message.replyToMessageId == null
                ? false
                : state.messages
                    .where((m) => m.id == message.replyToMessageId)
                    .firstOrNull
                    ?.isDeleted ??
                false,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: message.content));
              context.showSuccessSnackbar('Copied to clipboard');
            },
            onStar: () => ref
                .read(chatControllerProvider(state.conversation).notifier)
                .starMessage(message.id),
            onUnstar: () => ref
                .read(chatControllerProvider(state.conversation).notifier)
                .unstarMessage(message.id),
            onPin: () async {
              try {
                await ref
                    .read(chatControllerProvider(state.conversation).notifier)
                    .pinMessage(message);
              } catch (_) {
                if (context.mounted) {
                  context.showErrorSnackbar(
                    "Couldn't pin — you may already have 3 pinned messages.",
                  );
                }
              }
            },
            onUnpin: () => ref
                .read(chatControllerProvider(state.conversation).notifier)
                .unpinMessage(message),
            onEdit: () => _showEditDialog(context, ref, state.conversation, message),
            onDelete: () => _confirmAndDelete(context, ref, state.conversation, message),
            onShowEditHistory: (message) => _showEditHistorySheet(context, ref, message),
```

(Confirm the exact names `context.showSuccessSnackbar`/`context.showErrorSnackbar`
match this codebase's real extension methods — grep
`grep -rn "showSuccessSnackbar\|showErrorSnackbar" lib/core` before using
them verbatim; `chat_settings_screen.dart:85` already uses
`context.showSuccessSnackbar` so this is confirmed to exist, but confirm
`showErrorSnackbar` exists too and use whatever the real error-snackbar
method is named if different.)

Add the required import at the top of the file if not already present:

```dart
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
```

- [ ] **Step 3: Add `_confirmAndDelete` helper**

Add near the bottom of the file, alongside other private helper functions
(check the file's existing convention for where such helpers live —
likely near `onJumpToParent`/`onReply` if those are also file-level
functions rather than methods; match whatever's there):

```dart
Future<void> _confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
  Message message,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await ref
        .read(chatControllerProvider(conversation).notifier)
        .deleteMessage(message);
  } catch (_) {
    if (context.mounted) {
      context.showErrorSnackbar("Couldn't delete — try again.");
    }
  }
}
```

- [ ] **Step 4: Add `_showEditDialog` helper**

```dart
Future<void> _showEditDialog(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
  Message message,
) async {
  final controller = TextEditingController(text: message.content);
  final newContent = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit message'),
      content: TextField(controller: controller, maxLines: null, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();

  if (newContent == null || newContent.isEmpty || newContent == message.content) {
    return;
  }

  try {
    await ref
        .read(chatControllerProvider(conversation).notifier)
        .editMessage(message, newContent);
  } catch (_) {
    if (context.mounted) {
      context.showErrorSnackbar("Couldn't save edit — try again.");
    }
  }
}
```

- [ ] **Step 4b: Add `_showEditHistorySheet` helper**

Add immediately after `_showEditDialog`, following the same free-function
style:

```dart
Future<void> _showEditHistorySheet(
  BuildContext context,
  WidgetRef ref,
  Message message,
) async {
  final repository = ref.read(chatRepositoryProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: FutureBuilder<List<MessageEditHistoryEntry>>(
          future: repository.getMessageEditHistory(message.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final entries = snapshot.data!;
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Edit history', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...entries.map(
                  (entry) => ListTile(
                    title: Text(entry.previousContent),
                    subtitle: Text(DateFormat.yMMMd().add_jm().format(entry.editedAt)),
                  ),
                ),
                ListTile(
                  title: Text(message.content),
                  subtitle: const Text('Current'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
```

Add the required import at the top of `chat_screen.dart` if not already
present: `import 'package:intl/intl.dart';` (used elsewhere in this file
already for `DateFormat` per `message_bubble.dart`'s pattern — confirm
before adding a duplicate import).

- [ ] **Step 5: Add the pinned-messages banner**

Find where the message `ListView.builder` (around line 1102) sits inside
its parent layout (likely a `Column` under the AppBar). Add a banner
widget immediately above it, only when pins exist:

```dart
if (state.pinnedMessages.isNotEmpty)
  _PinnedMessagesBanner(
    pinnedMessages: state.pinnedMessages,
    onTap: (message) => onJumpToParent(message.id, state.messages),
  ),
```

(Reuses the existing `onJumpToParent` function already defined in this
file for reply-jump — same scroll-and-highlight mechanism, per the
design spec's explicit reuse decision.)

Add the banner widget at the bottom of the file:

```dart
class _PinnedMessagesBanner extends StatelessWidget {
  const _PinnedMessagesBanner({required this.pinnedMessages, required this.onTap});

  final List<Message> pinnedMessages;
  final void Function(Message) onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: pinnedMessages.length,
          itemBuilder: (context, index) {
            final message = pinnedMessages[index];
            return InkWell(
              onTap: () => onTap(message),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        message.isDeleted ? 'This message was deleted' : message.content,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Load starred/pinned state when the screen initializes**

Find where `ChatController`'s `_init()` (in `chat_state.dart`) or
`ChatScreen`'s `initState`/build-time setup already loads initial data
(e.g. wherever `getMessages` is first called). Add a call to populate
`pinnedMessages` at the same point:

In `ChatController._init()` (`chat_state.dart`), after the existing
initial message load, add:

```dart
    try {
      final pins = await _repository.getPinnedMessages(initialConversation.relationshipId);
      if (mounted) state = state.copyWith(pinnedMessages: pins);
    } catch (_) {
      // Best-effort — pinned banner just doesn't show if this fails,
      // never blocks the rest of chat from loading.
    }
```

(Match the exact surrounding `_init()` structure — read it first; this
snippet shows intent, adapt indentation/ordering to fit around whatever
already runs there without disturbing the existing message-load
sequence.)

Also subscribe pin changes on the existing realtime listener so the
banner updates live when the partner pins/unpins — find where
`watchConversationEvents` is already subscribed inside `_init()` or a
`_subscribeRealtime()`-style method, and after that event fires, also
refetch pins (or add a similar subscription using the new
`watchPinnedMessages` — since Task 3 made both streams share the same
underlying controller, a single existing `watchConversationEvents`
listener already fires for pin changes too; just make its handler also
call `_repository.getPinnedMessages(...)` and update
`state.pinnedMessages`, not just re-fetch messages).

- [ ] **Step 7: Run the full app test suite for chat**

Run: `flutter test test/features/chat/`
Expected: PASS, no regressions.

- [ ] **Step 8: Run `dart analyze` on every file touched this task**

Run: `dart analyze lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart
git commit -m "feat(chat): wire message actions into ChatScreen — edit/delete dialogs, pinned banner, copy/star handlers"
```

---

### Task 9: Starred messages screen

**Files:**
- Create: `lib/features/chat/presentation/screens/starred_messages_screen.dart`
- Modify: `lib/features/chat/presentation/screens/chat_settings_screen.dart`
- Modify: `lib/app/routing/app_router.dart`

**Interfaces:**
- Consumes: `ChatRepository.getStarredMessages` (Task 3).
- Produces: a reachable screen — this is the plan's final task.

- [ ] **Step 1: Read the router's existing route-registration pattern**

Read `lib/app/routing/app_router.dart` for how `previousRelationships` (a
recently-added route, per prior session context) or `chatImport` is
registered — exact `GoRoute`/`name`/`builder` shape to copy.

- [ ] **Step 2: Write the screen**

```dart
// lib/features/chat/presentation/screens/starred_messages_screen.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final starredMessagesProvider = FutureProvider<List<Message>>((ref) async {
  final repository = ref.watch(chatRepositoryProvider);
  return repository.getStarredMessages();
});

/// Private per-user list — never shows the partner's starred messages
/// (message_stars RLS is owner-only; see
/// docs/superpowers/specs/2026-08-13-message-actions-design.md decision 5).
class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starredAsync = ref.watch(starredMessagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Starred messages')),
      body: starredAsync.when(
        data: (messages) {
          if (messages.isEmpty) {
            return const Center(child: Text('No starred messages yet.'));
          }
          return ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return ListTile(
                title: Text(
                  message.isDeleted ? 'This message was deleted' : message.content,
                ),
                subtitle: Text(DateFormat.yMMMd().add_jm().format(message.createdAt)),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load starred messages.")),
      ),
    );
  }
}
```

- [ ] **Step 3: Register the route**

In `lib/app/routing/app_router.dart`, add a `GoRoute` for
`starredMessages` following the exact pattern found in Step 1 (likely
inside the same route group as `previousRelationships`/`chatImport`):

```dart
    GoRoute(
      name: 'starredMessages',
      path: 'starred-messages',
      builder: (context, state) => const StarredMessagesScreen(),
    ),
```

(Match the real parent route's path prefix/nesting exactly — copy the
`previousRelationships` entry's structure verbatim except for
name/path/builder, since that's the most recently added sibling route in
this same feature area.)

Add the import at the top of `app_router.dart`:

```dart
import 'package:attune/features/chat/presentation/screens/starred_messages_screen.dart';
```

- [ ] **Step 4: Add the entry point in `ChatSettingsScreen`**

In `lib/features/chat/presentation/screens/chat_settings_screen.dart`,
add a new `InfoRowWidget` after the existing "Previous relationships" row
(around line 238, before the historical-import conditional block):

```dart
              InfoRowWidget(
                title: 'Starred messages',
                subtitle: 'Messages you\'ve starred, just for you',
                icon: Icons.star_border,
                showAvatar: false,
                showDivider: false,
                onTap: () => context.pushNamed('starredMessages'),
              ),
```

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/screens/starred_messages_screen.dart lib/app/routing/app_router.dart lib/features/chat/presentation/screens/chat_settings_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Manually verify navigation**

This screen has no automated test in this task (a `FutureProvider` +
simple list — the repository method it calls, `getStarredMessages`, is
already covered by Task 3's repository work; screen-level testing is
lower-value here than for the interactive widgets in Tasks 5-7). Note in
your report that this was a deliberate scope call, not an oversight.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/presentation/screens/starred_messages_screen.dart lib/app/routing/app_router.dart lib/features/chat/presentation/screens/chat_settings_screen.dart
git commit -m "feat(chat): add starred messages screen, reachable from Chat Settings"
```

---

### Task 10: Full regression pass + `CHAT_SYSTEM_SPEC.md` amendment

**Files:**
- Modify: `lib/architecture/CHAT_SYSTEM_SPEC.md`

**Interfaces:**
- Consumes: everything from Tasks 1-9.
- Produces: nothing — this is the plan's final verification + doc-sync task.

- [ ] **Step 1: Run the full Flutter test suite**

Run: `flutter test`
Expected: PASS, no regressions anywhere in the app (not just the chat
feature — confirms nothing in `UniversalBubble`'s shared-widget change
broke forums or any other consumer).

- [ ] **Step 2: Run `dart analyze` on the whole project**

Run: `dart analyze`
Expected: `No issues found!`, or only pre-existing issues unrelated to
this feature (if any pre-existing issues exist, confirm via `git stash`
+ re-run that they predate this branch before treating them as
acceptable).

- [ ] **Step 3: Amend `CHAT_SYSTEM_SPEC.md`**

In `lib/architecture/CHAT_SYSTEM_SPEC.md`:

- §1.3 (line 106-108): update "Message editing, deletion, reactions,
  voice, video, and link previews are not launch behavior" to remove
  "editing, deletion" from that list, and add a sentence: "Message
  editing and deletion shipped under the retention/audit contract in
  `docs/superpowers/specs/2026-08-13-message-actions-design.md` — soft
  delete with a visible tombstone, kept edit history, 5-minute window,
  no retroactive analysis retraction. Reactions, voice, video, and link
  previews remain out of scope."
- §1.4's scope table (line 116): remove "message editing/deletion" from
  the "Month 4" row's feature list, since it's no longer future work.
- §19 (Resolved decisions table, line ~1193): update the "Message
  edit/delete" row's value from "Month 4 under a separate contract" to
  "Shipped — see 2026-08-13-message-actions-design.md" (or the exact
  existing table format/column names — read the table first, match its
  real structure).

Do not touch any other section — this task is a narrow, targeted doc sync,
not a general spec revision.

- [ ] **Step 4: Commit**

```bash
git add lib/architecture/CHAT_SYSTEM_SPEC.md
git commit -m "docs(chat): amend CHAT_SYSTEM_SPEC.md — message edit/delete shipped, no longer Month-4 gated"
```

---

## Algorithm Quality Review Checklist v3.1 — scoping and gate

Scope tags: `[MOBILE][MUTATION]`. See the design spec's own checklist
section for the full walkthrough (2.1, 2.5, 2.16, 2.17, 2.18, 2.22, 5.x)
— every task above implements exactly what that section specifies. The
final whole-branch review (after Task 10, per
`superpowers:subagent-driven-development`) should re-verify each item
against the merged diff, the same pattern used for the
chat-pulse-integration feature's final review.

## Manual verification required after merge (human with live Supabase access)

1. Apply `supabase/migrations/20260813120000_message_actions.sql` via
   `supabase db push --linked` (sandboxed dev environment cannot do this).
2. Confirm `delete_message`/`edit_message`/`pin_message` RPCs are
   callable end-to-end against a live relationship.
3. Confirm the 5-minute window is enforced against real wall-clock time
   (not just the SQL's own `now()` semantics — verify by editing/deleting
   a message just under and just over 5 minutes old).
4. Confirm `message_edit_history` has zero UPDATE/DELETE grant for
   `authenticated` on the live project (Checklist 2.22).
