import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the partner is viewing this conversation right now.
///
/// Polled rather than realtime, deliberately. Presence is a heartbeat: a
/// row rewritten every 20 seconds by each open chat. Subscribing to
/// chat_presence over the websocket would deliver an event per beat per
/// partner, all to render one line of text -- and would need that table
/// added to the realtime publication, widening what replication carries
/// for no benefit. A 15-second poll of a boolean is no less accurate than
/// a 45-second freshness window allows.
///
/// autoDispose, with the timer cancelled on dispose: a Stream.periodic
/// here kept ticking after the chat closed, which left a pending timer in
/// every widget test and, in the app, a poll per conversation ever opened
/// running for the rest of the session.
final partnerActiveInChatProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, relationshipId) {
      final repository = ref.watch(chatRepositoryProvider);
      final controller = StreamController<bool>();
      Timer? timer;
      var closed = false;

      Future<void> poll() async {
        if (closed) return;
        // The chat stays mounted behind the privacy cover and the lock
        // check (stories Wave 3): no RPC while Attune is not on screen.
        if (!ref.read(appContentVisibleProvider)) return;
        final active = await repository.partnerIsActiveInChat(relationshipId);
        if (closed || controller.isClosed) return;
        controller.add(active);
      }

      // Emitted immediately so the indicator does not wait a full interval
      // to appear on a chat the partner is already in.
      unawaited(poll());

      // Shorter than the 45-second freshness window, so the state can be
      // observed at least twice before it expires: one dropped poll must
      // not flicker the indicator off.
      timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());

      // One catch-up poll as soon as Attune is back on screen, rather than
      // up to 15 s of a stale line (final review I3).
      ref.listen<bool>(appContentVisibleProvider, (prev, next) {
        if (next && prev == false) unawaited(poll());
      });

      ref.onDispose(() {
        closed = true;
        timer?.cancel();
        unawaited(controller.close());
      });

      return controller.stream;
    });
