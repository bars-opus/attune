# OpinionsTab Unified Scroll — Design

## Problem

`OpinionsTab` currently stacks three independently-scrolling layers of fixed
chrome before any real content appears:

```
Scaffold(AppBar: logo/menu/search)
  TabsWithContent #1 (outer tab bar: Opinions | Forums)
    _OpinionsFeedTabs
      TabsWithContent #2 (inner tab bar: Following | Discover)
        DiscoverFeedScreen / FollowingFeedScreen (own ListView.builder)
```

When the Forums outer tab is active, there's a **fourth** layer: `ForumsTab`
mounts its own `Scaffold` + `AppBar` + `TabBar` (Contributing | Explore)
around `ContributingForumsScreen` / `ForumsExploreScreen`.

Each layer eats fixed vertical space regardless of scroll position, leaving
a cramped viewport for the actual feed. None of the chrome collapses or
scrolls away, so on smaller screens the visible scrollable area is small
relative to the screen.

## Goal

Scrolling any leaf feed (Discover, Following, Forums Explore, Forums
Contributing) scrolls the *whole* `OpinionsTab` surface as one unit — the
AppBar and both levels of tab bars scroll away together on scroll-down and
return together on scroll-up (Twitter/Threads-style), maximizing the visible
scrollable area.

## Non-goals

- No change to `navVisibilityProvider` / `AppFab(scrollAware: true)` — that
  shell-level bottom-nav-hide + FAB-reveal system stays exactly as built
  this session, independent of the header-collapse behavior added here.
- No change to anonymous-user gating, RLS, or any backend/data-layer code —
  this is a pure presentation-layer restructure.
- Outer tab (Opinions ↔ Forums) swipe-to-switch is explicitly out of scope;
  it becomes tap-only (see Architecture).

## Architecture

### Two sibling `NestedScrollView`s, swapped by `IndexedStack`

Flutter's `NestedScrollView` hosts exactly one scrolling body
(`TabBarView`) per instance. With two nesting levels of tabs, the correct
shape is **one `NestedScrollView` per outer tab**, each carrying both tab-bar
levels in its own header:

```
OpinionsTab (still one Scaffold, no AppBar of its own — the AppBar moves
             into each section's NestedScrollView header)
  IndexedStack (driven by an outer TabController's index — NOT a TabBarView,
                so switching sections is a hard swap, not a swipeable page)
    [0] _OpinionsSection   -> its own NestedScrollView
    [1] _ForumsSection     -> its own NestedScrollView
```

Each section's `NestedScrollView`:

- `headerSliverBuilder` returns, in order, as floating (not pinned) slivers
  that move together as one group:
  1. `SliverAppBar` — the existing logo/menu/search chrome, `floating: true`,
     `pinned: false`, `snap: true` so a small upward scroll brings the whole
     header group back immediately rather than requiring a full scroll-to-top.
  2. The **outer** Opinions/Forums `TabBar`, sliver-wrapped
     (`SliverPersistentHeader` with `floating: true`, or `SliverToBoxAdapter`
     inside the same floating group — exact choice made at implementation
     time based on which gives correct floating behavior in this Flutter
     version).
  3. That section's **inner** `TabBar` (Following/Discover, or
     Contributing/Explore).
- `body` is a `TabBarView` (that section's own `TabController`) holding the
  two leaf feeds as sliver-based scrollables.

Both `NestedScrollView`s' outer `TabController`s (the Opinions/Forums
selector) are driven by one shared `TabController` owned by `OpinionsTab`,
so the outer `TabBar` rendered inside *either* section's header reflects and
controls the same `IndexedStack` index.

### Leaf feed conversion: `ListView` → sliver

Every leaf feed inside a `NestedScrollView` body must start with a
`SliverOverlapInjector` (keyed to a `NestedScrollView.sliverOverlapAbsorberHandleFor`
handle) before its own content slivers — this is Flutter's required
mechanism to stop the header's overlap being double-counted. Conversions
needed:

- `DiscoverFeedScreen`: `ListView.builder` → `CustomScrollView` with
  `SliverOverlapInjector` + `SliverList.builder` (main feed) /
  `SliverFillRemaining` (empty/anonymous-preview states, replacing the
  current `LayoutBuilder`-sized `SizedBox` trick with the sliver-native
  equivalent).
- `FollowingFeedScreen`: same conversion, same empty-state handling.
- `ContributingForumsScreen`: `ListView`/`ListView.builder` → `CustomScrollView`
  with `SliverOverlapInjector` + `SliverList`.
- `ForumsExploreScreen`: already a `CustomScrollView` with multiple
  `SliverList` sections — only needs `SliverOverlapInjector` added as its
  first sliver, no other structural change.

`RefreshIndicator` and `AlwaysScrollableScrollPhysics` (both added earlier
this session so pull-to-refresh and FAB-reveal work on short feeds) are
preserved — `RefreshIndicator` wraps the `CustomScrollView` the same way it
wrapped the `ListView`.

### `ForumsTab` is removed

Its responsibilities (own `Scaffold`, own `AppBar`, own `TabBar`, own
`TabBarView`) fold entirely into `_ForumsSection`'s `NestedScrollView`. The
file is deleted; `_ForumsSection` becomes the sole place Forums'
Contributing/Explore tab structure is defined.

### Scroll-notification wiring: unchanged

`NestedScrollView`'s inner scroll positions dispatch the same
`ScrollNotification` types a plain `ListView` does, and they still bubble up
through the widget tree to any ancestor `NotificationListener`. Each leaf
feed's existing `NotificationListener<UserScrollNotification>` (feeding
`NavVisibilityScrollHandler.handle(ref, notification)`) requires **no
changes** — confirmed as the explicit, lower-risk choice over merging it
into a single NestedScrollView-driven controller.

### Anonymous users

The `IndexedStack`'s Forums slot keeps the existing
`isAuthenticated ? ... : ForumScreen()` branch — guests see the static
`ForumScreen` preview exactly as today; only the authenticated path routes
through the new `_ForumsSection`.

## Testing

- Manual: scroll each of the four leaf feeds and confirm the AppBar + both
  tab-bar levels scroll away together and return together.
- Manual: confirm the shell bottom nav + `AppFab` still hide/reveal
  independently of the header collapse (no double-animation conflict).
- Manual: confirm inner tab swipe (Following↔Discover, Contributing↔Explore)
  still works; confirm outer tab switch (Opinions↔Forums) is tap-only via
  the outer `TabBar` and correctly swaps the `IndexedStack`.
- Re-run the existing `flutter analyze` sweep across every touched file —
  no automated widget tests exist for this screen today (confirmed earlier
  this session), so this restructure doesn't need to invent new test
  infrastructure to stay consistent with the codebase's current coverage
  for this feature.

## Files touched

- `lib/features/opinions/presentation/screen/opinions_tab.dart` — rewritten:
  `OpinionsTab` becomes the `IndexedStack` + shared outer `TabController`
  host; `_OpinionsFeedTabs` is replaced by `_OpinionsSection`.
- New: `_ForumsSection` (likely a new file,
  `lib/features/forums/presentation/screens/forums_section.dart`, or inlined
  in `opinions_tab.dart` — decided at implementation time based on file-size
  conventions already established this session).
- `lib/features/opinions/presentation/screen/discover_feed_screen.dart` —
  `ListView.builder` → sliver-based `CustomScrollView`.
- `lib/features/opinions/presentation/screen/following_feed_screen.dart` —
  same conversion.
- `lib/features/forums/presentation/screens/contributing_forums_screen.dart`
  — same conversion.
- `lib/features/forums/presentation/screens/forums_explore_screen.dart` —
  add `SliverOverlapInjector` only.
- `lib/features/forums/presentation/screens/forums_tab.dart` — deleted.
- `lib/home/widgets/tabs_with_content.dart` — **not modified**. It remains
  in use elsewhere in the app for genuinely single-level tab surfaces; this
  restructure only stops `OpinionsTab` from using it, since its
  `useNestedScrollMode` flag doesn't solve the two-level-nesting problem
  (confirmed during brainstorming — it builds an isolated `CustomScrollView`
  per instance, not a shared `NestedScrollView`).
