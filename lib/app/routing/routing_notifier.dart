// lib/core/routing/routing_notifier.dart
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoutingNotifier extends ChangeNotifier {
  /// Key under which the recovery flag is persisted so it survives an app
  /// kill in the middle of the password-reset flow. Without this, a force
  /// quit between opening the reset link and saving the new password would
  /// leave the user logged in (with the recovery session) but with no prompt
  /// to actually change their password.
  static const _kRecoveryModeKey = 'auth.isRecoveryMode';

  final SharedPreferences? _prefs;

  RoutingNotifier({
    SharedPreferences? prefs,
    bool isFirstLaunch = false,
    bool flowV2 = false,
    bool guestAgeOk = false,
    bool underAgeBlocked = false,
    String? Function()? currentUserId,
    DateTime Function()? now,
  }) : _prefs = prefs,
       _isFirstLaunch = isFirstLaunch,
       _flowV2 = flowV2,
       _guestAgeOk = guestAgeOk,
       _underAgeBlocked = underAgeBlocked,
       _currentUserId = currentUserId ?? _supabaseUserId,
       _now = now ?? DateTime.now {
    _isRecoveryMode = prefs?.getBool(_kRecoveryModeKey) ?? false;
  }

  // ==================== SPEC 1 SIGN-IN (W2) ====================
  //
  // Read synchronously at boot (main.dart) and kept current by their
  // owners: flowV2 by App's listener on the public config, guestAgeOk by
  // G1, underAgeBlocked by X1. All false by default, so a notifier built
  // without them routes exactly as before.

  bool _flowV2;
  bool _guestAgeOk;
  bool _underAgeBlocked;
  final String? Function() _currentUserId;

  /// The clock the block and the sign-up draft are read against.
  final DateTime Function() _now;

  /// flow_signin_v2, effective: Welcome and the v2 sign-up instead of
  /// IntroScreen and LoginScreen.
  bool get flowV2 => _flowV2;

  /// G1 was passed on this install.
  bool get guestAgeOk => _guestAgeOk;

  /// X1's 30-day device block is in force: set by X1, or found in prefs
  /// (ruling C9: the replay's under-18 stop writes only there, and its
  /// block holds in this session too).
  bool get underAgeBlocked {
    final prefs = _prefs;
    return _underAgeBlocked ||
        (prefs != null && AgeGateStore.readBlocked(prefs, _now()));
  }

  /// The signed-in account, read live (the router's own user field is not
  /// kept in step with Auth).
  String? get currentUserId => _currentUserId();

  bool get isSignedIn => currentUserId != null;

  /// A sign-up this phone should go back to (Spec 1 §3.3): signed out with
  /// a code on its way (A4), or signed in as the account A4 just verified
  /// and not yet through A5. Read from the draft at each redirect.
  bool get signUpToResume {
    final prefs = _prefs;
    if (prefs == null) return false;
    final draft = SignUpDraftStore.readFrom(prefs, _now());
    if (draft == null) return false;
    final userId = currentUserId;
    return userId == null ? draft.awaitingCode : draft.verifiedUserId == userId;
  }

  void setFlowV2(bool value) {
    if (_flowV2 == value) return;
    _flowV2 = value;
    notifyListeners();
  }

  void setGuestAgeOk(bool value) {
    if (_guestAgeOk == value) return;
    _guestAgeOk = value;
    notifyListeners();
  }

  void setUnderAgeBlocked(bool value) {
    if (_underAgeBlocked == value) return;
    _underAgeBlocked = value;
    notifyListeners();
  }

  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  User? _user;
  Object? _profile;
  bool _isFirstLaunch;
  Timer? _debounceTimer;

  String? _pendingDeepLinkSlug;
  bool _deepLinkProcessed = false;
  String? _currentLocation;
  bool _isRecoveryMode = false;

  User? get user => _user;
  Object? get profile => _profile;
  bool get isFirstLaunch => _isFirstLaunch;
  String? get currentLocation => _currentLocation;
  String? get pendingDeepLinkSlug => _pendingDeepLinkSlug;
  bool get hasPendingDeepLink =>
      _pendingDeepLinkSlug != null && !_deepLinkProcessed;
  bool get isFullyAuthenticated => _user != null;
  bool get isRecoveryMode => _isRecoveryMode;

  void setRecoveryMode(bool value) {
    if (_isRecoveryMode != value) {
      _isRecoveryMode = value;
      // Fire-and-forget: persistence failure must not block the UI flow.
      _prefs?.setBool(_kRecoveryModeKey, value);
      notifyListeners();
    }
  }

  // Clears the user immediately without the debounce timer.
  // Use after an explicit sign-out so the router redirect sees null user
  // on the same frame, avoiding races with context.go calls.
  void clearUser() {
    _debounceTimer?.cancel();
    if (_user != null) {
      _user = null;
      notifyListeners();
    }
  }

  // Sets the authenticated user immediately without the debounce timer.
  // Use after sign-in so profile-loading events (which share the same
  // debounce timer) cannot cancel this update before it commits.
  void setUser(User user) {
    if (user != _user) {
      _user = user;
      notifyListeners();
    }
  }

  // Marks first launch as done without the debounce timer.
  // Use after setFirstLaunchCompleted() so context.go(home) isn't
  // bounced back to /intro by the router redirect in the same frame.
  void completeFirstLaunch() {
    _debounceTimer?.cancel();
    if (_isFirstLaunch) {
      _isFirstLaunch = false;
      notifyListeners();
    }
  }

  // ==================== LOCATION ====================

  void updateLocation(String location) {
    if (_currentLocation != location) {
      _currentLocation = location;
      notifyListeners();
    }
  }

  // ==================== DEEP LINK HANDLING ====================
  //
  // NOTE: setPendingDeepLink / consumePendingDeepLink are vestigial. The
  // warm-start deep link path in main.dart now calls _appRouter.go(...)
  // directly instead of stashing the slug here, and no consumer in the router
  // reads consumePendingDeepLink(). Cold-start universal links from
  // aurain.barsopus.com still fall through to setPendingDeepLink as a
  // safety net, but until a consumer is wired in (e.g. into the /_invisible
  // redirect) those will not auto-navigate. Left in place rather than
  // refactored out — the next time deep link routing is touched, either
  // wire up consumePendingDeepLink in the redirect or delete these methods.

  void setPendingDeepLink(String slug) {
    _pendingDeepLinkSlug = slug;
    _deepLinkProcessed = false;
    notifyListeners();
  }

  String? consumePendingDeepLink() {
    final slug = _pendingDeepLinkSlug;
    if (slug != null) {
      _pendingDeepLinkSlug = null;
      _deepLinkProcessed = true;
    }
    return slug;
  }

  void clearPendingDeepLink() {
    _pendingDeepLinkSlug = null;
    _deepLinkProcessed = false;
    notifyListeners();
  }

  // ==================== PROFILE ====================

  void updateProfile(Object? profile) {
    if (profile != _profile) {
      _profile = profile;
      notifyListeners();
    }
  }

  // ==================== CORE UPDATE ====================

  /// Debounced multi-field update.
  ///
  /// Auth, profile and first-launch listeners in [_AppState] fire in rapid
  /// succession during sign-in and app boot (often within the same frame).
  /// Without this 100 ms debounce, every individual update would notify
  /// listeners, the GoRouter redirect would re-evaluate against an
  /// intermediate state (e.g. `user != null, profile == null`) and bounce
  /// the user to the wrong screen. 100 ms is short enough to feel instant
  /// to the user but long enough to coalesce the three listener bursts
  /// into a single notification.
  ///
  /// Use the immediate setters ([setUser], [clearUser], [updateProfile],
  /// [completeFirstLaunch]) when you need a synchronous router refresh,
  /// e.g. right before a `context.go` call.
  void update({User? user, Object? profile, bool? isFirstLaunch}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      bool changed = false;
      if (user != _user) {
        _user = user;
        changed = true;
      }
      if (profile != _profile) {
        _profile = profile;
        changed = true;
      }
      if (isFirstLaunch != null && isFirstLaunch != _isFirstLaunch) {
        _isFirstLaunch = isFirstLaunch;
        changed = true;
      }
      if (changed) notifyListeners();
    });
  }

  // ==================== CLEANUP ====================

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
