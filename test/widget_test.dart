import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/home/home_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var pump = 0; pump < maxPumps; pump += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// A signed-out Supabase client.
///
/// ForumsSection.initState reads `supabaseClientProvider.auth.currentUser`
/// to pick its default tab, which asserts on the uninitialised singleton
/// in tests. Only `.auth.currentUser` is exercised; anything else throws
/// so an unnoticed new call site fails loudly rather than silently
/// returning null.
class _AnonymousAuth implements GoTrueClient {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no Supabase auth call should be issued');
}

class _AnonymousSupabase implements SupabaseClient {
  @override
  final GoTrueClient auth = _AnonymousAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no Supabase call should be issued');
}

void main() {
  testWidgets('renders the two-tab anonymous Attune home shell', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseClientProvider.overrideWithValue(_AnonymousSupabase()),
        ],
        child: ScreenUtilConfig.builder(
          builder:
              (_) => const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: HomeScreen(),
              ),
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('Chat'));

    expect(find.text('Opinions'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Hello!'), findsNothing);

    await tester.tap(find.text('Chat').last);
    await pumpUntilFound(tester, find.text('Hello!'));

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Continue with phone number'), findsOneWidget);
  });
}
