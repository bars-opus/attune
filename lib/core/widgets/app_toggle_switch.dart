import 'package:flutter/material.dart';

class AppToggleSwitch extends StatelessWidget {
  final bool? toggleValue;
  final ValueChanged<bool>? onToggleChanged;

  const AppToggleSwitch({
    super.key,
    this.toggleValue = false,
    this.onToggleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: toggleValue ?? false,
      onChanged: onToggleChanged,
      activeColor: Theme.of(context).colorScheme.primary,
      activeTrackColor: Theme.of(context).colorScheme.primary,
    );
  }
}
