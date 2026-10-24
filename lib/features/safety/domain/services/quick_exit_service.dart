// lib/features/safety/domain/services/quick_exit_service.dart

import 'dart:async';
import 'dart:io';
import 'package:attune/features/couple_map/data/couple_map_device_data.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickExitService {
  /// resetOnError, in the safety keys' own file: a reset wipes only the
  /// safety keys. The flag is mirrored in prefs, so a reset cannot lose it
  /// (Spec 2 review C2, I-4).
  static const defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: 'attune_safety',
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  @visibleForTesting
  static FlutterSecureStorage storage = defaultStorage;
  @visibleForTesting
  static Future<void> Function()? exitOverride;

  /// Story thumbnails, signed URLs and the last-known rings (05 #6).
  @visibleForTesting
  static Future<void> Function() clearStories = clearStoryDeviceCaches;
  static const String _requiresSafetyUnlockKey = 'safety_requires_unlock';
  static const _channel = MethodChannel('attune/safety');

  /// Execute quick exit from a screen's context.
  // GoRouter owns the root Navigator declaratively (its Page list), so an
  // imperative Navigator.pushAndRemoveUntil here throws
  // '!pageBased || isWaitingForExitingDecision' — go replaces the whole
  // stack the same way (route) => false used to.
  static Future<void> execute(BuildContext context) =>
      _run(() => context.goNamed('neutralScreen'));

  /// Execute quick exit from the root shell, above the Router (Spec 2).
  static Future<void> executeWithRouter(GoRouter router) =>
      _run(() => router.goNamed('neutralScreen'));

  static Future<void> _run(void Function() showCover) async {
    showCover();
    // The home-screen card and the lock-screen plan show plans: empty them
    // too. Fire-and-forget, after the cover is up, so nothing delays or
    // reveals activation.
    unawaited(clearTogetherDeviceSurfaces());
    // The map's tile cache holds the partner's area; pins hold faces.
    unawaited(clearCoupleMapDeviceData());
    // Story thumbnails sit in the shared image cache; empty it, with the
    // story URLs and rings snapshot (05 #6).
    unawaited(Future.sync(clearStories).catchError((Object _) {}));
    // The flag must be on disk before Attune leaves, or a kill during the
    // decoy comes back unlocked (Spec 2 review C3). The cover is already up,
    // so waiting reveals nothing; 300 ms is a minimum, not a maximum.
    try {
      await _markSafetyUnlockRequired();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Once more now the old screen is gone: anything it saved or downloaded
    // during the cover goes too (stories batch-4 review #2).
    unawaited(Future.sync(clearStories).catchError((Object _) {}));
    await (exitOverride ?? _exitApp)();
  }

  @visibleForTesting
  static Future<void> markSafetyUnlockRequired() =>
      _markSafetyUnlockRequired();

  static Future<void> _markSafetyUnlockRequired() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _requiresSafetyUnlockKey,
        true,
      );
    } catch (_) {}
    await storage.write(key: _requiresSafetyUnlockKey, value: 'true');
  }

  static Future<bool> requiresSafetyUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_requiresSafetyUnlockKey) ?? false) return true;
    return (await storage.read(key: _requiresSafetyUnlockKey)) == 'true';
  }

  static Future<void> clearSafetyUnlockRequired() async {
    await (await SharedPreferences.getInstance()).remove(
      _requiresSafetyUnlockKey,
    );
    await storage.delete(key: _requiresSafetyUnlockKey);
  }

  static Future<void> _exitApp() async {
    if (!Platform.isAndroid) return;
    // Removes the task, so Attune is not left in Recents (F3 (2)).
    try {
      await _channel.invokeMethod<void>('finishAndRemoveTask');
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
}

/// Neutral screen shown during quick exit
class NeutralScreen extends StatelessWidget {
  const NeutralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.today_outlined,
                size: 72,
                color: Color(0xFF6D7D8B),
              ),
              const SizedBox(height: 20),
              Text(
                'Daily overview',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF31404D),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Preparing your schedule...',
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5E6A73),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
