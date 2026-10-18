import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OneSignalService {
  final Ref _ref;
  bool _isInitialized = false;

  OneSignalService(this._ref);

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = Environment.oneSignalAppId;
    if (appId == null || appId.isEmpty) {
      return;
    }

    OneSignal.initialize(appId);

    if (Platform.isIOS) {
      await OneSignal.Notifications.requestPermission(true);
    }

    // Wire auth state changes → OneSignal login/logout.
    _setupUserListener();

    // Route a real OS-level notification tap through the same
    // onNotificationTap config the in-app inbox already uses. The SDK
    // buffers any click that arrives before this listener is registered
    // (including a cold-start tap that launches the app) and flushes it
    // once registration completes — no custom queue needed here.
    OneSignal.Notifications.addClickListener((event) {
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
      if (shouldSuppressForegroundPush(
        _ref.read(safetyLockProvider),
        _currentPath(),
      )) {
        event.preventDefault();
      }
    });

    // If the user is already authenticated when the service starts,
    // log in immediately and await completion before marking initialized.
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await OneSignal.login(user.id);
    }

    _isInitialized = true;
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
        await OneSignal.login(next.id);
      } else if (previous != null) {
        // A tap held for the person who just signed out is theirs, not the
        // next screen's (review I-5).
        _pendingTap = null;
        await OneSignal.logout();
      }
    });
  }
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
