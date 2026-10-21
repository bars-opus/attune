// lib/core/notifications/services/push_sdk.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// The slice of the OneSignal SDK Attune uses, behind an interface so
/// OneSignalService can be tested without the plugin's static channels.
abstract class PushSdk {
  Future<void> initialize(String appId);
  Future<void> login(String externalId);
  Future<void> logout();

  /// OS-level permission as the SDK last saw it.
  bool get permissionGranted;

  /// False once the OS will not show the dialog again (iOS: answered once).
  Future<bool> canRequestPermission();

  /// Shows the OS dialog; never falls back to opening Settings.
  Future<bool> requestPermission();

  /// This device's OneSignal push subscription id; null until the SDK has
  /// registered with APNs/FCM.
  String? get subscriptionId;
  bool get optedIn;
  Future<void> optIn();
  Future<void> optOut();

  /// Fires whenever the subscription changes (first registration, a
  /// reinstall, a token refresh, opt in/out).
  void onSubscriptionChanged(void Function(String? id, bool optedIn) listener);
}

class OneSignalPushSdk implements PushSdk {
  @override
  Future<void> initialize(String appId) => OneSignal.initialize(appId);

  @override
  Future<void> login(String externalId) => OneSignal.login(externalId);

  @override
  Future<void> logout() => OneSignal.logout();

  @override
  bool get permissionGranted => OneSignal.Notifications.permission;

  @override
  Future<bool> canRequestPermission() => OneSignal.Notifications.canRequest();

  @override
  Future<bool> requestPermission() =>
      OneSignal.Notifications.requestPermission(false);

  @override
  String? get subscriptionId => OneSignal.User.pushSubscription.id;

  @override
  bool get optedIn => OneSignal.User.pushSubscription.optedIn ?? false;

  @override
  Future<void> optIn() => OneSignal.User.pushSubscription.optIn();

  @override
  Future<void> optOut() => OneSignal.User.pushSubscription.optOut();

  @override
  void onSubscriptionChanged(void Function(String? id, bool optedIn) listener) {
    OneSignal.User.pushSubscription.addObserver((state) {
      listener(state.current.id, state.current.optedIn);
    });
  }
}
