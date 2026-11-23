// Spec 2 W8b (§3.12 App icon, §6.7, §3.15 standard list; R-80): App icon:
// "Attune" or "Plain", for everyone. Settings opens it at
// /settings/app-icon (not behind any lock; nothing here names Dating);
// Dating settings and D13 open the same page inside Dating
// (DatingAppIconScreen gives it Dating's back). The choice is the phone's
// (no server, so it works offline) and stays through quick exit and
// sign-out. iOS asks the person to confirm with its own alert; Android may
// close Attune while the launcher changes; both are said before the
// choice. A phone that can't change the icon says so.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/device/app_icon.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings -> App settings -> "App icon" (R-80), under flow_paths_v2 like
/// Spec 1's other rows; its value is the icon on the home screen now.
SettingsConfig? appIconSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(flowPathsV2Provider)) return null;
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'app_icon',
    title: loc.appIcon_title,
    subtitle: switch (ref.watch(appIconProvider).valueOrNull) {
      AppIconChoice.plain => loc.appIcon_plain,
      AppIconChoice.attune => loc.appIcon_attune,
      null => '',
    },
    icon: Icons.apps_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.appIcon,
    iconColor: Colors.grey,
    order: 3,
  );
}

class AppIconScreen extends ConsumerStatefulWidget {
  const AppIconScreen({super.key, this.leading});

  /// The AppBar's leading (Dating's back when the page is alone there);
  /// null: the AppBar's own.
  final Widget? leading;

  @override
  ConsumerState<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends ConsumerState<AppIconScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _choose(AppIconChoice choice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    // Fix round 1 (M-4): the row under this page reads the icon again even
    // when the phone answers after the page closed (iOS's completion).
    final container = ProviderScope.containerOf(context, listen: false);
    final ok = await ref.read(appIconControlProvider).choose(choice);
    container.invalidate(appIconProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final read = ref.watch(appIconProvider);
    final current = read.valueOrNull;
    final known = read.hasValue && !read.hasError;
    Widget option(AppIconChoice choice, String label, Widget preview) =>
        RadioListTile<AppIconChoice>(
          key: ValueKey('app_icon_${choice.name}'),
          contentPadding: EdgeInsets.zero,
          value: choice,
          groupValue: current,
          onChanged:
              _busy || current == null ? null : (c) => _choose(c ?? choice),
          title: Text(label),
          secondary: ExcludeSemantics(child: preview),
        );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(leading: widget.leading, title: Text(loc.appIcon_title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(loc.appIcon_intro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Spacing.md),
                if (known && current == null)
                  // A calm line, read out when it appears (never error red).
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                      child: Text(
                        loc.appIcon_unsupported,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else ...[
                  Semantics(
                    container: true,
                    label: loc.appIcon_title,
                    child: Column(
                      children: [
                        option(
                          AppIconChoice.attune,
                          loc.appIcon_attune,
                          const _AttuneIconPreview(),
                        ),
                        option(
                          AppIconChoice.plain,
                          loc.appIcon_plain,
                          const _PlainIconPreview(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? loc.appIcon_ios
                        : loc.appIcon_android,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_failed)
                  FlowErrorLine(text: loc.appIcon_failed, liveRegion: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The launcher art the home screen shows for "Attune" (pubspec's
/// flutter_launcher_icons image_path; the designer's art swap replaces
/// both at once).
const kAttuneLauncherArt = 'assets/images/attune_launcher_icon.png';

/// Final client fix (M-6): the usual icon as the home screen shows it, the
/// real launcher art (decoded at the size shown), not a sign.
class _AttuneIconPreview extends StatelessWidget {
  const _AttuneIconPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        kAttuneLauncherArt,
        key: const ValueKey('app_icon_attune_preview'),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
        excludeFromSemantics: true,
        // The art missing from a build: the app's colour, never a gap
        // (round 2, N-1: an error widget isn't sized by the image's width
        // and height, so it is sized here, as the preview box).
        errorBuilder:
            (_, __, ___) => SizedBox.square(
              key: const ValueKey('app_icon_attune_fallback'),
              dimension: 44,
              child: ColoredBox(color: scheme.primary),
            ),
      ),
    );
  }
}

/// The plain icon as the home screen shows it: one light ring on slate.
class _PlainIconPreview extends StatelessWidget {
  const _PlainIconPreview();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF56616B),
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFECEFF1), width: 3),
      ),
    ),
  );
}
