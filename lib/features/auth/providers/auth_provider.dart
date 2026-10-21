// lib/features/auth/presentation/providers/auth_provider.dart

import 'package:attune/core/providers/routing_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ==================== CORE PROVIDERS ====================

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

// ==================== STATE PROVIDERS ====================

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  // Seeds synchronously from the already-restored session before the first
  // onAuthStateChange event lands, rather than only mapping the live
  // stream. gotrue does replay the current session on subscribe
  // (AuthChangeEvent.initialSession), so in practice this rarely mattered —
  // but any consumer that reads .valueOrNull before that first event still
  // saw a real null (not "unknown yet"), and currentUserIdProvider-style
  // providers built on top of this stream would briefly compute against a
  // signed-out user even on an already-signed-in cold start. Yielding the
  // current session first removes that gap entirely instead of relying on
  // event-ordering timing.
  return Stream<User?>.multi((controller) {
    controller.add(authService.currentUser);
    final sub = authService.authStateChanges
        .map((event) => event.session?.user)
        .listen(controller.add, onError: controller.addError);
    controller.onCancel = sub.cancel;
  });
});

// Full auth state stream — exposes the event type (e.g. passwordRecovery).
final authEventProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Current user provider - use this to get the logged-in user
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull;
});

final authErrorProvider = StateProvider<String?>((ref) => null);

final isLoadingProvider = StateProvider<bool>((ref) => false);

// ==================== SIGN-OUT HOOKS ====================

/// Work other layers need around every sign-out, reached without this auth
/// layer importing them (chat review #18: the push device release lives in
/// OneSignalService, which itself depends on auth). The composition root
/// (main.dart) binds these; the defaults do nothing. Each hook is bounded
/// by its owner and must never throw.
class SignOutHooks {
  const SignOutHooks({this.beforeSignOut, this.signOutFailed});

  /// Runs while the session is still valid, alongside the chat cache wipe.
  final Future<void> Function()? beforeSignOut;

  /// The auth sign-out failed and the person is still signed in: undo what
  /// [beforeSignOut] released.
  final void Function()? signOutFailed;
}

final signOutHooksProvider = Provider<SignOutHooks>(
  (ref) => const SignOutHooks(),
);

// ==================== OPERATIONS PROVIDER ====================

final authOperationsProvider = Provider<AuthOperations>((ref) {
  return AuthOperations(ref);
});

class AuthOperations {
  final Ref ref;

  /// Single in-flight auth operation lock. Prevents two concurrent operations
  /// (e.g. user mashes "Sign in with Google" then "Sign in with Apple")
  /// from racing to toggle the shared `isLoadingProvider`, where the first
  /// to finish would prematurely clear the loading state while the second
  /// is still mid-flight.
  bool _busy = false;

  AuthOperations(this.ref);

  /// Wraps an auth op with mutual exclusion + shared loading/error state.
  /// Throws [StateError] if another auth op is already running so callers
  /// can surface a clear "please wait" message instead of silently queueing.
  Future<T> _exclusive<T>(Future<T> Function() op) async {
    if (_busy) {
      throw StateError('Another auth operation is already in progress.');
    }
    _busy = true;
    ref.read(isLoadingProvider.notifier).state = true;
    ref.read(authErrorProvider.notifier).state = null;
    try {
      return await op();
    } on AuthException catch (e) {
      ref.read(authErrorProvider.notifier).state = e.message;
      rethrow;
    } finally {
      _busy = false;
      ref.read(isLoadingProvider.notifier).state = false;
    }
  }

  // ==================== EMAIL/PASSWORD ====================

  Future<void> signInWithEmail(String email, String password) {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithEmail(email: email, password: password);
    });
  }

  Future<AuthResponse> signUpWithEmail(String email, String password) {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      return authService.signUpWithEmail(email: email, password: password);
    });
  }

  // ==================== OAUTH ====================

  Future<void> signInWithGoogle() {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
    });
  }

  Future<void> signInWithApple() {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithApple();
    });
  }

  // ==================== OTHER ====================

  Future<void> signOut() {
    return _exclusive(() async {
      final hooks = ref.read(signOutHooksProvider);
      Future<void> wipeQueue() async {
        try {
          // Clear chat cache before sign-out to prevent cross-session data leakage.
          // Non-fatal: if the wipe fails, sign-out still proceeds.
          await ref.read(chatCacheServiceProvider).clearAll();
        } catch (e) {
          debugPrint('⚠️ [AUTH] clearAll failed on sign-out: ${e.runtimeType}');
        }
        try {
          // I1: the queue rows' staged picks and prepared uploads, wholesale
          // (nothing references them now). A photo waiting offline on its
          // retry timer has no live controller to purge it. Bounded (3 s)
          // and owed to the next chat use when cut off; its own try so a
          // failed cache wipe never skips it.
          await ref.read(chatImagePickerProvider).wipeStaging();
        } catch (e) {
          debugPrint('⚠️ [AUTH] staging wipe failed on sign-out: ${e.runtimeType}');
        }
      }

      Future<void> wipeMedia() async {
        try {
          // Voice/video bytes cached by ChatMediaCache belong to this
          // session's person too (its own try: a failed chat cache wipe
          // must not leave them behind). Bounded by its owner (M3).
          await ref.read(chatMediaCacheProvider).clear();
        } catch (e) {
          debugPrint('⚠️ [AUTH] media cache clear failed on sign-out: ${e.runtimeType}');
        }
      }

      Future<void> wipeImages() async {
        try {
          // Decoded photos held in Flutter's in-memory ImageCache are this
          // person's too (process memory). Guarded: a host with no binding
          // (a bare test) has none to clear.
          final images = PaintingBinding.instance.imageCache;
          images
            ..clear()
            ..clearLiveImages();
        } catch (_) {}
        try {
          // I3: photos and video posters (DefaultCacheManager, under their
          // storage keys) are this person's too. Bounded by its owner.
          await ref.read(chatImageCacheProvider).clear();
        } catch (e) {
          debugPrint('⚠️ [AUTH] image cache clear failed on sign-out: ${e.runtimeType}');
        }
      }

      // Side by side, so the bounds do not add up: each store is wiped on
      // its own and none waits on another.
      Future<void> wipe() =>
          Future.wait([wipeQueue(), wipeMedia(), wipeImages()]);

      Future<void> release() async {
        // Chat review #18: release this device's push subscription while
        // the session can still prove whose it is. Best-effort and bounded
        // by its owner (~3 s server, then a local opt-out).
        try {
          await hooks.beforeSignOut?.call();
        } catch (e) {
          debugPrint('⚠️ [AUTH] push unregister failed on sign-out: ${e.runtimeType}');
        }
      }

      // The wipe starts first, exactly as before; the release runs beside
      // it, so neither waits on the other.
      await Future.wait([wipe(), release()]);
      // Always clear the persisted recovery flag so a future sign-in does
      // not inherit a stale "in recovery" state from a prior reset attempt.
      ref.read(routingNotifierProvider).setRecoveryMode(false);
      final authService = ref.read(authServiceProvider);
      try {
        await authService.signOut();
      } catch (_) {
        // Still signed in: hand the released device back (fix M2).
        if (authService.currentUser != null) {
          try {
            hooks.signOutFailed?.call();
          } catch (_) {}
        }
        rethrow;
      }
    });
  }

  Future<void> updatePassword(String newPassword) {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      await authService.updatePassword(newPassword);
    });
  }

  Future<void> resetPassword(String email) {
    return _exclusive(() async {
      final authService = ref.read(authServiceProvider);
      await authService.resetPassword(email);
    });
  }
}
