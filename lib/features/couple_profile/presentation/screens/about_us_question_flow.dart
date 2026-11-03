import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_choice.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The six About us questions (Spec 1 §3.8 AU1-AU6), in the spec's order.
enum AboutUsQuestion { stage, together, married, living, children, anniversary }

/// The questions to ask: AU3 only when Married.
List<AboutUsQuestion> aboutUsSequence(CoupleStage? stage) => [
  AboutUsQuestion.stage,
  AboutUsQuestion.together,
  if (stage == CoupleStage.married) AboutUsQuestion.married,
  AboutUsQuestion.living,
  AboutUsQuestion.children,
  AboutUsQuestion.anniversary,
];

/// AU1-AU6, one question per screen (Spec 1 §3.8): every one skippable
/// ("Skip", bottom left), step dots ("2 of 5"), a "why" line and "More about
/// this" on each; each answer saved as it is given (offline: queued on this
/// phone, §3.14). With [only], just that question (an edit from the About
/// us screen, or Together's "Add your anniversary"), saved, then [onDone].
/// A read-only profile (paused, inside the ending window) is said, with
/// its end date, and asks nothing.
/// With About us off ([coupleProfileEnabledProvider]) it shows nothing,
/// fetches nothing and closes, wherever it was opened from.
class AboutUsQuestionFlow extends ConsumerStatefulWidget {
  const AboutUsQuestionFlow({
    super.key,
    required this.target,
    required this.onDone,
    this.only,
    this.partnerName,
    this.now,
  });

  final AboutUsTarget target;
  final VoidCallback onDone;
  final AboutUsQuestion? only;

  /// Today, for "no future dates" and the year lists (tests pin it).
  final DateTime Function()? now;

  /// The partner's first name, for the draft's "More about this".
  final String? partnerName;

  @override
  ConsumerState<AboutUsQuestionFlow> createState() =>
      _AboutUsQuestionFlowState();
}

class _AboutUsQuestionFlowState extends ConsumerState<AboutUsQuestionFlow> {
  int _index = 0;
  bool _forward = true;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;

  List<AboutUsQuestion> _sequence(CoupleProfile profile) =>
      widget.only != null ? [widget.only!] : aboutUsSequence(profile.stage);

  void _next(CoupleProfile profile) {
    final sequence = _sequence(profile);
    if (_index + 1 >= sequence.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _forward = true;
      _index++;
      _error = null;
    });
  }

  void _back() {
    if (_index == 0) {
      widget.onDone();
      return;
    }
    setState(() {
      _forward = false;
      _index--;
      _error = null;
    });
  }

  Future<void> _submit(AboutUsPatch? patch) async {
    if (_busy) return;
    if (patch == null) {
      final profile =
          ref.read(coupleProfileProvider(widget.target)).valueOrNull;
      if (profile != null) _next(profile);
      return;
    }
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await ref.read(coupleProfileProvider(widget.target).notifier).save(patch);
    } on AboutUsRefused catch (refused) {
      error = refusalText(loc, refused.reason);
    } catch (_) {
      error = loc.flow_saveFailed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _errorCount++;
    });
    if (error != null) {
      SemanticsService.announce(error, Directionality.of(context));
      return;
    }
    final profile = ref.read(coupleProfileProvider(widget.target)).valueOrNull;
    if (profile != null) _next(profile);
  }

  bool _closing = false;

  /// About us is off (couple_profile, effective under flow_couples_v2):
  /// whatever opened this (an entry point, a deep link) reaches no step and
  /// fetches nothing; it closes once, after this frame.
  Widget _off() {
    if (!_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone();
      });
    }
    return const Scaffold(body: SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(coupleProfileEnabledProvider)) return _off();
    final loc = AppLocalizations.of(context)!;
    final async = ref.watch(coupleProfileProvider(widget.target));
    final profile = async.valueOrNull;
    if (profile == null) {
      final failed = async.hasError && !async.isLoading;
      // A refusal at load (the space is gone, sealed, archived) can't be
      // retried; anything else is the connection.
      final refused = failed && async.error is AboutUsRefused;
      return FlowFrame(
        title: loc.aboutUs_title,
        onBack: widget.onDone,
        body:
            failed
                ? FlowErrorLine(
                  text:
                      refused
                          ? loc.aboutUs_errorReadOnly
                          : loc.aboutUs_loadFailed,
                  liveRegion: true,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                )
                : LinearProgressIndicator(semanticsLabel: loc.aboutUs_title),
        actions: [
          if (failed && !refused)
            FlowPrimaryButton(
              label: loc.flow_tryAgain,
              onPressed:
                  () => ref.invalidate(coupleProfileProvider(widget.target)),
            ),
          if (refused)
            FlowSecondaryButton(
              label: loc.flow_close,
              onPressed: widget.onDone,
            ),
        ],
      );
    }
    if (profile.readOnly) return _ReadOnlyFrame(profile, onDone: widget.onDone);
    final sequence = _sequence(profile);
    final index = _index.clamp(0, sequence.length - 1);
    final question = sequence[index];
    final step = _StepContext(
      profile: profile,
      stepText: widget.only != null ? null : (index + 1, sequence.length),
      isLast: index == sequence.length - 1,
      single: widget.only != null,
      busy: _busy,
      error: _error,
      errorCount: _errorCount,
      draftPartnerName:
          widget.target.isDraft ? (widget.partnerName ?? '') : null,
      coupleName:
          widget.target.relationshipId == null
              ? null
              : ref
                  .watch(coupleNameProvider(widget.target.relationshipId!))
                  .valueOrNull,
      suggestions:
          widget.target.relationshipId == null
              ? const []
              : ref.watch(
                aboutUsDateSuggestionsProvider(widget.target.relationshipId!),
              ),
      onSubmit: _submit,
      onSkip: () => _next(profile),
      onBack: _back,
      today: (widget.now ?? DateTime.now)(),
      // W5 final review M-2 (ruling): only for AU6, only while About us
      // keeps no reminder of its own.
      handMadeReminder:
          question == AboutUsQuestion.anniversary &&
          widget.target.relationshipId != null &&
          profile.anniversaryReminderId == null &&
          (ref
                  .watch(
                    aboutUsHandMadeAnniversaryProvider(
                      widget.target.relationshipId!,
                    ),
                  )
                  .valueOrNull ??
              false),
    );
    return SharedAxisStep(
      stepKey: question,
      forward: _forward,
      child: switch (question) {
        AboutUsQuestion.stage => _StageStep(step: step),
        AboutUsQuestion.together => _TogetherStep(step: step),
        AboutUsQuestion.married => _MarriedStep(step: step),
        AboutUsQuestion.living => _LivingStep(step: step),
        AboutUsQuestion.children => _ChildrenStep(step: step),
        AboutUsQuestion.anniversary => _AnniversaryStep(step: step),
      },
    );
  }
}

/// Paused or inside the ending window (Spec 1 §3.8): read, never written,
/// so no question is asked; said with the day it goes.
class _ReadOnlyFrame extends StatelessWidget {
  const _ReadOnlyFrame(this.profile, {required this.onDone});

  final CoupleProfile profile;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final until = profile.readUntil;
    return FlowFrame(
      title: loc.aboutUs_title,
      onBack: onDone,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    loc.aboutUs_errorReadOnly,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (until != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              loc.aboutUs_readOnlyUntil(MyDateFormat.toDate(until)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [FlowSecondaryButton(label: loc.flow_close, onPressed: onDone)],
    );
  }
}

/// What every step gets from the flow.
class _StepContext {
  const _StepContext({
    required this.profile,
    required this.stepText,
    required this.isLast,
    required this.single,
    required this.busy,
    required this.error,
    required this.errorCount,
    required this.draftPartnerName,
    required this.coupleName,
    required this.suggestions,
    required this.onSubmit,
    required this.onSkip,
    required this.onBack,
    required this.today,
    this.handMadeReminder = false,
  });

  final CoupleProfile profile;

  /// (step, total) for "2 of 5"; null for a single question.
  final (int, int)? stepText;
  final bool isLast;
  final bool single;
  final bool busy;
  final String? error;
  final int errorCount;

  /// Non-null for a draft: the partner's first name, '' when unknown.
  final String? draftPartnerName;

  /// The couple's chat name (coupleNameProvider), null until they choose
  /// one or for a draft (Batch 5 ruling: AU2's helper names the couple).
  final String? coupleName;
  final List<AboutUsDateSuggestion> suggestions;
  final Future<void> Function(AboutUsPatch? patch) onSubmit;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  /// Today (the flow's clock).
  final DateTime today;

  /// W5 final review M-2 (ruling "M-2 replaced"): the couple already has
  /// a yearly anniversary reminder made by hand, so About us adds none of
  /// its own (sync_anniversary_reminder) and AU6 says so.
  final bool handMadeReminder;
}

/// A rule a step checked itself, shown under its answers and read out.
void _announce(BuildContext context, String message) =>
    SemanticsService.announce(message, Directionality.of(context));

/// One question's screen: the question as the title, the step dots, the
/// answers, the "why" line, "More about this", the error; Continue (Done on
/// the last, Save for a single question), and Skip at the bottom left.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.step,
    required this.title,
    required this.children,
    required this.onContinue,
    this.hint,
    this.why,
    this.localError,
  });

  final _StepContext step;
  final String title;
  final String? hint;
  final String? why;
  final List<Widget> children;

  /// Null while nothing can be saved yet.
  final VoidCallback? onContinue;

  /// A rule this screen checked itself (a future date, a missing year).
  final String? localError;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final error = localError ?? step.error;
    final counter = step.stepText;
    return FlowFrame(
      title: title,
      hint: hint,
      onBack: step.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (counter != null) ...[
            Semantics(
              label: loc.aboutUs_stepSemantics(counter.$1, counter.$2),
              child: ExcludeSemantics(
                child: Text(
                  loc.aboutUs_step(counter.$1, counter.$2),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          // §3.14: an answer given offline is kept on this phone; say so
          // until it is shared.
          if (step.profile.pendingSync) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    loc.aboutUs_pendingSync,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
          ],
          ...children,
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              key: ValueKey('about-us-error-${step.errorCount}-$error'),
              text: error,
              liveRegion: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          if (why != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              why!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          FlowTextLink(
            label: loc.aboutUs_moreAbout,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _showMoreAbout(context, step.draftPartnerName),
          ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label:
              step.single
                  ? loc.aboutUs_save
                  : step.isLast
                  ? loc.aboutUs_done
                  : loc.flow_continue,
          busy: step.busy,
          onPressed: onContinue,
        ),
        if (!step.single)
          FlowTextLink(
            label: loc.aboutUs_skip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: step.busy ? () {} : step.onSkip,
          ),
      ],
    );
  }
}

Future<void> _showMoreAbout(BuildContext context, String? draftPartnerName) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      return AllowLargeText(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.aboutUs_moreAbout,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  loc.aboutUs_moreAboutBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (draftPartnerName != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    draftPartnerName.isEmpty
                        ? loc.aboutUs_moreAboutDraftUnnamed
                        : loc.aboutUs_moreAboutDraft(draftPartnerName),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
                FlowSecondaryButton(
                  label: loc.flow_close,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A labelled dropdown, full width, that grows with the text size.
class _PartDropdown<T> extends StatelessWidget {
  const _PartDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<(T?, String)> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final (item, text) in items)
            DropdownMenuItem<T>(value: item, child: Text(text)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

List<(int?, String)> _months({String? none}) => [
  if (none != null) (null, none),
  for (var m = 1; m <= 12; m++) (m, MyDateFormat.toMonth(DateTime(2000, m))),
];

List<(int?, String)> _days({String? none}) => [
  if (none != null) (null, none),
  for (var d = 1; d <= 31; d++) (d, '$d'),
];

/// Years from the latest the server takes down to 1900 (review M-1). The
/// server takes dates up to its UTC today + 1 (the earliest time zone's
/// today, P-3), so on 31 December a partner in UTC+14 can store next
/// year; [chosen] (the stored or picked year) is always listed, so a
/// dropdown never holds a value it doesn't list (an assert in debug, a
/// blank in release).
List<(int?, String)> _years(DateTime today, [int? chosen]) {
  var top = today.toUtc().add(const Duration(days: 1)).year;
  if (today.year > top) top = today.year;
  if (chosen != null && chosen > top) top = chosen;
  return [
    for (var y = top; y >= 1900; y--) (y, MyDateFormat.toYear(DateTime(y))),
  ];
}

/// The index of the ceremony the anniversary follows, or null.
int? _onCeremony(CoupleProfile profile) => switch (profile.anniversarySource) {
  AnniversarySource.ceremony1 when profile.ceremonies.isNotEmpty => 0,
  AnniversarySource.ceremony2 when profile.ceremonies.length > 1 => 1,
  _ => null,
};

/// The owner's ruling ("never a silent stop") and review I-1: an answer
/// that would stop the anniversary reminder (leaving Married, removing the
/// ceremony it is on, or that ceremony's day) asks first. The keys to add
/// to the answer's one write: "The day you got together" (with the full
/// date when AU2 hasn't one), "Turn it off"; null for Cancel (nothing is
/// sent).
Future<Map<String, Object?>?> _confirmReminderStop(
  BuildContext context,
  _StepContext step,
) => showModalBottomSheet<Map<String, Object?>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder:
      (_) => _ReminderStopSheet(
        since: step.profile.togetherSince,
        today: step.today,
      ),
);

class _ReminderStopSheet extends StatefulWidget {
  const _ReminderStopSheet({required this.since, required this.today});

  final TogetherSince? since;
  final DateTime today;

  @override
  State<_ReminderStopSheet> createState() => _ReminderStopSheetState();
}

class _ReminderStopSheetState extends State<_ReminderStopSheet> {
  /// True once "The day you got together" needs the date's missing parts.
  bool _asking = false;
  int? _year;
  int? _month;
  int? _day;
  String? _error;

  static const _together = {'anniversary_source': 'together_since'};

  void _chooseTogether() {
    final since = widget.since;
    if (since != null && since.hasDay) {
      Navigator.of(context).pop(_together);
      return;
    }
    setState(() {
      _asking = true;
      _year = since?.date.year;
      _month =
          since?.precision == DatePrecision.month ? since!.date.month : null;
    });
  }

  void _fail(String message) {
    setState(() => _error = message);
    _announce(context, message);
  }

  void _save() {
    final loc = AppLocalizations.of(context)!;
    final year = _year;
    if (year == null) {
      _fail(loc.aboutUs_errorNeedsYear);
      return;
    }
    final month = _month;
    final day = _day;
    final date =
        month == null || day == null ? null : civilDate(year, month, day);
    if (date == null) {
      _fail(loc.aboutUs_errorNoSuchDate);
      return;
    }
    if (isFutureCivilDate(date, widget.today)) {
      _fail(loc.aboutUs_errorFuture);
      return;
    }
    Navigator.of(context).pop({
      ...AboutUsPatch.togetherSince(
        TogetherSince(date, DatePrecision.day),
      ).values,
      ..._together,
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final since = widget.since;
    final askYear = since == null;
    final askMonth = since == null || since.precision == DatePrecision.year;
    return AllowLargeText(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.aboutUs_reminderStopTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                loc.aboutUs_reminderStopBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (!_asking) ...[
                FlowPrimaryButton(
                  label: loc.aboutUs_anniversaryTogether,
                  onPressed: _chooseTogether,
                ),
                const SizedBox(height: Spacing.sm),
                FlowSecondaryButton(
                  label: loc.aboutUs_reminderStopOff,
                  onPressed:
                      () => Navigator.of(
                        context,
                      ).pop({'anniversary_source': 'off'}),
                ),
              ] else ...[
                Semantics(
                  header: true,
                  child: Text(
                    loc.aboutUs_anniversaryWhatDay,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (askYear)
                  _PartDropdown<int>(
                    key: const ValueKey('about-us-stop-year'),
                    label: loc.aboutUs_yearLabel,
                    value: _year,
                    items: _years(widget.today, _year),
                    onChanged: (y) => setState(() => _year = y),
                  ),
                if (askMonth)
                  _PartDropdown<int>(
                    key: const ValueKey('about-us-stop-month'),
                    label: loc.aboutUs_monthLabel,
                    value: _month,
                    items: _months(),
                    onChanged: (m) => setState(() => _month = m),
                  ),
                _PartDropdown<int>(
                  key: const ValueKey('about-us-stop-day'),
                  label: loc.aboutUs_dayLabel,
                  value: _day,
                  items: _days(),
                  onChanged: (d) => setState(() => _day = d),
                ),
                if (_error != null) ...[
                  FlowErrorLine(
                    key: ValueKey('about-us-stop-error-$_error'),
                    text: _error!,
                    liveRegion: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                FlowPrimaryButton(label: loc.aboutUs_save, onPressed: _save),
              ],
              const SizedBox(height: Spacing.sm),
              FlowTextLink(
                label: loc.flow_cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- AU1

/// AU1's "In your own words", held to what the server keeps: at most
/// [stageWordsMax] code points as its `char_length` counts them (an emoji
/// family is five), not the characters the eye sees, which is what
/// LengthLimitingTextInputFormatter counts (batch-3 carry, M-5). Typing at
/// the limit does nothing; a paste is cut to what fits, whole characters
/// only, never half an emoji.
class _StageWordsFormatter extends TextInputFormatter {
  const _StageWordsFormatter();

  static String _fit(String start, Iterable<String> chars, String end) {
    var kept = '';
    for (final char in chars) {
      if (!stageWordsFit('$start$kept$char$end')) break;
      kept += char;
    }
    return kept;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Mid-composition (an IME) the text isn't final yet.
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    if (stageWordsFit(newValue.text)) return newValue;
    final old = oldValue.text;
    final at = oldValue.selection.isCollapsed ? oldValue.selection.end : -1;
    if (at >= 0 &&
        at <= old.length &&
        stageWordsFit(old) &&
        newValue.text.length > old.length &&
        newValue.text.startsWith(old.substring(0, at)) &&
        newValue.text.endsWith(old.substring(at))) {
      // An insertion at the cursor: keep what fits of what was inserted.
      final start = old.substring(0, at);
      final end = old.substring(at);
      final inserted = newValue.text.substring(
        at,
        newValue.text.length - end.length,
      );
      final kept = _fit(start, inserted.characters, end);
      return TextEditingValue(
        text: '$start$kept$end',
        selection: TextSelection.collapsed(offset: at + kept.length),
      );
    }
    final kept = _fit('', newValue.text.characters, '');
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

class _StageStep extends StatefulWidget {
  const _StageStep({required this.step});

  final _StepContext step;

  @override
  State<_StageStep> createState() => _StageStepState();
}

class _StageStepState extends State<_StageStep> {
  late CoupleStage? _stage = widget.step.profile.stage;
  late final _words = TextEditingController(
    text: widget.step.profile.stageWords ?? '',
  );
  String? _localError;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  AboutUsPatch? _patch() {
    final words =
        _stage == CoupleStage.other ? normalizeStageWords(_words.text) : null;
    final before = widget.step.profile;
    if (_stage == before.stage &&
        words == normalizeStageWords(before.stageWords)) {
      return null;
    }
    return AboutUsPatch.stage(_stage, words: words);
  }

  Future<void> _continue() async {
    final loc = AppLocalizations.of(context)!;
    // The server counts code points (char_length): never send what it
    // would refuse.
    if (_stage == CoupleStage.other && !stageWordsFit(_words.text)) {
      setState(() => _localError = loc.aboutUs_errorWordsTooLong);
      _announce(context, loc.aboutUs_errorWordsTooLong);
      return;
    }
    setState(() => _localError = null);
    final patch = _patch();
    final before = widget.step.profile;
    // Ruling "leaving Married": the ceremonies go with Married, and an
    // anniversary on one would stop with them. Never silently: ask first.
    if (patch != null &&
        before.stage == CoupleStage.married &&
        _stage != CoupleStage.married &&
        _onCeremony(before) != null) {
      final extra = await _confirmReminderStop(context, widget.step);
      if (extra == null || !mounted) return;
      widget.step.onSubmit(AboutUsPatch({...patch.values, ...extra}));
      return;
    }
    widget.step.onSubmit(patch);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_stageQuestion,
      why: loc.aboutUs_stageWhy,
      localError: _localError,
      onContinue: _stage == null ? null : _continue,
      children: [
        for (final (stage, helper) in [
          (CoupleStage.dating, null),
          (CoupleStage.engaged, loc.aboutUs_stageEngagedHelper),
          (CoupleStage.married, loc.aboutUs_stageMarriedHelper),
          (CoupleStage.other, null),
        ])
          AboutUsChoice(
            label: stageText(loc, stage),
            helper: helper,
            selected: _stage == stage,
            onTap:
                () => setState(() {
                  _stage = stage;
                  _localError = null;
                }),
          ),
        if (_stage == CoupleStage.other)
          FlowTextField(
            controller: _words,
            label: loc.aboutUs_stageWordsLabel,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [_StageWordsFormatter()],
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_localError != null) setState(() => _localError = null);
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU2

class _TogetherStep extends StatefulWidget {
  const _TogetherStep({required this.step});

  final _StepContext step;

  @override
  State<_TogetherStep> createState() => _TogetherStepState();
}

class _TogetherStepState extends State<_TogetherStep> {
  int? _year;
  int? _month;
  int? _day;
  bool _withDay = false;
  bool _yearOnly = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final since = widget.step.profile.togetherSince;
    if (since != null) _fill(since);
  }

  void _fill(TogetherSince since) {
    _year = since.date.year;
    _yearOnly = since.precision == DatePrecision.year;
    _month = _yearOnly ? null : since.date.month;
    _withDay = since.precision == DatePrecision.day;
    _day = _withDay ? since.date.day : null;
  }

  void _fail(String message) {
    setState(() => _localError = message);
    _announce(context, message);
  }

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final year = _year;
    if (year == null) {
      _fail(loc.aboutUs_errorNeedsYear);
      return;
    }
    final TogetherSince since;
    if (_yearOnly || _month == null) {
      since = TogetherSince(DateTime(year), DatePrecision.year);
    } else if (_withDay && _day != null) {
      // Batch-3 carry: a real day only (no 30 February rolling over).
      final date = civilDate(year, _month!, _day!);
      if (date == null) {
        _fail(loc.aboutUs_errorNoSuchDate);
        return;
      }
      since = TogetherSince(date, DatePrecision.day);
    } else {
      since = TogetherSince(DateTime(year, _month!), DatePrecision.month);
    }
    if (since == widget.step.profile.togetherSince) {
      setState(() => _localError = null);
      widget.step.onSubmit(null);
      return;
    }
    if (isFutureCivilDate(since.date, widget.step.today)) {
      _fail(loc.aboutUs_errorFuture);
      return;
    }
    // The anniversary follows this date and needs its day: the server
    // would refuse the write (anniversary_needs_day), so ask for it here.
    if (widget.step.profile.anniversarySource ==
            AnniversarySource.togetherSince &&
        !since.hasDay) {
      _fail(loc.aboutUs_errorAnniversaryNeedsDay);
      return;
    }
    setState(() => _localError = null);
    widget.step.onSubmit(AboutUsPatch.togetherSince(since));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final today = widget.step.today;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_sinceQuestion,
      // Batch-5 rulings: the couple's name when they have one, else no
      // couple noun at all (M-1); never "you both".
      hint:
          widget.step.coupleName == null
              ? loc.aboutUs_sinceHelperUnnamed
              : loc.aboutUs_sinceHelper(widget.step.coupleName!),
      why: loc.aboutUs_sinceWhy,
      localError: _localError,
      onContinue: _year == null ? null : _continue,
      children: [
        if (widget.step.suggestions.isNotEmpty) ...[
          Semantics(
            container: true,
            label: loc.aboutUs_sinceSuggestions,
            explicitChildNodes: true,
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final suggestion in widget.step.suggestions)
                  ActionChip(
                    label: Text(suggestion.label),
                    onPressed: () => setState(() => _fill(suggestion.since)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        if (!_yearOnly)
          _PartDropdown<int>(
            key: const ValueKey('about-us-since-month'),
            label: loc.aboutUs_monthLabel,
            value: _month,
            items: _months(),
            onChanged: (m) => setState(() => _month = m),
          ),
        _PartDropdown<int>(
          key: const ValueKey('about-us-since-year'),
          label: loc.aboutUs_yearLabel,
          value: _year,
          items: _years(today, _year),
          onChanged: (y) => setState(() => _year = y),
        ),
        if (!_yearOnly && _withDay)
          _PartDropdown<int>(
            key: const ValueKey('about-us-since-day'),
            label: loc.aboutUs_dayLabel,
            value: _day,
            items: _days(none: loc.aboutUs_notSure),
            onChanged: (d) => setState(() => _day = d),
          ),
        if (!_yearOnly && !_withDay)
          FlowTextLink(
            label: loc.aboutUs_sinceAddDay,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => setState(() => _withDay = true),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _yearOnly,
          title: Text(loc.aboutUs_sinceNoMonth),
          onChanged:
              (on) => setState(() {
                _yearOnly = on ?? false;
                if (_yearOnly) {
                  _month = null;
                  _day = null;
                  _withDay = false;
                }
              }),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU3

class _CeremonyDraft {
  _CeremonyDraft([Ceremony? from])
    : year = from?.year,
      month = from?.month,
      day = from?.day,
      label = from?.label;

  int? year;
  int? month;
  int? day;
  CeremonyLabel? label;
}

class _MarriedStep extends StatefulWidget {
  const _MarriedStep({required this.step});

  final _StepContext step;

  @override
  State<_MarriedStep> createState() => _MarriedStepState();
}

class _MarriedStepState extends State<_MarriedStep> {
  late final List<_CeremonyDraft> _drafts = [
    for (final c in widget.step.profile.ceremonies) _CeremonyDraft(c),
    if (widget.step.profile.ceremonies.isEmpty) _CeremonyDraft(),
  ];
  String? _localError;

  void _fail(String message) {
    setState(() => _localError = message);
    _announce(context, message);
  }

  Future<void> _continue() async {
    final loc = AppLocalizations.of(context)!;
    final today = widget.step.today;
    final ceremonies = <Ceremony>[];
    final dates = <DateTime>[];
    for (final d in _drafts) {
      if (d.year == null) {
        _fail(loc.aboutUs_errorNeedsYear);
        return;
      }
      final day = d.month == null ? null : d.day;
      // Batch-3 carry: a real day only (no 30 February rolling over).
      final date =
          d.month == null
              ? DateTime(d.year!)
              : day == null
              ? DateTime(d.year!, d.month!)
              : civilDate(d.year!, d.month!, day);
      if (date == null) {
        _fail(loc.aboutUs_errorNoSuchDate);
        return;
      }
      dates.add(date);
      ceremonies.add(
        Ceremony(year: d.year!, month: d.month, day: day, label: d.label),
      );
    }
    final before = widget.step.profile.ceremonies;
    final same =
        before.length == ceremonies.length &&
        [
          for (var i = 0; i < before.length; i++) before[i] == ceremonies[i],
        ].every((x) => x);
    if (same) {
      setState(() => _localError = null);
      widget.step.onSubmit(null);
      return;
    }
    if (dates.any((date) => isFutureCivilDate(date, today))) {
      _fail(loc.aboutUs_errorFuture);
      return;
    }
    setState(() => _localError = null);
    final patch = AboutUsPatch.ceremonies(ceremonies);
    // Review I-1 and batch-1 Minor 1: the anniversary is on a ceremony
    // that goes ("Remove this ceremony") or loses its full date. The
    // server would stop the reminder (or refuse the write): never
    // silently, ask first.
    final on = _onCeremony(widget.step.profile);
    if (on != null &&
        (on >= ceremonies.length || ceremonies[on].fullDate == null)) {
      final extra = await _confirmReminderStop(context, widget.step);
      if (extra == null || !mounted) return;
      widget.step.onSubmit(AboutUsPatch({...patch.values, ...extra}));
      return;
    }
    widget.step.onSubmit(patch);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final today = widget.step.today;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_marryQuestion,
      localError: _localError,
      onContinue: _drafts.every((d) => d.year != null) ? _continue : null,
      children: [
        for (var i = 0; i < _drafts.length; i++) ...[
          if (_drafts.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Semantics(
                header: true,
                child: Text(
                  loc.aboutUs_ceremonyN(i + 1),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          _PartDropdown<int>(
            key: ValueKey('about-us-ceremony-$i-year'),
            label: loc.aboutUs_yearLabel,
            value: _drafts[i].year,
            items: _years(today, _drafts[i].year),
            onChanged: (y) => setState(() => _drafts[i].year = y),
          ),
          _PartDropdown<int>(
            key: ValueKey('about-us-ceremony-$i-month'),
            label: loc.aboutUs_monthOptional,
            value: _drafts[i].month,
            items: _months(none: loc.aboutUs_notSure),
            onChanged:
                (m) => setState(() {
                  _drafts[i].month = m;
                  if (m == null) _drafts[i].day = null;
                }),
          ),
          if (_drafts[i].month != null)
            _PartDropdown<int>(
              key: ValueKey('about-us-ceremony-$i-day'),
              label: loc.aboutUs_dayOptional,
              value: _drafts[i].day,
              items: _days(none: loc.aboutUs_notSure),
              onChanged: (d) => setState(() => _drafts[i].day = d),
            ),
          Semantics(
            container: true,
            label: loc.aboutUs_ceremonyLabelGroup,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    loc.aboutUs_ceremonyLabelGroup,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final label in CeremonyLabel.values)
                      ChoiceChip(
                        label: Text(ceremonyLabelText(loc, label)),
                        selected: _drafts[i].label == label,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected:
                            (on) => setState(
                              () => _drafts[i].label = on ? label : null,
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (i == 1)
            FlowTextLink(
              label: loc.aboutUs_removeCeremony,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => setState(() => _drafts.removeAt(1)),
            ),
          const SizedBox(height: Spacing.md),
        ],
        if (_drafts.length < 2)
          FlowTextLink(
            label: loc.aboutUs_addCeremony,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => setState(() => _drafts.add(_CeremonyDraft())),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU4

class _LivingStep extends StatefulWidget {
  const _LivingStep({required this.step});

  final _StepContext step;

  @override
  State<_LivingStep> createState() => _LivingStepState();
}

class _LivingStepState extends State<_LivingStep> {
  late Living? _living = widget.step.profile.living;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_livingQuestion,
      why: loc.aboutUs_livingWhy,
      onContinue:
          _living == null
              ? null
              : () => widget.step.onSubmit(
                _living == widget.step.profile.living
                    ? null
                    : AboutUsPatch.living(_living),
              ),
      children: [
        for (final living in Living.values)
          AboutUsChoice(
            label: livingText(loc, living),
            selected: _living == living,
            onTap: () => setState(() => _living = living),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU5

class _ChildrenStep extends StatefulWidget {
  const _ChildrenStep({required this.step});

  final _StepContext step;

  @override
  State<_ChildrenStep> createState() => _ChildrenStepState();
}

class _ChildrenStepState extends State<_ChildrenStep> {
  late Children? _children = widget.step.profile.children;
  late final Set<ChildAgeBand> _bands = {...widget.step.profile.childAgeBands};

  AboutUsPatch? _patch() {
    final bands = [
      for (final band in ChildAgeBand.values)
        if (_children == Children.yes && _bands.contains(band)) band,
    ];
    final before = widget.step.profile;
    if (_children == before.children &&
        listEquals(bands, before.childAgeBands)) {
      return null;
    }
    return AboutUsPatch.children(_children, bands: bands);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_childrenQuestion,
      why: loc.aboutUs_childrenWhy,
      onContinue:
          _children == null ? null : () => widget.step.onSubmit(_patch()),
      children: [
        for (final children in Children.values)
          AboutUsChoice(
            label: childrenChoiceText(loc, children),
            selected: _children == children,
            onTap: () => setState(() => _children = children),
          ),
        if (_children == Children.yes)
          Semantics(
            container: true,
            label: loc.aboutUs_childrenAges,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.xs),
                ExcludeSemantics(
                  child: Text(
                    loc.aboutUs_childrenAges,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final band in ChildAgeBand.values)
                      FilterChip(
                        label: Text(bandText(loc, band)),
                        selected: _bands.contains(band),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected:
                            (on) => setState(
                              () => on ? _bands.add(band) : _bands.remove(band),
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU6

class _AnniversaryStep extends StatefulWidget {
  const _AnniversaryStep({required this.step});

  final _StepContext step;

  @override
  State<_AnniversaryStep> createState() => _AnniversaryStepState();
}

class _AnniversaryStepState extends State<_AnniversaryStep> {
  late AnniversarySource? _source =
      widget.step.profile.anniversarySource == AnniversarySource.off &&
              widget.step.profile.changes[AboutUsField.anniversary] == null
          ? null
          : widget.step.profile.anniversarySource;
  int? _year;
  int? _month;
  int? _day;
  String? _localError;

  CoupleProfile get _profile => widget.step.profile;

  @override
  void initState() {
    super.initState();
    final missing = _missing;
    _year = missing?.year;
    _month = missing?.month;
  }

  /// What the chosen source's date still lacks for a reminder (AU6 "What
  /// day was it?"): the year and month it already has, null for a part to
  /// ask; null when nothing is needed. Preflight F-3: "The day you got
  /// together" with AU2 unanswered asks the whole date, so Together's "Add
  /// your anniversary" never dead-ends on an empty About us.
  ({int? year, int? month})? get _missing {
    switch (_source) {
      case AnniversarySource.togetherSince:
        final since = _profile.togetherSince;
        if (since == null) return (year: null, month: null);
        if (since.hasDay) return null;
        return (
          year: since.date.year,
          month:
              since.precision == DatePrecision.month ? since.date.month : null,
        );
      case AnniversarySource.ceremony1 || AnniversarySource.ceremony2:
        final i = _source == AnniversarySource.ceremony1 ? 0 : 1;
        if (_profile.ceremonies.length <= i) return null;
        final c = _profile.ceremonies[i];
        if (c.fullDate != null) return null;
        return (year: c.year, month: c.month);
      default:
        return null;
    }
  }

  void _select(AnniversarySource source) => setState(() {
    _source = source;
    _localError = null;
    final missing = _missing;
    _year = missing?.year;
    _month = missing?.month;
    _day = null;
  });

  void _fail(String message) {
    setState(() => _localError = message);
    _announce(context, message);
  }

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final source = _source;
    if (source == null) return;
    final missing = _missing;
    if (missing == null) {
      widget.step.onSubmit(
        source == _profile.anniversarySource &&
                _profile.changes[AboutUsField.anniversary] != null
            ? null
            : AboutUsPatch.anniversary(source),
      );
      return;
    }
    final year = _year;
    if (year == null) {
      _fail(loc.aboutUs_errorNeedsYear);
      return;
    }
    final month = _month;
    final day = _day;
    // Batch-3 carry: a real day only (no 30 February rolling over).
    final date =
        month == null || day == null ? null : civilDate(year, month, day);
    if (date == null) {
      _fail(loc.aboutUs_errorNoSuchDate);
      return;
    }
    if (isFutureCivilDate(date, widget.step.today)) {
      _fail(loc.aboutUs_errorFuture);
      return;
    }
    setState(() => _localError = null);
    if (source == AnniversarySource.togetherSince) {
      widget.step.onSubmit(
        AboutUsPatch.anniversary(
          source,
          completedSince: TogetherSince(date, DatePrecision.day),
        ),
      );
      return;
    }
    final i = source == AnniversarySource.ceremony1 ? 0 : 1;
    final ceremonies = [..._profile.ceremonies];
    final c = ceremonies[i];
    ceremonies[i] = Ceremony(
      year: c.year,
      month: date.month,
      day: date.day,
      label: c.label,
    );
    widget.step.onSubmit(
      AboutUsPatch.anniversary(source, completedCeremonies: ceremonies),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final missing = _missing;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_anniversaryQuestion,
      hint:
          widget.step.handMadeReminder
              ? loc.aboutUs_anniversaryHandMade
              : null,
      localError: _localError,
      onContinue: _source == null ? null : _continue,
      children: [
        AboutUsChoice(
          label: loc.aboutUs_anniversaryNo,
          selected: _source == AnniversarySource.off,
          onTap: () => _select(AnniversarySource.off),
        ),
        // Preflight F-3: always offered (with AU2 unanswered it asks the
        // whole date below).
        AboutUsChoice(
          label: loc.aboutUs_anniversaryTogether,
          selected: _source == AnniversarySource.togetherSince,
          onTap: () => _select(AnniversarySource.togetherSince),
        ),
        for (var i = 0; i < _profile.ceremonies.length && i < 2; i++)
          AboutUsChoice(
            label: ceremonyAnniversaryText(loc, _profile.ceremonies[i]),
            selected:
                _source ==
                (i == 0
                    ? AnniversarySource.ceremony1
                    : AnniversarySource.ceremony2),
            onTap:
                () => _select(
                  i == 0
                      ? AnniversarySource.ceremony1
                      : AnniversarySource.ceremony2,
                ),
          ),
        if (missing != null) ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            header: true,
            child: Text(
              loc.aboutUs_anniversaryWhatDay,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          if (missing.year == null)
            _PartDropdown<int>(
              key: const ValueKey('about-us-anniversary-year'),
              label: loc.aboutUs_yearLabel,
              value: _year,
              items: _years(widget.step.today, _year),
              onChanged: (y) => setState(() => _year = y),
            ),
          // P-19: the month only when it isn't known.
          if (missing.month == null)
            _PartDropdown<int>(
              key: const ValueKey('about-us-anniversary-month'),
              label: loc.aboutUs_monthLabel,
              value: _month,
              items: _months(),
              onChanged: (m) => setState(() => _month = m),
            ),
          _PartDropdown<int>(
            key: const ValueKey('about-us-anniversary-day'),
            label: loc.aboutUs_dayLabel,
            value: _day,
            items: _days(),
            onChanged: (d) => setState(() => _day = d),
          ),
        ],
      ],
    );
  }
}
