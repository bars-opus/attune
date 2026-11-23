// Spec 2 W7a (§3.7 Appeal; §3.15; D8): the one appeal of a restriction,
// opened from the restricted screen. Split out of restricted_screen.dart
// in Task 4 fix round 1 (M-8), as report_sheet.dart sits beside the
// report. An appeal on its way survives the sheet: back and the barrier do
// nothing, a pop from outside (the lock, quick exit) still re-reads the
// screen once it lands, and the request key is held per account, so a
// sheet opened again after busy sends the same request (R-T4-4); the text
// counts code points as the server does (R-T4-3); already_appealed and
// appeal_unavailable read the screen again (R-T4-5); another account
// closes it, even mid-send (R-T4-6). Fix round 1: it says it is the one
// appeal (M-5), its label is short and "Optional" with the count wraps
// under the field (M-1), and it opens without the slide (§3.15, M-7).
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart'
    show DatingActionKeys;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/setup/dating_text_rules.dart'
    show DatingRuneLimit;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// §3.7 the appeal, opened as [account]: true when the screen should read
/// again (sent, already appealed, or no longer appealable). An appeal on
/// its way when the sheet is closed from outside is still waited for
/// (R-T4-4).
Future<bool> showDatingAppealSheet(
  BuildContext context, {
  required String? account,
  required String restrictionId,
}) async {
  // Spec 2 W8a round 2 (Re-1-M2): nothing opens once Dating is blank.
  if (datingSheetRefused) return false;
  Future<bool>? sending;
  // A sheet removed from outside (closeDatingSheets: the lock, quick exit)
  // never completes its own future (Navigator.removeRoute), so its going
  // is told here too.
  final gone = Completer<bool?>();
  void end(bool? value) {
    if (!gone.isCompleted) gone.complete(value);
  }

  unawaited(
    showModalBottomSheet<bool>(
      context: context,
      routeSettings: datingSheetSettings('appeal'),
      isScrollControlled: true,
      // R-T4-4: never dragged away mid-send; the sheet has its own Close.
      enableDrag: false,
      // §3.15 (fix round 1, M-7): the appeal never animates.
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder:
          (sheet) => DatingSheetTracker(
            child: AllowLargeText(
              child: _AppealSheet(
                account: account,
                restrictionId: restrictionId,
                onSending: (f) => sending = f,
                onGone: () => end(null),
              ),
            ),
          ),
    ).then(end),
  );
  final popped = await gone.future;
  if (popped != null) return popped;
  final pending = sending;
  return pending == null ? false : await pending;
}

class _AppealSheet extends ConsumerStatefulWidget {
  const _AppealSheet({
    required this.account,
    required this.restrictionId,
    required this.onSending,
    required this.onGone,
  });

  final String? account;
  final String restrictionId;
  final ValueChanged<Future<bool>> onSending;

  /// The sheet left the tree (after its own pop, or removed from outside).
  final VoidCallback onGone;

  @override
  ConsumerState<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends ConsumerState<_AppealSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _reason;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _close(false, force: true),
      );
    });
  }

  /// R-T4-4: one key store per account (memory only, D8), so a sheet
  /// opened again after busy sends the same request.
  DatingActionKeys get _keys =>
      ref.read(datingReportKeysProvider(widget.account));

  @override
  void dispose() {
    widget.onGone();
    _text.dispose();
    super.dispose();
  }

  /// The sheet closes; [force] (another account) even while the appeal is
  /// on its way, which the person's own back or barrier never does.
  void _close(bool readAgain, {bool force = false}) {
    if (_closed || !mounted || (_busy && !force)) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(readAgain);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final account = widget.account;
    final text = _text.text.trim();
    setState(() {
      _busy = true;
      _reason = null;
    });
    // Read before the wait: the sheet may be gone when the answer lands.
    final keys = _keys;
    final done = Completer<bool>();
    widget.onSending(done.future);
    final r = await ref
        .read(datingReportGatewayProvider)
        .appeal(
          keys.keyFor('appeal', [widget.restrictionId, text]),
          widget.restrictionId,
          text.isEmpty ? null : text,
        );
    keys.settle('appeal', reason: r.reason);
    // already_appealed: the first one stands; the screen reads it again.
    final settled = r.ok || r.reason == 'already_appealed';
    done.complete(settled || r.reason == 'appeal_unavailable');
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (settled) {
      setState(() => _busy = false);
      _close(true);
      return;
    }
    setState(() {
      _busy = false;
      _reason = r.reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final reason = _reason;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(reason == 'appeal_unavailable');
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.md + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.dating_appeal,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              // M-5: the one appeal, said before anything is sent.
              Text(loc.dating_appealOnce, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Spacing.md),
              // M-1: the label above the field, where it wraps at large
              // text (a field's own label is one line and clips); merged
              // with the field, so a screen reader names the field by it.
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.dating_appealHint,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: Spacing.xs),
                    TextField(
                      key: const ValueKey('dating_appeal_text'),
                      controller: _text,
                      enabled: !_busy,
                      // R-T4-3: code points, as the server counts.
                      inputFormatters: const [DatingRuneLimit(500)],
                      onChanged: (_) => setState(() {}),
                      maxLines: 5,
                      minLines: 3,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      textCapitalization: TextCapitalization.sentences,
                      // "Optional" and the count wrap under the field.
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                loc.dating_appealCount(_text.text.runes.length, 500),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!online) DatingCalmLine(loc.dating_offline),
              if (reason != null)
                reason == 'busy'
                    ? DatingCalmLine(loc.dating_busy)
                    : FlowErrorLine(
                      text:
                          reason == 'appeal_unavailable'
                              ? loc.dating_cardGone
                              : loc.dating_errorGeneric,
                      liveRegion: true,
                    ),
              const SizedBox(height: Spacing.sm),
              FlowPrimaryButton(
                key: const ValueKey('dating_appeal_send'),
                label: loc.dating_appealSend,
                busy: _busy,
                onPressed:
                    online && !_busy && reason != 'appeal_unavailable'
                        ? _send
                        : null,
              ),
              const SizedBox(height: Spacing.sm),
              FlowSecondaryButton(
                key: const ValueKey('dating_appeal_close'),
                label: loc.dating_close,
                onPressed:
                    _busy ? null : () => _close(reason == 'appeal_unavailable'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
