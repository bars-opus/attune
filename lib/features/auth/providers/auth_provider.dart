// lib/features/auth/presentation/providers/auth_provider.dart

import 'package:attune/core/providers/routing_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
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
      try {
        // Clear chat cache before sign-out to prevent cross-session data leakage.
        // Non-fatal: if the wipe fails, sign-out still proceeds.
        await ref.read(chatCacheServiceProvider).clearAll();
      } catch (e) {
        debugPrint('⚠️ [AUTH] clearAll failed on sign-out: ${e.runtimeType}');
      }
      // Always clear the persisted recovery flag so a future sign-in does
      // not inherit a stale "in recovery" state from a prior reset attempt.
      ref.read(routingNotifierProvider).setRecoveryMode(false);
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
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
