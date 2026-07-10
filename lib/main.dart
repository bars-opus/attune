import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:attune/app/app.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeSupabase();
  _initializeDeepLinks();
  final chatCache = ChatCacheService();
  await chatCache.init();

  final prefs = await SharedPreferences.getInstance();
  final routingNotifier = RoutingNotifier(
    prefs: prefs,
    isFirstLaunch: PreferencesService(prefs).isFirstLaunch,
  );
  final appRouter = createAppRouter(routingNotifier);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => routingNotifier),
        appRouterProvider.overrideWithValue(appRouter),
        chatCacheServiceProvider.overrideWithValue(chatCache),
        notificationConfigProvider.overrideWithValue(
          buildNanoEmbryoNotificationConfig(),
        ),
      ],
      child: const App(),
    ),
  );
}

Future<void> _initializeSupabase() async {
  final hasSupabaseConfig =
      Environment.supabaseUrl.isNotEmpty &&
      Environment.supabaseAnonKey.isNotEmpty;

  if (!hasSupabaseConfig) {
    debugPrint('[startup] Supabase config missing; auth/backend disabled.');
    return;
  }

  try {
    await Supabase.initialize(
      url: Environment.supabaseUrl,
      publishableKey: Environment.supabaseAnonKey,
      debug: Environment.isDebug,
    ).timeout(const Duration(seconds: 30));
    debugPrint('[startup] Supabase initialized.');
  } catch (error) {
    debugPrint(
      '[startup] Supabase initialization failed: ${error.runtimeType}',
    );
  }
}

void _initializeDeepLinks() {
  final appLinks = AppLinks();

  unawaited(
    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) _handleDeepLink(uri);
        })
        .catchError((error) {
          debugPrint('[deep-link] initial link failed: ${error.runtimeType}');
        }),
  );

  appLinks.uriLinkStream.listen(
    _handleDeepLink,
    onError: (Object error) {
      debugPrint('[deep-link] stream error: ${error.runtimeType}');
    },
  );
}

void _handleDeepLink(Uri uri) {
  debugPrint('[deep-link] received ${_redactUri(uri)}');

  if (_isAuthCallback(uri)) {
    debugPrint('[deep-link] auth callback detected.');
    unawaited(_handleAuthCallback(uri));
    return;
  }

  final inviteCode = _extractInviteCode(uri);
  if (inviteCode != null) {
    debugPrint('[deep-link] invite detected.');
    unawaited(_storePendingInviteCode(inviteCode));
  }
}

Future<void> _storePendingInviteCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await OnboardingStore(
    prefs,
    scope: OnboardingStore.anonymousScope,
  ).storePendingInviteCode(code);
}

Future<void> _handleAuthCallback(Uri uri) async {
  try {
    await Supabase.instance.client.auth
        .getSessionFromUrl(uri)
        .timeout(const Duration(seconds: 30));
    debugPrint('[deep-link] auth session established.');
  } catch (error) {
    debugPrint('[deep-link] auth callback failed: ${error.runtimeType}');
  }
}

bool _isAuthCallback(Uri uri) {
  return uri.scheme == 'attune' &&
      uri.host == 'auth' &&
      uri.path == '/callback';
}

String? _extractInviteCode(Uri uri) {
  final isInviteLink = uri.scheme == 'attune' && uri.host == 'invite';
  if (!isInviteLink) return null;

  final code = uri.queryParameters['code']?.trim();
  return code == null || code.isEmpty ? null : code;
}

String _redactUri(Uri uri) {
  final base = '${uri.scheme}://${uri.host}${uri.path}';
  return uri.hasQuery ? '$base?[redacted]' : base;
}
