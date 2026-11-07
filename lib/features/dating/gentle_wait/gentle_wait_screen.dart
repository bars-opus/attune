// Spec 2 W2: D0, the gentle wait (§3.2 D0, §3.0, §3.15). Shown only while
// get_dating_home() answers `gentle_wait`; W3a gives it its route
// (/dating/setup/wait, behind the Dating lock) and the next step.
// Never animated; large text let through (FlowFrame's AllowLargeText);
// the dates read in full words; the three answers are typed into memory
// only and saved on the server when the person asks.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GentleWaitScreen extends ConsumerStatefulWidget {
  const GentleWaitScreen({super.key, required this.onSetUp, this.onBack});

  /// "Set up Dating now": setup runs as usual (W3a opens the next step).
  final VoidCallback onSetUp;

  /// The back button; none when null.
  final VoidCallback? onBack;

  @override
  ConsumerState<GentleWaitScreen> createState() => _GentleWaitScreenState();
}

enum _Status { none, saved, cleared, busy, clearBusy, failed }

class _GentleWaitScreenState extends ConsumerState<GentleWaitScreen> {
  final _answers = {
    for (final key in gentleWaitQuestionKeys) key: TextEditingController(),
  };

  /// The account whose saved answers are in the fields (D8).
  String? _seededFor;
  bool _saving = false;
  _Status _status = _Status.none;

  /// The read of the account now signed in (D8: one per account).
  ProviderSubscription<AsyncValue<GentleWait>>? _read;

  /// Failed reads so far: each failure is a new live region, so a repeat
  /// failure after Retry is read out again (fix round 1, M-1).
  int _readFailures = 0;

  /// Whether the server holds answers for this account: blank fields then
  /// save as the clear, and the button says so (B3 carry).
  bool _savedAny = false;

  /// Blank means nothing but whitespace (spaces, newlines, tabs): the
  /// server's view too, since blank answers are sent as '' (fix round 1).
  static bool _anyAnswer(Iterable<String> answers) =>
      answers.any((a) => a.trim().isNotEmpty);

  /// What the three fields hold right now, shown or not (D8 tests: nothing
  /// of the last account stays in memory while the next one's read is out).
  @visibleForTesting
  List<String> get debugAnswerTexts => [
    for (final controller in _answers.values) controller.text,
  ];

  @override
  void initState() {
    super.initState();
    // D8: another account on this phone starts from empty fields, never
    // from what the last one typed or saved.
    ref.listenManual<String?>(gentleWaitAccountProvider, (previous, next) {
      if (previous == next) return;
      for (final controller in _answers.values) {
        controller.clear();
      }
      setState(() {
        _seededFor = null;
        _status = _Status.none;
        _saving = false;
        _readFailures = 0;
      });
      _listenTo(next);
    });
    _listenTo(ref.read(gentleWaitAccountProvider));
  }

  /// Follows [account]'s own read only; the last account's subscription is
  /// closed, so its entry (and its answers) is disposed (fix round 1, I-2).
  void _listenTo(String? account) {
    _read?.close();
    _read = ref.listenManual<AsyncValue<GentleWait>>(
      gentleWaitProvider(account),
      (_, next) {
        if (next is AsyncError<GentleWait> && !next.isLoading) {
          setState(() => _readFailures++);
        }
        // Only a finished read seeds the fields.
        if (next is! AsyncData<GentleWait>) return;
        final data = next.value;
        if (_seededFor == account) return;
        for (final key in gentleWaitQuestionKeys) {
          _answers[key]!.text = data.answers[key] ?? '';
        }
        _seededFor = account;
        _savedAny = _anyAnswer(data.answers.values);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final account = ref.read(gentleWaitAccountProvider);
    // Whitespace is blank, sent as blank; the rest is sent trimmed
    // (fix round 1, I-1: the server trims only spaces).
    final answers = {
      for (final entry in _answers.entries) entry.key: entry.value.text.trim(),
    };
    final clearing = !_anyAnswer(answers.values);
    // Said "cleared" only when the button was the clear.
    final wasClear = clearing && _savedAny;
    setState(() {
      _saving = true;
      _status = _Status.none;
    });
    var result = GentleWaitSave.failed;
    try {
      final gateway = ref.read(gentleWaitGatewayProvider);
      // All blank is the clear: the server's never-gated branch, never the
      // setup-guarded save (exposure-reducing; fix round 1, I-1).
      result = clearing ? await gateway.clear() : await gateway.save(answers);
    } catch (_) {
      result = GentleWaitSave.failed;
    }
    // D8: the account changed while this was out; the next one hears
    // nothing about it (its fields were already emptied).
    if (!mounted || ref.read(gentleWaitAccountProvider) != account) return;
    setState(() {
      _saving = false;
      _status = switch (result) {
        GentleWaitSave.saved => wasClear ? _Status.cleared : _Status.saved,
        // Calm: nothing is lost and Save tries again (B3 carry); a clear
        // never says the answers are "still here" (fix round 1, M-5).
        GentleWaitSave.busy => clearing ? _Status.clearBusy : _Status.busy,
        _ => _Status.failed,
      };
      if (result == GentleWaitSave.saved) _savedAny = !clearing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final wait = ref.watch(
      gentleWaitProvider(ref.watch(gentleWaitAccountProvider)),
    );
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    // Only a finished read is shown: a loading or failed frame (a first
    // read, or the next account's) never shows the last data (D8).
    final data = wait is AsyncData<GentleWait> ? wait.value : null;
    return FlowFrame(
      title: loc.dating_gentleWaitTitle,
      onBack: widget.onBack,
      actions: [
        FlowPrimaryButton(
          label: loc.dating_gentleWaitSetUp,
          onPressed: widget.onSetUp,
        ),
      ],
      body:
          data != null
              ? _body(context, loc, data, online)
              : wait is AsyncError<GentleWait>
              ? _readFailed(
                context,
                loc,
                busy: wait.error is GentleWaitBusy,
                retrying: wait.isLoading,
              )
              : Center(
                // D0 is never animated (§3.2): a ring that stands still, and
                // reads as "Loading", never a percentage (fix round 1, M-2).
                child: CircularProgressIndicator(
                  value: 0.75,
                  semanticsLabel: loc.loadingDefaultMessage,
                  semanticsValue: '',
                ),
              ),
    );
  }

  Widget _readFailed(
    BuildContext context,
    AppLocalizations loc, {
    required bool busy,
    required bool retrying,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KeyedSubtree(
        key: ValueKey('gentle_wait_read_failed_${_readFailures - 1}'),
        child:
            busy
                ? _CalmLine(text: loc.dating_busy)
                : FlowErrorLine(
                  text: loc.dating_errorGeneric,
                  liveRegion: true,
                ),
      ),
      const SizedBox(height: Spacing.md),
      FlowSecondaryButton(
        label: loc.dating_retry,
        busy: retrying,
        onPressed:
            () => ref.invalidate(
              gentleWaitProvider(ref.read(gentleWaitAccountProvider)),
            ),
      ),
    ],
  );

  Widget _body(
    BuildContext context,
    AppLocalizations loc,
    GentleWait data,
    bool online,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final endedAt = data.endedAt;
    final opensAt = data.opensAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online) ...[
          _OfflineBanner(text: loc.dating_offline),
          const SizedBox(height: Spacing.md),
        ],
        if (endedAt != null && opensAt != null) ...[
          Text(
            // W2 final review M-4: "If you both close it sooner" only when
            // closing it together still can end the wait.
            (data.canShorten
                ? loc.dating_gentleWaitBody
                : loc.dating_gentleWaitBodyNoShortcut)(
              MyDateFormat.toDate(endedAt.toLocal()),
              MyDateFormat.toDate(opensAt.toLocal()),
            ),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Text(
          loc.dating_gentleWaitNotJudgement,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: Spacing.lg),
        Semantics(
          header: true,
          child: Text(
            loc.dating_gentleWaitQuestionsTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          loc.dating_gentleWaitQuestionsHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (key, question) in [
          ('q1', loc.dating_gentleWaitQuestion1),
          ('q2', loc.dating_gentleWaitQuestion2),
          ('q3', loc.dating_gentleWaitQuestion3),
        ]) ...[
          const SizedBox(height: Spacing.md),
          _ReflectionField(
            key: ValueKey('gentle_wait_$key'),
            controller: _answers[key]!,
            label: question,
            countLabel: loc.dating_gentleWaitAnswerCount,
          ),
        ],
        const SizedBox(height: Spacing.md),
        ListenableBuilder(
          listenable: Listenable.merge(_answers.values.toList()),
          builder:
              (context, _) => FlowSecondaryButton(
                label:
                    _savedAny && !_anyAnswer(_answers.values.map((c) => c.text))
                        ? loc.dating_gentleWaitClear
                        : loc.dating_gentleWaitSave,
                busy: _saving,
                // W2 final review M-6: nothing typed and nothing saved is
                // nothing to save (it would say "saved" for nothing).
                onPressed:
                    online &&
                            (_savedAny ||
                                _anyAnswer(_answers.values.map((c) => c.text)))
                        ? _save
                        : null,
              ),
        ),
        if (!online) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            loc.dating_connectToSave,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_status == _Status.saved) ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              loc.dating_gentleWaitSaved,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
        if (_status == _Status.cleared) ...[
          const SizedBox(height: Spacing.sm),
          _CalmLine(text: loc.dating_gentleWaitCleared),
        ],
        if (_status == _Status.busy) ...[
          const SizedBox(height: Spacing.sm),
          _CalmLine(text: loc.dating_gentleWaitBusy),
        ],
        if (_status == _Status.clearBusy) ...[
          const SizedBox(height: Spacing.sm),
          _CalmLine(text: loc.dating_gentleWaitClearBusy),
        ],
        if (_status == _Status.failed) ...[
          const SizedBox(height: Spacing.sm),
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        ],
        const SizedBox(height: Spacing.lg),
        _HealingCard(
          text: loc.dating_gentleWaitHealing,
          onTap: () => context.push(RouteNames.healingJourney),
        ),
      ],
    );
  }
}

/// A calm line, read out when it appears: a confirmation, or a busy server
/// (never error wording, never the error colour).
class _CalmLine extends StatelessWidget {
  const _CalmLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Keeps an answer within [gentleWaitAnswerMax] code points (the server's
/// count), so a long paste is cut here rather than refused there.
class _CodePointLimit extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= gentleWaitAnswerMax) return newValue;
    final kept = String.fromCharCodes(
      newValue.text.runes.take(gentleWaitAnswerMax),
    );
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

/// One question: its text above a multi-line field, read as the field's
/// name (§3.15 D0: "three labelled fields"), with a character count.
class _ReflectionField extends StatelessWidget {
  const _ReflectionField({
    super.key,
    required this.controller,
    required this.label,
    required this.countLabel,
  });

  final TextEditingController controller;
  final String label;
  final String Function(int count, int max) countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [_CodePointLimit()],
            decoration: InputDecoration(
              border: const OutlineInputBorder(
                borderRadius: BorderRadiusTokens.mdAll,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadiusTokens.mdAll,
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder:
              (context, value, _) => Text(
                countLabel(value.text.runes.length, gentleWaitAnswerMax),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        ),
      ],
    );
  }
}

/// §3.0: "You're offline. Dating needs a connection." Read out when it
/// appears; never animated.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadiusTokens.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.smMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Healing is here if you want it…" → Healing (offered, never required).
class _HealingCard extends StatelessWidget {
  const _HealingCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusTokens.mdAll,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.self_improvement_outlined,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: Spacing.smMd),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
