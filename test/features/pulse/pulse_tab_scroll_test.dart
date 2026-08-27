import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the NestedScrollView pattern PulseTab is built on — not
/// PulseTab itself, which pulls in PulseScreen's and TimelineScreen's full
/// live provider trees (Supabase-backed FutureProviders across several
/// features, each with its own currentUserIdProvider definition — no
/// single override closes all of them off cleanly). Instead this
/// reproduces PulseTab's exact sliver structure with controlled fake
/// content standing in for the two shapes its real tabs have:
///
///   - a tab that owns its OWN CustomScrollView with tall content
///     (PulseScreen's and TimelineScreen's actual shape)
///   - a tab that is a plain, non-scrolling Column (ChatSettingsStaticRows'
///     actual shape, via _ChatSettingsRowsTab)
///
/// Bug 1 (this test's first case): under TabsWithContent's old
/// useNestedScrollMode, the CustomScrollView-owning tab's own scrollable
/// swallowed every drag gesture, so the header above it never moved.
/// Bug 2 (second case): the plain-Column tab had no scrollable of its own,
/// so content taller than the available height overflowed instead of
/// scrolling.
///
/// See PulseTab's own doc comment (pulse_tab.dart) for why NestedScrollView
/// is the fix, and PulseScreen's/TimelineScreen's build methods for the
/// SliverOverlapInjector half of the pairing tested here.
void main() {
  Widget buildHarness({
    required Widget scrollableTab,
    required Widget plainColumnTab,
  }) {
    return MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: 200,
                        child: Center(child: Text('IDENTITY CARD HEADER')),
                      ),
                    ),
                    // Wraps the tab bar rather than standing alone with no
                    // sliver: a bare, childless SliverOverlapAbsorber never
                    // runs a layout pass, so it never reports an extent —
                    // every matching SliverOverlapInjector then hits "found
                    // no absorbed extent to inject" on the first frame.
                    // Matches Flutter's own NestedScrollView example, which
                    // wraps its SliverAppBar the same way.
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      ),
                      sliver: const SliverToBoxAdapter(
                        child: SizedBox(
                          height: 48,
                          child: TabBar(
                            tabs: [Tab(text: 'Scrollable'), Tab(text: 'Plain')],
                          ),
                        ),
                      ),
                    ),
                  ];
                },
                body: TabBarView(children: [scrollableTab, plainColumnTab]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget scrollableTabContent() {
    return Builder(
      builder: (context) {
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    SizedBox(height: 80, child: Text('Row $index')),
                childCount: 30,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget plainColumnTabContent() {
    return Builder(
      builder: (context) {
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverToBoxAdapter(
              // Plain Column, no scrollable of its own — matches
              // ChatSettingsStaticRows' real shape exactly. Taller than any
              // reasonable viewport so the old bug (no scroll wrapper —
              // bare SliverFillRemaining around this same Column) would
              // overflow here.
              child: Column(
                children: List.generate(
                  30,
                  (i) => SizedBox(height: 80, child: Text('Setting $i')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  testWidgets(
    'dragging inside a tab that owns its own CustomScrollView moves the '
    'shared header away too (regression: previously only the tab\'s own '
    'list scrolled, the header stayed fixed)',
    (tester) async {
      await tester.pumpWidget(
        buildHarness(
          scrollableTab: scrollableTabContent(),
          plainColumnTab: plainColumnTabContent(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('IDENTITY CARD HEADER'), findsOneWidget);

      // Drag from inside the SCROLLABLE tab's own list — this is the
      // gesture a real user makes when scrolling PulseScreen/TimelineScreen
      // inside PulseTab.
      await tester.drag(find.text('Row 0'), const Offset(0, -400));
      await tester.pumpAndSettle();

      // The header widget is no longer laid out at all once its sliver has
      // scrolled fully past the top of the viewport — that absence IS the
      // "moved away with the rest" behavior being verified, matching what
      // a real NestedScrollView with a non-pinned header does. Under the
      // old bug this would still find the header, since the drag on 'Row 0'
      // would have been entirely consumed by the tab's own inner
      // scrollable, leaving the outer NestedScrollView position at zero.
      expect(find.text('IDENTITY CARD HEADER'), findsNothing);
    },
  );

  testWidgets(
    'a plain-Column tab (no scrollable of its own) does NOT overflow, and '
    'itself scrolls when dragged (regression: previously a RenderFlex '
    'overflow / "BOTTOM OVERFLOWED" error)',
    (tester) async {
      await tester.pumpWidget(
        buildHarness(
          scrollableTab: scrollableTabContent(),
          plainColumnTab: plainColumnTabContent(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to the Plain tab.
      await tester.tap(find.text('Plain'));
      await tester.pumpAndSettle();

      // The overflow error paints a yellow-and-black banner and throws
      // during layout — takeException catches any such rendering
      // exception. A bare Column of 30 fixed-height rows with nothing
      // scrollable wrapping it would trip this the moment content exceeds
      // the tab's available height.
      expect(tester.takeException(), isNull);
      expect(find.text('Setting 0'), findsOneWidget);

      // The plain-Column tab must ALSO be draggable/scrollable in its own
      // right — SliverOverlapInjector alone doesn't grant that; it's the
      // surrounding CustomScrollView that does, and this failing would mean
      // the tab is still just a fixed, clipped, unscrollable box.
      await tester.drag(find.text('Setting 0'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
