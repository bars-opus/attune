import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/providers/locale_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/theme_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) {
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
