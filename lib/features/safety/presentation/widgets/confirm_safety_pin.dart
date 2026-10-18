import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';

/// Asks for the Safety PIN before a sensitive action (Spec 3c, plan review
/// I8: downloading everything), so someone holding the unlocked phone cannot
/// take the journal and check-ins away. True when no PIN is set.
Future<bool> confirmSafetyPin(
  BuildContext context, {
  SafetyPinStore? store,
}) async {
  final s = store ?? SafetyPinStore.instance;
  if (!await s.hasPin()) return true;
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConfirmPinSheet(store: s),
  );
  return ok ?? false;
}

class _ConfirmPinSheet extends StatefulWidget {
  const _ConfirmPinSheet({required this.store});
  final SafetyPinStore store;

  @override
  State<_ConfirmPinSheet> createState() => _ConfirmPinSheetState();
}

class _ConfirmPinSheetState extends State<_ConfirmPinSheet> {
  String _entry = '';
  String? _error;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final r = await widget.store.check(_entry);
      if (!mounted) return;
      if (r.result == PinCheck.ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _entry = '';
        _error =
            r.result == PinCheck.waiting
                ? 'Try again later.'
                : "That PIN didn't match.";
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter your Safety PIN', style: text.titleMedium),
            SizedBox(
              height: 32,
              child:
                  _error == null
                      ? null
                      : Center(
                        child: Text(
                          _error!,
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
            ),
            PinKeypad(
              length: _entry.length,
              enabled: !_busy,
              onDigit:
                  (d) => setState(() {
                    if (_entry.length < 8) _entry += d;
                  }),
              onDelete:
                  () => setState(() {
                    if (_entry.isNotEmpty) {
                      _entry = _entry.substring(0, _entry.length - 1);
                    }
                  }),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _entry.length >= 4 && !_busy ? _confirm : null,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
