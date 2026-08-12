# Chat Reply/Thread + Shared UniversalBubble Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring swipe-to-reply, quoted-reply preview, and tap-to-jump-to-parent (with a highlight flash) into 1:1 chat, sharing the underlying bubble/gesture/animation widget with the forum debate room instead of duplicating it a second time.

**Architecture:** A new `messages.reply_to_message_id`/`quoted_text` column pair (mirroring `forum_posts`) flows through `Message`, `ChatRepository.sendTextMessage`, `PendingSend` (offline outbox), and `ChatController.sendMessage`. A new shared `UniversalBubble` widget in `lib/core/widgets/` is extracted from `ForumPostBubble`'s existing swipe/quote/jump/highlight machinery; both `MessageBubble` and `ForumPostBubble` become thin wrappers around it, so the two callers' existing visible behavior is unchanged except that chat gains the new gestures for the first time.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + RLS + `flutter_slidable`), existing `AnimatedScaleFade`/`ShakeTransition`/`SettleIn` animation widgets.

## Global Constraints

- Chat messages have no reply-thread UI in comments/likes/report — this plan adds ONLY swipe-to-reply, quoted preview, and jump-to-parent to chat. No likes, no report, no "N replies" bottom sheet (see design spec's Out of Scope).
- `CommentThreadScreen`'s card-shaped reply system is NOT touched by this plan.
- `MessageBubble`/`ForumPostBubble` must remain visually and behaviorally identical to their current appearance for every feature that already exists on them — this is a refactor for existing behavior, an addition only for chat's new gestures. `test/features/chat/message_bubble_test.dart`'s existing 6 tests must all still pass unmodified.
- Design spec: `docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md`.

---

## File Structure

- **Modify** `supabase/migrations/` — new migration file adding `reply_to_message_id`/`quoted_text` to `public.messages`, a validation trigger, and the column-level INSERT grant update.
- **Modify** `lib/features/chat/domain/entities/message.dart` — add `replyToMessageId`/`quotedText` fields.
- **Modify** `lib/features/chat/data/cache/pending_send.dart` — add the same two fields to the offline-outbox model.
- **Modify** `lib/features/chat/data/repositories/chat_repository.dart` — extend `sendTextMessage`'s signature.
- **Modify** `lib/features/chat/data/repositories/supabase_chat_repository.dart` — extend `_messageColumns`, the insert body, and `sendTextMessage`'s implementation.
- **Modify** `lib/features/chat/presentation/state/chat_state.dart` — `sendMessage` accepts an optional reply target; `_attemptSend`/`_restorePendingMessages` thread the fields through.
- **Create** `lib/core/widgets/universal_bubble.dart` — the new shared widget.
- **Modify** `lib/features/chat/presentation/widgets/message_bubble.dart` — becomes a thin wrapper over `UniversalBubble`, gains swipe-to-reply + jump-to-parent params.
- **Modify** `lib/features/forums/presentation/widgets/forum_post_bubble.dart` — becomes a thin wrapper over `UniversalBubble`, same external behavior.
- **Modify** `lib/features/chat/presentation/screens/chat_screen.dart` — reply-target state, `GlobalKey` registry for jump-to-parent, quoted-preview strip above the composer, wires `onReply`/`onJumpToParent`/`isHighlighted` into each `MessageBubble`.
- **Test:** `test/features/chat/message_bubble_test.dart` (existing, must still pass), `test/core/widgets/universal_bubble_test.dart` (new).

---

## Task 1: Database migration — reply columns, validation trigger, insert grant

**Files:**
- Create: `supabase/migrations/20260827120000_chat_message_replies.sql`

**Interfaces:**
- Produces: `public.messages.reply_to_message_id` (uuid, nullable, FK to `public.messages.id` ON DELETE SET NULL), `public.messages.quoted_text` (text, nullable). A `BEFORE INSERT` trigger `validate_message_reply_before_insert` that rejects a reply whose parent is in a different relationship. `authenticated` gains INSERT grant on both new columns.

- [ ] **Step 1: Write the migration file**

```sql
-- Reply/quote support for 1:1 chat messages, mirroring forum_posts'
-- reply_to_post_id/quoted_text exactly (same reasoning: quoted_text is a
-- content snapshot so the preview survives the parent being edited/removed
-- later, avoiding a join just to render it).
-- See docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reply_to_message_id uuid
    REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS quoted_text text;

COMMENT ON COLUMN public.messages.reply_to_message_id IS
  'Parent message this one replies to, if any. ON DELETE SET NULL: message deletion is not a launch feature, but a reply must never be force-deleted just because its parent is removed later.';
COMMENT ON COLUMN public.messages.quoted_text IS
  'Snapshot of the parent message''s content at reply time, for rendering the quoted-preview block without a join.';

-- A reply's parent must be a message in the SAME relationship — messages_
-- insert_sender_active (20260705120000_chat_system_v1_2.sql) already
-- restricts relationship_id to the caller's own active relationship, but
-- says nothing about reply_to_message_id independently pointing somewhere
-- else. RLS alone can't express "these two columns must agree," hence a
-- trigger — same pattern as validate_message_media_before_insert
-- (20260705133000_chat_media_month2.sql).
CREATE OR REPLACE FUNCTION public.validate_message_reply_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_relationship_id uuid;
BEGIN
  IF NEW.reply_to_message_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT relationship_id INTO v_parent_relationship_id
  FROM public.messages
  WHERE id = NEW.reply_to_message_id;

  IF v_parent_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Reply target message does not exist';
  END IF;

  IF v_parent_relationship_id IS DISTINCT FROM NEW.relationship_id THEN
    RAISE EXCEPTION 'Reply target must be in the same relationship';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_message_reply_before_insert ON public.messages;
CREATE TRIGGER validate_message_reply_before_insert
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.validate_message_reply_before_insert();

-- messages_insert_sender_active's column-level GRANT
-- (20260705120000_chat_system_v1_2.sql) is an explicit allowlist — without
-- adding these two columns to it, every reply insert fails with a
-- permission error even though the row-level policy itself would allow it.
REVOKE INSERT ON public.messages FROM authenticated;
GRANT INSERT (
  relationship_id,
  sender_id,
  client_message_id,
  content,
  media_url,
  media_type,
  reply_to_message_id,
  quoted_text
) ON public.messages TO authenticated;
```

- [ ] **Step 2: Apply the migration to the linked Supabase project**

Run: `npx supabase db push --linked`

Confirm the prompt lists exactly `20260827120000_chat_message_replies.sql`, then accept.

- [ ] **Step 3: Verify the trigger rejects a cross-relationship reply**

Run this against the project's SQL editor (or via `psql`) using two real relationship IDs and a real message ID from a DIFFERENT relationship than the one being inserted into — confirm it raises `Reply target must be in the same relationship`. This is a manual verification step (no automated DB test harness exists in this repo for edge functions/triggers) — note the result in the task's completion comment.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260827120000_chat_message_replies.sql
git commit -m "feat(chat): add reply_to_message_id/quoted_text to messages"
```

---

## Task 2: `Message` entity gains reply fields

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Test: `test/features/chat/message_reply_fields_test.dart` (new)

**Interfaces:**
- Consumes: nothing new (pure entity change).
- Produces: `Message.replyToMessageId` (`String?`), `Message.quotedText` (`String?`) — read by `_hydrateMessages` (Task 3), `ChatController` (Task 5), `UniversalBubble`/`MessageBubble` (Task 7).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/message_reply_fields_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message reply fields', () {
    test('fromRow reads reply_to_message_id and quoted_text', () {
      final message = Message.fromRow({
        'id': 'm2',
        'relationship_id': 'r1',
        'sender_id': 'them',
        'client_message_id': 'c2',
        'content': 'sounds good',
        'created_at': '2026-08-12T10:00:00Z',
        'delivered_at': null,
        'read_at': null,
        'media_url': null,
        'media_thumbnail_url': null,
        'media_type': null,
        'source': 'native',
        'reply_to_message_id': 'm1',
        'quoted_text': 'want to grab lunch?',
      }, currentUserId: 'me');

      expect(message.replyToMessageId, 'm1');
      expect(message.quotedText, 'want to grab lunch?');
    });

    test('fromRow tolerates missing reply columns (both null)', () {
      final message = Message.fromRow({
        'id': 'm2',
        'relationship_id': 'r1',
        'sender_id': 'them',
        'client_message_id': 'c2',
        'content': 'hi',
        'created_at': '2026-08-12T10:00:00Z',
        'delivered_at': null,
        'read_at': null,
        'media_url': null,
        'media_thumbnail_url': null,
        'media_type': null,
        'source': 'native',
      }, currentUserId: 'me');

      expect(message.replyToMessageId, isNull);
      expect(message.quotedText, isNull);
    });

    test('copyWith preserves reply fields when not overridden', () {
      const message = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 'them',
        content: 'hi',
        createdAt: null == null ? null : null, // placeholder replaced below
        status: MessageStatus.sent,
        isMine: false,
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );
    });

    test('toJson/fromJson round-trips reply fields', () {
      final original = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 'them',
        content: 'hi',
        createdAt: DateTime(2026, 8, 12, 10),
        status: MessageStatus.sent,
        isMine: false,
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      final restored = Message.fromJson(original.toJson());
      expect(restored.replyToMessageId, 'm1');
      expect(restored.quotedText, 'earlier text');
    });

    test('Message.optimistic accepts reply fields', () {
      final message = Message.optimistic(
        id: '_local_c3',
        clientMessageId: 'c3',
        relationshipId: 'r1',
        senderId: 'me',
        content: 'replying now',
        createdAt: DateTime(2026, 8, 12, 11),
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      expect(message.replyToMessageId, 'm1');
      expect(message.quotedText, 'earlier text');
    });
  });
}
```

Delete the third test (`copyWith preserves reply fields when not overridden`) before running — it has a placeholder `createdAt` that won't compile. Replace it with:

```dart
    test('copyWith preserves reply fields when not overridden', () {
      final message = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 'them',
        content: 'hi',
        createdAt: DateTime(2026, 8, 12, 10),
        status: MessageStatus.sent,
        isMine: false,
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      final copied = message.copyWith(status: MessageStatus.read);
      expect(copied.replyToMessageId, 'm1');
      expect(copied.quotedText, 'earlier text');
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/message_reply_fields_test.dart`
Expected: FAIL — `replyToMessageId`/`quotedText` are undefined named parameters on `Message`.

- [ ] **Step 3: Implement the entity change**

In `lib/features/chat/domain/entities/message.dart`, add two fields to the class, threading them through every constructor/factory/method exactly the way `mediaKey`/`mediaType` already are (both are simple nullable `String?` fields with no derived logic):

```dart
  final String? mediaThumbnailKey;
  final String? signedMediaUrl;
  final String? localMediaPath;
  final String source;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final MessageStatus status;
  final bool isMine;
  final String? replyToMessageId;
  final String? quotedText;

  const Message({
    required this.id,
    required this.clientMessageId,
    required this.relationshipId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.status,
    required this.isMine,
    this.mediaKey,
    this.mediaType,
    this.mediaThumbnailKey,
    this.signedMediaUrl,
    this.localMediaPath,
    this.source = 'native',
    this.deliveredAt,
    this.readAt,
    this.replyToMessageId,
    this.quotedText,
  });
```

In `Message.fromRow`, add to the constructor call:

```dart
      replyToMessageId: row['reply_to_message_id'] as String?,
      quotedText: row['quoted_text'] as String?,
```

In `Message.optimistic`, add two optional params and thread them:

```dart
  factory Message.optimistic({
    required String id,
    required String clientMessageId,
    required String relationshipId,
    required String senderId,
    required String content,
    required DateTime createdAt,
    String? mediaKey,
    String? mediaType,
    String? mediaThumbnailKey,
    String? localMediaPath,
    String? replyToMessageId,
    String? quotedText,
  }) {
    return Message(
      id: id,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      content: content,
      createdAt: createdAt,
      mediaKey: mediaKey,
      mediaType: mediaType,
      localMediaPath: localMediaPath,
      source: 'native',
      status: MessageStatus.sending,
      isMine: true,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );
  }
```

In `copyWith`, add both params (same `??` pattern as every other field):

```dart
  Message copyWith({
    // ...existing params...
    String? replyToMessageId,
    String? quotedText,
  }) {
    return Message(
      // ...existing fields...
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      quotedText: quotedText ?? this.quotedText,
    );
  }
```

In `toJson`, add:

```dart
      'replyToMessageId': replyToMessageId,
      'quotedText': quotedText,
```

In `fromJson`, add:

```dart
      replyToMessageId: json['replyToMessageId'] as String?,
      quotedText: json['quotedText'] as String?,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/message_reply_fields_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/features/chat/domain/entities/message.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart test/features/chat/message_reply_fields_test.dart
git commit -m "feat(chat): add replyToMessageId/quotedText to Message entity"
```

---

## Task 3: Repository — send + hydrate reply fields

**Files:**
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`

**Interfaces:**
- Consumes: `Message.replyToMessageId`/`quotedText` from Task 2.
- Produces: `ChatRepository.sendTextMessage(..., replyToMessageId: String?, quotedText: String?)` — consumed by `ChatController._attemptSend` in Task 5.

- [ ] **Step 1: Extend the abstract interface**

In `lib/features/chat/data/repositories/chat_repository.dart`, change:

```dart
  Future<Message> sendTextMessage({
    required String relationshipId,
    required String senderId,
    required String clientMessageId,
    required String content,
    String? mediaKey,
    String? mediaType,
  });
```

to:

```dart
  Future<Message> sendTextMessage({
    required String relationshipId,
    required String senderId,
    required String clientMessageId,
    required String content,
    String? mediaKey,
    String? mediaType,
    String? replyToMessageId,
    String? quotedText,
  });
```

- [ ] **Step 2: Extend `_messageColumns` and the implementation**

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`, change:

```dart
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,source';
```

to:

```dart
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,source,'
      'reply_to_message_id,quoted_text';
```

Change `sendTextMessage`'s signature and insert body (around line 249):

```dart
  @override
  Future<Message> sendTextMessage({
    required String relationshipId,
    required String senderId,
    required String clientMessageId,
    required String content,
    String? mediaKey,
    String? mediaType,
    String? replyToMessageId,
    String? quotedText,
  }) async {
    final user = _currentUser;
    if (senderId != user.id) {
      throw const PostgrestException(
        message: 'Authenticated sender mismatch.',
        code: '42501',
      );
    }
    final row =
        await _supabase
            .from('messages')
            .insert({
              'relationship_id': relationshipId,
              'sender_id': user.id,
              'client_message_id': clientMessageId,
              'content': content,
              'media_url': mediaKey,
              'media_type': mediaType,
              'reply_to_message_id': replyToMessageId,
              'quoted_text': quotedText,
            })
            .select(_messageColumns)
            .single();

    return _hydrateMessage(row, user.id);
  }
```

`_hydrateMessage`/`_hydrateMessages` need no changes — they already call `Message.fromRow(row, ...)` directly, which now reads the two new columns from Task 2.

- [ ] **Step 3: Run dart analyze**

Run: `dart analyze lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart
git commit -m "feat(chat): thread reply fields through ChatRepository.sendTextMessage"
```

---

## Task 4: `PendingSend` gains reply fields (offline outbox)

**Files:**
- Modify: `lib/features/chat/data/cache/pending_send.dart`
- Test: `test/features/chat/pending_send_reply_test.dart` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `PendingSend.replyToMessageId`/`quotedText` — consumed by `ChatController.sendMessage`/`_attemptSend`/`_restorePendingMessages` in Task 5.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/pending_send_reply_test.dart
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PendingSend toJson/fromJson round-trips reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'replying',
      createdAt: DateTime(2026, 8, 12, 9),
      replyToMessageId: 'm1',
      quotedText: 'the earlier message',
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.replyToMessageId, 'm1');
    expect(restored.quotedText, 'the earlier message');
  });

  test('PendingSend.copyWith preserves reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'replying',
      createdAt: DateTime(2026, 8, 12, 9),
      replyToMessageId: 'm1',
      quotedText: 'the earlier message',
    );

    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.replyToMessageId, 'm1');
    expect(copied.quotedText, 'the earlier message');
  });

  test('PendingSend without a reply has null reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'not a reply',
      createdAt: DateTime(2026, 8, 12, 9),
    );

    expect(original.replyToMessageId, isNull);
    expect(original.quotedText, isNull);
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.replyToMessageId, isNull);
    expect(restored.quotedText, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/pending_send_reply_test.dart`
Expected: FAIL — `replyToMessageId` undefined named parameter.

- [ ] **Step 3: Implement**

In `lib/features/chat/data/cache/pending_send.dart`, add the two fields:

```dart
class PendingSend {
  final String clientMessageId;
  final String relationshipId;
  final String senderId;
  final String text;
  final String? localMediaPath;
  final String? mediaMimeType;
  final String? mediaType;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCategory;
  final PendingSendState state;
  final String? replyToMessageId;
  final String? quotedText;

  const PendingSend({
    required this.clientMessageId,
    required this.relationshipId,
    required this.senderId,
    required this.text,
    this.localMediaPath,
    this.mediaMimeType,
    this.mediaType,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCategory,
    this.state = PendingSendState.queued,
    this.replyToMessageId,
    this.quotedText,
  });
```

`copyWith` never needs to CHANGE reply info on retry (only `attempts`/`nextAttemptAt`/`lastErrorCategory`/`state` are ever overridden by callers), so it just needs to keep passing the existing values through unconditionally — add these two lines to the constructor call inside `copyWith`:

```dart
  PendingSend copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastErrorCategory,
    PendingSendState? state,
  }) {
    return PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      text: text,
      localMediaPath: localMediaPath,
      mediaMimeType: mediaMimeType,
      mediaType: mediaType,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCategory: lastErrorCategory ?? this.lastErrorCategory,
      state: state ?? this.state,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );
  }
```

In `toJson`:

```dart
  Map<String, dynamic> toJson() {
    return {
      'clientMessageId': clientMessageId,
      'relationshipId': relationshipId,
      'senderId': senderId,
      'text': text,
      'localMediaPath': localMediaPath,
      'mediaMimeType': mediaMimeType,
      'mediaType': mediaType,
      'createdAt': createdAt.toIso8601String(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt?.toIso8601String(),
      'lastErrorCategory': lastErrorCategory,
      'state': state.name,
      'replyToMessageId': replyToMessageId,
      'quotedText': quotedText,
    };
  }
```

In `fromJson`:

```dart
  factory PendingSend.fromJson(Map<String, dynamic> json) {
    return PendingSend(
      clientMessageId: json['clientMessageId'] as String,
      relationshipId: json['relationshipId'] as String,
      senderId: json['senderId'] as String,
      text: json['text'] as String,
      localMediaPath: json['localMediaPath'] as String?,
      mediaMimeType: json['mediaMimeType'] as String?,
      mediaType: json['mediaType'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt:
          json['nextAttemptAt'] == null
              ? null
              : DateTime.parse(json['nextAttemptAt'] as String),
      lastErrorCategory: json['lastErrorCategory'] as String?,
      state: PendingSendState.values.byName(json['state'] as String),
      replyToMessageId: json['replyToMessageId'] as String?,
      quotedText: json['quotedText'] as String?,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/pending_send_reply_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/features/chat/data/cache/pending_send.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/data/cache/pending_send.dart test/features/chat/pending_send_reply_test.dart
git commit -m "feat(chat): add reply fields to PendingSend offline outbox model"
```

---

## Task 5: `ChatController.sendMessage` accepts an optional reply target

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart`

**Interfaces:**
- Consumes: `Message.replyToMessageId`/`quotedText` (Task 2), `PendingSend.replyToMessageId`/`quotedText` (Task 4), `ChatRepository.sendTextMessage(..., replyToMessageId:, quotedText:)` (Task 3).
- Produces: `ChatController.sendMessage(String content, {String? replyToMessageId, String? quotedText})` — consumed by `ChatScreen._sendDraftText` in Task 8.

- [ ] **Step 1: Modify `sendMessage`**

In `lib/features/chat/presentation/state/chat_state.dart`, change (around line 387):

```dart
  Future<void> sendMessage(String content) async {
    if (!Message.isValidContent(content) || !state.conversation.canSend) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: content,
      createdAt: now,
    );

    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: content,
      createdAt: now,
    );

    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );

    await _attemptSend(pending);
  }
```

to:

```dart
  Future<void> sendMessage(
    String content, {
    String? replyToMessageId,
    String? quotedText,
  }) async {
    if (!Message.isValidContent(content) || !state.conversation.canSend) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: content,
      createdAt: now,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );

    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: content,
      createdAt: now,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );

    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );

    await _attemptSend(pending);
  }
```

- [ ] **Step 2: Thread the fields through `_attemptSend`**

Around line 618, change the `sendTextMessage` call:

```dart
      final canonical = await repository.sendTextMessage(
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        clientMessageId: pending.clientMessageId,
        content: pending.text,
        mediaKey: mediaKey,
        mediaType: pending.mediaType,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );
```

- [ ] **Step 3: Thread the fields through `_restorePendingMessages`**

Around line 903, change:

```dart
    return queue.map((pending) {
      return Message.optimistic(
        id: '_local_${pending.clientMessageId}',
        clientMessageId: pending.clientMessageId,
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        content: pending.text,
        createdAt: pending.createdAt,
        mediaType: pending.mediaType,
        localMediaPath: pending.localMediaPath,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      ).copyWith(
        status: switch (pending.state) {
          PendingSendState.failedPermanent => MessageStatus.failed,
          PendingSendState.sending => MessageStatus.sending,
          PendingSendState.queued => MessageStatus.queued,
        },
      );
    }).toList();
```

- [ ] **Step 4: Run dart analyze**

Run: `dart analyze lib/features/chat/presentation/state/chat_state.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the existing chat controller tests to confirm no regression**

Run: `flutter test test/features/chat/chat_controller_test.dart`
Expected: PASS (all existing tests, since `replyToMessageId`/`quotedText` default to null and every existing call site omits them)

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart
git commit -m "feat(chat): ChatController.sendMessage accepts an optional reply target"
```

---

## Task 6: `UniversalBubble` shared widget

**Files:**
- Create: `lib/core/widgets/universal_bubble.dart`
- Test: `test/core/widgets/universal_bubble_test.dart` (new)

**Interfaces:**
- Consumes: `flutter_slidable` (`Slidable`, `ActionPane`, `SlidableAction`, `DismissiblePane`), `AnimatedScaleFade`, existing app color scheme extensions.
- Produces: `UniversalBubble` widget — consumed by `MessageBubble` (Task 7) and `ForumPostBubble` (Task 9). Full param list below.

This task extracts the generic bubble/swipe/quote/jump/highlight shell from `ForumPostBubble` (`lib/features/forums/presentation/widgets/forum_post_bubble.dart`, the `build()` method's `Align > Padding > IntrinsicWidth > Slidable > Row > ... > DecoratedBox` structure) into a widget that takes content, colors, and callbacks as parameters instead of forum-specific fields.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/widgets/universal_bubble_test.dart
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('isMine=true aligns bubble to the right', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('isMine=false aligns bubble to the left', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('hello'),
        footer: const SizedBox.shrink(),
      ),
    );

    final align = tester.widget<Align>(find.byType(Align).first);
    expect(align.alignment, Alignment.centerLeft);
  });

  testWidgets('renders content and footer', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: true,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('bubble content'),
        footer: const Text('footer content'),
      ),
    );

    expect(find.text('bubble content'), findsOneWidget);
    expect(find.text('footer content'), findsOneWidget);
  });

  testWidgets('quotedText renders a tappable preview block that calls onJumpToParent',
      (tester) async {
    var jumped = false;
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('reply body'),
        footer: const SizedBox.shrink(),
        quotedText: 'the original message',
        onJumpToParent: () => jumped = true,
      ),
    );

    expect(find.text('the original message'), findsOneWidget);
    await tester.tap(find.text('the original message'));
    expect(jumped, isTrue);
  });

  testWidgets('no quotedText means no quote block rendered', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('plain message'),
        footer: const SizedBox.shrink(),
      ),
    );

    expect(find.byIcon(Icons.format_quote), findsNothing);
  });

  testWidgets('startActionPane is wired into the Slidable', (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('swipeable'),
        footer: const SizedBox.shrink(),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) {},
              icon: Icons.reply,
              label: 'Reply',
            ),
          ],
        ),
      ),
    );

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidable.startActionPane, isNotNull);
  });

  testWidgets('no action panes means Slidable still renders with null panes',
      (tester) async {
    await _pump(
      tester,
      UniversalBubble(
        isMine: false,
        bubbleColor: Colors.blue,
        onBubbleColor: Colors.white,
        content: const Text('no gestures'),
        footer: const SizedBox.shrink(),
      ),
    );

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidable.startActionPane, isNull);
    expect(slidable.endActionPane, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: FAIL — `UniversalBubble` does not exist.

- [ ] **Step 3: Implement `UniversalBubble`**

```dart
// lib/core/widgets/universal_bubble.dart

import 'package:attune/core/utils/animations/animated_scale_fade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// The shared bubble shell behind both MessageBubble (1:1 chat) and
/// ForumPostBubble (debate room) — alignment, fill color, swipe gestures,
/// quoted-reply preview + tap-to-jump, and the jump highlight-flash all
/// used to be duplicated between the two features (ForumPostBubble's own
/// doc comment: "This mirrors MessageBubble in the 1:1 chat feature
/// exactly"). Extracted here so it exists once; each caller supplies its
/// own content, footer, colors, and swipe actions.
///
/// See docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md.
class UniversalBubble extends StatelessWidget {
  const UniversalBubble({
    super.key,
    required this.isMine,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.content,
    required this.footer,
    this.leading,
    this.startActionPane,
    this.endActionPane,
    this.quotedText,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.maxWidth = 320,
  });

  /// True puts the bubble on the right, false on the left.
  final bool isMine;

  /// Bubble fill color. Chat passes colorScheme.primary (mine) /
  /// surfaceContainerHighest (theirs); forums passes colorScheme.primary
  /// (mine) / onBackground (theirs) — each caller keeps its own existing
  /// pairing, this widget does not choose one.
  final Color bubbleColor;

  /// Color for content painted on top of [bubbleColor] (text, icons).
  final Color onBubbleColor;

  /// The bubble's main content — a Text for a forum post, a richer
  /// image+caption layout for a chat message with media.
  final Widget content;

  /// The row below the bubble, outside its fill — chat's time/status-chip
  /// row, or forum's time/like/reply/report/side-badge row.
  final Widget footer;

  /// Leading widget beside the bubble (forum's status avatar). Null means
  /// nothing renders there — chat has no per-message avatar today.
  final Widget? leading;

  /// Swipe-right-to-left action pane (e.g. Reply). Null disables that
  /// swipe direction entirely.
  final ActionPane? startActionPane;

  /// Swipe-left-to-right action pane (e.g. Report/Delete). Null disables
  /// that swipe direction entirely.
  final ActionPane? endActionPane;

  /// The quoted parent-message preview text, shown above [content] inside
  /// the bubble when this message/post IS a reply. Null means this isn't a
  /// reply — no quote block renders at all.
  final String? quotedText;

  /// Tapping the quote block calls this — the caller is responsible for
  /// scrolling to and highlighting the actual parent (see
  /// ChatScreen/DebateRoomScreen's own jump implementations). Null means
  /// the quote block renders without a tap affordance (e.g. inside a
  /// replies-only bottom sheet with no independent scroll position).
  final VoidCallback? onJumpToParent;

  /// True while this bubble is the current jump-to target — flashes a
  /// colored border ring that fades back out, so the eye lands on the
  /// right bubble after a jump.
  final bool isHighlighted;

  /// Max bubble width in logical pixels before content wraps.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // IntrinsicWidth: Slidable internally builds a Stack for its action
        // panes, which expands to fill whatever width it's handed
        // regardless of its child's own size — without this every bubble
        // renders full-width and Align's left/right positioning above is
        // silently defeated (see ForumPostBubble's identical comment on
        // this, which is where this fix was first discovered).
        child: IntrinsicWidth(
          child: Slidable(
            startActionPane: startActionPane,
            endActionPane: endActionPane,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                Flexible(
                  child: Column(
                    crossAxisAlignment:
                        isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  isHighlighted
                                      ? bubbleColor
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(2),
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
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: onBubbleColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.format_quote,
                                              size: 20,
                                              color: onBubbleColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                quotedText!,
                                                style: TextStyle(
                                                  color: onBubbleColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: footer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Note: `AnimatedScaleFade` is imported but unused directly in this file — it's referenced by callers (forum's replies row already uses it independently). Remove that import; it's not needed here. Re-check imports compile clean in Step 5.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/universal_bubble_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Run dart analyze and remove unused imports if flagged**

Run: `dart analyze lib/core/widgets/universal_bubble.dart`
Expected: `No issues found!` — if the `animated_scale_fade.dart` import is flagged unused, remove it.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/universal_bubble.dart test/core/widgets/universal_bubble_test.dart
git commit -m "feat(core): add shared UniversalBubble widget"
```

---

## Task 7: `MessageBubble` becomes a thin `UniversalBubble` wrapper, gains reply gestures

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Test: `test/features/chat/message_bubble_test.dart` (existing — must still pass unmodified)

**Interfaces:**
- Consumes: `UniversalBubble` (Task 6), `Message.replyToMessageId`/`quotedText` (Task 2).
- Produces: `MessageBubble(message:, onRetry:, onRemove:, showStatus:, onReply:, onJumpToParent:, isHighlighted:)` — consumed by `ChatScreen` in Task 8. `onReply`, `onJumpToParent`, `isHighlighted` are new optional params; every existing param is unchanged.

- [ ] **Step 1: Confirm the existing test file still describes required behavior**

Read `test/features/chat/message_bubble_test.dart` (already shown in context above) — no changes needed to this file. It is the regression gate: every one of its 6 tests must pass after this task's changes with zero modification to the test file itself.

- [ ] **Step 2: Rewrite `MessageBubble` as a `UniversalBubble` wrapper**

Replace `lib/features/chat/presentation/widgets/message_bubble.dart`'s `MessageBubble` class (keep `_BubbleBody` and `_StatusChip` as-is — only `MessageBubble.build` changes) with:

```dart
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'dart:io';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onRemove,
    this.showStatus = true,
    this.onReply,
    this.onJumpToParent,
    this.isHighlighted = false,
  });

  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final bool showStatus;

  /// Swipe-to-reply target. Null (the default) disables the swipe gesture
  /// entirely — e.g. a read-only/archived conversation has nothing
  /// sensible to reply into.
  final VoidCallback? onReply;

  /// Tapping this message's quoted-parent preview (only rendered when
  /// message.quotedText is non-null) calls this to scroll to and flash the
  /// parent. Null means no tap affordance on the quote block.
  final VoidCallback? onJumpToParent;

  /// True while this is the current jump-to target — see UniversalBubble.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final colorScheme = Theme.of(context).colorScheme;

    return UniversalBubble(
      isMine: isMine,
      bubbleColor:
          isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      onBubbleColor:
          isMine ? colorScheme.onPrimary : colorScheme.onSurface,
      quotedText: message.quotedText,
      onJumpToParent: message.quotedText == null ? null : onJumpToParent,
      isHighlighted: isHighlighted,
      startActionPane:
          onReply == null
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                // Reply never removes the message from the list, so this
                // must NEVER actually dismiss — same pattern
                // ForumPostBubble/CommentThreadScreen use: fire onReply
                // from confirmDismiss and veto (return false) to get the
                // past-threshold full-swipe gesture without entering
                // Slidable's resize/removal flow.
                dismissible: DismissiblePane(
                  confirmDismiss: () async {
                    onReply!();
                    return false;
                  },
                  onDismissed: () {},
                  closeOnCancel: true,
                ),
                children: [
                  SlidableAction(
                    onPressed: (_) => onReply!(),
                    backgroundColor:
                        isMine
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                    foregroundColor:
                        isMine ? colorScheme.onPrimary : colorScheme.onSurface,
                    icon: Icons.reply,
                    label: 'Reply',
                  ),
                ],
              ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isImported)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'Imported from WhatsApp',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          _BubbleBody(message: message, isMine: isMine),
        ],
      ),
      footer: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Semantics(
            label: _absoluteTimeLabel(context, message.createdAt),
            excludeSemantics: true,
            child: Text(
              _timeLabel(context, message.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (showStatus && isMine)
            _StatusChip(message: message, onRetry: onRetry),
          if (message.isFailed && onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          if (message.isFailed && onRemove != null)
            TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }

  /// Short, locale-aware clock label shown visually (e.g. "3:04 PM").
  static String _timeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.jm(locale).format(time);
  }

  /// Full absolute date+time announced to screen readers so relative/short
  /// visual times remain accessible (Spec 11.4). Visual semantics are excluded
  /// so the reader announces this label instead of the terse clock string.
  static String _absoluteTimeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMEEEEd(locale).add_jm().format(time);
  }
}
```

Leave `_BubbleBody` and `_StatusChip` classes exactly as they already are in the file (no changes needed — `_BubbleBody`'s own text color logic already branches on `isMine`, which still works since `MessageBubble` still computes and passes `isMine` the same way).

One nuance: `_BubbleBody`'s existing `color` computation uses
`colorScheme.onPrimary`/`colorScheme.onSurface` — confirm this still
matches `UniversalBubble`'s `onBubbleColor` param above (both now say
`colorScheme.onSurface` for the "theirs" case, replacing the original
`colorScheme.onSurface` that `_BubbleBody` already had — no mismatch,
this was already consistent, just now also passed to `UniversalBubble`
for its own quote-block/footer-constraint styling).

- [ ] **Step 3: Run the existing test suite to verify no regression**

Run: `flutter test test/features/chat/message_bubble_test.dart`
Expected: PASS — all 6 existing tests, unmodified, still green.

- [ ] **Step 4: Run dart analyze**

Run: `dart analyze lib/features/chat/presentation/widgets/message_bubble.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart
git commit -m "refactor(chat): MessageBubble wraps UniversalBubble, gains reply gestures"
```

---

## Task 8: `ChatScreen` — reply-target state, quoted-preview strip, jump-to-parent

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`

**Interfaces:**
- Consumes: `MessageBubble(onReply:, onJumpToParent:, isHighlighted:)` (Task 7), `ChatController.sendMessage(content, {replyToMessageId, quotedText})` (Task 5).
- Produces: nothing consumed by later tasks — this is the final integration point.

- [ ] **Step 1: Add reply-target and jump-target state to `_ChatScreenState`**

In `lib/features/chat/presentation/screens/chat_screen.dart`, add fields alongside the existing ones (around line 49-51):

```dart
  final Set<String> _animatedMessageIds = <String>{};
  bool _headerExpanded = false;
  bool _isForeground = true;

  /// Reply target set by swiping a message — mirrors
  /// DebateRoomScreen._replyToPostId/_replyToQuotedText exactly. Null means
  /// no reply is pending; the quoted-preview strip above the composer only
  /// renders when this is non-null.
  String? _replyToMessageId;
  String? _replyToQuotedText;

  /// One GlobalKey per message, registered fresh on every build (never
  /// only-if-absent, so a key never survives past the message it was
  /// created for) — mirrors DebateRoomScreen._postKeys, adapted from that
  /// screen's SliverList to this screen's ListView.builder. Used by
  /// _jumpToMessage to scroll a currently-built message into view.
  final Map<String, GlobalKey> _messageKeys = {};

  /// The message currently flashed as a jump target, and a timer to clear
  /// the flash — mirrors DebateRoomScreen._highlightedPostId/_highlightTimer.
  String? _highlightedMessageId;
  Timer? _highlightTimer;
```

- [ ] **Step 2: Dispose the highlight timer**

In `dispose()` (around line 65-72), add:

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onDraftChanged);
    _controller.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }
```

- [ ] **Step 3: Add reply-target and jump-to-message methods**

Add these methods to `_ChatScreenState`, near `_send`/`_sendDraftText` (around line 133-158):

```dart
  void _setReplyTarget(String messageId, String contentPreview) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToQuotedText =
          contentPreview.length > 60
              ? '${contentPreview.substring(0, 60)}...'
              : contentPreview;
    });
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToMessageId = null;
      _replyToQuotedText = null;
    });
  }

  /// Scrolls to and flashes [messageId] if it's currently built (mounted
  /// GlobalKey). Returns whether it found something to scroll to — the
  /// caller falls back to an index-based estimate when this returns false.
  /// Mirrors DebateRoomScreen._tryEnsureVisible exactly.
  bool _tryEnsureMessageVisible(String messageId) {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) return false;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );

    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
    return true;
  }

  /// Jump to a reply's parent message — mirrors
  /// DebateRoomScreen._jumpToPost exactly, adapted for this screen's
  /// reversed ListView.builder (state.messages is already newest-first,
  /// matching the reversed list's visual top-to-bottom order, so the same
  /// index × averageExtent estimate applies with no sign flip needed).
  Future<void> _jumpToMessage(
    String messageId,
    List<Message> currentMessages,
  ) async {
    if (_tryEnsureMessageVisible(messageId)) return;

    final index = currentMessages.indexWhere((m) => m.id == messageId);
    if (index == -1 || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final averageExtent =
        position.viewportDimension /
        (_messageKeys.isEmpty ? 8 : _messageKeys.length);
    final estimatedOffset = index * averageExtent;

    await _scrollController.animateTo(
      estimatedOffset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    _tryEnsureMessageVisible(messageId);
  }
```

Add the `Message` import needed for `_jumpToMessage`'s parameter type — check whether `lib/features/chat/domain/entities/message.dart` is already imported in this file:

Run: `grep -n "import.*message.dart" lib/features/chat/presentation/screens/chat_screen.dart`

If not present, add `import 'package:attune/features/chat/domain/entities/message.dart';` to the import block at the top of the file.

- [ ] **Step 4: Wire reply-target clearing into `_sendDraftText`**

Change `_sendDraftText` (around line 148-158) from:

```dart
  Future<void> _sendDraftText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendMessage(text);
    _controller.clear();
    await _clearDraft();
    _scrollToLatest();
  }
```

to:

```dart
  Future<void> _sendDraftText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendMessage(
          text,
          replyToMessageId: _replyToMessageId,
          quotedText: _replyToQuotedText,
        );
    _controller.clear();
    await _clearDraft();
    _clearReplyTarget();
    _scrollToLatest();
  }
```

- [ ] **Step 5: Add the quoted-preview strip above the composer**

Find the composer block (around line 462-483):

```dart
          if (conversation.canSend)
            ChatTextField(
              controller: _controller,
              onSend: () {
                unawaited(_send());
              },
              onAttachImage:
                  imageSharingEnabled.valueOrNull == true
                      ? () {
                        unawaited(_attachImage());
                      }
                      : null,
              onOpenTranslator:
                  translatorEnabled.valueOrNull == true
                      ? () {
                        unawaited(_openTranslator());
                      }
                      : null,
              showAttachImage: imageSharingEnabled.valueOrNull == true,
              showTranslator: translatorEnabled.valueOrNull == true,
              enabled: !state.isSending,
            )
```

Change it to add the reply-preview strip immediately before it, inside the same enclosing `Column`/list of children (find the exact enclosing widget by reading the file — insert as a sibling directly above the `if (conversation.canSend)` block):

```dart
          if (conversation.canSend && _replyToMessageId != null)
            AnimatedScaleFade(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: CardInkWell(
                  padding: const EdgeInsets.only(left: 12),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Replying to',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: '\n${_replyToQuotedText ?? ''}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: _clearReplyTarget,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (conversation.canSend)
            ChatTextField(
              controller: _controller,
              onSend: () {
                unawaited(_send());
              },
              onAttachImage:
                  imageSharingEnabled.valueOrNull == true
                      ? () {
                        unawaited(_attachImage());
                      }
                      : null,
              onOpenTranslator:
                  translatorEnabled.valueOrNull == true
                      ? () {
                        unawaited(_openTranslator());
                      }
                      : null,
              showAttachImage: imageSharingEnabled.valueOrNull == true,
              showTranslator: translatorEnabled.valueOrNull == true,
              enabled: !state.isSending,
            )
```

`CardInkWell` and `AnimatedScaleFade` need imports if not already present in this file — check:

Run: `grep -n "import.*card_inkwell\|import.*animated_scale_fade" lib/features/chat/presentation/screens/chat_screen.dart`

If missing, add:
```dart
import 'package:attune/core/utils/animations/animated_scale_fade.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
```

- [ ] **Step 6: Wire `onReply`/`onJumpToParent`/`isHighlighted`/`GlobalKey` registration into the message list**

In the `ListView.builder`'s `itemBuilder` (around line 940-991), find:

```dart
          final message = state.messages[index];
```

and immediately after it, add the key registration (mirrors `DebateRoomScreen`'s `_postKeys[post.id] = GlobalKey()` pattern):

```dart
          final message = state.messages[index];
          final messageKey = _messageKeys[message.id] = GlobalKey();
```

Then change the `MessageBubble` construction:

```dart
          Widget bubble = MessageBubble(
            message: message,
            onRetry:
                message.isFailed
                    ? () => ref
                        .read(
                          chatControllerProvider(state.conversation).notifier,
                        )
                        .retryMessage(message)
                    : null,
            onRemove:
                message.isFailed
                    ? () => ref
                        .read(
                          chatControllerProvider(state.conversation).notifier,
                        )
                        .removeFailedMessage(message)
                    : null,
            onReply:
                state.conversation.canSend
                    ? () => _setReplyTarget(message.id, message.content)
                    : null,
            onJumpToParent:
                message.replyToMessageId == null
                    ? null
                    : () => _jumpToMessage(
                      message.replyToMessageId!,
                      state.messages,
                    ),
            isHighlighted: _highlightedMessageId == message.id,
          );
```

Wrap the final `SettleIn` return in a `KeyedSubtree` using `messageKey` so `_messageKeys` actually resolves to a mounted context — find the existing return (around line 1013-1023):

```dart
          return SettleIn(
            key: ValueKey(message.clientMessageId),
            animate: shouldAnimate,
            duration: staggeredDuration,
            beginOffset:
                message.isMine ? const Offset(0, 0.12) : const Offset(0, 0.10),
            child: bubble,
          );
```

change to:

```dart
          return KeyedSubtree(
            key: messageKey,
            child: SettleIn(
              key: ValueKey(message.clientMessageId),
              animate: shouldAnimate,
              duration: staggeredDuration,
              beginOffset:
                  message.isMine
                      ? const Offset(0, 0.12)
                      : const Offset(0, 0.10),
              child: bubble,
            ),
          );
```

- [ ] **Step 7: Run dart analyze**

Run: `dart analyze lib/features/chat/presentation/screens/chat_screen.dart`
Expected: `No issues found!`

- [ ] **Step 8: Manual verification (no automated widget test exists for ChatScreen's full integration — this is a live-app check)**

Run the app, open a conversation with at least 2 messages, and verify:
1. Swiping a message left reveals a Reply action; releasing past the threshold sets the reply target.
2. The quoted-preview strip appears above the composer showing "Replying to" + a snippet.
3. Tapping the × on the strip clears it.
4. Sending while a reply target is set produces a new message; tapping that new message's quote block scrolls to and briefly highlights the original message.
5. Scroll the parent message far out of view, then jump to it again — confirm the index-based fallback still finds and highlights it (not just the fast path).

Note the result of this manual check in the task's completion comment.

- [ ] **Step 9: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart
git commit -m "feat(chat): swipe-to-reply, quoted preview, jump-to-parent in ChatScreen"
```

---

## Task 9: `ForumPostBubble` becomes a thin `UniversalBubble` wrapper (no behavior change)

**Files:**
- Modify: `lib/features/forums/presentation/widgets/forum_post_bubble.dart`

**Interfaces:**
- Consumes: `UniversalBubble` (Task 6).
- Produces: nothing new — `ForumPostBubble`'s external API (`post`, `userSide`, `onReply`, `replies`, `onShowReplies`, `onJumpToParent`, `isHighlighted`) is unchanged, so `DebateRoomScreen` (its only caller) needs zero changes.

This task is a pure refactor: `ForumPostBubble`'s current `build()` method inlines the same bubble/swipe/quote/jump/highlight shell `UniversalBubble` now provides. Replace that inlined shell with a call to `UniversalBubble`, keeping every forum-specific behavior (like button, report, side badge, replies row, delete) exactly as it is today, just repackaged as `UniversalBubble`'s `footer`/`leading`/`content`/action-pane params.

- [ ] **Step 1: Identify the exact boundary between "shell" and "forum-specific content"**

Re-read `lib/features/forums/presentation/widgets/forum_post_bubble.dart`'s `build()` method (lines 114-542 as read during planning). The shell being replaced is: the outer `Align > Padding > IntrinsicWidth > Slidable > Row > Flexible > Column > ConstrainedBox > AnimatedContainer > DecoratedBox > Padding` structure (lines 158-399), and the quoted-text block inside it (lines 344-385).

Everything forum-specific stays as-is and becomes `UniversalBubble`'s params:
- The `if (!isMine) CircleAvatar(...)` status avatar (lines 272-283) → `leading`.
- The post content `Text(post.content, ...)` (lines 388-393) → the tail of `content` (quote block is now handled by `UniversalBubble` itself via its own `quotedText` param — do NOT duplicate it here).
- The meta row (time, like, reply, report, side badge — lines 400-505) → `footer`.
- The replies row (lines 506-532) → append it as an additional child in the `footer`'s own `Column`, since `UniversalBubble`'s `footer` slot is a single widget (wrap the existing meta-row `Row` plus the conditional replies row in a `Column` when passing to `footer`).
- The `Slidable`'s `startActionPane`/`endActionPane` (lines 183-260) → passed through unchanged as `UniversalBubble.startActionPane`/`endActionPane`.

- [ ] **Step 2: Rewrite `_ForumPostBubbleState.build()`**

Replace the `build()` method's `return Align(...)` block (everything from `return Align(` through its matching closing, i.e. lines 158-541 in the pre-refactor file) with:

```dart
    return UniversalBubble(
      isMine: isMine,
      bubbleColor: bubbleColor,
      onBubbleColor: onBubbleColor,
      quotedText: post.quotedText,
      onJumpToParent: widget.onJumpToParent,
      isHighlighted: widget.isHighlighted,
      leading:
          isMine
              ? null
              : CircleAvatar(
                radius: 14.r,
                backgroundColor: statusIconColor,
                child: Icon(
                  statusIcon,
                  size: 14.r,
                  color: colorScheme.background,
                ),
              ),
      startActionPane:
          !canReply
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                dismissible: DismissiblePane(
                  confirmDismiss: () async {
                    widget.onReply();
                    return false;
                  },
                  onDismissed: () {},
                  closeOnCancel: true,
                ),
                children: [
                  SlidableAction(
                    onPressed: (_) => widget.onReply(),
                    backgroundColor: sideColor,
                    foregroundColor:
                        isForSide ? colorScheme.onPrimary : colorScheme.onAgainst,
                    icon: Icons.reply,
                    label: 'Reply',
                  ),
                ],
              ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          if (!isMine)
            SlidableAction(
              onPressed: (_) => _showReportDialog(),
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.flag_outlined,
              label: 'Report',
            ),
          if (isMine)
            SlidableAction(
              onPressed: (_) async {
                if (await _confirmDeletePost(context)) {
                  await deleteForumPost(
                    ref,
                    postId: post.id,
                    topicId: post.topicId,
                    side: post.side,
                  );
                }
              },
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
        ],
      ),
      content: Text(
        post.content,
        style: textTheme.bodyMedium?.copyWith(color: onBubbleColor),
      ),
      footer: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                timeAgo,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Gap(Spacing.sm.w),
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: Padding(
                  padding: EdgeInsets.all(Spacing.xs.w),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        post.userLiked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color:
                            post.userLiked
                                ? colorScheme.error
                                : colorScheme.onSurface.withOpacity(0.6),
                      ),
                      if (effectiveLikeCount > 0) ...[
                        Gap(Spacing.xs.w),
                        AnimatedRollingCounter(
                          count: effectiveLikeCount,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (canReply) ...[
                Gap(Spacing.sm.w),
                InkWell(
                  onTap: widget.onReply,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.xs.w),
                    child: Text(
                      'Reply',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              Gap(Spacing.xs.w),
              _SideBadge(sideColor: sideColor),
              SizedBox(
                height: 24.h,
                width: 24.w,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'More',
                  icon: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onSelected: (value) {
                    if (value == 'report') _showReportDialog();
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('Report'),
                        ),
                      ],
                ),
              ),
            ],
          ),
          if (widget.replies != null && widget.replies!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: Spacing.xs.h,
                right: Spacing.xl,
                left: Spacing.xl,
              ),
              child: RepliesRow(
                replyStatuses: [
                  for (final reply in widget.replies!) reply.relationshipStatus,
                ],
                replyCount: widget.replies!.length,
                alignEnd: isMine,
                avatarSize: 18,
                overlap: 12,
                maxAvatars: 3,
                accentColor: colorScheme.primary,
                onTap: widget.onShowReplies!,
              ),
            ),
        ],
      ),
    );
  }
```

Add the new import at the top of the file:

```dart
import 'package:attune/core/widgets/universal_bubble.dart';
```

Everything above `return UniversalBubble(...)` in `build()` (the `colorScheme`/`textTheme`/`post`/`effectiveLikeCount`/`isMine`/`isForSide`/`canReply`/`sideColor`/`bubbleColor`/`onBubbleColor`/`statusDisplay`/`statusIcon`/`statusIconColor`/`timeAgo` computations) stays exactly as it already is in the file — only the return statement's shell changes.

`_confirmDeletePost`, `_showReportDialog`, `_buildReportOption`, `_toggleLike`, and the `_SideBadge` class at the bottom of the file are unchanged.

- [ ] **Step 3: Run dart analyze**

Run: `dart analyze lib/features/forums/presentation/widgets/forum_post_bubble.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification against the debate room (no existing automated test file for this widget)**

Run: `find test -iname "*forum_post_bubble*"` to confirm there is genuinely no existing test to run automatically.

Run the app, open a debate room topic with existing posts (including at least one reply), and verify:
1. Bubble alignment/colors are unchanged from before this refactor.
2. Swipe-to-reply still works.
3. Swipe-to-report (others' posts) and swipe-to-delete (own posts) still work.
4. Tapping a quoted-reply block still jumps to and flashes the parent post.
5. The "N replies" row still opens the replies bottom sheet.
6. Like button and report menu still work.

Note the result of this manual check in the task's completion comment.

- [ ] **Step 5: Commit**

```bash
git add lib/features/forums/presentation/widgets/forum_post_bubble.dart
git commit -m "refactor(forums): ForumPostBubble wraps UniversalBubble"
```

---

## Task 10: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full chat + forum + universal-bubble test suite**

Run: `flutter test test/features/chat/ test/core/widgets/universal_bubble_test.dart`
Expected: PASS — every test across `message_bubble_test.dart`, `message_reply_fields_test.dart`, `pending_send_reply_test.dart`, `chat_controller_test.dart`, `universal_bubble_test.dart`, plus every other existing file under `test/features/chat/`.

- [ ] **Step 2: Run `dart analyze` across the whole project**

Run: `dart analyze`
Expected: zero new errors (pre-existing unrelated info/warning-level lints elsewhere in the project are not this plan's concern — only confirm no errors and no new issues in the files this plan touched).

- [ ] **Step 3: Confirm no other callers of the changed signatures were missed**

Run: `grep -rn "sendTextMessage(\|\.sendMessage(" lib --include="*.dart" | grep -v "_test.dart"`

Confirm every call site either passes the new optional params or omits them safely (all existing call sites besides `ChatScreen`/`ChatController` itself should be unaffected since the new params are optional with null defaults).

- [ ] **Step 4: Final commit if any cleanup was needed, otherwise confirm the branch is clean**

Run: `git status --short`

If clean, no commit needed — this task is verification-only.
