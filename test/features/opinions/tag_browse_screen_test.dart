// Spec 3 (forum removal) §7.2, risk R6: a tag page is one list of opinions.
// No Opinions/Forums tabs; the title, Follow button, cards and empty state
// are unchanged, and the header lays out at default and largest text.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OpinionModel _opinion(String id) => OpinionModel(
  id: id,
  authorHandle: 'quiet-otter',
  isMine: false,
  content: 'Opinion $id about trust',
  relationshipStatus: 'single',
  likeCount: 0,
  dislikeCount: 0,
  commentCount: 0,
  createdAt: DateTime(2026, 10, 20),
);

/// One page, nothing more to load (no trailing spinner).
class _TagFeed extends OpinionsByTagNotifier {
  _TagFeed(this._items);
  final List<OpinionModel> _items;

  @override
  Future<List<OpinionModel>> build(String arg) async => _items;

  @override
  bool get hasMore => false;
}

Future<void> _pumpTagPage(
  WidgetTester tester, {
  List<OpinionModel> opinions = const [],
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(null),
        opinionsByTagProvider.overrideWith(() => _TagFeed(opinions)),
        isTagFollowedProvider.overrideWith((ref, slug) => false),
      ],
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
              home: const TagBrowseScreen(tagSlug: 'trust'),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one list of opinions under the title and Follow button', (
    tester,
  ) async {
    await _pumpTagPage(tester, opinions: [_opinion('a'), _opinion('b')]);

    expect(find.text('#trust'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.byType(OpinionCard), findsNWidgets(2));
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Forums'), findsNothing);
    expect(find.text('Opinions'), findsNothing);
  });

  testWidgets('no opinions shows the opinions empty state', (tester) async {
    await _pumpTagPage(tester);

    expect(find.text('No opinions tagged #trust'), findsOneWidget);
    expect(find.textContaining('forums'), findsNothing);
  });

  testWidgets('a guest tapping Follow is asked to sign in', (tester) async {
    await _pumpTagPage(tester);

    await tester.tap(find.text('Follow'));
    await tester.pump();

    expect(find.text('Sign in to perform this action'), findsOneWidget);
  });

  testWidgets('the header keeps its pre-removal spacing (390 x 844)', (
    tester,
  ) async {
    // Batch-1 review #1: before the removal, the AppBar squeezed its toolbar
    // above the old two-row bottom, so people saw the title about 31 lp above
    // Follow in a header about 110 lp tall (the old height minus the tab
    // row). Without the tab row, a 100.h toolbar renders in full and opens a
    // gap of about 54 lp.
    await _pumpTagPage(tester, opinions: [_opinion('a')]);

    final gap =
        tester.getRect(find.text('Follow')).top -
        tester.getRect(find.text('#trust')).bottom;
    expect(gap, closeTo(31.0, 2));
    expect(tester.getSize(find.byType(AppBar)).height, closeTo(110.2, 2));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the header lays out at text scale $scale', (tester) async {
      await _pumpTagPage(tester, opinions: [_opinion('a')], textScale: scale);

      expect(tester.takeException(), isNull);
      expect(find.text('Follow'), findsOneWidget);
    });
  }
}
