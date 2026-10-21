import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/data/owed_push_release_store.dart';
import 'package:attune/core/notifications/data/push_subscription_registry.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart'
    show chatConnectivityProvider;
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class OneSignalService {
  OneSignalService(
    this._ref, {
    PushSdk? sdk,
    String? platform,
    Future<void> Function(String relationshipId)? ackChatDelivery,
  }) : _sdk = sdk ?? OneSignalPushSdk(),
       _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
       _ackChatDelivery = ackChatDelivery;

  /// Stamps delivered_at for the partner's undelivered messages in a
  /// relationship. Injected for tests; null means "the chat repository",
  /// resolved at call time (`_ref` is not usable in an initializer list).
  final Future<void> Function(String relationshipId)? _ackChatDelivery;

  final Ref _ref;
  final PushSdk _sdk;
  final String _platform;
  bool _isInitialized = false;
  bool _askedThisRun = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = Environment.oneSignalAppId;
    if (appId == null || appId.isEmpty) {
      _markStarted(false);
      return;
    }

    // Awaited so the SDK's permission/subscription state is loaded before
    // attach() reads it, and so an init error is caught here, not lost.
    // Bounded: if the SDK stalls, the listeners below still register and
    // the SDK keeps starting in the background.
    try {
      await _sdk.initialize(appId).timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('[push] OneSignal init: ${error.runtimeType}');
    }
    _markStarted(true);

    // Route a real OS-level notification tap through the same
    // onNotificationTap config the in-app inbox already uses. The SDK
    // buffers any click that arrives before this listener is registered
    // (including a cold-start tap that launches the app) and flushes it
    // once registration completes — no custom queue needed here.
    OneSignal.Notifications.addClickListener((event) {
      // Acks delivery only: shows and navigates nothing, so it is safe
      // under the Safety lock (the tap itself still waits below).
      unawaited(handleChatPushReceived(event.notification.additionalData));
      final additionalData = event.notification.additionalData;
      if (additionalData == null) return;

      final notification = appNotificationFromPushData(
        notificationId: event.notification.notificationId,
        title: event.notification.title,
        body: event.notification.body,
        additionalData: additionalData,
      );

      // Spec 2: while the Safety PIN is required (or before the Router has
      // mounted) the tap waits and is replayed on unlock -- never dropped,
      // never shown above the lock (review I5).
      // On iOS the decoy stays in the foreground after a quick exit, so a
      // tap on an earlier notification must wait there too (review I-2).
      final navigatorContext = appNavigatorKey.currentContext;
      if (navigatorContext == null ||
          shouldDeferNotificationTap(
            state: _ref.read(safetyLockProvider),
            path: _currentPath(),
            navigatorReady: true,
          )) {
        _pendingTap = notification;
        return;
      }
      final config = _ref.read(notificationConfigProvider);
      config.onNotificationTap?.call(notification, navigatorContext);
    });

    // Spec 2: no banner over the lock screen or the quick-exit decoy
    // (review I10).
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Before the lock check: a suppressed banner still means the device
      // has the message. Acks only; nothing is shown or navigated.
      unawaited(handleChatPushReceived(event.notification.additionalData));
      if (shouldSuppressForegroundPush(
        _ref.read(safetyLockProvider),
        _currentPath(),
      )) {
        event.preventDefault();
      }
    });

    await attach();
    _isInitialized = true;
  }

  /// RC-14: a chat push the SDK hands to Dart (shown in the foreground, or
  /// tapped) proves the row reached this device, so it is acked delivered
  /// now rather than when the chat opens. Best-effort, never throws.
  /// Skipped when signed out (a late push for a released account must not
  /// call the RPC). Whether the push's relationship is the signed-in
  /// user's is not known client-side; the RPC is SECURITY DEFINER and only
  /// touches active relationships the caller belongs to, so a foreign id
  /// is a no-op.
  Future<void> handleChatPushReceived(
    Map<String, dynamic>? additionalData,
  ) async {
    try {
      final relationshipId = chatRelationshipIdForDeliveryAck(additionalData);
      if (relationshipId == null) return;
      if (_ref.read(currentUserProvider) == null) return;
      final ack =
          _ackChatDelivery ??
          _ref.read(chatRepositoryProvider).markRelationshipDelivered;
      await ack(relationshipId);
    } catch (error) {
      debugPrint('chat delivery ack failed: ${error.runtimeType}');
    }
  }

  /// Everything that follows the SDK's existence: auth → login/logout, the
  /// permission prompt (chat review #15: after sign-in, lock open, both
  /// platforms — Android 13+ never asked before) and, from Task 8, the
  /// device's push subscription. Separate from initialize() so tests drive
  /// it with a fake PushSdk.
  @visibleForTesting
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _markStarted(true);
    _setupUserListener();
    _sdk.onSubscriptionChanged((id, optedIn) {
      if (!optedIn) {
        // Opted out (OS settings, or our own sign-out): the server may
        // deactivate this id (Task 7), so an opt back in sends it again.
        _forgetRegistration();
        return;
      }
      if (id != null && id.isNotEmpty) unawaited(_syncSubscription());
    });
    _ref.listen<SafetyLockState>(safetyLockProvider, (_, __) {
      unawaited(_maybeAskForPermission());
    });
    // An offline sign-out's owed release (final review I1), signed in or
    // not. Never awaited here: a register waits for it, nothing else does.
    unawaited(_retryOwedRelease());

    // If the user is already authenticated when the service starts, log in
    // and offer the prompt now. This can wait on the OS dialog, so nothing
    // on the startup path awaits initialize() (App.initState fires it).
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await _onSignedIn(user.id);
    } else {
      // A release from a sign-out that landed before attach() is done: the
      // auth listener was not there to see it end.
      _releasedFor = null;
      await _releaseIfSignedOutAtStart();
    }
  }

  /// Chat review #18 (fix C1): a sign-out that ran before OneSignal started
  /// (the Safety lock's cold-start sign-out races initialize()) could not
  /// opt the device out, and the auth listener never sees a past change. A
  /// phone that starts signed out but still opted in is opted out here.
  /// Waits for the auth stream to resolve first: on a cold start it is
  /// briefly unknown, and a signed-in phone must not flap out and back in.
  Future<void> _releaseIfSignedOutAtStart() async {
    bool loading;
    try {
      loading = _ref.read(authStateProvider).isLoading;
    } catch (_) {
      loading = false;
    }
    if (!loading) {
      await _releaseSignedOutDevice();
      return;
    }
    late final ProviderSubscription<AsyncValue<User?>> resolved;
    resolved = _ref.listen<AsyncValue<User?>>(authStateProvider, (_, next) {
      if (next.isLoading) return;
      resolved.close();
      // Decided from the resolved value: currentUserProvider is refreshed
      // only after this listener runs.
      if (next.valueOrNull != null) return;
      unawaited(_releaseSignedOutDevice());
    });
  }

  Future<void> _releaseSignedOutDevice() async {
    if (_ref.read(currentUserProvider) != null || !_sdk.optedIn) return;
    await _optOutBounded();
    // Signed in meanwhile: that sign-in owns the SDK user now.
    if (_ref.read(currentUserProvider) != null) return;
    try {
      await _sdk.logout();
    } catch (_) {}
  }

  bool _attached = false;

  /// False when OneSignal was never started (no app id configured, or the
  /// first seconds of a cold start): nothing to release, and the plugin
  /// must not be called before its initialize.
  bool _sdkStarted = false;

  /// Completed by initialize() on every exit (false: no app id, OneSignal
  /// never starts) or by attach(). A sign-out during start-up waits on it.
  final Completer<bool> _started = Completer<bool>();

  void _markStarted(bool started) {
    _sdkStarted = started;
    if (!_started.isCompleted) _started.complete(started);
  }

  /// This device's push subscription id once OneSignal has started (I2:
  /// "sign out other devices" keeps this one), else null.
  String? get currentSubscriptionId {
    if (!_sdkStarted) return null;
    final id = _sdk.subscriptionId;
    return id == null || id.isEmpty ? null : id;
  }

  /// What the server holds for this run: `epoch|user|subscription`
  /// of the last register that succeeded (null = nothing sent yet).
  String? _registeredKey;

  /// Bumped whenever the server's copy may be gone (opt-out, release,
  /// sign-out), so an older success never counts as current.
  int _epoch = 0;

  /// The register call in flight, so a burst of triggers sends it once and
  /// sign-out can wait for it before releasing.
  Future<void>? _registering;
  String? _registeringKey;

  /// The person whose device beforeSignOut released: nothing re-registers
  /// or opts back in for them until the sign-out lands (a token refresh in
  /// that window would otherwise undo the release).
  String? _releasedFor;

  /// Bumped by every release (beforeSignOut, a revoked session): a sign-in
  /// run that started before it stops at its next step (fix round 2 #1).
  int _releases = 0;

  /// `user|subscription` whose server unregister succeeded: only then is a
  /// repeat release a no-op (fix round 2 #4). Cleared by a register.
  String? _unregisteredKey;

  static const _unregisterBound = Duration(seconds: 3);
  static const _registerBound = Duration(seconds: 10);
  static const _optOutBound = Duration(seconds: 2);
  static const _releaseBound = Duration(seconds: 5);
  static const _owedStoreBound = Duration(seconds: 2);

  /// The owed release in flight, so a register waits for it (the register
  /// must land last) and a burst of triggers sends it once.
  Future<void>? _owedReleasing;

  /// Listening for the network to return while a release is owed.
  ProviderSubscription<AsyncValue<bool>>? _owedRetryWhenOnline;

  void _forgetRegistration() => _epoch++;

  Future<void> _onSignedIn(String userId) async {
    // Released and on the way out (a token refresh in the sign-out window):
    // no login, no prompt, no opt-in.
    if (_releasedFor == userId) return;
    _releasedFor = null;
    // A real sign-in: the server's copy may be live again (or a register
    // may fail), so an earlier unregister no longer makes a repeat release
    // a no-op (final review M4).
    _unregisteredKey = null;
    final releases = _releases;
    // Re-checked after every await: a release (or an account switch) that
    // lands during the login or the OS prompt ends this run (round 2 #1).
    bool stillCurrent() =>
        _releases == releases &&
        _releasedFor != userId &&
        _ref.read(currentUserProvider)?.id == userId;
    await _sdk.login(userId);
    if (!stillCurrent()) return;
    await _maybeAskForPermission();
    if (!stillCurrent()) return;
    // A previous sign-out on this phone opted the device out; a granted
    // permission means optIn() shows no dialog.
    await _optInIfGranted();
    if (!stillCurrent()) return;
    await _syncSubscription();
  }

  Future<void> _optInIfGranted() async {
    if (_sdk.optedIn || !_sdk.permissionGranted) return;
    try {
      await _sdk.optIn();
    } catch (_) {}
  }

  /// After "sign out other devices" stopped the other phones (I2): the
  /// server may have stopped this one too (no id known when it asked), so
  /// this phone's registration is sent again rather than deduped. Sent as
  /// soon as its id is known (round 2 #3).
  void refreshRegistration() {
    _forgetRegistration();
    unawaited(_syncSubscription());
  }

  /// Chat review #18: the server pushes only to devices registered by the
  /// signed-in session. Sent once per (person, subscription id) while opted
  /// in; again after an opt-out/opt-in, a new id, or an app restart.
  Future<void> _syncSubscription() async {
    final user = _ref.read(currentUserProvider);
    final id = _sdk.subscriptionId;
    if (user == null || id == null || id.isEmpty || !_sdk.optedIn) return;
    if (user.id == _releasedFor) return;
    final key = '$_epoch|${user.id}|$id';
    if (_registeredKey == key || _registeringKey == key) return;
    final attempt = _register(key, id);
    _registering = attempt;
    _registeringKey = key;
    try {
      await attempt;
    } finally {
      if (identical(_registering, attempt)) {
        _registering = null;
        _registeringKey = null;
      }
    }
  }

  /// Never throws.
  Future<void> _register(String key, String id) async {
    // An owed release still on its way goes first: the register must be the
    // last word for this device (final review I1). Bounded by its own call.
    // Both read before any await: a release that starts after this point
    // waits for this register instead (_sendOwedRelease) and re-reads the
    // id it clears, so the two can never wait on each other.
    final owing = _owing;
    final owed = _owedReleasing;
    if (owing != null) await owing;
    if (owed != null) await owed;
    try {
      await _ref
          .read(pushSubscriptionRegistryProvider)
          .register(subscriptionId: id, platform: _platform)
          .timeout(_registerBound);
      _registeredKey = key;
      _unregisteredKey = null;
      // The device now belongs to whoever registered it: nothing owed.
      await _clearOwedRelease(id);
    } catch (e) {
      if (isPushSessionRevoked(e)) {
        // Signed out from another device: this session is dead and will
        // end at its next refresh. Treat it as signed out now -- opt out,
        // and no retry or opt-in until a real sign-in (no loop).
        _releasedFor = _ref.read(currentUserProvider)?.id;
        _releases++;
        _forgetRegistration();
        await _optOutBounded();
        return;
      }
      // Retried on the next subscription change or sign-in; until then this
      // phone simply gets no push (never someone else's).
      debugPrint('push subscription register failed: ${e.runtimeType}');
    }
  }

  /// Called while the session is still valid, before auth sign-out: the
  /// server forgets this device, and the device stops receiving even if
  /// that call failed (offline sign-out). The SDK logout follows from the
  /// auth listener. Bounded (~3 s server + ~2 s opt-out); never throws.
  Future<void> beforeSignOut() async {
    // No app id: OneSignal never starts, nothing to release.
    if (_started.isCompleted && !_sdkStarted) return;
    final userId = _ref.read(currentUserProvider)?.id;
    // Already fully released for this person (the Safety fallback after a
    // failed AuthOperations sign-out): nothing left to do. Only when the
    // server unregister succeeded -- a revoked-session opt-out or a failed
    // call still needs it (round 2 #4).
    if (_sdkStarted &&
        userId != null &&
        _releasedFor == userId &&
        !_sdk.optedIn &&
        _unregisteredKey == '$userId|${_sdk.subscriptionId}') {
      return;
    }
    _releasedFor = userId;
    _releases++;
    _forgetRegistration();
    // The id whose unregister did not succeed (final review I1).
    String? unreleased;
    var unregistered = false;
    try {
      // Bounded: an offline sign-out, or one racing OneSignal's start-up,
      // must not hang. A register still in flight goes first, so the
      // release is the last word.
      await () async {
        if (!_sdkStarted && !await _started.future) return;
        final pending = _registering;
        if (pending != null) await pending;
        final id = _sdk.subscriptionId;
        if (id == null || id.isEmpty) return;
        unreleased = id;
        await _ref.read(pushSubscriptionRegistryProvider).unregister(id);
        unregistered = true;
        _unregisteredKey = '$userId|$id';
        // An earlier failed sign-out's owed release is settled too.
        await _clearOwedRelease(id);
      }().timeout(_unregisterBound);
    } catch (e) {
      debugPrint('push subscription unregister failed: ${e.runtimeType}');
      // Timed out before the id was read (behind a register): the id
      // OneSignal holds now is the one the server may still target.
      unreleased ??= currentSubscriptionId;
    }
    // Still starting (or no app id): the plugin must not be called yet;
    // attach() opts the signed-out phone out once it has started.
    if (!_sdkStarted) return;
    final owed = unregistered ? null : unreleased;
    // The opt-out stops the device receiving even if the server call failed
    // -- but only once OneSignal syncs it, which needs the app open online.
    // The owed release closes that gap from the server side (I1).
    await Future.wait([
      _optOutBounded(),
      if (owed != null) _oweRelease(owed),
    ]);
  }

  /// The auth sign-out failed and the person is still signed in (fix M2):
  /// undo the release so this phone gets their pushes again.
  void cancelRelease() {
    _unregisteredKey = null; // final review M4: see _onSignedIn
    if (_releasedFor == null) return;
    final user = _ref.read(currentUserProvider);
    _releasedFor = null;
    if (user == null || !_sdkStarted) return;
    final id = currentSubscriptionId;
    unawaited(() async {
      // Still signed in: the device is still theirs, so the release the
      // failed sign-out left owing must not silence it later (I1).
      if (id != null) await _clearOwedRelease(id);
      await _onSignedIn(user.id);
    }());
  }

  // ---- Owed release (plan 1b final review I1) ----
  //
  // A sign-out whose server unregister failed (offline) leaves this phone's
  // push_tokens row active, and no session remains to fix it: once the
  // phone is online with the app closed, the previous account's pushes
  // would still reach it. The id is kept (OwedPushReleaseStore) and sent to
  // release_push_subscription -- callable signed out -- on the next start
  // and whenever the network returns, until it lands. A register of the
  // same id (the device is someone's again) settles it too.

  /// The owed-release write in flight: a register waits for it, so a slow
  /// write can never land after the device's new owner registered it (and
  /// so silence them at the next start).
  Future<void>? _owing;

  Future<void> _oweRelease(String id) {
    final write = () async {
      try {
        await _ref
            .read(owedPushReleaseStoreProvider)
            .write(id)
            .timeout(_owedStoreBound);
      } catch (e) {
        debugPrint('owed push release not saved: ${e.runtimeType}');
      }
      _retryOwedReleaseWhenOnline();
    }();
    _owing = write;
    return write.whenComplete(() {
      if (identical(_owing, write)) _owing = null;
    });
  }

  Future<String?> _readOwedRelease() async {
    try {
      return await _ref
          .read(owedPushReleaseStoreProvider)
          .read()
          .timeout(_owedStoreBound);
    } catch (_) {
      return null;
    }
  }

  /// Clears the owed release only if it is still [id]. Never throws.
  Future<void> _clearOwedRelease(String id) async {
    try {
      final store = _ref.read(owedPushReleaseStoreProvider);
      if (await store.read().timeout(_owedStoreBound) != id) return;
      await store.clear().timeout(_owedStoreBound);
    } catch (_) {}
  }

  Future<void> _retryOwedRelease() =>
      _owedReleasing ??= _sendOwedRelease().whenComplete(
        () => _owedReleasing = null,
      );

  /// Never throws.
  Future<void> _sendOwedRelease() async {
    // Read before any await: a register that starts after this waits for
    // it instead (_register), so the two can never wait on each other.
    final registering = _registering;
    var id = await _readOwedRelease();
    if (id == null) {
      _stopOwedRetry();
      return;
    }
    if (registering != null) {
      // A register already in flight settles the release if it lands.
      await registering;
      id = await _readOwedRelease();
      if (id == null) {
        _stopOwedRetry();
        return;
      }
    }
    try {
      await _ref
          .read(pushSubscriptionRegistryProvider)
          .release(id)
          .timeout(_releaseBound);
    } catch (e) {
      if (!isPushSubscriptionInvalid(e)) {
        debugPrint('owed push release failed: ${e.runtimeType}');
        _retryOwedReleaseWhenOnline();
        return;
      }
      // Malformed: resending can never succeed.
    }
    await _clearOwedRelease(id);
    _stopOwedRetry();
  }

  void _retryOwedReleaseWhenOnline() {
    if (_owedRetryWhenOnline != null) return;
    _owedRetryWhenOnline = _ref.listen<AsyncValue<bool>>(
      chatConnectivityProvider,
      (previous, next) {
        if (next.valueOrNull == true && previous?.valueOrNull != true) {
          unawaited(_retryOwedRelease());
        }
      },
    );
  }

  void _stopOwedRetry() {
    _owedRetryWhenOnline?.close();
    _owedRetryWhenOnline = null;
  }

  Future<void> _optOutBounded() async {
    try {
      await _sdk.optOut().timeout(_optOutBound);
    } catch (_) {}
  }

  Future<void> _maybeAskForPermission() async {
    bool osCanPrompt;
    try {
      osCanPrompt = await _sdk.canRequestPermission();
    } catch (_) {
      // The SDK could not say; asking blind could nag, so stay quiet.
      osCanPrompt = false;
    }
    // Read after the await: the person may have signed out, locked or
    // quick-exited to the decoy meanwhile.
    if (!shouldAskForPushPermission(
      signedIn: _ref.read(currentUserProvider) != null,
      lock: _ref.read(safetyLockProvider),
      path: _currentPath(),
      alreadyGranted: _sdk.permissionGranted,
      osCanPrompt: osCanPrompt,
      askedThisRun: _askedThisRun,
    )) {
      return;
    }
    _askedThisRun = true;
    final userId = _ref.read(currentUserProvider)?.id;
    try {
      await _sdk.requestPermission();
    } catch (_) {
      // A refused or failed prompt is not an error; the OS remembers.
    }
    // Granted now (e.g. the prompt waited for the lock to open): a device
    // an earlier sign-out opted out is opted back in and registered at
    // once, not at the next restart (round 2 #5). Only for the person who
    // was asked, still signed in and not on the way out.
    if (userId == null ||
        _releasedFor == userId ||
        _ref.read(currentUserProvider)?.id != userId ||
        !_sdk.permissionGranted) {
      return;
    }
    await _optInIfGranted();
    if (_releasedFor == userId ||
        _ref.read(currentUserProvider)?.id != userId) {
      return;
    }
    await _syncSubscription();
  }

  AppNotification? _pendingTap;

  String _currentPath() {
    try {
      return _ref
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;
    } catch (_) {
      return '';
    }
  }

  /// Delivers a tap that arrived while Attune was locked (Spec 2), and only
  /// into a signed-in, open app (review I-5).
  void replayPendingTap() {
    final notification = _pendingTap;
    final navigatorContext = appNavigatorKey.currentContext;
    if (notification == null || navigatorContext == null) return;
    if (!canReplayNotificationTap(
      signedIn: _ref.read(currentUserProvider) != null,
      state: _ref.read(safetyLockProvider),
      path: _currentPath(),
      navigatorReady: true,
    )) {
      return;
    }
    _pendingTap = null;
    final config = _ref.read(notificationConfigProvider);
    config.onNotificationTap?.call(notification, navigatorContext);
  }

  void _setupUserListener() {
    _ref.listen(currentUserProvider, (previous, next) async {
      if (next != null) {
        await _onSignedIn(next.id);
      } else if (previous != null) {
        // A tap held for the person who just signed out is theirs, not the
        // next screen's (review I-5).
        _pendingTap = null;
        _forgetRegistration();
        _releasedFor = null;
        // Catch-all for sign-outs that never ran beforeSignOut (EULA
        // decline, a session revoked from another device): a signed-out
        // phone receives nothing (chat review #18). No session is left to
        // unregister with, so the server row is released on the next
        // online start (controller ruling on final review I1) -- unless
        // beforeSignOut's unregister already landed for this person.
        final id = currentSubscriptionId;
        final owe =
            id != null && _unregisteredKey != '${previous.id}|$id'
            ? _oweRelease(id)
            : null;
        if (_sdk.optedIn) await _optOutBounded();
        if (owe != null) await owe;
        await _sdk.logout();
      }
    });
  }
}

/// The relationship to ack for a push payload, or null when the push is not
/// a new chat message (a reaction push delivers no message). Pure.
String? chatRelationshipIdForDeliveryAck(Map<String, dynamic>? additionalData) {
  if (additionalData == null) return null;
  if (additionalData['type'] != 'new_message') return null;
  final id = additionalData['relationship_id'];
  return id is String && id.isNotEmpty ? id : null;
}

/// Converts a OneSignal click event's raw fields into the AppNotification
/// shape onNotificationTap already expects — pure, no OneSignal SDK types
/// in the signature, so it's testable without mocking the plugin. title/
/// body default to '' (matching AppNotification's non-nullable fields)
/// since onNotificationTap's own body only ever reads `.data`, never
/// `.title`/`.body` (confirmed: every existing case in notification_config.dart's
/// switch reads only notification.data), so an empty string here is inert,
/// not a silent data-loss bug.
AppNotification appNotificationFromPushData({
  required String notificationId,
  String? title,
  String? body,
  Map<String, dynamic>? additionalData,
}) {
  return AppNotification(
    id: notificationId,
    title: title ?? '',
    body: body ?? '',
    data: additionalData,
    createdAt: DateTime.now(),
  );
}

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService(ref);
});
