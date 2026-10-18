import 'dart:async';

import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String retryCopy(Duration left) {
  if (left.inSeconds < 60) {
    return 'Try again in ${left.inSeconds.clamp(1, 59)} seconds.';
  }
  if (left.inMinutes < 50) {
    return 'Try again in ${(left.inSeconds / 60).ceil()} minutes.';
  }
  if (left.inMinutes < 90) return 'Try again in about an hour.';
  return 'Try again in about ${(left.inMinutes / 60).round()} hours.';
}

/// Neutral on purpose (Spec 2 ruling R2-7): no app name, no logo, no name.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _message;
  DateTime? _retryAt;
  bool _confirmForgot = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // A wait set before a restart shows at once (review I4).
    Future.microtask(() async {
      final at = await ref.read(safetyLockDepsProvider).pins.retryAt();
      if (!mounted || at == null) return;
      setState(() {
        _retryAt = at;
        _message = retryCopy(at.difference(DateTime.now().toUtc()));
      });
      _startTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _waiting =>
      _retryAt != null && DateTime.now().toUtc().isBefore(_retryAt!);

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (!_waiting) {
          _retryAt = null;
          _message = null;
          _tick?.cancel();
        } else {
          _message = retryCopy(_retryAt!.difference(DateTime.now().toUtc()));
        }
      });
    });
  }

  Future<void> _unlock() async {
    if (_busy || _pin.isEmpty || _waiting) return;
    setState(() => _busy = true);
    final r = await ref.read(safetyLockProvider.notifier).unlock(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      switch (r.result) {
        case PinCheck.ok:
          _message = null;
        case PinCheck.wrong:
          _retryAt = r.retryAt;
          _message =
              r.retryAt == null
                  ? "That PIN didn't match."
                  : retryCopy(r.retryAt!.difference(DateTime.now().toUtc()));
        case PinCheck.waiting:
          _retryAt = r.retryAt;
          _message = retryCopy(r.retryAt!.difference(DateTime.now().toUtc()));
      }
    });
    if (_retryAt != null) _startTick();
  }

  Future<void> _forgot() async {
    final ok = await ref.read(safetyLockProvider.notifier).forgot();
    if (!mounted || ok) return;
    setState(() {
      _confirmForgot = false;
      _message = "Couldn't sign out. Try again.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child:
                  _confirmForgot
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Sign out of Attune? You'll need your phone number to sign back in. Your PIN will be removed.",
                            textAlign: TextAlign.center,
                            style: text.bodyLarge,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _forgot,
                            child: const Text('Sign out'),
                          ),
                          TextButton(
                            onPressed:
                                () => setState(() => _confirmForgot = false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Enter PIN', style: text.headlineSmall),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 24,
                            child:
                                _message == null
                                    ? null
                                    : Text(
                                      _message!,
                                      style: text.bodyMedium?.copyWith(
                                        color: scheme.error,
                                      ),
                                    ),
                          ),
                          const SizedBox(height: 16),
                          PinKeypad(
                            length: _pin.length,
                            enabled: !_busy && !_waiting,
                            onDigit:
                                (d) => setState(() {
                                  if (_pin.length < 8) _pin += d;
                                  if (_message != null && !_waiting) {
                                    _message = null;
                                  }
                                }),
                            onDelete:
                                () => setState(() {
                                  if (_pin.isNotEmpty) {
                                    _pin = _pin.substring(0, _pin.length - 1);
                                  }
                                }),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed:
                                _pin.length >= 4 && !_busy && !_waiting
                                    ? _unlock
                                    : null,
                            child: const Text('Unlock'),
                          ),
                          TextButton(
                            onPressed:
                                () => setState(() => _confirmForgot = true),
                            child: const Text('Forgot PIN?'),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
