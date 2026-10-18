import 'package:attune/app/feature_flag_refresher.dart';
import 'dart:async';

import 'package:attune/app/app_shell.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/locale_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/theme_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's translations, plus the rich-text editor's (Planning). Quill's
/// own dialogs and menus (link, copy/paste) open in overlays outside any
/// local wrapper, so its translations must be registered app-wide.
const appLocalizationsDelegates = [
  ...AppLocalizations.localizationsDelegates,
  FlutterQuillLocalizations.delegate,
];

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(localeNotifierProvider.notifier).initialize();
    });
    Future.microtask(() {
      if (!mounted) return;
      ref.read(oneSignalServiceProvider).initialize();
    });
    // The home-screen distance widget: costs nothing unless opted in.
    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(coupleWidgetPublisherProvider).startIfEnabled());
    });
    // Fire-and-forget preload so first send/receive has no cold-start latency.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(soundServiceProvider).preload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(currentLocaleProvider);

    return ScreenUtilConfig.builder(
      builder: (context) {
        return MaterialApp.router(
          title: 'Attune',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          // The root shell (Spec 2): lock gate, privacy cover, quick exit.
          // Flags re-read on resume and sign-in (sync audit 2026-10-18).
          builder:
              (context, child) => FeatureFlagRefresher(
                child: appShell(
                  router: router,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
        );
      },
    );
  }
}
