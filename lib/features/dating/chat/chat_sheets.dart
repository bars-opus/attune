// Spec 2 W6a (§3.6; D8): the chat's sheets. The Safety sheet (Report
// first since W7a; Block, Unmatch, Safety resources; W6c's rows), Unmatch's
// confirm, Swap contacts with its one-time card, and what a hidden span
// means. Each answers once (a second tap does nothing), shows nothing of
// the last account once the signed-in account changes and then closes
// choosing nothing, and carries a Dating sheet's route name (the unlock
// removes it). None of them is ever animated beyond the sheet itself.
//
// Final client fix wave: the Safety sheet offers no second Block once this
// person has just blocked (M-7); the answer sheet says the answer waits for
// both and has its own hint (C-9), and hands back what was written however
// it closes without Send (M-9).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the Safety sheet's person chose.
enum DatingSafetyChoice {
  // Spec 2 W7a (§3.6, R-43): Report, first; open for 30 days after the end.
  report,
  block,
  unmatch,
  closeKindly,
  resources,
  weMet,
  planMeet,
}

Future<T?> _show<T>(
  BuildContext context,
  String name,
  String? account,
  Widget Function(BuildContext context, void Function(T?) close) builder,
) {
  // Spec 2 W8a round 2 (Re-1-M2): nothing opens once Dating is blank.
  if (datingSheetRefused) return Future<T?>.value();
  return showModalBottomSheet<T>(
    context: context,
    routeSettings: datingSheetSettings(name),
    isScrollControlled: true,
    builder:
        (sheet) => DatingSheetTracker(
          child: AllowLargeText(
            child: _OnceSheet<T>(account: account, builder: builder),
          ),
        ),
  );
}

class _OnceSheet<T> extends ConsumerStatefulWidget {
  const _OnceSheet({required this.account, required this.builder});

  final String? account;
  final Widget Function(BuildContext context, void Function(T?) close) builder;

  @override
  ConsumerState<_OnceSheet<T>> createState() => _OnceSheetState<T>();
}

class _OnceSheetState<T> extends ConsumerState<_OnceSheet<T>> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(null));
    });
  }

  void _close(T? chosen) {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(chosen);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    return widget.builder(context, _close);
  }
}

Widget _frame(BuildContext context, String title, List<Widget> children) =>
    SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: Spacing.sm),
            ...children,
          ],
        ),
      ),
    );

/// §3.6 the Safety sheet, opened as [account] for [name]'s chat. W6a's
/// rows: Block, Unmatch (while the chat is open) and Safety resources.
/// [blocked]: this person has just blocked here (no second Block).
Future<DatingSafetyChoice?> showDatingSafetySheet(
  BuildContext context, {
  required String? account,
  required String name,
  required bool ended,
  bool weMet = false,
  bool blocked = false,
}) => _show<DatingSafetyChoice>(context, 'chat-safety', account, (
  context,
  close,
) {
  final loc = AppLocalizations.of(context)!;
  Widget row(String title, IconData icon, DatingSafetyChoice choice) =>
      InfoRowWidget(
        title: title,
        subtitle: '',
        icon: icon,
        showAvatar: false,
        disableTrailing: true,
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        onTap: () => close(choice),
      );
  return _frame(context, loc.dating_chatSafety, [
    row(
      name.isEmpty
          ? loc.dating_reportTitleNoName
          : loc.dating_reportTitle(name),
      Icons.flag_outlined,
      DatingSafetyChoice.report,
    ),
    if (!blocked)
      row(
        name.isEmpty ? loc.dating_blockRowNoName : loc.dating_blockRow(name),
        Icons.block,
        DatingSafetyChoice.block,
      ),
    if (!ended)
      row(
        loc.dating_chatSafetyUnmatch,
        Icons.person_remove_outlined,
        DatingSafetyChoice.unmatch,
      ),
    // Spec 2 W6c (§3.6): Close kindly, and We met.
    if (!ended)
      row(
        loc.dating_closeKindly,
        Icons.waving_hand_outlined,
        DatingSafetyChoice.closeKindly,
      ),
    row(
      loc.dating_chatSafetyResources,
      Icons.health_and_safety_outlined,
      DatingSafetyChoice.resources,
    ),
    // Spec 2 W6c (§3.6 meeting kit; the spec's order: Plan a meet, then We
    // met).
    if (!ended)
      row(
        loc.dating_planTitle,
        Icons.event_note_outlined,
        DatingSafetyChoice.planMeet,
      ),
    if (!ended && !weMet)
      row(loc.dating_weMet, Icons.handshake_outlined, DatingSafetyChoice.weMet),
  ]);
});

/// §3.6 Unmatch's confirm: true when the person chose Unmatch. Offline,
/// Unmatch waits (nothing is queued).
Future<bool> showDatingUnmatchSheet(
  BuildContext context, {
  required String? account,
  required String name,
}) async =>
    await _show<bool>(context, 'chat-unmatch', account, (context, close) {
      return Consumer(
        builder: (context, ref, _) {
          final loc = AppLocalizations.of(context)!;
          final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
          return _frame(
            context,
            name.isEmpty
                ? loc.dating_unmatchTitleNoName
                : loc.dating_unmatchTitle(name),
            [
              Text(
                name.isEmpty
                    ? loc.dating_unmatchBodyNoName
                    : loc.dating_unmatchBody(name),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: Spacing.md),
              if (!online) DatingCalmLine(loc.dating_offline),
              FlowPrimaryButton(
                label: loc.dating_unmatchConfirm,
                onPressed: online ? () => close(true) : null,
              ),
              const SizedBox(height: Spacing.sm),
              FlowSecondaryButton(
                label: loc.dating_blockCancel,
                onPressed: () => close(false),
              ),
            ],
          );
        },
      );
    }) ==
    true;

/// §3.6 Swap contacts: what swapping means and the one-time card (shown
/// each time the sheet opens: nothing is stored to remember it, D20).
/// True when the person chose Swap. Offline, Swap waits (fix round 1, M-5:
/// nothing is queued), as Unmatch does.
Future<bool> showDatingSwapSheet(
  BuildContext context, {
  required String? account,
}) async =>
    await _show<bool>(context, 'chat-swap', account, (context, close) {
      return Consumer(
        builder:
            (context, ref, _) => _swapBody(
              context,
              online: ref.watch(datingOnlineProvider).valueOrNull ?? true,
              close: close,
            ),
      );
    }) ==
    true;

Widget _swapBody(
  BuildContext context, {
  required bool online,
  required void Function(bool?) close,
}) {
  final loc = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  return _frame(context, loc.dating_chatSwap, [
    Text(loc.dating_chatSwapSheetBody, style: theme.textTheme.bodyLarge),
    const SizedBox(height: Spacing.md),
    Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadiusTokens.mdAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                loc.dating_chatSwapCard,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: Spacing.md),
    if (!online) DatingCalmLine(loc.dating_offline),
    FlowPrimaryButton(
      label: loc.dating_chatSwapConfirm,
      onPressed: online ? () => close(true) : null,
    ),
    const SizedBox(height: Spacing.sm),
    FlowSecondaryButton(
      label: loc.dating_chatSwapNotYet,
      onPressed: () => close(false),
    ),
  ]);
}

/// Spec 2 W6b Task 7 fix round 1 (M-2): before a card's number is called,
/// S1's confirm in a Dating sheet ("Calls may show in your phone's call
/// history."). True when the person chose Call. A call needs no
/// connection.
Future<bool> showDatingCallSheet(
  BuildContext context, {
  required String? account,
  required String number,
}) async =>
    await _show<bool>(context, 'chat-call', account, (context, close) {
      final loc = AppLocalizations.of(context)!;
      return _frame(context, loc.support_callConfirmTitle(number), [
        Text(
          loc.support_callConfirmBody,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: Spacing.md),
        FlowPrimaryButton(
          label: loc.support_callConfirmCall,
          onPressed: () => close(true),
        ),
        const SizedBox(height: Spacing.sm),
        FlowSecondaryButton(
          label: loc.dating_blockCancel,
          onPressed: () => close(false),
        ),
      ]);
    }) ==
    true;

/// What the person chose on Get help's confirm.
enum DatingCheckinHelpChoice { show, message }

/// Spec 2 W6c Task 10 (§3.6 Get help): asked first. [show]: the country's
/// support directory, emergency first (no connection needed: S1's
/// directory falls back to its bundled catalogue). Fix round 1 (I-6):
/// Message someone you trust is offered here too, so a person who can't
/// have numbers on screen has the silent text at once. Null: Cancel, or
/// another account.
Future<DatingCheckinHelpChoice?> showDatingCheckinHelpSheet(
  BuildContext context, {
  required String? account,
}) => _show<DatingCheckinHelpChoice>(context, 'checkin-help', account, (
  context,
  close,
) {
  final loc = AppLocalizations.of(context)!;
  return _frame(context, loc.dating_checkinHelpTitle, [
    const SizedBox(height: Spacing.sm),
    FlowPrimaryButton(
      label: loc.dating_checkinHelpShow,
      onPressed: () => close(DatingCheckinHelpChoice.show),
    ),
    const SizedBox(height: Spacing.sm),
    FlowSecondaryButton(
      key: const ValueKey('dating_checkin_help_message'),
      label: loc.dating_checkinMessageSomeone,
      onPressed: () => close(DatingCheckinHelpChoice.message),
    ),
    const SizedBox(height: Spacing.sm),
    FlowSecondaryButton(
      label: loc.dating_blockCancel,
      onPressed: () => close(null),
    ),
  ]);
});

/// §3.6: what a hidden span is.
Future<void> showDatingMaskedSheet(
  BuildContext context, {
  required String? account,
}) => _show<void>(context, 'chat-masked', account, (context, close) {
  final loc = AppLocalizations.of(context)!;
  return _frame(context, loc.dating_chatMaskedTitle, [
    Text(
      loc.dating_chatMaskedExplain,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    const SizedBox(height: Spacing.md),
    FlowSecondaryButton(label: loc.dating_chatOk, onPressed: () => close(null)),
  ]);
});

/// Spec 2 W6c (§3.6) Close kindly's confirm: the reviewed message, then
/// [Send and end] or [Cancel]. True when the person chose to send. Offline,
/// it waits (nothing is queued).
Future<bool> showDatingCloseKindlySheet(
  BuildContext context, {
  required String? account,
}) async =>
    await _show<bool>(context, 'chat-close-kindly', account, (context, close) {
      return Consumer(
        builder: (context, ref, _) {
          final loc = AppLocalizations.of(context)!;
          final theme = Theme.of(context);
          final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
          return _frame(context, loc.dating_closeKindlyTitle, [
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadiusTokens.mdAll,
              ),
              child: Text(
                loc.dating_closeKindlyMessage,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (!online) DatingCalmLine(loc.dating_offline),
            FlowPrimaryButton(
              label: loc.dating_closeKindlySend,
              onPressed: online ? () => close(true) : null,
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_blockCancel,
              onPressed: () => close(false),
            ),
          ]);
        },
      );
    }) ==
    true;

/// The guided answer's limit, as the server counts it (`char_length`: code
/// points), the same as a message's (`kDatingMessageMax`).
const _guidedMax = 1000;

/// Spec 2 W6c (§3.6): this side's answer to the guided question; the text,
/// or null when the person went back. [initial] is an answer that was not
/// sent (memory only). Offline, Send waits (nothing is queued). M-9:
/// [onDraft] gets what was written whenever the sheet goes without Send
/// (Cancel, a swipe, the system back, the lock or another account).
Future<String?> showDatingGuidedAnswerSheet(
  BuildContext context, {
  required String? account,
  required String question,
  String? initial,
  ValueChanged<String>? onDraft,
}) => _show<String>(context, 'chat-guided', account, (context, close) {
  return _GuidedAnswer(
    question: question,
    initial: initial,
    close: close,
    onDraft: onDraft,
  );
});

class _GuidedAnswer extends ConsumerStatefulWidget {
  const _GuidedAnswer({
    required this.question,
    required this.close,
    this.initial,
    this.onDraft,
  });

  final String question;
  final String? initial;
  final void Function(String?) close;
  final ValueChanged<String>? onDraft;

  @override
  ConsumerState<_GuidedAnswer> createState() => _GuidedAnswerState();
}

class _GuidedAnswerState extends ConsumerState<_GuidedAnswer> {
  late final _text = TextEditingController(text: widget.initial);

  /// Send was chosen: what was written is the answer, not a draft.
  bool _sent = false;

  @override
  void dispose() {
    if (!_sent) widget.onDraft?.call(_text.text);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _frame(context, widget.question, [
        // C-9 (T9 M-8): the answer stays hidden until both have answered.
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            loc.dating_guidedWaitingNoName,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (context, value, _) {
            // As the composer (W6a fix round 1, M-10): counted as the server
            // counts; near the limit a counter, over it a line and no Send.
            final count = value.text.runes.length;
            final over = count > _guidedMax;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('dating_guided_answer'),
                  controller: _text,
                  minLines: 2,
                  maxLines: 6,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_guidedMax * 2),
                  ],
                  textCapitalization: TextCapitalization.sentences,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(
                    hintText: loc.dating_guidedAnswerHint,
                    counterText:
                        count >= _guidedMax - 100
                            ? loc.dating_chatCounter(count, _guidedMax)
                            : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (over)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: FlowErrorLine(
                      text: loc.dating_chatTooLong,
                      liveRegion: true,
                    ),
                  ),
                const SizedBox(height: Spacing.sm),
                if (!online) DatingCalmLine(loc.dating_offline),
                FlowPrimaryButton(
                  label: loc.dating_chatSend,
                  onPressed:
                      !online || over || value.text.trim().isEmpty
                          ? null
                          : () {
                            _sent = true;
                            widget.close(_text.text);
                          },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Spacing.sm),
        FlowSecondaryButton(
          label: loc.dating_blockCancel,
          onPressed: () => widget.close(null),
        ),
      ]),
    );
  }
}
