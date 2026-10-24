import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Posts what is waiting without anyone opening Conversations (01 #9), the
/// story twin of `ChatOutboxDrainer`: on app resume, on connectivity
/// returning, and once for whoever is signed in (cold start and every later
/// sign-in). Warmed once from `App.initState`.
final storyOutboxTriggersProvider = Provider<StoryOutboxTriggers>((ref) {
  final triggers = StoryOutboxTriggers(ref);
  ref.onDispose(triggers.dispose);
  return triggers;
});

class StoryOutboxTriggers {
  StoryOutboxTriggers(this._ref) {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(poke()));
    _ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        unawaited(poke());
      }
    });
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        scheduleMicrotask(() => unawaited(_onSignedIn(next.id)));
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  /// A forced pass: backoff timers paused while backgrounded, or waiting on
  /// a network that is now back, go now.
  Future<void> poke() async {
    if (_disposed || _ref.read(currentUserProvider) == null) return;
    await _ref.read(storyOutboxProvider.notifier).flush(force: true);
  }

  Future<void> _onSignedIn(String userId) async {
    if (_disposed) return;
    // Account switch: any sign-in (cold start included) wipes every OTHER
    // person's queued stories and captures, so a session that ended
    // without a sign-out never leaves them behind (05 #2).
    await _ref.read(storyOutboxWiperProvider).wipeExcept(userId);
    await poke();
  }

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
