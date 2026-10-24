// Spec 3 (forum removal) D1, risk R5: with Forums gone, "+" has one thing to
// make, so it opens the opinion composer directly (no one-row chooser). The
// caller's onOpinionPosted reaches the composer unchanged, and a guest's FAB
// still asks them to sign in.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';
import 'package:attune/core/widgets/create_content_fab.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(
  WidgetTester tester,
  Widget Function(BuildContext context) body, {
  String? userId = 'u1',
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(userId),
        userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
        allTagsProvider.overrideWith((ref) async => const <String>[]),
        // The FAB is scroll-aware: it takes taps only while the nav bar is
        // scrolled away.
        navVisibilityProvider.overrideWith((ref) => false),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: Builder(builder: body)),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('show() opens the opinion composer with the caller callback', (
    tester,
  ) async {
    void onPosted() {}
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed:
            () => CreateContentChooser.show(
              context: context,
              backgroundColor: Colors.white,
              onOpinionPosted: onPosted,
            ),
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(
      tester
          .widget<OpinionComposeScreen>(find.byType(OpinionComposeScreen))
          .onPosted,
      same(onPosted),
    );
    expect(find.text('Share an opinion'), findsNothing);
    expect(find.text('Start a forum topic'), findsNothing);
  });

  testWidgets('a signed-in FAB tap opens the composer directly', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (_) => const Center(
        child: CreateContentFab(heroTag: 'fab', isAuthenticated: true),
      ),
    );

    await tester.tap(find.byType(CreateContentFab));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(find.text('Start a forum topic'), findsNothing);
  });

  testWidgets('a guest FAB tap asks to sign in and opens nothing', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (_) => const Center(
        child: CreateContentFab(heroTag: 'fab', isAuthenticated: false),
      ),
      userId: null,
    );

    await tester.tap(find.byType(CreateContentFab));
    await tester.pump();

    expect(find.text('Sign in to perform this action'), findsOneWidget);
    expect(find.byType(OpinionComposeScreen), findsNothing);
  });

  testWidgets('dismissing the composer opens nothing else', (tester) async {
    // The old chooser stashed the tapped row in a static field; a dismissed
    // sheet must neither replay a stale pick nor report a post.
    var posted = false;
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed:
            () => CreateContentChooser.show(
              context: context,
              backgroundColor: Colors.white,
              onOpinionPosted: () => posted = true,
            ),
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 20)); // the barrier above the sheet
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(posted, isFalse);
  });
}
