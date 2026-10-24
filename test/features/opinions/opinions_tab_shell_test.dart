// Spec 3 (forum removal) §7.2, risks R2-R4: with the Forums tab gone the
// Opinions tab is one section. Following/Discover sit directly under the app
// bar, a guest lands on Discover, a sign-in mid-session jumps to Following,
// switching sub-tabs brings a hidden nav back, and the header lays out at
// default and largest text.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/core/widgets/create_content_fab.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyFollowing extends FollowingFeedNotifier {
  @override
  Future<List<OpinionModel>> build() async => const [];
}

class _EmptyDiscover extends DiscoverFeedNotifier {
  @override
  Future<List<OpinionModel>> build() async => const [];
}

/// The signed-in user id the test flips; null is a guest.
final _uid = StateProvider<String?>((ref) => null);

Future<ProviderContainer> _pumpTab(
  WidgetTester tester, {
  String? userId,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWith((ref) => ref.watch(_uid)),
      userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
      myAuthorHandleProvider.overrideWith((ref) async => 'quiet-otter'),
      followingFeedProvider.overrideWith(_EmptyFollowing.new),
      discoverFeedProvider.overrideWith(_EmptyDiscover.new),
      allTagsProvider.overrideWith((ref) async => const <String>[]),
    ],
  );
  addTearDown(container.dispose);
  container.read(_uid.notifier).state = userId;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
              home: const OpinionsTab(),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The Following (0) / Discover (1) page currently selected.
int _feedIndex(WidgetTester tester) =>
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index;

void main() {
  testWidgets('a guest sees one Following/Discover bar and lands on Discover', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.text('Forums'), findsNothing);
    expect(find.byType(SimpleTabs), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(_feedIndex(tester), 1);
    expect(find.byType(CreateContentFab), findsOneWidget);
  });

  testWidgets('a signed-in user lands on Following', (tester) async {
    await _pumpTab(tester, userId: 'u1');

    expect(find.text('Forums'), findsNothing);
    expect(_feedIndex(tester), 0);
  });

  testWidgets('signing in mid-session jumps from Discover to Following', (
    tester,
  ) async {
    final container = await _pumpTab(tester);
    expect(_feedIndex(tester), 1);

    container.read(_uid.notifier).state = 'u1';
    await tester.pumpAndSettle();

    expect(_feedIndex(tester), 0);
  });

  testWidgets('switching Following/Discover brings a hidden nav back', (
    tester,
  ) async {
    final container = await _pumpTab(tester, userId: 'u1');
    container.read(navVisibilityProvider.notifier).state = false;
    await tester.pump();

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(_feedIndex(tester), 1);
    expect(container.read(navVisibilityProvider), isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    for (final userId in [null, 'u1']) {
      testWidgets('the header lays out at text scale $scale '
          '(${userId == null ? 'guest' : 'signed in'})', (tester) async {
        await _pumpTab(tester, userId: userId, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.text('Following'), findsOneWidget);
      });
    }
  }

  testWidgets('the app-bar + opens the opinion composer directly', (
    tester,
  ) async {
    await _pumpTab(tester, userId: 'u1');

    await tester.tap(find.byTooltip('add opinions'));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(find.text('Share an opinion'), findsNothing);
    expect(find.text('Start a forum topic'), findsNothing);
  });
}
