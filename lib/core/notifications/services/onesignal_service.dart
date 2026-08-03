import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
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

      final navigatorContext = appNavigatorKey.currentContext;
      if (navigatorContext == null) return;

      final notification = appNotificationFromPushData(
        notificationId: event.notification.notificationId,
        title: event.notification.title,
        body: event.notification.body,
        additionalData: additionalData,
      );

      final config = _ref.read(notificationConfigProvider);
      config.onNotificationTap?.call(notification, navigatorContext);
    });

    // If the user is already authenticated when the service starts,
    // log in immediately and await completion before marking initialized.
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await OneSignal.login(user.id);
    }

    _isInitialized = true;
  }

  void _setupUserListener() {
    _ref.listen(currentUserProvider, (previous, next) async {
      if (next != null) {
        await OneSignal.login(next.id);
      } else if (previous != null) {
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
