import 'package:flutter/material.dart';

/// A 0–9 keypad with dots: no system keyboard and no text field, so it works
/// above the Navigator where there is no Overlay (Spec 2 ruling R2-6).
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.length,
    required this.onDigit,
    required this.onDelete,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget key(String label, VoidCallback onTap, {String? semantics}) =>
        SizedBox(
          width: 72,
          height: 64,
          child: Semantics(
            button: true,
            label: semantics ?? label,
            excludeSemantics: true,
            child: InkResponse(
              onTap: enabled ? onTap : null,
              radius: 32,
              child: Center(child: Text(label, style: text.headlineSmall)),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '$length digits entered',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 8; i++)
                if (i < length || i < 4)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      i < length ? Icons.circle : Icons.circle_outlined,
                      size: 14,
                      color: scheme.onSurface,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(d, () => onDigit(d))],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 72, height: 64),
            key('0', () => onDigit('0')),
            key('⌫', onDelete, semantics: 'Delete'),
          ],
        ),
      ],
    );
  }
}
