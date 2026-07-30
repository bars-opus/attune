// lib/core/widgets/poll_composer.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:flutter/services.dart';

/// Tappable icon button that opens [PollComposer], via
/// [BottomSheetUtils.showDocumentationBottomSheet] — the same modal-sheet
/// pattern the opinion/topic compose screens already use for themselves
/// (OpinionComposeScreen, SubmitTopicScreen) and for TagSearchScreen, so a
/// poll is edited in its own focused sheet instead of expanding inline and
/// pushing the rest of the compose form down. Compact by design (an icon,
/// not a full-width row) to sit beside TagPickerRow's own icon button in
/// the same Row.
///
/// [currentOptions] is owned by the parent (mirrors [PollComposer.onChanged]
/// exactly) — the same "options can't be edited after posting" 2-4/60-char
/// rules still live entirely in [PollComposer] itself.
class PollComposerRow extends StatelessWidget {
  final List<String>? currentOptions;
  final ValueChanged<List<String>?> onChanged;

  const PollComposerRow({
    super.key,
    required this.currentOptions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppIconButton(
      icon: Icons.bar_chart_rounded,
      onPressed: () {
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          backgroundColor: colorScheme.neutral,
          widget: _PollComposerSheet(
            // Tapping this button is the "start a poll" action, so the sheet
            // must open straight into the 2-option editor — passing null
            // here would instead open PollComposer in its collapsed "+ Add
            // poll" state, forcing a second, redundant tap before any
            // fields appear. Mirrors PollComposer._enable()'s own
            // minOptions seeding for the same reason: two empty options is
            // the smallest valid poll.
            initialOptions:
                currentOptions ??
                List.filled(PollComposer.minOptions, '', growable: false),
            onChanged: onChanged,
          ),
        );
      },
      iconColor: colorScheme.onBackground,
    );
  }
}

/// The sheet's content: [PollComposer] itself plus a Done button to close
/// it. [PollComposer] only ever reports outward via onChanged (it has no
/// return-a-value contract of its own), so this sheet doesn't need — and
/// deliberately doesn't attempt — to read back a value on close; [onChanged]
/// already kept the parent's state current on every edit while the sheet
/// was open.
class _PollComposerSheet extends StatefulWidget {
  final List<String>? initialOptions;
  final ValueChanged<List<String>?> onChanged;

  const _PollComposerSheet({
    required this.initialOptions,
    required this.onChanged,
  });

  @override
  State<_PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<_PollComposerSheet> {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BottomSheetHeader(title: 'Poll'),

        Gap(Spacing.md.h),
        PollComposer(
          initialOptions: widget.initialOptions,
          onChanged: widget.onChanged,
        ),
        Gap(Spacing.lg.h),

        SemanticContainerWidget(
          content: 'Options can\'t be edited after posting.',
          icon: Icons.info_outline,
          title: '',
          backgroundColor: Colors.grey.withOpacity(0.1),
          borderColor: Colors.grey,
          iconColor: Colors.grey,
          textTheme: textTheme,
        ),
      ],
    );
  }
}

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

  /// Pre-seeds the editor as already-enabled with these options — used by
  /// [PollComposerRow] so reopening the sheet to tweak an existing poll
  /// doesn't reset back to the collapsed "Add poll" state and lose what was
  /// already typed. Null (the default) is the original collapsed behavior.
  final List<String>? initialOptions;

  const PollComposer({super.key, required this.onChanged, this.initialOptions});

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
  void initState() {
    super.initState();
    final initial = widget.initialOptions;
    if (initial != null && initial.isNotEmpty) {
      _enabled = true;
      for (final option in initial) {
        final controller = TextEditingController(text: option);
        controller.addListener(_notify);
        _controllers.add(controller);
        _focusNodes.add(FocusNode());
      }
    }
  }

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
      return AppIconButton(
        icon: Icons.tag,
        onPressed: _enable,
        iconColor: colorScheme.onBackground,
      );

      // Align(
      //   alignment: Alignment.centerLeft,
      //   child:
      //    TextButton.icon(
      //     onPressed: _enable,
      //     icon: const Icon(Icons.bar_chart_rounded, size: 18),
      //     // label: const Text('Add poll'),
      //   ),
      // );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Poll',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
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
                  child: AppTextFormField(
                    label: '',
                    height: 50.h,
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    maxLength: PollComposer.maxOptionLength,
                    isSmall: true,
                    textInputAction:
                        i == _controllers.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        PollComposer.maxOptionLength,
                      ),
                    ],
                    hintText: 'Option ${i + 1}',
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
      ],
    );
  }
}
