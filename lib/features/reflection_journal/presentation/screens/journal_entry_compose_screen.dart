// lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart
import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryComposeScreen extends ConsumerStatefulWidget {
  const JournalEntryComposeScreen({super.key, this.entryId});

  final String? entryId;

  @override
  ConsumerState<JournalEntryComposeScreen> createState() =>
      _JournalEntryComposeScreenState();
}

class _JournalEntryComposeScreenState
    extends ConsumerState<JournalEntryComposeScreen> {
  final _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _promptDismissed = false;
  bool _isSaving = false;
  static const int minContentLength = 10;

  String? _promptUsed;
  bool _loadedExisting = false;

  @override
  void initState() {
    super.initState();
    _promptUsed = randomJournalPrompt();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (widget.entryId != null) {
        await ref.read(
          updateJournalEntryProvider((
            entryId: widget.entryId!,
            content: content,
          )).future,
        );
        unawaited(
          ref.read(analyseJournalEntryProvider(widget.entryId!).future),
        );
      } else {
        final newId = await ref.read(
          createJournalEntryProvider((
            content: content,
            promptUsed: _promptDismissed ? null : _promptUsed,
          )).future,
        );
        unawaited(ref.read(analyseJournalEntryProvider(newId).future));
      }
      if (mounted) {
        context.showSuccessSnackbar('Saved. Sit with that for a bit.');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackbar(
          'Could not save that just now. Your writing is still here — try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (widget.entryId != null && !_loadedExisting) {
      final entryAsync = ref.watch(journalEntryProvider(widget.entryId!));
      entryAsync.whenData((entry) {
        if (!_loadedExisting) {
          _controller.text = entry.content;
          _loadedExisting = true;
        }
      });
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InfoRowWidget(
                      title:
                          widget.entryId != null ? 'Edit entry' : 'New entry',
                      subtitle: '',
                      iconColor: colorScheme.onBackground,
                      icon: Icons.close,
                      showAvatar: false,
                      showTrailingArrow: true,
                      showDivider: false,
                      disableTrailing: true,
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                  ),

                  if (_controller.text.trim().length >= minContentLength)
                    ShakeTransition(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutBack,
                      child: AppButton(
                        elevation: 0,
                        animateButton: false,
                        label: 'Save',
                        isLoading: _isSaving,
                        onPressed: _isSaving ? null : _save,
                        textColor: colorScheme.surface,
                        size: ButtonSize.large,
                        width: 100,
                        padding: Spacing.horizontalMd,
                        height: 30.h,
                        borderRadius: BorderRadius.circular(100.r),
                      ),
                    ),
                ],
              ),
              Gap(Spacing.lg.h),
              if (widget.entryId == null &&
                  !_promptDismissed &&
                  _promptUsed != null)
                SemanticContainerWidget(
                  content: _promptUsed ?? '',
                  icon: Icons.lightbulb_outline,
                  title: 'Pro Tip',
                  backgroundColor: colorScheme.success.withOpacity(0.1),
                  borderColor: colorScheme.success,
                  iconColor: colorScheme.success,
                  textTheme: textTheme,
                ),
              Gap(Spacing.lg.h),
              AppTextFormField(
                controller: _controller,
                focusNode: _focusNode,
                hintText:
                    "What's on your mind? Write freely. This stays private",
                maxLines: 12,
                minLines: 5,
                autofocus: true,
                // buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null, // Custom counter
                onChanged: (_) => setState(() {}),
                enabled: !_isSaving,
                label: '',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
