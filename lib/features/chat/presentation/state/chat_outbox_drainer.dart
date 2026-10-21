import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Sends what is still queued for chats that are not open.
///
/// A message typed in a tunnel, with the chat then closed, used to wait
/// until that chat was reopened: the only flushers lived in the chat's own
/// controller. On app resume and on connectivity returning this reads the
/// signed-in account's outbox, wakes the controller of every relationship
/// that has waiting rows (or lands on the one already running — the family
/// keys on the relationship), flushes it, and releases it so it is evicted
/// on the usual keep-alive. Warmed once from App.initState.
final chatOutboxDrainerProvider = Provider<ChatOutboxDrainer>((ref) {
  final drainer = ChatOutboxDrainer(ref);
  ref.onDispose(drainer.dispose);
  return drainer;
});

class ChatOutboxDrainer {
  ChatOutboxDrainer(this._ref) {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(drain()));
    _ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        unawaited(drain());
      }
    });
    // A cold start is neither a resume (the app is already resumed when
    // this attaches) nor a connectivity transition (the first value is
    // not one), and a sign-in is neither: drain once for whoever is signed
    // in now, and again for every account that signs in later.
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        scheduleMicrotask(() => unawaited(drain()));
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  /// The pass running now, and the one queued behind it.
  Future<void>? _running;
  Future<void>? _queued;

  /// One pass over the outbox. A call made while a pass runs joins one
  /// more pass after it (connectivity can return while a resume's pass is
  /// still failing offline) and completes when that pass has.
  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) {
      return _queued ??= running.then((_) {
        _queued = null;
        return drain();
      });
    }
    final run = _drainOnceSafely();
    _running = run;
    return run.whenComplete(() {
      if (identical(_running, run)) _running = null;
    });
  }

  Future<void> _drainOnceSafely() async {
    try {
      await _drainOnce();
    } catch (error) {
      ChatLog.e('outbox drain failed', error);
    }
  }

  Future<void> _drainOnce() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;
    final userId = user.id;
    // Signed out or into another account since the pass began: this
    // pass's queue and relationships belong to the previous account.
    bool accountChanged() => _ref.read(currentUserProvider)?.id != userId;

    final cache = _ref.read(chatCacheServiceProvider);
    final queue = await cache.readOutbox(userId);
    final relationshipIds = <String>{
      for (final item in queue)
        if (item.senderId == userId &&
            item.state != PendingSendState.failedPermanent)
          item.relationshipId,
    };
    if (relationshipIds.isEmpty || accountChanged()) return;

    final timeout = _ref.read(chatConfigProvider).networkTimeout;
    List<Conversation> conversations;
    try {
      conversations = await _ref
          .read(conversationsProvider.future)
          .timeout(timeout);
    } catch (_) {
      // Offline or slow: the list this device last held still names the
      // relationships; a queued row for one that ended is told so by its
      // own controller (Spec 16).
      conversations = await cache.readConversations(userId);
    }

    for (final conversation in conversations) {
      if (_disposed || accountChanged()) return;
      // Not in the list: the relationship is gone, nothing may send for it.
      if (!relationshipIds.remove(conversation.relationshipId)) continue;
      if (conversation.isArchived) continue;
      // Listening (not just reading) keeps the autoDispose controller alive
      // for the flush; closing the subscription afterwards starts its
      // normal keep-alive eviction.
      final subscription = _ref.listen<ChatState>(
        chatControllerProvider(conversation),
        (_, __) {},
      );
      try {
        final controller = _ref.read(
          chatControllerProvider(conversation).notifier,
        );
        // Let a freshly woken chat finish its open (outbox restore, first
        // page) first: a flush racing the restore could leave a stale local
        // bubble beside the row it just sent. An open that takes longer
        // than this ends in the chat's own open-time flush instead.
        await controller.whenOpened.timeout(timeout * _openBoundRequests);
        if (_disposed || accountChanged()) return;
        // One chat's slow pass must not hold the others; it carries on in
        // its controller either way.
        await controller.flushOutbox(force: true).timeout(timeout);
      } catch (error) {
        ChatLog.e(
          'outbox drain failed '
          'rel=${ChatLog.shortId(conversation.relationshipId)}',
          error,
        );
      } finally {
        subscription.close();
      }
    }
  }

  /// The open is a few bounded requests in a row (first page, header,
  /// pins, delivered); wait for about that many.
  static const _openBoundRequests = 4;

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
