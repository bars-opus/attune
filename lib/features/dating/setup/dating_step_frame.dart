// Spec 2 W3b (§3.0): what every setup step shares. "Step {n} of 12" as text
// and dots (no motion); the offline banner, with the primary disabled and
// "Connect to save this answer."; Skip bottom-left where allowed; large
// text through FlowFrame's AllowLargeText. The mixin: one idempotency key
// per action (Fable H3c), settled once its answer is final; the person's
// saved answers seeded once per account, and nothing of one account shown
// to the next (D8). A failed read or write is generic copy, never the
// error's text (server text can echo what was typed).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingStepFrame extends ConsumerWidget {
  const DatingStepFrame({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.onBack,
    this.hint,
    this.primary,
    this.more = const [],
    this.onSkip,
  });

  final String step;
  final String title;
  final String? hint;
  final Widget body;
  final VoidCallback onBack;
  final Widget? primary;
  final List<Widget> more;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final n = datingStepNumber(step);
    return FlowFrame(
      title: title,
      hint: hint,
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n != null) ...[
            DatingStepProgress(n: n),
            const SizedBox(height: Spacing.md),
          ],
          if (!online) ...[
            DatingOfflineBanner(text: loc.dating_offline),
            const SizedBox(height: Spacing.md),
          ],
          body,
        ],
      ),
      actions: [
        if (primary != null) primary!,
        if (primary != null && !online)
          Text(
            loc.dating_connectToSave,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ...more,
        if (onSkip != null)
          FlowTextLink(
            label: loc.dating_skip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: onSkip!,
          ),
      ],
    );
  }
}

class DatingStepProgress extends StatelessWidget {
  const DatingStepProgress({super.key, required this.n, this.total = 12});

  final int n;
  final int total;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.dating_stepOf(n, total),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Spacing.xs),
        ExcludeSemantics(
          child: Wrap(
            spacing: 4,
            children: [
              for (var i = 1; i <= total; i++)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= n ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class DatingOfflineBanner extends StatelessWidget {
  const DatingOfflineBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.onSurface),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio group read as one labelled group; a choice clicks (§3.0).
///
/// T6 fix 1: the label is read once (I-2: the container carries it, the
/// visible text is excluded); [showLabel] false hides it where the screen
/// title already asks the question (it is still the group's name). With
/// [onCleared], tapping the chosen option again clears it (M-4: an optional
/// answer can be taken back). Each option sends its own value, so a null
/// option ("Either side") can be chosen too.
class DatingChoiceGroup<T> extends StatelessWidget {
  const DatingChoiceGroup({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.showLabel = true,
    this.onCleared,
  });

  final String label;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final bool showLabel;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel)
          ExcludeSemantics(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
        for (final (option, text) in options)
          RadioListTile<T>(
            value: option,
            groupValue: value,
            toggleable: onCleared != null,
            contentPadding: EdgeInsets.zero,
            title: Text(text),
            onChanged:
                onChanged == null
                    ? null
                    : (_) {
                      HapticFeedback.selectionClick();
                      if (onCleared != null && option == value) {
                        onCleared!();
                      } else {
                        onChanged!(option);
                      }
                    },
          ),
      ],
    ),
  );
}

/// A writer's refusal in words (never another person's state).
String datingWriteError(AppLocalizations loc, DatingWrite w) => switch (w
    .reason) {
  'busy' => loc.dating_busy,
  'not_eligible' => loc.dating_sectionUnavailable,
  'reverify_device' => loc.dating_sectionReverify,
  'rate_limited' => loc.dating_errorRateLimited,
  'not_available' => loc.dating_notAvailableHere,
  'contact_details' => loc.dating_contactFilter,
  'unkind' => loc.dating_kindnessFilter,
  'consent_required' => loc.dating_errorConsent,
  'country_change_limited' => loc.dating_countryChangeLimited,
  // Final fix (M-7): the raised reasons a setup screen names (the
  // repository's allowlist), each in words.
  'terms_consent_required' ||
  'dating_opt_in_required' => loc.dating_errorConsent,
  'path_not_dating' => loc.dating_errorPathNotDating,
  _ => loc.dating_errorGeneric,
};

/// The refusal line: calm for busy, error-red with an icon otherwise.
/// Final fix (M-7): a raised consent or path refusal also offers the way
/// on (D4's terms, How you use Attune).
Widget datingRefusalLine(AppLocalizations loc, DatingWrite w) {
  if (w.reason == 'busy') {
    return Semantics(liveRegion: true, child: Text(loc.dating_busy));
  }
  final line = FlowErrorLine(text: datingWriteError(loc, w), liveRegion: true);
  final (label, place) = switch (w.reason) {
    'terms_consent_required' || 'dating_opt_in_required' => (
      loc.dating_sectionFinish,
      DatingPaths.step('privacy'),
    ),
    'path_not_dating' => (loc.dating_openHowYouUse, RouteNames.howYouUseAttune),
    _ => (null, null),
  };
  if (label == null || place == null) return line;
  return Builder(
    builder:
        (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line,
            FlowTextLink(
              label: label,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(place),
            ),
          ],
        ),
  );
}

/// A read that failed: generic copy and Retry (T6 carry B). Never the
/// error itself.
class DatingLoadError extends StatelessWidget {
  const DatingLoadError({super.key, required this.busy, required this.onRetry});

  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.dating_retry,
            busy: busy,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

mixin DatingStepState<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  DatingActionKeys keys = DatingActionKeys();
  bool saving = false;
  DatingWrite? refusal;
  String? _seededFor;
  AsyncValue<DatingMyProfile>? _read;

  /// The answers the person changed on this screen (T6 fix 1 M-3, fix 2
  /// N-1): a saved answer that arrives later fills every other field and
  /// never overwrites one of these.
  final _touched = <String>{};

  /// Empties every answer typed on this screen.
  void resetAnswers();

  /// Fills the answers from the person's saved ones, each field only when
  /// the person hasn't changed it ([isTouched]).
  void seedAnswers(DatingMyProfile profile);

  bool isTouched(String field) => _touched.contains(field);

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        resetAnswers();
        _seededFor = null;
        _touched.clear();
        saving = false;
        refusal = null;
        keys = DatingActionKeys();
      });
    });
  }

  /// The saved answers; seeds the screen once per account, from a finished
  /// read only (a loading or failed frame never shows anything old). Called
  /// first in build, so the frame the read lands in already shows them.
  DatingMyProfile? watchProfile() {
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingMyProfileProvider(account));
    _read = read;
    final profile = read.hasError ? null : read.valueOrNull;
    if (profile != null && _seededFor != account) {
      _seededFor = account;
      seedAnswers(profile);
    }
    return profile;
  }

  /// The saved answers are on screen (fix 2, N-1): until then a save could
  /// send an empty field over a saved answer, so Continue waits for it.
  bool get profileReady => _seededFor != null && !profileFailed;

  /// The last [watchProfile] read failed (shown as [DatingLoadError]).
  bool get profileFailed => _read?.hasError ?? false;

  /// The profile read is running again after a failure.
  bool get profileRetrying => _read?.isLoading ?? false;

  void retryProfile() =>
      ref.invalidate(datingMyProfileProvider(ref.read(datingAccountProvider)));

  /// Final fix (I-3): R-40's return, unless the save cleared an answer
  /// the server needs again (a new Dating country clears gender and
  /// who-to-meet; an identity change where same-gender is off clears
  /// who-to-meet). Read from the profile as saved; when that read fails,
  /// [predicted] (the server's rule) decides. Without `from`: [onward].
  Future<void> moveOnFrom(
    DatingStepNav nav,
    String onward, {
    String? predicted,
  }) async {
    final askAgain = nav.askAgain;
    if (askAgain == null) return nav.next(onward);
    final account = ref.read(datingAccountProvider);
    setState(() => saving = true);
    String? again;
    try {
      final p = await ref.read(datingMyProfileProvider(account).future);
      again =
          p.identity == null
              ? 'you'
              : p.seeking.isEmpty
              ? 'meet'
              : null;
    } catch (_) {
      again = predicted;
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() => saving = false);
    if (again != null) return askAgain(again);
    nav.next(onward);
  }

  /// Applies an answer the person gave to [fields] (M-3, N-1).
  void answer(List<String> fields, VoidCallback change) => setState(() {
    _touched.addAll(fields);
    change();
  });

  Future<void> write(
    String action,
    Object payload,
    Future<DatingWrite> Function(String key) call,
    void Function(DatingWrite w) onSaved,
  ) async {
    if (saving) return;
    final account = ref.read(datingAccountProvider);
    final keys = this.keys;
    setState(() {
      saving = true;
      refusal = null;
    });
    DatingWrite w;
    try {
      w = await call(keys.keyFor(action, '$account|$payload'));
    } catch (_) {
      // The repository answers rather than throws; if anything does, it
      // is failed (the key kept), never the error's text.
      w = DatingWrite.failed;
    }
    // A final answer drops the key, so the next save is a new request; a
    // busy or failed one keeps it, so the retry is the same (carry A).
    keys.settle(action, reason: w.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      saving = false;
      refusal = w.ok ? null : w;
    });
    if (w.ok) {
      ref.invalidate(datingMyProfileProvider(account));
      onSaved(w);
    }
  }
}
