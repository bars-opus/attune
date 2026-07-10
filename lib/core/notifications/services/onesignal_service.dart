import 'dart:io';

import 'package:attune/core/config/env.dart';
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

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService(ref);
});
