// lib/core/widgets/poll_composer.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/services.dart';

/// Attach-a-poll control for the opinion and topic compose screens (§8.11).
///
/// Starts collapsed behind an "Add poll" affordance, because a poll is optional
/// and the post body is the primary input. Once added, it shows 2-4 plain-text
/// option fields.
///
/// Options are immutable after the post is created, so this is the only place
/// they can be edited — the composer enforces the same 2-4 / 60-char limits the
/// RPC does, to fail in the form rather than at submit.
class PollComposer extends StatefulWidget {
  /// Fires whenever the poll changes. Emits null when there is no valid poll to
  /// attach, so the parent can pass it straight to the repository.
  final ValueChanged<List<String>?> onChanged;

  const PollComposer({super.key, required this.onChanged});

  static const int minOptions = 2;
  static const int maxOptions = 4;
  static const int maxOptionLength = 60;

  @override
  State<PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<PollComposer> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _enabled = false;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _enable() {
    setState(() {
      _enabled = true;
      // Open with the minimum: two empty options is the smallest valid poll.
      for (var i = 0; i < PollComposer.minOptions; i++) {
        _addOptionField(notify: false);
      }
    });
    // Focus the first field so the keyboard is already where the user is going.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty) _focusNodes.first.requestFocus();
    });
    _notify();
  }

  void _remove() {
    setState(() {
      _enabled = false;
      for (final controller in _controllers) {
        controller.dispose();
      }
      for (final node in _focusNodes) {
        node.dispose();
      }
      _controllers.clear();
      _focusNodes.clear();
    });
    _notify();
  }

  void _addOptionField({bool notify = true}) {
    if (_controllers.length >= PollComposer.maxOptions) return;
    final controller = TextEditingController();
    controller.addListener(_notify);
    _controllers.add(controller);
    _focusNodes.add(FocusNode());
    if (notify) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodes.last.requestFocus();
      });
      _notify();
    }
  }

  void _removeOptionField(int index) {
    if (_controllers.length <= PollComposer.minOptions) return;
    setState(() {
      _controllers.removeAt(index).dispose();
      _focusNodes.removeAt(index).dispose();
    });
    _notify();
  }

  /// The poll as the repository wants it, or null when it is not yet valid.
  /// Mirrors the RPC's rule: blank options are dropped, then 2-4 must remain.
  List<String>? _currentValue() {
    if (!_enabled) return null;
    final filled =
        _controllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
    if (filled.length < PollComposer.minOptions) return null;
    if (filled.length > PollComposer.maxOptions) return null;
    return filled;
  }

  void _notify() => widget.onChanged(_currentValue());

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!_enabled) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _enable,
          icon: const Icon(Icons.bar_chart_rounded, size: 18),
          label: const Text('Add poll'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Poll', style: textTheme.titleSmall),
            const Spacer(),
            TextButton(onPressed: _remove, child: const Text('Remove')),
          ],
        ),
        const Gap(Spacing.xs),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    maxLength: PollComposer.maxOptionLength,
                    textInputAction:
                        i == _controllers.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        PollComposer.maxOptionLength,
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Option ${i + 1}',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadiusTokens.mdAll,
                      ),
                    ),
                  ),
                ),
                // Only removable down to the 2-option minimum.
                if (_controllers.length > PollComposer.minOptions)
                  IconButton(
                    onPressed: () => _removeOptionField(i),
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove option ${i + 1}',
                  ),
              ],
            ),
          ),
        if (_controllers.length < PollComposer.maxOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOptionField,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add option'),
            ),
          ),
        Text(
          'Options can\'t be edited after posting.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
