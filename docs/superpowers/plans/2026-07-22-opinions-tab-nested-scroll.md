# OpinionsTab Unified Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `OpinionsTab` scroll as one unified surface — AppBar, outer Opinions/Forums tab bar, and inner Following/Discover (or Contributing/Explore) tab bar all collapse and return together as the leaf feed scrolls, instead of sitting as fixed chrome above a cramped scrollable area.

**Architecture:** Replace the current `Scaffold(AppBar) > TabsWithContent#1 > TabsWithContent#2 > ListView` stack with `Scaffold > IndexedStack[_OpinionsSection, ForumsSection]`, where each section owns its own `NestedScrollView` (`SliverAppBar` + outer `TabBar` + inner `TabBar` in `headerSliverBuilder`, leaf feeds as a sliver-based `TabBarView` body). Both sections' outer `TabBar`s are driven by one `TabController` owned by `OpinionsTab`, keeping the `IndexedStack` index and both headers' outer tab in sync. `ForumsTab` is deleted; its `Scaffold`/`AppBar`/`TabBar`/`TabBarView` responsibilities fold into `ForumsSection`.

**Tech Stack:** Flutter, Riverpod (`ConsumerWidget`/`ConsumerStatefulWidget`), existing `SimpleTabs`/`AppTabItem`/`AppTabsStyle` tab-bar widgets, existing `AppFab`/`ScrollAwareFab`/`navVisibilityProvider`.

## Global Constraints

- No change to `navVisibilityProvider` / `AppFab(scrollAware: true)` wiring — the shell-level bottom-nav-hide + FAB-reveal system stays exactly as built, independent of the new header-collapse behavior.
- No change to anonymous-user gating, RLS, or any backend/data-layer code — pure presentation-layer restructure.
- Outer tab (Opinions ↔ Forums) swipe-to-switch is explicitly out of scope — tap-only via `IndexedStack`, not `TabBarView`.
- `SliverAppBar` for each section: `floating: true, pinned: false, snap: true`.
- Every leaf feed inside a `NestedScrollView` body must start with a `SliverOverlapInjector` keyed to that section's `NestedScrollView.sliverOverlapAbsorberHandleFor` handle.
- `RefreshIndicator` and `AlwaysScrollableScrollPhysics` (already present on Discover/Following) must be preserved through the sliver conversion.
- Each leaf feed's existing `NotificationListener<UserScrollNotification>` → `NavVisibilityScrollHandler.handle(ref, notification)` wiring requires no changes.
- `lib/home/widgets/tabs_with_content.dart` is **not modified** — it stays in use elsewhere for single-level tab surfaces.
- The Forums `IndexedStack` slot keeps the existing `isAuthenticated ? ... : ForumScreen()` branch — guests still see the static `ForumScreen` preview, unchanged.
- One shared `AppFab` per section (not one per leaf tab) — Discover's and Following's FABs are functionally identical (both push `OpinionComposeScreen`); consolidate to one FAB at `_OpinionsSection` level. `ForumsExploreScreen`'s FAB (different action: "Submit a topic") consolidates to one FAB at `ForumsSection` level, present only while the inner tab is Explore (Contributing has no FAB today).

---

## File Structure

- `lib/features/opinions/presentation/screen/opinions_tab.dart` — rewritten. `OpinionsTab` becomes the `IndexedStack` + shared outer `TabController` host. `_OpinionsFeedTabs` is replaced by `_OpinionsSection`.
- `lib/features/forums/presentation/screens/forums_section.dart` — new file. `ForumsSection` lives here (mirrors `_OpinionsSection`'s shape, kept out of `opinions_tab.dart` to match the existing one-responsibility-per-file convention used by `forums_tab.dart` today).
- `lib/features/opinions/presentation/screen/discover_feed_screen.dart` — `ListView`/`ListView.builder` → `CustomScrollView` + `SliverOverlapInjector` + slivers. Own `Scaffold`/FAB removed.
- `lib/features/opinions/presentation/screen/following_feed_screen.dart` — same conversion. Own `Scaffold`/FAB removed.
- `lib/features/forums/presentation/screens/contributing_forums_screen.dart` — `ListView`/`ListView.builder` → `CustomScrollView` + `SliverOverlapInjector` + slivers.
- `lib/features/forums/presentation/screens/forums_explore_screen.dart` — add `SliverOverlapInjector` as first sliver. Own `Scaffold`/FAB removed (FAB moves to `ForumsSection`).
- `lib/features/forums/presentation/screens/forums_tab.dart` — deleted.

---

### Task 1: Convert `DiscoverFeedScreen` to sliver-based scrolling, remove its `Scaffold`/FAB

**Files:**
- Modify: `lib/features/opinions/presentation/screen/discover_feed_screen.dart`

**Interfaces:**
- Consumes: `NestedScrollView.sliverOverlapAbsorberHandleFor(context)` — supplied by the ancestor `NestedScrollView` built in Task 5 (`_OpinionsSection`). Until Task 5 exists, this call resolves at runtime only when mounted under a real `NestedScrollView`; that's fine, `flutter analyze` type-checks regardless of the runtime ancestor.
- Produces: `DiscoverFeedScreen` becomes a bare sliver-content widget (no `Scaffold`, no `floatingActionButton`) — Task 5 relies on `DiscoverFeedScreen()` being safe to place directly inside a `TabBarView` inside a `NestedScrollView` body, and on the FAB's `onPressed` logic (push `OpinionComposeScreen`, invalidate `discoverFeedProvider`) being available for `_OpinionsSection` to replicate as its own shared FAB.

Read the current full file first — it is 280 lines and the exact empty-state / populated-list / anonymous-preview branches must be preserved, only their `ListView` shells change to slivers.

- [ ] **Step 1: Read the current file in full**

Run: read `lib/features/opinions/presentation/screen/discover_feed_screen.dart` completely before editing. Confirm the class name (`DiscoverFeedScreen extends ConsumerStatefulWidget`, state class `_DiscoverFeedScreenState`), the `_scrollController`, `_onScroll`, `_anonymousPreviewOpinions`, and the three render branches (`_buildAnonymousPreview`, empty-state `LayoutBuilder`, populated `ListView.builder`) match what's described below. If anything differs, adapt the steps to match actual content — don't blindly paste.

- [ ] **Step 2: Remove the `Scaffold` and `floatingActionButton`, replace with the bare body**

The `build` method currently returns:

```dart
return Scaffold(
  floatingActionButton: isAuthenticated
      ? AppFab(
          scrollAware: true,
          heroTag: 'opinions-discover-fab',
          icon: Icons.add,
          onPressed: () async {
            final needsRefresh = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OpinionComposeScreen()),
            );
            if (needsRefresh == true) {
              ref.invalidate(discoverFeedProvider);
            }
          },
        )
      : null,
  body: NotificationListener<UserScrollNotification>(
    onNotification: (notification) =>
        NavVisibilityScrollHandler.handle(ref, notification),
    child: RefreshIndicator(
      onRefresh: () async => ref.invalidate(discoverFeedProvider),
      child: isAuthenticated
          ? opinionsAsync.when(...)
          : _buildAnonymousPreview(context),
    ),
  ),
);
```

Replace with (drop `Scaffold`, drop `floatingActionButton` — that logic moves to `_OpinionsSection` in Task 5, keep everything else identical):

```dart
return NotificationListener<UserScrollNotification>(
  onNotification: (notification) =>
      NavVisibilityScrollHandler.handle(ref, notification),
  child: RefreshIndicator(
    onRefresh: () async => ref.invalidate(discoverFeedProvider),
    child: isAuthenticated
        ? opinionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: ErrorStateWidget.from(error)),
            data: (opinions) => _buildFeedSliver(context, opinions),
          )
        : _buildAnonymousPreviewSliver(context),
  ),
);
```

Keep the exact `loading`/`error` branches that exist in the current file — only the `data:` branch and the anonymous branch change shape (they become sliver-returning, see next steps). If the current `opinionsAsync.when` is inlined directly in `build()` rather than calling a named method, extract it into `_buildFeedSliver` as shown so the sliver conversion below has a clear home.

- [ ] **Step 3: Convert the populated-list branch to `CustomScrollView` + `SliverOverlapInjector` + `SliverList`**

The current populated branch is:

```dart
return ListView.builder(
  controller: _scrollController,
  physics: const AlwaysScrollableScrollPhysics(),
  itemCount: opinions.length + (hasMore ? 1 : 0),
  itemBuilder: (context, index) {
    if (index >= opinions.length) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ));
    }
    final opinion = opinions[index];
    return OpinionCard(
      opinion: opinion,
      onCommentTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CommentThreadScreen(opinionId: opinion.id),
      )),
      onProfileTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnonymousProfileScreen(userId: opinion.userId),
      )),
    );
  },
);
```

(Adapt field/callback names to match whatever the actual read in Step 1 shows — `OpinionCard`'s exact constructor args, `opinion.id`/`opinion.userId` field names, etc. Do not invent new field names.)

Replace with a method returning a `Widget` that wraps the same content in `CustomScrollView`:

```dart
Widget _buildFeedSliver(BuildContext context, List<Opinion> opinions) {
  final hasMore = ref.watch(discoverFeedProvider.notifier).hasMore; // match actual hasMore source from Step 1
  return CustomScrollView(
    controller: _scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverOverlapInjector(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= opinions.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final opinion = opinions[index];
            return OpinionCard(
              opinion: opinion,
              onCommentTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommentThreadScreen(opinionId: opinion.id),
                ),
              ),
              onProfileTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnonymousProfileScreen(userId: opinion.userId),
                ),
              ),
            );
          },
          childCount: opinions.length + (hasMore ? 1 : 0),
        ),
      ),
    ],
  );
}
```

Preserve the exact `hasMore` expression from the file read in Step 1 (it may be a local variable already computed above the `ListView.builder`, not a fresh provider read — if so, keep computing it the same way and just pass it into this method as a parameter instead of re-deriving it).

- [ ] **Step 4: Convert the empty-state branch to `SliverFillRemaining`**

The current empty-state branch (inside `opinionsAsync.when(data: ...)`, when `opinions.isEmpty`) is:

```dart
return LayoutBuilder(
  builder: (context, constraints) => ListView(
    controller: _scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(
        height: constraints.maxHeight,
        child: Center(child: EmptyStateWidget(/* existing args */)),
      ),
    ],
  ),
);
```

Replace with:

```dart
return CustomScrollView(
  controller: _scrollController,
  physics: const AlwaysScrollableScrollPhysics(),
  slivers: [
    SliverOverlapInjector(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
    ),
    SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: EmptyStateWidget(/* same existing args from Step 1's read */)),
    ),
  ],
);
```

`SliverFillRemaining(hasScrollBody: false)` is the sliver-native equivalent of the `LayoutBuilder`+`SizedBox(height: constraints.maxHeight)` trick — drop the `LayoutBuilder` entirely, it's no longer needed.

- [ ] **Step 5: Convert `_buildAnonymousPreview` to `_buildAnonymousPreviewSliver`**

The current method is a plain `ListView` with a `SemanticContainerWidget` intro card followed by mapped `_anonymousPreviewOpinions` as `OpinionCard(showFollowButton: false)`. Rename to `_buildAnonymousPreviewSliver` and convert:

```dart
Widget _buildAnonymousPreviewSliver(BuildContext context) {
  return CustomScrollView(
    controller: _scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverOverlapInjector(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return const SemanticContainerWidget(/* same existing args from Step 1's read */);
            }
            final opinion = _anonymousPreviewOpinions[index - 1];
            return OpinionCard(opinion: opinion, showFollowButton: false);
          },
          childCount: _anonymousPreviewOpinions.length + 1,
        ),
      ),
    ],
  );
}
```

Match the exact `SemanticContainerWidget` constructor args and any per-item callbacks (`onCommentTap`/`onProfileTap` if present in the anonymous preview) from the Step 1 read — don't drop any existing behavior.

- [ ] **Step 6: Remove now-unused imports if `AppFab`/`OpinionComposeScreen` are no longer referenced in this file**

If `AppFab` and `OpinionComposeScreen` were only used by the removed `floatingActionButton`, remove their imports. If `OpinionComposeScreen` is still referenced elsewhere in the file, keep it.

- [ ] **Step 7: Run `flutter analyze` on this file**

Run: `flutter analyze lib/features/opinions/presentation/screen/discover_feed_screen.dart`
Expected: no errors related to this file. `SliverOverlapInjector`/`NestedScrollView.sliverOverlapAbsorberHandleFor` calls will type-check fine even though no real `NestedScrollView` ancestor exists yet in the tree at this point in the plan — the runtime requirement (a real ancestor) is satisfied later in Task 5.

- [ ] **Step 8: Commit**

```bash
git add lib/features/opinions/presentation/screen/discover_feed_screen.dart
git commit -m "refactor(opinions): convert DiscoverFeedScreen to sliver-based scrolling"
```

---

### Task 2: Convert `FollowingFeedScreen` to sliver-based scrolling, remove its `Scaffold`/FAB

**Files:**
- Modify: `lib/features/opinions/presentation/screen/following_feed_screen.dart`

**Interfaces:**
- Consumes: same `NestedScrollView.sliverOverlapAbsorberHandleFor(context)` pattern as Task 1.
- Produces: `FollowingFeedScreen` becomes a bare sliver-content widget, safe to place inside `_OpinionsSection`'s `TabBarView` (Task 5). Retains `AutomaticKeepAliveClientMixin`/`wantKeepAlive => true` — do not remove, `super.build(context)` call in `build()` must stay as the first line.

- [ ] **Step 1: Read the current file in full**

Run: read `lib/features/opinions/presentation/screen/following_feed_screen.dart` completely. Confirm structure matches: `ConsumerStatefulWidget` with `AutomaticKeepAliveClientMixin`, own `Scaffold`+FAB (heroTag `'opinions-following-fab'`, same `OpinionComposeScreen` target as Discover but invalidating `followingFeedProvider` instead), `NotificationListener<UserScrollNotification>` wrapping `RefreshIndicator` wrapping `ListView`/`ListView.builder`, no pagination (`_onScroll` is a no-op stub).

- [ ] **Step 2: Remove the `Scaffold` and `floatingActionButton`**

Same pattern as Task 1 Step 2 — drop `Scaffold`, drop `floatingActionButton`, keep `super.build(context)` (required by `AutomaticKeepAliveClientMixin`) as the first statement in `build()`, return the `NotificationListener` wrapping `RefreshIndicator` directly:

```dart
@override
Widget build(BuildContext context) {
  super.build(context);
  // ... existing ref.watch calls ...
  return NotificationListener<UserScrollNotification>(
    onNotification: (notification) =>
        NavVisibilityScrollHandler.handle(ref, notification),
    child: RefreshIndicator(
      onRefresh: () async => ref.invalidate(followingFeedProvider),
      child: /* existing when(...) or direct branch, converted below */,
    ),
  );
}
```

- [ ] **Step 3: Convert the populated-list branch to `CustomScrollView` + `SliverOverlapInjector` + `SliverList`**

Following has no pagination trailing item (confirmed: `_onScroll` is a no-op stub, no `hasMore` concept). Convert:

```dart
return ListView.builder(
  controller: _scrollController,
  physics: const AlwaysScrollableScrollPhysics(),
  itemCount: opinions.length,
  itemBuilder: (context, index) => OpinionCard(/* existing args */),
);
```

to:

```dart
Widget _buildFeedSliver(BuildContext context, List<Opinion> opinions) {
  return CustomScrollView(
    controller: _scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverOverlapInjector(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => OpinionCard(/* same existing args from Step 1's read */),
          childCount: opinions.length,
        ),
      ),
    ],
  );
}
```

- [ ] **Step 4: Convert the empty-state branch to `SliverFillRemaining`**

Same conversion as Task 1 Step 4 — replace the `LayoutBuilder`+`ListView`+`SizedBox(height: constraints.maxHeight)` pattern with `CustomScrollView` + `SliverOverlapInjector` + `SliverFillRemaining(hasScrollBody: false)`, preserving the exact `EmptyStateWidget` args from Step 1's read (Following's empty-state copy differs from Discover's — e.g. "follow people to see their opinions" vs Discover's message — keep Following's actual current text).

- [ ] **Step 5: Remove now-unused `AppFab`/`OpinionComposeScreen` imports if applicable**

Same check as Task 1 Step 6.

- [ ] **Step 6: Run `flutter analyze` on this file**

Run: `flutter analyze lib/features/opinions/presentation/screen/following_feed_screen.dart`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/opinions/presentation/screen/following_feed_screen.dart
git commit -m "refactor(opinions): convert FollowingFeedScreen to sliver-based scrolling"
```

---

### Task 3: Convert `ContributingForumsScreen` to sliver-based scrolling

**Files:**
- Modify: `lib/features/forums/presentation/screens/contributing_forums_screen.dart`

**Interfaces:**
- Consumes: same `NestedScrollView.sliverOverlapAbsorberHandleFor(context)` pattern.
- Produces: `ContributingForumsScreen` becomes a bare sliver-content widget for `ForumsSection`'s `TabBarView` (Task 6). This screen has no `Scaffold`/FAB today — no FAB-hoisting needed here, only the sliver conversion.

- [ ] **Step 1: Read the current file in full**

Run: read `lib/features/forums/presentation/screens/contributing_forums_screen.dart` completely (128 lines). Confirm: no `Scaffold`, guest branch is a bare `ListView` with one `SemanticContainerWidget` "Contributing is account-only" card, authenticated branch is `NotificationListener<UserScrollNotification>` wrapping `RefreshIndicator` wrapping `contributingAsync.when(...)`, populated branch is `ListView.builder(padding: EdgeInsets.all(Spacing.md.w), ...)` with `ForumCard(forum:, userSide:)`, empty-state branch is a plain `Center(child: Column(...))` (not sliver-native today, and does NOT currently have the `AlwaysScrollableScrollPhysics` treatment).

- [ ] **Step 2: Convert the guest branch to a sliver**

Current:

```dart
return ListView(
  children: [
    SemanticContainerWidget(/* existing args */),
  ],
);
```

Replace with:

```dart
return CustomScrollView(
  physics: const AlwaysScrollableScrollPhysics(),
  slivers: [
    SliverOverlapInjector(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
    ),
    SliverToBoxAdapter(
      child: SemanticContainerWidget(/* same existing args from Step 1's read */),
    ),
  ],
);
```

- [ ] **Step 3: Convert the authenticated populated-list branch to `CustomScrollView` + `SliverOverlapInjector` + `SliverList`**

Current:

```dart
return ListView.builder(
  padding: EdgeInsets.all(Spacing.md.w),
  itemCount: forums.length,
  itemBuilder: (context, index) {
    final forum = forums[index];
    return ForumCard(forum: forum, userSide: userSide);
  },
);
```

Replace with:

```dart
return CustomScrollView(
  physics: const AlwaysScrollableScrollPhysics(),
  slivers: [
    SliverOverlapInjector(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
    ),
    SliverPadding(
      padding: EdgeInsets.all(Spacing.md.w),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final forum = forums[index];
            return ForumCard(forum: forum, userSide: userSide);
          },
          childCount: forums.length,
        ),
      ),
    ),
  ],
);
```

- [ ] **Step 4: Convert the authenticated empty-state branch to a sliver, preserving the inert button as-is**

Current empty state is `Center(child: Column(children: [..., ElevatedButton.icon(onPressed: /* no-op, comment about needing a tab controller reference */)]))`. This plan does not fix that pre-existing no-op button — out of scope, preserve verbatim. Wrap only the scroll shell:

```dart
return CustomScrollView(
  physics: const AlwaysScrollableScrollPhysics(),
  slivers: [
    SliverOverlapInjector(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
    ),
    SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: Column(/* exact existing children from Step 1's read, including the inert ElevatedButton.icon and its comment, unchanged */)),
    ),
  ],
);
```

- [ ] **Step 5: Run `flutter analyze` on this file**

Run: `flutter analyze lib/features/forums/presentation/screens/contributing_forums_screen.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/forums/presentation/screens/contributing_forums_screen.dart
git commit -m "refactor(forums): convert ContributingForumsScreen to sliver-based scrolling"
```

---

### Task 4: Add `SliverOverlapInjector` to `ForumsExploreScreen`, remove its `Scaffold`/FAB

**Files:**
- Modify: `lib/features/forums/presentation/screens/forums_explore_screen.dart`

**Interfaces:**
- Consumes: same `NestedScrollView.sliverOverlapAbsorberHandleFor(context)` pattern.
- Produces: `ForumsExploreScreen` becomes a bare sliver-content widget for `ForumsSection`'s `TabBarView` (Task 6). Its FAB (`heroTag: 'forums-explore-fab'`, label `'Submit a topic'`, pushes `SubmitTopicScreen`, invalidates `votingTopicsProvider` on success) moves to `ForumsSection` as the section-level FAB, active only while the inner tab index is Explore (index 1).

- [ ] **Step 1: Remove the `Scaffold` and `floatingActionButton`, add `SliverOverlapInjector` as the first sliver**

Current `build()` (from the file already read in full this session, reproduced here exactly):

```dart
return Scaffold(
  floatingActionButton: AppFab(
    scrollAware: true,
    heroTag: 'forums-explore-fab',
    icon: Icons.add,
    label: 'Submit a topic',
    onPressed: () async {
      if (!isAuthenticated) {
        context.showInfoSnackbar(
          'Continue with phone number from Chat to submit a topic.',
        );
        return;
      }
      final needsRefresh = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubmitTopicScreen()),
      );
      if (needsRefresh == true) {
        ref.invalidate(votingTopicsProvider);
      }
    },
  ),
  body: NotificationListener<UserScrollNotification>(
    onNotification:
        (notification) =>
            NavVisibilityScrollHandler.handle(ref, notification),
    child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildSectionHeader('Active debates', Icons.forum_outlined),
        ),
        _buildActiveForumsList(),
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Topics waiting for votes',
            Icons.how_to_vote_outlined,
          ),
        ),
        _buildVotingTopicsList(),
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Quiet forums',
            Icons.hourglass_empty_outlined,
          ),
        ),
        _buildQuietForumsList(),
      ],
    ),
  ),
);
```

Replace with:

```dart
return NotificationListener<UserScrollNotification>(
  onNotification:
      (notification) =>
          NavVisibilityScrollHandler.handle(ref, notification),
  child: CustomScrollView(
    slivers: [
      SliverOverlapInjector(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      ),
      SliverToBoxAdapter(
        child: _buildSectionHeader('Active debates', Icons.forum_outlined),
      ),
      _buildActiveForumsList(),
      SliverToBoxAdapter(
        child: _buildSectionHeader(
          'Topics waiting for votes',
          Icons.how_to_vote_outlined,
        ),
      ),
      _buildVotingTopicsList(),
      SliverToBoxAdapter(
        child: _buildSectionHeader(
          'Quiet forums',
          Icons.hourglass_empty_outlined,
        ),
      ),
      _buildQuietForumsList(),
    ],
  ),
);
```

Note: `isAuthenticated` is still read via `ref.watch(supabaseClientProvider).auth.currentUser?.id != null` at the top of `build()` — keep that line even though the FAB code that used to consume it in this file is gone, because `ForumsSection` (Task 6) needs the equivalent check for its own hoisted FAB and may `ref.watch` it independently there instead. If `isAuthenticated` becomes truly unused in this file after the edit, remove the now-dead local variable and its `ref.watch` line — check with `flutter analyze`'s unused-variable warning in Step 2.

- [ ] **Step 2: Run `flutter analyze` on this file**

Run: `flutter analyze lib/features/forums/presentation/screens/forums_explore_screen.dart`
Expected: no errors. If `isAuthenticated` is now flagged unused, remove it per the note in Step 1.

- [ ] **Step 3: Commit**

```bash
git add lib/features/forums/presentation/screens/forums_explore_screen.dart
git commit -m "refactor(forums): add SliverOverlapInjector to ForumsExploreScreen, remove own Scaffold/FAB"
```

---

### Task 5: Rewrite `opinions_tab.dart` — `IndexedStack` host + `_OpinionsSection`

**Files:**
- Modify: `lib/features/opinions/presentation/screen/opinions_tab.dart`

**Interfaces:**
- Consumes: `DiscoverFeedScreen()` and `FollowingFeedScreen()` (Tasks 1–2, now bare sliver-content widgets), `ForumsSection` (Task 6, produced next but referenced here — Task 6 must land before this task's `flutter analyze` will pass; if executed out of order, a stubbed `ForumsSection` temporarily is NOT acceptable per "no placeholders" — execute Task 6 first or immediately after and analyze both together), `ForumScreen` (unchanged, existing import), `navVisibilityProvider` (unchanged), `currentUserIdProvider` (unchanged), `discoverFeedProvider`/`followingFeedProvider` (for the hoisted FAB's invalidate calls), `OpinionComposeScreen` (for the hoisted FAB's push target).
- Produces: `OpinionsTab` (public, unchanged name/constructor — `const OpinionsTab({super.key})` — so no call-site changes needed elsewhere in the app), a shared outer `TabController` (`_outerTabController`, length 2) driving both `_OpinionsSection`'s and `ForumsSection`'s outer `TabBar`, and the `IndexedStack` index.

- [ ] **Step 1: Convert `OpinionsTab` from `ConsumerWidget` to `ConsumerStatefulWidget`**

It needs a `TabController`, which requires a `TickerProvider` (`SingleTickerProviderStateMixin`) and `State` lifecycle (`initState`/`dispose`) — `ConsumerWidget` can't hold this. Replace the whole file:

```dart
// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_section.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
// NOTE: forums_section.dart does not exist until Task 6 runs — this import
// will not resolve, and flutter analyze on this file alone will fail, until
// Task 6 is complete. This is expected; see Step 3 of this task.
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpinionsTab extends ConsumerStatefulWidget {
  const OpinionsTab({super.key});

  @override
  ConsumerState<OpinionsTab> createState() => _OpinionsTabState();
}

class _OpinionsTabState extends ConsumerState<OpinionsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _outerTabController;

  @override
  void initState() {
    super.initState();
    _outerTabController = TabController(length: 2, vsync: this);
    // Opinions/Forums sections are both kept alive in the IndexedStack, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _outerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_outerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _outerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _outerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _outerTabController,
        builder: (context, _) => IndexedStack(
          index: _outerTabController.index,
          children: [
            _OpinionsSection(
              outerTabController: _outerTabController,
              isAuthenticated: isAuthenticated,
            ),
            isAuthenticated
                ? ForumsSection(outerTabController: _outerTabController)
                : const ForumScreen(),
          ],
        ),
      ),
    );
  }
}
```

Note: `AnimatedBuilder` around the `IndexedStack` is necessary because `_outerTabController.index` changes don't otherwise trigger a rebuild of `_OpinionsTabState` — `TabController` is not itself a `Listenable` consumed automatically by `IndexedStack`. Confirm this compiles; `TabController extends Animation<double>` which implements `Listenable`, so `AnimatedBuilder(animation: _outerTabController, ...)` is valid.

- [ ] **Step 2: Add `_OpinionsSection` — the `NestedScrollView` host for the Opinions side**

Append to the same file (or keep in the same file per the spec's "decided at implementation time" note — this plan keeps `_OpinionsSection` in `opinions_tab.dart` since it's tightly coupled to `_outerTabController`, while `ForumsSection` gets its own file in Task 6 to mirror the existing `forums_tab.dart` convention being replaced):

```dart
class _OpinionsSection extends ConsumerStatefulWidget {
  const _OpinionsSection({
    required this.outerTabController,
    required this.isAuthenticated,
  });

  final TabController outerTabController;
  final bool isAuthenticated;

  @override
  ConsumerState<_OpinionsSection> createState() => _OpinionsSectionState();
}

class _OpinionsSectionState extends ConsumerState<_OpinionsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTabController;

  @override
  void initState() {
    super.initState();
    // Anonymous users follow nobody, so Following can only show them a
    // "unlocks after verification" gate. Land them on Discover — the whole
    // point of the anonymous-browsing rule is that they see real content
    // without an account.
    _innerTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isAuthenticated ? 0 : 1,
    );
    // Following/Discover are both kept alive as sibling sub-tabs, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _innerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_innerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _innerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _innerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      floatingActionButton: widget.isAuthenticated
          ? AppFab(
              scrollAware: true,
              heroTag: 'opinions-fab',
              icon: Icons.add,
              onPressed: () async {
                final needsRefresh = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpinionComposeScreen(),
                  ),
                );
                if (needsRefresh == true) {
                  if (_innerTabController.index == 0) {
                    ref.invalidate(followingFeedProvider);
                  } else {
                    ref.invalidate(discoverFeedProvider);
                  }
                }
              },
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              backgroundColor: colorScheme.neutral,
              floating: true,
              pinned: false,
              snap: true,
              leading: AppIconButton(
                icon: Icons.menu,
                onPressed: () {
                  if (kDebugMode) {
                    context.push(RouteNames.onboarding, extra: true);
                  }
                },
              ),
              title: SizedBox(
                width: 30,
                height: 30,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
                  child: Image.asset(
                    color: colorScheme.primary,
                    'assets/images/attune_logo_white.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              actions: [
                AppIconButton(
                  icon: Icons.search,
                  onPressed: () {
                    if (kDebugMode) {
                      context.push(RouteNames.onboarding, extra: true);
                    }
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(48.h),
                child: SimpleTabs(
                  tabs: const [
                    AppTabItem(
                      label: 'Opinions',
                      icon: Icons.rate_review_outlined,
                    ),
                    AppTabItem(label: 'Forums', icon: Icons.forum_outlined),
                  ],
                  controller: widget.outerTabController,
                  scrollable: false,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: SimpleTabs(
                tabs: const [
                  AppTabItem(label: 'Following'),
                  AppTabItem(label: 'Discover'),
                ],
                controller: _innerTabController,
                scrollable: false,
                style: AppTabsStyle(
                  indicatorColor: colorScheme.primary,
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _innerTabController,
          children: const [FollowingFeedScreen(), DiscoverFeedScreen()],
        ),
      ),
    );
  }
}
```

Notes carried forward exactly from the original file (verify against Step 1's earlier full read of the pre-existing `opinions_tab.dart`, reproduced in this plan's context): `colorScheme.neutral` Scaffold background, `AppIconButton` menu/search actions with the identical `kDebugMode` guard pushing `RouteNames.onboarding, extra: true`, the `attune_logo_white.png` asset with `colorScheme.primary` tint and `BorderRadiusTokens.md` clip. The outer `TabBar`'s `AppTabsStyle` was not customized on the original outer `TabsWithContent` (only the inner one had `AppTabsStyle` overrides) — so the outer `SimpleTabs` above intentionally uses default styling, matching original behavior; only the inner `SimpleTabs` gets the `colorScheme`-derived `AppTabsStyle`, matching the original `_OpinionsFeedTabs`.

`SliverOverlapAbsorber` wraps the `SliverAppBar` (not a bare `SliverToBoxAdapter`) because `SliverAppBar` is itself a sliver that needs overlap absorption when placed in a `headerSliverBuilder` alongside a pinned/floating configuration — this is the standard Flutter `NestedScrollView` pattern (see Flutter's own `NestedScrollView` example in framework docs). The outer tab bar is placed in `SliverAppBar.bottom` (making it float together with the AppBar as one group, per the spec's "one floating group" requirement) rather than as a separate sibling sliver — this guarantees they move as a single unit without needing a second `SliverPersistentHeader`.

- [ ] **Step 3: Run `flutter analyze` on this file (expect errors referencing missing `forums_section.dart` until Task 6 lands — acceptable mid-plan, must be clean after Task 6)**

Run: `flutter analyze lib/features/opinions/presentation/screen/opinions_tab.dart`
Expected: an error only about the unresolved `forums_section.dart` import (since Task 6 hasn't run yet). No other errors. If other errors appear, fix them now — they are not explained by the missing Task 6 file.

- [ ] **Step 4: Commit**

```bash
git add lib/features/opinions/presentation/screen/opinions_tab.dart
git commit -m "refactor(opinions): rewrite OpinionsTab as IndexedStack + NestedScrollView _OpinionsSection"
```

---

### Task 6: Create `_ForumsSection`, delete `ForumsTab`

**Files:**
- Create: `lib/features/forums/presentation/screens/forums_section.dart`
- Delete: `lib/features/forums/presentation/screens/forums_tab.dart`

**Interfaces:**
- Consumes: `TabController outerTabController` (passed in from `_OpinionsTabState`, Task 5), `ContributingForumsScreen()` and `ForumsExploreScreen()` (Tasks 3–4, now bare sliver-content widgets), `votingTopicsProvider` (for the hoisted FAB's invalidate call), `SubmitTopicScreen` (for the hoisted FAB's push target), `supabaseClientProvider` (for the `isAuthenticated` check the FAB's `onPressed` used to do inline in `ForumsExploreScreen`).
- Produces: `_ForumsSection` — a private `ConsumerStatefulWidget` (this is a leading-underscore class in a separate file, so it must be exported as `ForumsSection` instead — see Step 1's note before writing this).

- [ ] **Step 1: Naming correction — Dart privacy is file-scoped, not app-scoped**

A `_`-prefixed class is only accessible within its own file. Since `opinions_tab.dart` (Task 5) references this section from a different file, it must be a public class. Name it `ForumsSection` (no underscore) in `forums_section.dart`, and update Task 5's `_OpinionsTabState.build()` reference from `_ForumsSection(...)` to `ForumsSection(...)` (go back and fix this in `opinions_tab.dart` now if Task 5 already used the underscored name).

- [ ] **Step 2: Write `forums_section.dart`**

```dart
// lib/features/forums/presentation/screens/forums_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/contributing_forums_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_explore_screen.dart';
import 'package:attune/features/forums/presentation/screens/submit_topic_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumsSection extends ConsumerStatefulWidget {
  const ForumsSection({super.key, required this.outerTabController});

  final TabController outerTabController;

  @override
  ConsumerState<ForumsSection> createState() => _ForumsSectionState();
}

class _ForumsSectionState extends ConsumerState<ForumsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTabController;

  @override
  void initState() {
    super.initState();
    _innerTabController = TabController(length: 2, vsync: this);
    // Contributing/Explore are both kept alive as sibling sub-tabs, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _innerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_innerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _innerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _innerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;

    return Scaffold(
      floatingActionButton: AnimatedBuilder(
        animation: _innerTabController,
        builder: (context, _) {
          // Contributing has no FAB today — only show it while Explore
          // (index 1) is active, matching the original per-screen FAB
          // placement (ForumsExploreScreen owned its own FAB; Contributing
          // never had one).
          if (_innerTabController.index != 1) return const SizedBox.shrink();
          return AppFab(
            scrollAware: true,
            heroTag: 'forums-explore-fab',
            icon: Icons.add,
            label: 'Submit a topic',
            onPressed: () async {
              if (!isAuthenticated) {
                context.showInfoSnackbar(
                  'Continue with phone number from Chat to submit a topic.',
                );
                return;
              }
              final needsRefresh = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubmitTopicScreen()),
              );
              if (needsRefresh == true) {
                ref.invalidate(votingTopicsProvider);
              }
            },
          );
        },
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              floating: true,
              pinned: false,
              snap: true,
              title: const Text('Forums'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(48.h),
                child: SimpleTabs(
                  tabs: const [
                    AppTabItem(
                      label: 'Opinions',
                      icon: Icons.rate_review_outlined,
                    ),
                    AppTabItem(label: 'Forums', icon: Icons.forum_outlined),
                  ],
                  controller: widget.outerTabController,
                  scrollable: false,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SimpleTabs(
              tabs: const [
                AppTabItem(label: 'Contributing'),
                AppTabItem(label: 'Explore'),
              ],
              controller: _innerTabController,
              scrollable: false,
              style: AppTabsStyle(
                indicatorColor: colorScheme.primary,
                activeColor: colorScheme.primary,
                inactiveColor: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _innerTabController,
          children: const [ContributingForumsScreen(), ForumsExploreScreen()],
        ),
      ),
    );
  }
}
```

Note: the outer tab bar shown here (Opinions/Forums via `widget.outerTabController`) is duplicated between `_OpinionsSection` (Task 5) and `ForumsSection` — this is required, not accidental: each `NestedScrollView` needs its own copy of the outer `TabBar` rendered in its own header so it scrolls/collapses correctly within that section's own scroll position, while both copies share the same `TabController` so tapping either one drives the same `IndexedStack` index (per the spec's explicit architecture). The original `ForumsTab`'s `AppBar(title: Text('Forums'))` had no logo/menu/search — only `_OpinionsSection`'s `SliverAppBar` carries those; `ForumsSection`'s `SliverAppBar` keeps the simple `title: Text('Forums')` to match `ForumsTab`'s original chrome exactly, plus the newly-required outer tab bar in `bottom`.

`unselectedLabelColor`/`inactiveColor` used `withOpacity` in the original `forums_tab.dart` (not `withValues(alpha:)` like the Opinions inner tabs) — preserved as-is above since it's pre-existing code being moved, not new code; not a scope item for this plan to fix the deprecation-lint difference between the two call sites.

- [ ] **Step 3: Delete `forums_tab.dart`**

```bash
rm lib/features/forums/presentation/screens/forums_tab.dart
```

- [ ] **Step 4: Search for any remaining references to `ForumsTab` and remove/update them**

Run: `grep -rn "ForumsTab" lib/ --include="*.dart"`
Expected: no matches (the only usage was in the old `opinions_tab.dart`, already rewritten in Task 5 to reference `ForumsSection` instead). If any other file imports `forums_tab.dart` or references the `ForumsTab` class, update it to use `ForumsSection` with the appropriate `outerTabController` — but no such usage is expected based on the codebase read so far in this session.

- [ ] **Step 5: Run `flutter analyze` on both files together**

Run: `flutter analyze lib/features/opinions/presentation/screen/opinions_tab.dart lib/features/forums/presentation/screens/forums_section.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/forums/presentation/screens/forums_section.dart
git rm lib/features/forums/presentation/screens/forums_tab.dart
git commit -m "refactor(forums): replace ForumsTab with NestedScrollView-based ForumsSection"
```

---

### Task 7: Full-project analyze sweep and manual verification

**Files:** none (verification-only task)

**Interfaces:**
- Consumes: all files touched in Tasks 1–6.
- Produces: confirmation the restructure is internally consistent app-wide (no stray references, no analyzer errors).

- [ ] **Step 1: Run `flutter analyze` across the whole project**

Run: `flutter analyze`
Expected: no new errors introduced by this restructure. Pre-existing warnings/infos unrelated to the touched files are out of scope — do not fix unrelated pre-existing issues as part of this task.

- [ ] **Step 2: Confirm no remaining references to deleted/renamed symbols**

Run: `grep -rn "_OpinionsFeedTabs\|ForumsTab\b" lib/ --include="*.dart"`
Expected: no matches. (`ForumsSection`/`_ForumsSectionState` matches are fine and expected — the grep pattern targets only the old names.)

- [ ] **Step 3: Manual verification — start the app and walk through the spec's test checklist**

Run: `flutter run` (or use whatever run configuration the project normally uses), then manually verify:
- Scrolling Discover, Following, Forums Explore, and Forums Contributing each scrolls the AppBar + both tab-bar levels away together, and a small upward scroll (not full scroll-to-top) brings the header group back (confirms `floating: true, snap: true` behavior).
- The shell bottom nav and `AppFab` still hide/reveal independently of the header collapse — no double-animation conflict or FAB jumping.
- Inner tab swipe (Following↔Discover, Contributing↔Explore) still works via `TabBarView`'s default swipe physics (neither `_innerTabController`'s `TabBarView` was given `NeverScrollableScrollPhysics`, so this should work unchanged).
- Outer tab switch (Opinions↔Forums) works via tapping the outer `TabBar` in either section's header, and correctly swaps the `IndexedStack` — confirm swipe does NOT switch outer tabs (expected per spec, `IndexedStack` has no swipe).
- Anonymous (guest) user: Forums slot shows the static `ForumScreen` preview unchanged; Opinions slot lands on Discover (not Following) per the existing `initialIndex: isAuthenticated ? 0 : 1` logic.
- The FAB on the Opinions side appears only when authenticated, opens `OpinionComposeScreen`, and invalidates the correct provider (`followingFeedProvider` when on Following tab, `discoverFeedProvider` when on Discover tab) based on which inner tab is active at the moment of a successful compose.
- The FAB on the Forums side appears only while the Explore inner tab is active (not Contributing), and behaves identically to its pre-refactor version (guest snackbar gate, push `SubmitTopicScreen`, invalidate `votingTopicsProvider`).

This is manual-only per the spec ("no automated widget tests exist for this screen today... doesn't need to invent new test infrastructure"). Report the outcome of each checklist item.

- [ ] **Step 4: Commit (only if Step 3 required follow-up fixes; otherwise this task produces no diff and needs no commit)**

If manual verification in Step 3 surfaced any bugs, fix them in the relevant file from Tasks 1–6, re-run `flutter analyze` on that file, then:

```bash
git add <fixed files>
git commit -m "fix(opinions): address manual verification findings from NestedScrollView restructure"
```

If no fixes were needed, skip this step — there is nothing to commit.
