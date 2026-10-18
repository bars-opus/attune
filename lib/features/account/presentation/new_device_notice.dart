import 'dart:convert';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/account/data/account_sessions.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What to tell the person: a device that signed in since the last check, or
/// (null [device]) the one-time "review where you're signed in" (review M9).
class DeviceNotice {
  const DeviceNotice({this.device});
  final SignedInDevice? device;
}

final newDeviceUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

final newDeviceClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

String _currentPath(Ref ref) {
  try {
    return ref
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
  } catch (_) {
    return '';
  }
}

/// True while the app is open (not checking, not locked).
final newDeviceLockOpenProvider = Provider<bool>(
  (ref) => ref.watch(safetyLockProvider) == SafetyLockState.open,
);

/// No check while the PIN is required or the decoy screen is up (review I6).
final newDeviceCheckAllowedProvider = Provider<bool Function()>(
  (ref) =>
      () =>
          ref.read(safetyLockProvider) == SafetyLockState.open &&
          _currentPath(ref) != RouteNames.neutralScreen,
);

/// Spec 2 (research 06 §3 F7 (2)): checks the account's sessions when the app
/// opens, comes back (the lock opening again; at most every 5 minutes) or a
/// person signs in, and holds what to tell them (review I6, M-6).
class NewDeviceWatcher extends Notifier<DeviceNotice?> {
  static const throttle = Duration(minutes: 5);

  static String knownKey(String userId) => 'account_known_sessions:$userId';

  DateTime? _lastCheck;
  bool _running = false;

  @override
  DeviceNotice? build() {
    // Every return from the background passes through the lock's check
    // (checking -> open), so checking on that transition never races a
    // resume that is about to lock (review M-6).
    ref.listen<bool>(newDeviceLockOpenProvider, (prev, next) {
      if (next && prev == false) maybeCheck();
    });
    ref.listen<String?>(newDeviceUserIdProvider, (prev, next) {
      if (next == null) {
        state = null;
      } else if (next != prev) {
        maybeCheck(force: true);
      }
    });
    Future.microtask(maybeCheck);
    return null;
  }

  Future<void> maybeCheck({bool force = false}) async {
    if (_running) return;
    final userId = ref.read(newDeviceUserIdProvider);
    if (userId == null || !ref.read(newDeviceCheckAllowedProvider)()) return;
    final now = ref.read(newDeviceClockProvider)();
    final last = _lastCheck;
    if (!force && last != null && now.difference(last) < throttle) return;
    _lastCheck = now;
    _running = true;
    try {
      final found = await check(
        ref.read(accountSessionsRepositoryProvider),
        userId,
      );
      if (found != null) state = found;
    } finally {
      _running = false;
    }
  }

  void dismiss() => state = null;

  /// Names this device, lists the sessions and compares them with the ones
  /// this phone has already seen for [userId]. Every error says nothing.
  static Future<DeviceNotice?> check(
    AccountSessionsRepository repo,
    String userId,
  ) async {
    try {
      try {
        await repo.registerThisDevice();
      } catch (_) {}
      final now = await repo.list();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(knownKey(userId));
      final known =
          raw == null
              ? null
              : {for (final id in jsonDecode(raw) as List) id as String};
      await prefs.setString(
        knownKey(userId),
        jsonEncode([for (final d in now) d.sessionId]),
      );
      if (known == null) {
        return now.any((d) => !d.isCurrent) ? const DeviceNotice() : null;
      }
      final fresh = newSessionIds(known: known, now: now);
      if (fresh.isEmpty) return null;
      final newest = now
          .where((d) => fresh.contains(d.sessionId))
          .reduce((a, b) => b.signedInAt.isAfter(a.signedInAt) ? b : a);
      return DeviceNotice(device: newest);
    } catch (_) {
      return null;
    }
  }
}

final newDeviceNoticeProvider =
    NotifierProvider<NewDeviceWatcher, DeviceNotice?>(NewDeviceWatcher.new);

/// The banner over the app (mounted in the app shell, inside the lock gate).
class NewDeviceNotice extends ConsumerWidget {
  const NewDeviceNotice({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(newDeviceNoticeProvider);
    // The child stays the Stack's first child whether or not there is a
    // notice, so the Navigator below is never re-parented.
    return Stack(
      children: [
        child,
        if (notice != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 72,
            child: ListenableBuilder(
              listenable: router.routerDelegate,
              builder: (context, _) {
                final path =
                    router.routerDelegate.currentConfiguration.uri.path;
                if (path == RouteNames.neutralScreen) {
                  return const SizedBox.shrink();
                }
                return _Banner(
                  notice: notice,
                  onDismiss: ref.read(newDeviceNoticeProvider.notifier).dismiss,
                  onReview: () {
                    ref.read(newDeviceNoticeProvider.notifier).dismiss();
                    router.pushNamed('signedInDevices');
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.notice,
    required this.onDismiss,
    required this.onReview,
  });

  final DeviceNotice notice;
  final VoidCallback onDismiss;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = notice.device;
    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d == null) ...[
              Text("Review where you're signed in", style: text.titleSmall),
              const SizedBox(height: 4),
              Text(
                "You can now see the phones on your account and sign out any "
                "you don't use.",
                style: text.bodyMedium,
              ),
            ] else
              Text(
                'A new device signed in to your account: '
                '${d.label ?? 'Unnamed device'}, '
                '${MyDateFormat.toDate(d.signedInAt.toLocal())}. '
                'Not you? Review your devices.',
                style: text.bodyMedium,
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onReview, child: const Text('Review')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
