import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/dismiss_keyboard_on_tap.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/safety_providers.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A narrower view of the screen, opened from another place: grief support
/// from Healing's "Someone I love died", help for young people from X1.
enum SupportFocus {
  grief(SupportCategory.grief),
  youth(SupportCategory.youth);

  const SupportFocus(this.category);

  final SupportCategory category;

  /// The route's `focus` query value; anything else is the whole screen.
  static SupportFocus? parse(String? value) {
    for (final f in values) {
      if (f.name == value) return f;
    }
    return null;
  }
}

/// Settings -> Support (Spec 1 §5.2, W7a): "Find support", signed in or
/// not, built by the Settings screen only while support_resources_v2 is on.
SettingsConfig supportResourcesSetting(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'support_resources',
    title: loc.support_settingsTitle,
    subtitle: loc.support_settingsSubtitle,
    icon: Icons.support_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.safetyResources,
    onTap: () => context.push(RouteNames.safetyResources),
    // Grey: the Support section's colour (W7 ruling PF-L1).
    iconColor: Colors.grey,
    order: 0,
  );
}

/// The order categories are shown in, after emergency (Spec 1 §8 W7a).
const supportCategoryOrder = [
  SupportCategory.dv,
  SupportCategory.crisis,
  SupportCategory.sexualAssault,
  SupportCategory.sextortion,
  SupportCategory.childSafety,
  SupportCategory.youth,
  SupportCategory.lgbtqLegal,
  SupportCategory.grief,
  SupportCategory.perinatal,
  SupportCategory.addiction,
  SupportCategory.financialControl,
];

String supportCategoryLabel(AppLocalizations loc, SupportCategory c) =>
    switch (c) {
      SupportCategory.emergency => loc.support_categoryEmergency,
      SupportCategory.dv => loc.support_categoryDv,
      SupportCategory.crisis => loc.support_categoryCrisis,
      SupportCategory.sexualAssault => loc.support_categorySexualAssault,
      SupportCategory.sextortion => loc.support_categorySextortion,
      SupportCategory.childSafety => loc.support_categoryChildSafety,
      SupportCategory.youth => loc.support_categoryYouth,
      SupportCategory.lgbtqLegal => loc.support_categoryLgbtqLegal,
      SupportCategory.grief => loc.support_categoryGrief,
      SupportCategory.perinatal => loc.support_categoryPerinatal,
      SupportCategory.addiction => loc.support_categoryAddiction,
      SupportCategory.financialControl => loc.support_categoryFinancialControl,
    };

/// Support resources v2 (Spec 1 §8 W7a), shown by [SafetyResourcesScreen]
/// under support_resources_v2 (same route, so every link keeps working).
/// The country line and picker; emergency numbers first; each number and
/// link opened only after a confirmation that says what it may leave on the
/// phone; categories, with "Not the police" on help that isn't; the fallback
/// for a country without a checked list; the bundled catalogue offline.
/// Never animated (§2.2); quick exit in the bar and the app shell's gesture.
class SupportResourcesV2Screen extends ConsumerWidget {
  const SupportResourcesV2Screen({super.key, this.focus});

  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final title = switch (focus) {
      SupportFocus.grief => loc.support_griefTitle,
      SupportFocus.youth => loc.support_youthTitle,
      null => loc.support_resourcesTitle,
    };
    final country = ref.watch(supportCountryProvider);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: loc.support_quickExit,
              onPressed: () => ref.read(quickExitProvider).call(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              if (focus == null) ...[
                const SafetyPinPromptCard(),
                const SafetySelfCheckRow(),
                const ReportChildConcernLink(),
                Text(
                  loc.support_resourcesIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  loc.support_resourcesNoEmergencyService,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.md),
              ],
              switch (country) {
                AsyncData(:final value) => _Directory(
                  country: value,
                  focus: focus,
                ),
                AsyncError() => _Directory(country: null, focus: focus),
                _ => const _Waiting(),
              },
              if (focus == null) ...[
                const SizedBox(height: Spacing.xl),
                const _QuickExitCard(),
              ],
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  // onSurface, not the theme's green: 4.5:1 (§2.3).
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  // Reached by go() too (a notification, Healing): nothing
                  // to pop there, so home (sign-in's redirect takes a
                  // signed-out person to Welcome).
                  onPressed:
                      () =>
                          context.canPop()
                              ? context.pop()
                              : context.go(RouteNames.home),
                  // A focused view (grief, youth) says Back: never "not
                  // relevant" to someone who just lost a person (M-7).
                  child: Text(
                    focus == null ? loc.support_notNow : loc.support_back,
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

String _countryName(AppLocalizations loc, String iso) => countryNameFor(
  iso,
  special: {'GB': loc.flow_countryUk, 'US': loc.flow_countryUs},
);

class _Directory extends ConsumerWidget {
  const _Directory({required this.country, required this.focus});

  final String? country;
  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = ref.watch(supportResourcesProvider(country));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountryLine(country: country),
        const SizedBox(height: Spacing.md),
        switch (answer) {
          AsyncData(:final value) => _Listing(answer: value, focus: focus),
          // A load that failed is not "no checked list": no sentence, only
          // the directory and the emergency line.
          AsyncError() => const _Unsupported(
            country: null,
            directoryUrl: supportDirectoryUrl,
          ),
          _ => const _Waiting(),
        },
      ],
    );
  }
}

class _CountryLine extends ConsumerWidget {
  const _CountryLine({required this.country});

  final String? country;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final current = country;
    final selected =
        current == null
            ? PhoneCountries.defaultCountry
            : PhoneCountries.all.firstWhere(
              (c) => c.isoCode == current,
              orElse: () => PhoneCountries.defaultCountry,
            );
    // Never animated (§2.2): showModalBottomSheet directly, not the shared
    // BottomSheetUtils (left as it is). The SizedBox bounds the picker's
    // Expanded list; the width rule is the shared helper's.
    final size = MediaQuery.sizeOf(context);
    final height = size.height * 0.9;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      constraints: BoxConstraints(
        maxHeight: height,
        maxWidth:
            size.shortestSide > Breakpoints.mobile
                ? ContentWidth.sheet
                : double.infinity,
      ),
      // The shell clamps every route, this sheet's too, to 1.0 (I-1).
      builder:
          (_) => AllowLargeText(
            child: DismissKeyboardOnTap(
              child: SizedBox(
                height: height,
                child: PhoneCountryPickerSheet(
                  selectedCountry: selected,
                  onCountrySelected:
                      (picked) =>
                          ref
                              .read(supportCountryOverrideProvider.notifier)
                              .state = picked.isoCode,
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final iso = country;
    // At 2.0 "Choose a country" is wider than the line's half: the button
    // wraps within half the width instead of overflowing (I-1). Its natural
    // width is used whenever it fits, so nothing moves at 1.0.
    return LayoutBuilder(
      builder:
          (context, constraints) => Row(
            children: [
              Expanded(
                child: Text(
                  iso == null
                      ? loc.support_chooseCountry
                      : loc.support_helpFor(_countryName(loc, iso)),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  onPressed: () => _choose(context, ref),
                  child: Text(
                    iso == null
                        ? loc.support_chooseCountryButton
                        : loc.support_changeCountry,
                    textAlign: TextAlign.center,
                    semanticsLabel:
                        iso == null
                            ? loc.support_chooseCountryButton
                            : loc.support_changeCountryLabel(
                              _countryName(loc, iso),
                            ),
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _Listing extends ConsumerWidget {
  const _Listing({required this.answer, required this.focus});

  final SupportResources answer;
  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final signedIn = ref.watch(homeAuthProvider).currentUser != null;
    final focused = focus;
    final children = <Widget>[];

    void section(String heading, List<SupportResource> rows) {
      if (rows.isEmpty) return;
      children
        ..add(_Heading(heading))
        ..addAll([for (final r in rows) _ResourceCard(resource: r)]);
    }

    section(loc.support_emergencyHeading, answer.emergency);
    // A checked list without an emergency number still says what to do in
    // an emergency (the unsupported card says it for the rest).
    if (answer.emergency.isEmpty && answer.countrySupported) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            loc.support_localEmergency,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }
    if (!answer.countrySupported) {
      children.add(
        _Unsupported(
          country: answer.country,
          directoryUrl: answer.directoryUrl,
        ),
      );
    } else if (focused != null) {
      final rows = answer.inCategory(focused.category);
      if (rows.isEmpty) {
        children.add(
          _Unsupported(
            country: answer.country,
            directoryUrl: answer.directoryUrl,
            line: loc.support_noFocusList(
              _countryName(loc, answer.country ?? ''),
            ),
          ),
        );
      } else {
        section(supportCategoryLabel(loc, focused.category), rows);
      }
    } else {
      for (final c in supportCategoryOrder) {
        section(supportCategoryLabel(loc, c), answer.inCategory(c));
      }
      section(loc.support_anywhereHeading, answer.anywhere);
    }
    if (focused == SupportFocus.grief && signedIn) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: Spacing.lg),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => context.push(RouteNames.reflectionJournal),
            child: Text(loc.support_writeInJournal),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Asks before anything leaves the app, and says what it may leave behind.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final loc = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    // The shell clamps every route, dialogs too, to 1.0: this one carries
    // the privacy warning, so it takes the phone's large text (I-1).
    builder:
        (dialogContext) => AllowLargeText(
          child: AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              // 4.5:1 (§2.3): onSurface and the tonal pair, not the theme's
              // green.
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor:
                      Theme.of(dialogContext).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(loc.support_cancel),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ),
  );
  return ok ?? false;
}

Future<void> _openLink(
  BuildContext context,
  WidgetRef ref,
  String url, {
  String? site,
  String? body,
}) async {
  final loc = AppLocalizations.of(context)!;
  final name = site ?? Uri.tryParse(url)?.host ?? url;
  if (await _confirm(
        context,
        title: loc.support_linkConfirmTitle(name),
        body: body ?? loc.support_linkConfirmBody,
        action: loc.support_open,
      ) &&
      context.mounted) {
    await ref.read(supportLauncherProvider)(context, url);
  }
}

class _ResourceCard extends ConsumerWidget {
  const _ResourceCard({required this.resource});

  final SupportResource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = resource;
    final emergency = r.category == SupportCategory.emergency;
    final tag =
        r.isPolice
            ? loc.support_police
            : emergency
            ? null
            : loc.support_notPolice;

    Future<void> call(String number) async {
      if (await _confirm(
            context,
            title: loc.support_callConfirmTitle(number),
            body: loc.support_callConfirmBody,
            action: loc.support_callConfirmCall,
          ) &&
          context.mounted) {
        await ref.read(supportLauncherProvider)(
          context,
          'tel:${supportDialString(number)}',
        );
      }
    }

    Future<void> text(String number) async {
      if (await _confirm(
            context,
            title: loc.support_textConfirmTitle(number),
            body: loc.support_textConfirmBody,
            action: loc.support_open,
          ) &&
          context.mounted) {
        await ref.read(supportLauncherProvider)(
          context,
          'sms:${supportDialString(number)}',
        );
      }
    }

    final actions = <Widget>[
      if (r.phone case final phone?)
        _Action(
          icon: Icons.call_outlined,
          label: loc.support_call(phone),
          onPressed: () => call(phone),
        ),
      if (r.sms case final sms?)
        _Action(
          icon: Icons.sms_outlined,
          label: loc.support_text(sms),
          onPressed: () => text(sms),
        ),
      if (r.whatsapp case final whatsapp?)
        _Action(
          icon: Icons.chat_outlined,
          label: loc.support_whatsapp,
          onPressed:
              () => _openLink(
                context,
                ref,
                'https://wa.me/${supportDialString(whatsapp).replaceAll('+', '')}',
                // A chat stays in WhatsApp, not in a browser's history.
                site: loc.support_whatsapp,
                body: loc.support_whatsappConfirmBody,
              ),
        ),
      if (r.url case final url?)
        _Action(
          icon: Icons.open_in_new,
          label: loc.support_website,
          onPressed: () => _openLink(context, ref, url),
        ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      // Emergency numbers stand out by a border, never by colour alone:
      // they also sit first, under their own heading.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
        side:
            emergency
                ? BorderSide(color: scheme.error, width: 2)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (tag != null) ...[const SizedBox(height: Spacing.xs), _Tag(tag)],
            if (r.description case final description?) ...[
              const SizedBox(height: Spacing.xs),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (r.hours case final hours?) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                hours,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: 2,
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _Unsupported extends ConsumerWidget {
  const _Unsupported({
    required this.country,
    required this.directoryUrl,
    this.line,
  });

  final String? country;
  final String directoryUrl;

  /// Replaces the "no checked list" sentence (a focused view).
  final String? line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final iso = country;
    final sentence =
        line ??
        (iso == null ? null : loc.support_unsupported(_countryName(loc, iso)));
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sentence != null) ...[
              Text(sentence, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Spacing.sm),
            ],
            // Tonal: white on the theme's green is 3.3:1 (§2.3).
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _openLink(context, ref, directoryUrl),
              child: Text(loc.support_findHelpline),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              loc.support_localEmergency,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing for the first 400 ms; then a bar with words (§2.2).
class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox(height: 48);
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: Spacing.sm),
        Text(loc.support_loading),
      ],
    );
  }
}

class _QuickExitCard extends ConsumerWidget {
  const _QuickExitCard();

  static const _exitRed = Color(0xFFB3261E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
        side: BorderSide(color: scheme.error, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          children: [
            Text(
              loc.support_quickExit,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              loc.support_quickExitBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                // A red danger button at 4.5:1 (§2.3) in both themes: the
                // app's error/onError pair is 3.7:1 in light (white on
                // #F44336), so this button alone uses M3's error red,
                // white on #B3261E at 6.5:1 (B2 fix round 2).
                backgroundColor: _exitRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => ref.read(quickExitProvider).call(context),
              child: Text(loc.support_exitNow),
            ),
          ],
        ),
      ),
    );
  }
}
