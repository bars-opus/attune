// lib/features/safety/domain/services/quick_exit_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

class QuickExitService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const String _requiresSafetyUnlockKey = 'safety_requires_unlock';

  /// Execute quick exit
  static Future<void> execute(BuildContext context) async {
    unawaited(_markSafetyUnlockRequired());
    _showNeutralCover(context);

    Future.delayed(const Duration(milliseconds: 300), () {
      _exitApp();
    });
  }

  static Future<void> _markSafetyUnlockRequired() {
    return _storage.write(key: _requiresSafetyUnlockKey, value: 'true');
  }

  static Future<bool> requiresSafetyUnlock() async {
    return (await _storage.read(key: _requiresSafetyUnlockKey)) == 'true';
  }

  static Future<void> clearSafetyUnlockRequired() {
    return _storage.delete(key: _requiresSafetyUnlockKey);
  }

  static void _showNeutralCover(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NeutralScreen()),
      (route) => false,
    );
  }

  static void _exitApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
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
