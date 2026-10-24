# Spec 3: Forum removal (Opinions stays exactly as it is)

**Date:** 2026-10-24 · **Status:** design, for owner review · **Waves:** 3
**Build order (synthesis §11, §12):** Spec 3 W1 → Spec 3 W2 → Spec 1 (W1–W7, W9, W10; W8 is held empty) → Spec 2 W1–W10 → **Spec 3 W3** → Spec 2 W11. Migration timestamps are assigned at build time (House rules), so later waves may run in any dependency-valid order; the wave gates below are the dependencies.

**Naming:** "Spec 1/2/3" here are the three October 2026 specs (app flow and identity, Dating Mode, forum removal). They are not the earlier launch program's "Spec 2" (Safety PIN and quick exit) or "Spec 3a/3b/3c" (lifecycle, deletion, export), which older code comments cite. `attune_spec3a` is the scratch database of that older program and only shares a name with this spec.

**Sources:**
- `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md`: §12 (owner rulings), §6 (forum removal), §11 (Spec 3 waves).
- `06-attune-flow-audit.md` §2.5 (blast radius), §2.8 (Games), §3.3 (risks).
- `07-opinions-without-forums.md` §2.1 and §2.9 (what Opinions shares with Forums).
- The code itself. Every row below was checked by grep against `main` at `a7b07e79`, and the database rows also against the local `attune_spec3a` database (read-only `pg_proc`, `pg_class`, `pg_constraint` and `cron.job` queries).

**Binding decisions this spec follows:**
- Remove the screens, routes, jobs, edge functions and notifications now. Drop the tables in a later wave, after one release on every test device.
- **Opinions stays exactly as it is.** Its redesign (Spec 1 W8) is deferred by the owner's Q9 ruling.
- Keep everything Opinions uses, even when its name says "forum".
- Fresh start: there are no real users.
- Don't touch in-chat Games.
- Spec 3 W1–W2 run before Spec 1.

**House rules for every wave:**
- **Formatting:** never `dart format` a file that already exists; format only the files this spec creates.
- **Migrations:**
  - New files only; never edit an applied migration.
  - Every migration is idempotent (`IF EXISTS`, `CREATE OR REPLACE`, guarded `DO` blocks).
  - Every new or redefined `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name.
  - A migration that needs to be atomic carries its own `BEGIN; … COMMIT;`. No `CREATE INDEX CONCURRENTLY` in any migration (it can't run inside a transaction).
  - **Filenames and timestamps:** this spec lists each migration by **name, purpose and order within its wave only**. The implementer assigns the real `YYYYMMDDHHMMSS_` prefix when the wave is built: later than every migration already applied (check the newest file in `supabase/migrations` and `supabase migration list`), strictly increasing in the listed order, and in the actual build order. The same rule applies to any hotfix migration written while the program runs. `supabase db push` refuses a file that sorts before the newest applied one.
- **Local SQL (non-destructive harness):** only against the scratch database `attune_spec3a`, only through `psql`. Never run `scripts/local_pg_setup.sh` (it runs `dropdb` and `createdb`) or `scripts/local_pg_grants.sql` against it. The step-by-step procedure is in §7.1.
- **Environment:** this spec reads and sets no `attune_environment` setting. "Production" in the checklists means the currently linked Supabase project, which is the dev/testing project until the owner's launch switch.
- **Commits and deploys:** no commits, no deploys and no `supabase db push` by the implementer. The owner does those from the checklists below.
- **Libraries:** Riverpod, Supabase and GoRouter as they are now. No new packages.

---

## 1. Goal and non-goals

### Goal
- Forums disappear from the app completely: no tab, screen, route, compose option, manual topic, carousel card, copy, push or job.
- Every server path that could create, read or announce forum content is shut, and is shown to be shut.
- The forum schema is then dropped cleanly, leaving no dangling reference in code, SQL, crons or edge functions.
- Opinions, polls, tags, reports, bans, mutes and in-chat Games behave exactly as before.

### Non-goals
- **Any Opinions change beyond removing the Forums entry points.** Handles, author pages, reactions, status labels and the report thresholds stay as they are. The Opinions redesign (Spec 1 W8) is deferred and its number is held empty. Spec 1 W9 adds only the content filter on the six writers, the "Need support now?" link, the at-risk report reason, review queue v0 and the two restored moderation notices (S1 D17, §5.7).
- **Renaming the kept "forum" objects.** `forum_reports` stays `forum_reports` and `enqueue_forum_notification` stays as it is. A rename would rewrite every Opinions RPC body for no user-visible gain. Spec 1 W9 re-creates some of them but renames nothing (S1 §5.7), so the names stay.
- **Restoring the Opinions removal and ban notices**, which are already missing today (§10 F-1). That is an Opinions behaviour change, so Spec 1 W9 does it (S1 D17). W3 then keeps whatever the live body does.
- **Moving forum content into Opinions.** There are no users, so there is nothing to move, and there is no "Debates are now polls" card.
- **Cleaning the forum-only optional parameters of `UniversalBubble` and `ChatTextField`.** Chat and Games use those widgets.
- **Comment-only mentions of forums** in files this spec does not otherwise edit (06 §2.5.2 lists them). They stay as they are, to keep the diff surgical.
- **`ATTUNE_MASTER_SPEC.md`** (§9's "Nested Forums area" and decision 11's wording). These go to Spec 1 W10's approved doc amendments as one line: "Forums retired 2026-10, Spec 3". `ATTUNE_SOUL.md` and `ATTUNE_THESIS.md` are never edited.
- **The `process-scheduled-notifications` payload allowlist** (`forum_post_id`, `topic_id`). Redeploying the dispatcher for every push type to remove two inert keys isn't worth the risk.
- **The stale `forum_feed_cache_*` SharedPreferences keys on test devices.** They read as a miss, so they're harmless. Cleaning them would mean touching a startup path.
- **Games**: anything under `lib/features/games/**` or `lib/features/community/**`, the game routes, `ChatScreen`'s game entry points and `report_custom_question`.

---

## 2. What the code check found (where it differs from 06)

| # | Finding | Consequence |
|---|---|---|
| V1 | `discover_feed_screen.dart:164` calls `CreateContentChooser.show(context:, backgroundColor:, onOpinionPosted:)`. It never passes `onTopicSubmitted`. | **No edit.** It compiles unchanged once `show()` keeps those three parameters. |
| V2 | `chat_docs.dart:56` has user-visible manual text: "…like Opinions and Forums." 06 missed it. | Edited in W1. |
| V3 | The only `anon` grant on `get_post_poll(uuid, uuid)` is in a **forum** migration (`20260821120000_public_forum_reads.sql:40`), yet guest Opinions polls depend on it. | **W2 must not revoke it.** W3 keeps its signature so the grant survives. A contract pins it. |
| V4 | `activate_pending_topics()` and `expire_old_topics()` are EXECUTE-able by `authenticated` (`20260716120000:851-852`): any signed-in user can run the activation sweep. | Revoked in W2. |
| V5 | The forum client writes **directly to tables** (`topic_votes`, `forum_post_likes`, `topic_impressions`, `user_forum_sides`, `forum_posts`) and reads both views, not only RPCs. | W2 revokes table and view privileges as well as EXECUTE. |
| V6 | Three kept tables point into forum tables: the FKs `post_polls_topic_id_fkey`, `forum_reports_forum_post_id_fkey` and `forum_reports_topic_id_fkey`. They also carry forum-only indexes and constraints: `post_polls_one_parent`, `post_polls_unique_topic`, `idx_post_polls_topic`, `forum_reports_check`, `forum_reports_unique_reporter_forum_post`, `forum_reports_unique_reporter_topic`, `idx_forum_reports_forum_post_id`, `idx_forum_reports_topic_id`, and the partial index `idx_scheduled_notifications_forum_activity`. All verified on `attune_spec3a`. | W3 handles each one explicitly. |
| V7 | `get_post_poll` and `private.create_poll_for_post` read and write `post_polls.topic_id`. | Both are replaced in the same transaction that drops the column (W3 step 4). |
| V8 | **Pre-existing defect:** the live `admin_confirm_content_removal` (last defined in `20260802120000`) no longer enqueues `forum_content_removed` or `forum_posting_banned`. The `20260727120000` version did, and the `20260802` rewrite dropped both calls. Confirmed on `attune_spec3a`: the function body has no `enqueue_forum_notification` call. | Not fixed here (§10 F-1); Spec 1 W9 restores both notices (S1 D17) before W3 runs. W3 preserves the live behaviour exactly, whichever body is live. |
| V9 | `test/widget_test.dart` overrides **the forum feature's own** `supabaseClientProvider` (`forum_providers.dart:14`), one of nine same-named providers, so that `ForumsSection.initState` can run. | The override and its fakes are deleted with `ForumsSection`. |
| V10 | The Stories handoff deploy command (`docs/reviews/2026-10-24-stories-handoff.md:105-113`) names `activate-topics` and `forum-quiet-check`. | W2 checklist step 0, and risk R12. |
| V11 | The database holds exactly **29 forum-only functions**, plus **3 shared functions** that touch forum tables: `assert_can_post`, `admin_confirm_content_removal` and `enqueue_forum_notification` (`pg_proc` scan of `attune_spec3a`). | §3.9 lists all 32. |
| V12 | `attune_spec3a` has the crons `activate-topics-sweep` and `forum-quiet-check`. `mark-quiet-forums` exists only in production; it was registered by hand as jobid 3. | W2 removes them by name, then sweeps by command pattern. |
| V13 | The manual registers 35 modules on today's `main`. Without `ForumDocs` there are 34, and the guard needs at least 33. Spec 1 and Spec 2 register more topics later, so the total moves. Nothing links to the topic id `forums`: no related-topic entry, no flag entry, no `getById('forums')`. | Unregistering it is safe. The test asserts the forum topic is absent and the guard floor holds; it never pins an exact count (§7.4). The intro and login carousels lose the card automatically (`visibleModules`). |
| V14 | All forum push producers write to `scheduled_notifications`, which is push-only. `in_app_notifications` is written only by the chat outbox and `evaluate-ask2-eligibility`. | The in-app inbox holds no forum rows, so nothing there needs routing. |
| V15 | No platform deep link names a forum path: nothing in AndroidManifest, Info.plist or `main.dart`'s `_handleDeepLink` (auth, planning and invite only). | No route stubs needed (§5). |

---

## 3. Inventory (exhaustive)

### 3.1 Client files deleted (W1): 21 files

| Path | What it is | Action | Reason |
|---|---|---|---|
| `lib/features/forums/data/cache/forum_feed_cache.dart` (66 lines) | `ForumFeedCache`, `forumFeedCacheProvider`, `enum ForumFeed` | delete | Forum-only. Its `FeedCacheStore` base stays. |
| `lib/features/forums/data/models/forum_post_model.dart` (78) | `ForumPostModel` | delete | Forum-only |
| `lib/features/forums/data/models/topic_model.dart` (176) | `TopicModel` | delete | Forum-only. Its last outside users are the router and tag browse, both edited. |
| `lib/features/forums/data/repositories/forum_repository.dart` (477) | `ForumRepository`: 22 forum RPCs plus direct table access | delete | Forum-only |
| `lib/features/forums/presentation/providers/forum_providers.dart` (679) | 23 providers and 5 notifiers (§3.4) | delete | Forum-only |
| `lib/features/forums/presentation/screens/contributing_forums_screen.dart` (121) | Contributing tab | delete | Forum-only |
| `lib/features/forums/presentation/screens/debate_room_screen.dart` (799) | Debate room | delete | Forum-only |
| `lib/features/forums/presentation/screens/forum_insight_screen.dart` (867) | Forum Insight | delete | Forum-only |
| `lib/features/forums/presentation/screens/forums_explore_screen.dart` (312) | Explore tab | delete | Forum-only |
| `lib/features/forums/presentation/screens/forums_section.dart` (248) | `ForumsSection`, the Forums side of the Opinions tab | delete | Forum-only |
| `lib/features/forums/presentation/screens/side_selection_screen.dart` (280) | FOR / AGAINST / browse picker | delete | Forum-only |
| `lib/features/forums/presentation/screens/submit_topic_screen.dart` (242) | Topic composer | delete | Forum-only |
| `lib/features/forums/presentation/widgets/forum_card.dart` (317) | `ForumCard` | delete | Forum-only |
| `lib/features/forums/presentation/widgets/forum_card_subdetails.dart` (96) | `ForumCardSubDetails` | delete | Forum-only |
| `lib/features/forums/presentation/widgets/forum_post_bubble.dart` (526) | `ForumPostBubble`, a `UniversalBubble` caller | delete | Forum-only. `UniversalBubble` itself stays. |
| `lib/features/forums/presentation/widgets/mini_container_indicator.dart` (54) | `MiniContainerIndicator` | delete | Forum-only |
| `lib/features/forums/presentation/widgets/topic_impression_tracker.dart` (131) | `TopicImpressionTracker`, `WidgetsBindingListener` | delete | Forum-only (no outside users) |
| `lib/features/forums/presentation/widgets/topic_voting_card.dart` (307) | `TopicVotingCard` | delete | Forum-only |
| `lib/home/widgets/forum_home.dart` (29) | `ForumHome`, already unused | delete | Dead code |
| `lib/app/documentations/user_manual/data/forum_docs.dart` (203) | `ForumDocs`, manual topic id `forums` | delete | Documents a removed feature |
| `test/features/forums/forum_feed_cache_test.dart` (294) | Forum cache test | delete | Its subject is deleted |

Every outside import of `lib/features/forums/**` was checked. There are exactly four: `app_router.dart:35-38`, `opinions_tab.dart:9-11`, `tag_browse_screen.dart:5-7` and `create_content_chooser.dart:4`, plus `test/widget_test.dart:11`. No export barrel re-exports a forum file. Every shared file the forum code imports still has at least one other user once Forums is gone (each counted by grep), so none becomes orphaned.

### 3.2 Client files edited (W1): 26 files

| Path : lines | What changes | Reason |
|---|---|---|
| `lib/core/notifications/config/notification_config.dart:163-172` | The three retired types route to `RouteNames.home` unconditionally. Lines 185-192 (`forum_content_removed`, `forum_posting_banned`) are unchanged. | §5. This is done first, so the compiler then proves no case still names a removed route. |
| `lib/app/routing/app_router.dart:35-38, 245-247, 549-599` | Remove the four forum imports, the three `RouteNames` constants and the three `GoRoute`s. Every other route, including all Games routes, is untouched. | The routes go |
| `lib/features/opinions/presentation/screen/opinions_tab.dart` | See W1 step 3. Remove imports 9-11 and the outer `TabController`, its listener, mixin, `initState` and `dispose` (28-53). `build` returns the same outer `Scaffold` (same `colorScheme.onBackground` background) with `_OpinionsSection(isAuthenticated:)` as its body: no `IndexedStack`, no `AnimatedBuilder` (55-83). Drop `_OpinionsSection.outerTabController` (87-93). Drop the FAB's `onTopicSubmitted` (202). Drop the `SliverAppBar.bottom` Opinions/Forums tab row (332-345). Correct the `didUpdateWidget` comment (129-136) to say the section is kept alive by the home shell's keep-alive tab page, not by the removed `IndexedStack`. Following/Discover, guest-lands-on-Discover (115-119), the sign-in flip (137-139), the inner nav-visibility reset, scroll-to-top, the leading row, Tags and search are all unchanged. | The Forums tab and the outer bar go |
| `lib/core/widgets/create_content_chooser.dart` | `show({context, backgroundColor, onOpinionPosted})` opens `OpinionComposeScreen(onPosted: onOpinionPosted)` directly in the same bottom sheet as today. Delete the `SubmitTopicScreen` import (4), `onTopicSubmitted` (24), the `_CreateChoice` enum, `_lastChoice`, the switch (37-53) and `_CreateContentChooserSheet` (67-120). Rewrite the class doc as a single direct compose entry. The class name stays, so callers compile unchanged. | A one-option chooser is an extra tap for nothing (decision D1) |
| `lib/core/widgets/create_content_fab.dart:6-19, 26, 31-37, 43, 62` | Remove `onTopicSubmitted` (field, parameter and pass-through) and the forum wording in the doc comments. `heroTag` stays required. The guest snackbar is unchanged. | Topic submission goes |
| `lib/features/opinions/presentation/screen/tag_browse_screen.dart` | One list instead of two tabs. Remove imports 5-7, `SingleTickerProviderStateMixin` and the `TabController` (43-57), `_handleTopicScroll` (94-100), `topicsAsync` (108), the `SimpleTabs` (181-194), the `TabBarView` with its second `Builder` (201-255; the body becomes the opinions `Builder`), and `_buildTopicList` (308-345). The `bottom:` holds only the Follow button, with `preferredSize` matched to that row. Update the class docs (16-19, 29-33). Opinion list, follow, refresh, load-more and empty state are unchanged. | The tag-browse Forums tab goes |
| `lib/features/opinions/presentation/screen/tag_search_screen.dart:57` | `'Find opinions and forums using a tag'` → `'Find opinions using a tag'` | Copy |
| `lib/features/onboarding/presentation/widgets/profile_setup_step.dart:22` | `'… Opinions and forums stay anonymous.'` → `'Use the name you want to see in chat. Opinions stay anonymous.'` | Copy (shared with Spec 1, §9) |
| `lib/app/documentations/user_manual/data/manual_documentation_registry.dart:22, 133` | Remove the `forum_docs.dart` import and the `ForumDocs()` entry | Manual topic goes (the guard's floor of 33 still holds) |
| `lib/app/documentations/user_manual/data/chat_docs.dart:56` | "…like Opinions and Forums." → "…like Opinions." | Copy (V2) |
| `lib/i10n/app_en.arb:321` | `mutedItemSubtitle` → `"Anonymous Opinions accounts you've muted"` | Copy |
| `lib/i10n/app_de.arb:326` | → `"Anonyme Opinions-Konten, die Sie stummgeschaltet haben"` | Copy |
| `lib/i10n/app_es.arb:325` | → `"Cuentas anónimas de Opinions que has silenciado"` | Copy |
| `lib/i10n/app_fr.arb:326` | → `"Comptes anonymes d'Opinions que vous avez mis en sourdine"` | Copy |
| `lib/i10n/app_it.arb:326` | → `"Account anonimi di Opinions che hai silenziato"` | Copy |
| `lib/i10n/app_pt.arb:326` | → `"Contas anônimas do Opinions que você silenciou"` | Copy |
| `lib/i10n/generated/app_localizations.dart:1111` and `app_localizations_{en,de,es,fr,it,pt}.dart:541` | The same strings, edited by hand. There is no `l10n.yaml`; the generated files are checked in. | Kept in step with the ARB files |
| `lib/architecture/FORUM.md` | A retirement banner at the top, plus a one-line "Retired (Spec 3, 2026-10)" note under §5 and §6 and above the forum rows of §9 and §10. Banner text: "Forums retired 2026-10 (Spec 3): screens and pushes removed in W1, producers stopped in W2, tables dropped in W3. §4, §7 and §8 still describe Opinions." | §4 still documents Opinions (synthesis §6 keep row) |
| `test/widget_test.dart:10-11, 24-47, 61` | Remove the forum import, the `supabase_flutter` import, `_AnonymousAuth`, `_AnonymousSupabase` and the `supabaseClientProvider` override. Add `expect(find.text('Forums'), findsNothing)`. Every other expectation is unchanged. | Its only reason was `ForumsSection` (V9) |
| `test/core/notifications/notification_tap_routing_test.dart:24-37` | Delete the forum payload group. The 36-questions and opinion groups stay. | Replaced by a behavioural test (§7) |

Not edited, and why:
- `discover_feed_screen.dart`: see V1.
- `home_screen.dart`: the tab id `opinions` and `Icons.forum_outlined` are an Opinions icon, not Forums.
- `intro_screen.dart` and `login_profile.dart`: they read the registry.
- `opinions_docs.dart`: no forum text, and its "sourced from FORUM.md" comment stays true.
- `settings_data.dart`: it reads the l10n key.
- `manual_content_guard_test.dart`: the floor of 33 still holds (34 modules on today's `main`).

### 3.3 Routes, route names and deep links

| Item | What it is | Action | Reason |
|---|---|---|---|
| `RouteNames.debateRoom = '/debateRoom'`, `GoRoute` name `debateRoom` (record extra `topicId, topicTitle, userSide, initialTopic`) | Debate room route | delete (W1) | Screen deleted |
| `RouteNames.sideSelection = '/sideSelection'`, name `sideSelection` (extra `TopicModel`) | Side picker route | delete (W1) | Screen deleted |
| `RouteNames.forumInsight = '/forumInsight'`, name `forumInsight` (extra `String topicId`) | Insight route; the target of forum pushes | delete (W1) | Screen deleted. Pushes re-routed first (§5). |
| Push payload key `topic_id` (`forum_topic_activated`, `forum_activity`, `forum_quiet`) | Push deep link | ignored (W1). The key stays in the dispatcher allowlist. | §5 |
| Realtime broadcast channels `topic-counts:<topic_id>` and `post-counts:<post_id>` | Live forum counts | client subscribers deleted (W1); server senders dropped (W3, inside the counter functions) | Forum-only. `opinion-counts` and `CountBroadcastChannel` stay. |
| Platform deep links (Android intent filters, iOS associated domains, `main.dart` `_handleDeepLink`) | None name a forum path (V15) | none | Nothing to remove; no redirect stubs (D5) |

### 3.4 Providers and widgets (all deleted with their files in W1)

**Providers (`forum_providers.dart`):** `supabaseClientProvider` (the forum copy), `forumRepositoryProvider`, `currentUserStatusProvider`, `submitTopicProvider`, `forumsExploreTagFilterProvider`, `votingTopicsProvider`, `activeForumsProvider`, `quietForumsProvider`, `castTopicVoteProvider`, `recordTopicImpressionProvider`, `recordTopicVisitProvider`, `joinForumProvider`, `forumPostsProvider`, `submitForumPostProvider`, `likeForumPostProvider`, `unlikeForumPostProvider`, `contributingForumsProvider`, `topicDetailsProvider`, `reportForumProvider`, `reportForumPostProvider`, `forumTopicsByTagProvider`, `topicLiveCountsProvider`, `postLikeLiveCountProvider`. **Plus** `forumFeedCacheProvider` (cache file). Notifiers: `VotingTopicsNotifier`, `ActiveForumsNotifier`, `QuietForumsNotifier`, `ContributingForumsNotifier`, `ForumTopicsByTagNotifier`.

**Widgets and classes:** `ForumsSection`, `ForumsExploreScreen`, `ContributingForumsScreen`, `DebateRoomScreen`, `SideSelectionScreen`, `ForumInsightScreen`, `SubmitTopicScreen`, `ForumCard`, `ForumCardSubDetails`, `ForumPostBubble`, `MiniContainerIndicator`, `TopicImpressionTracker`, `WidgetsBindingListener`, `TopicVotingCard`, `TopicModel`, `ForumPostModel`, `ForumRepository`, `ForumFeedCache`, `TopicLiveCounts`, `ForumHome`, `ForumDocs`. Also the private chart, legend, poll-results, side-badge and replies-sheet classes inside `forum_insight_screen.dart` and `forum_post_bubble.dart`.

Outside the forum folder, the only users were `votingTopicsProvider` (`opinions_tab.dart:10, 202`) and `forumTopicsByTagProvider`, `TopicModel` and `ForumCard` (`tag_browse_screen.dart`). Both files are edited.

### 3.5 Tests

| Path | Action | Wave | Reason |
|---|---|---|---|
| `test/features/forums/forum_feed_cache_test.dart` | delete | W1 | Subject deleted |
| `test/widget_test.dart` | edit | W1 | V9 |
| `test/core/notifications/notification_tap_routing_test.dart` | edit | W1 | Forum group removed |
| `test/core/notifications/retired_forum_push_routing_test.dart` | **new** | W1 | §5 behaviour |
| `test/features/opinions/opinions_tab_shell_test.dart` | **new** | W1 | Opinions shell regression |
| `test/features/opinions/tag_browse_screen_test.dart` | **new** | W1 | Tag browse regression |
| `test/core/widgets/create_content_chooser_test.dart` | **new** | W1 | Direct compose |
| `test/architecture/no_forum_references_test.dart` | **new** (W1); extended in W2 and W3 | W1–W3 | No dangling references |
| `supabase/tests/forum_retirement_contracts.sql` | **new** (W2); extended in W3 | W2–W3 | Producers shut; Opinions intact; schema gone |
| `supabase/tests/security_lockdown_contracts.sql:17` | edit: the array becomes `['public.opinion_tags', 'public.tags']` | W3 | `forum_topic_tags` no longer exists |
| `test/core/widgets/universal_bubble_test.dart:329, 500-608` ("forums-shaped bubble" guards) | **keep** | — | They protect `UniversalBubble` for chat and Games |
| `test/app/theme/design_tokens_test.dart:11` | **keep** | — | Comment only; the token is shared |
| `test/app/documentations/manual_content_guard_test.dart:24` (≥ 33) | **keep** | — | The floor of 33 still holds |
| `supabase/tests/data_export_contracts.sql:229` (no `forum` section) | **keep** | — | Still the rule |
| `supabase/tests/account_deletion_contracts.sql:74-76` (opinion poll fixture) | **keep** | — | Uses `opinion_id` only, so it stays valid after W3 |

### 3.6 Edge functions, crons and operator scripts

| Item | What it is | Action | Wave |
|---|---|---|---|
| `supabase/functions/activate-topics/index.ts` (119 lines) | Hourly: `activate_pending_topics`, `expire_old_topics`, then `enqueuePush(type 'forum_topic_activated')` to voters | undeploy and delete the folder | W2 |
| `supabase/functions/forum-quiet-check/index.ts` (90) | Every 2 h: scans `forum_topics`, calls `notify_quiet_topic` (queues `forum_quiet`) | undeploy and delete the folder | W2 |
| Cron `activate-topics-sweep` `'23 * * * *'` | `invoke_edge_function('activate-topics')`. Created in `20260907120000_register_scheduled_jobs.sql:44, 173-177`. | unschedule by name | W2 |
| Cron `forum-quiet-check` `'7 */2 * * *'` | `invoke_edge_function('forum-quiet-check')`. Created in `20260907120000:46, 185-189`. | unschedule by name | W2 |
| Cron **`mark-quiet-forums`** `'0 1 * * *'` (production jobid 3, untracked) | `UPDATE forum_topics SET status = 'quiet' …`. Registered by hand and patched by `supabase/sql/patch_mark_quiet_forums_null_last_post.sql`. | unschedule by name, then a command-pattern sweep | W2 |
| `supabase/sql/schedule_activate_topics.sql` (23) | Operator script | delete | W2 |
| `supabase/sql/schedule_forum_quiet_check.sql` (42) | Operator script | delete | W2 |
| `supabase/sql/patch_mark_quiet_forums_null_last_post.sql` (36) | Operator script | delete | W2 |
| `supabase/functions/process-scheduled-notifications/index.ts:102-109` | Allowlist keeps `forum_post_id` and `topic_id` | **keep** | — |
| `public.invoke_edge_function`, `public.scheduled_jobs_health()` | Shared cron helpers | **keep** | — |

### 3.7 Notification types

| Type | Producer | Client tap today | Action |
|---|---|---|---|
| `forum_topic_activated` | `activate-topics` edge function | push `/forumInsight` | W1: tap → home. W2: producer undeployed, pending rows cancelled. W3: historic rows deleted. |
| `forum_activity` | `private.queue_forum_activity_notifications` (called by `create_forum_post`) | push `/forumInsight` | W1: tap → home. W2: `create_forum_post` revoked, pending rows cancelled. W3: function and rows dropped. |
| `forum_quiet` | `notify_quiet_topic` (called by `forum-quiet-check`) | push `/forumInsight` | W1: tap → home. W2: producer stopped, pending rows cancelled. W3: function and rows dropped. |
| `forum_content_removed` | `admin_confirm_content_removal` (20260727 version; currently not produced, V8) | home | **keep**: this is Opinions moderation |
| `forum_posting_banned` | Same function | home | **keep**: Opinions ban notice |
| `opinion_liked`, `opinion_commented`, `opinion_comment_reply` | Opinions RPCs through `enqueue_forum_notification` | push `/opinionLoader` | **keep**, unchanged |

### 3.8 Manual topics and docs

| Item | Action | Reason |
|---|---|---|
| Topic id `forums` (sections `forum_what_it_is`, `forum_submitting`, `forum_debate_room`, `forum_insight`; FAQs `faq_forum_topic_live`, `faq_forum_side_choice`, `faq_forum_switch_side`, `faq_forum_reply_other_side`, `faq_forum_browse`, `faq_forum_anonymous`; order 20) | delete (W1) | Feature removed. No related-topic, flag or `getById` reference exists (V13). |
| Intro carousel (`intro_screen.dart:40`) and login carousel (`login_profile.dart:26`) | none; the Forums card disappears through `visibleModules` | Spec 1 owns these files (§9) |
| `chat_docs.dart:56` | edit (W1) | V2 |
| `lib/architecture/FORUM.md` | edit (W1): banners | Kept for §4 (Opinions) |
| `ATTUNE_MASTER_SPEC.md`, `SAFETY_SYSTEM_SPEC.md`, `THIS_OR_THAT.md` | none here. Master Spec: one amendment line handed to Spec 1 W10. | Doc amendments are batched there |
| `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md` | never edited | Binding |

### 3.9 Database objects

**Tables (8), forum-only, dropped in W3, client access revoked in W2:**

| Table | Created in | Client grants today | Notes |
|---|---|---|---|
| `forum_topics` | `20260716120000:107` | authenticated ALL; RLS | Referenced by `post_polls.topic_id` and `forum_reports.topic_id` (V6) |
| `topic_votes` | `20260716120000:130` | authenticated ALL | Written directly by the client |
| `topic_impressions` | `20260716120000:139` | authenticated ALL | Written directly by the client |
| `forum_posts` | `20260716120000:147` | authenticated ALL | Referenced by `forum_reports.forum_post_id` |
| `forum_post_likes` | `20260716120000:166` | authenticated ALL | Written directly by the client |
| `user_forum_sides` | `20260716120000:174` | authenticated ALL | Written directly by the client |
| `forum_topic_tags` | `20260731120000:79` | none (revoked; lockdown `20261017195000:16`) | Named in `security_lockdown_contracts.sql:17` |
| `forum_topic_visits` | `20260727130000:71` | authenticated ALL | — |

**Views (2):** `public_forum_topics` and `public_forum_posts` (`20260716120000:222, 240`; redefined in `20260730140000` and `20260809120000`). authenticated SELECT; **anon SELECT** from `20260821120000:33, 36`. Revoked in W2, dropped first in W3.

**Forum-only functions (29).** EXECUTE revoked in W2 from PUBLIC, anon, authenticated and service_role; dropped in W3.

| # | Signature | Client / anon today | Role |
|---|---|---|---|
| 1 | `public.activate_pending_topics()` | authenticated (V4) | Producer (`activate-topics`) |
| 2 | `public.expire_old_topics()` | authenticated (V4) | Producer |
| 3 | `public.mark_quiet_topics()` | service only | Documented fix, never scheduled |
| 4 | `public.notify_quiet_topic(uuid)` | service only | Producer (`forum-quiet-check`) |
| 5 | `private.queue_forum_activity_notifications(uuid, uuid)` | private | Producer (inside `create_forum_post`) |
| 6 | `public.record_forum_topic_visit(uuid)` | authenticated | — |
| 7 | `public.create_forum_post(uuid, text, text, uuid, text)` | authenticated | — |
| 8 | `public.create_forum_topic(text)` | authenticated | — |
| 9 | `public.create_forum_topic_with_poll(text, text[])` | authenticated | — |
| 10 | `public.edit_forum_post(uuid, text)` | authenticated | — |
| 11 | `public.attach_forum_topic_tags(uuid, text[])` | authenticated | — |
| 12 | `public.get_forum_topic_tags(uuid)` | authenticated + **anon** (`20260823130000:12`) | — |
| 13 | `public.get_forum_topics_by_tag(text, int, int)` | authenticated + **anon** (`20260822120000:24`) | — |
| 14 | `public.get_tags_for_forum_topics(uuid[])` | authenticated + **anon** (`20260821120000:28`) | — |
| 15 | `public.get_polls_for_topics(uuid[])` | authenticated | Called by the dead `PollRepository.getPollIdsForTopics` |
| 16 | `public.get_active_forums_filtered(text[])` | authenticated + **anon** (`20260821120000:26`) | — |
| 17 | `public.get_quiet_forums_filtered(text[])` | authenticated + **anon** (`20260821120000:27`) | — |
| 18 | `public.get_voting_topics_filtered(text[])` | authenticated + **anon** (`20260821120000:25`) | — |
| 19–25 | `public.increment_topic_upvote_count(uuid)`, `decrement_topic_upvote_count(uuid)`, `increment_topic_downvote_count(uuid)`, `decrement_topic_downvote_count(uuid)`, `increment_topic_post_count(uuid, text)`, `decrement_topic_post_count(uuid, text)`, `increment_topic_seen_count(uuid)` | authenticated | Counters; the vote counters broadcast `topic-counts:` |
| 26–27 | `public.increment_forum_post_like_count(uuid)`, `decrement_forum_post_like_count(uuid)` | authenticated | Broadcast `post-counts:` |
| 28 | `public.report_forum_post(uuid, text)` | authenticated | Writes `forum_reports.forum_post_id` |
| 29 | `public.report_forum_topic(uuid, text)` | authenticated | Writes `forum_reports.topic_id` |

**Shared functions that touch forum objects (kept; only their forum branches change in W3):**

| Function | Forum part | W3 change |
|---|---|---|
| `private.assert_can_post(uuid, text)` (`20260716140000:73-120`) | `ELSIF p_kind = 'topic'` reads `forum_topics`, plus a `forum_post` comment | Branch and comment removed. Opinion (5 per 24 h, 60 s cooldown), comment (20 per 24 h) and ban gate unchanged. |
| `public.admin_confirm_content_removal(text, uuid)` (live: `20260802120000:205-267`) | `ELSIF p_content_type = 'forum_post'` updates `forum_posts` | Branch removed, so `'forum_post'` now raises `invalid_content_type`. Everything else is byte-for-byte the live body at W3 time, which includes the two notices Spec 1 W9 restores (V8). |
| `private.enqueue_forum_notification(uuid, text, text, text, uuid, uuid, uuid)` | `p_forum_post_id` parameter written into metadata | **None**: the signature stays, and every Opinions caller uses named arguments |
| `public.get_post_poll(uuid, uuid)` | `p_topic_id` branch | Same signature, same anon and authenticated grants. The body matches `opinion_id` only and ignores `p_topic_id`. |
| `private.create_poll_for_post(uuid, uuid, uuid, text[])` | Inserts `topic_id` | Same signature. Raises `topic_polls_retired` (22023) if `p_topic_id` is not null; inserts `(opinion_id, created_by)`. |

**Kept tables: forum columns, constraints and indexes (W3 step 3 and 4):**

| Object | Action |
|---|---|
| `post_polls.topic_id` (FK `post_polls_topic_id_fkey`), `post_polls_one_parent` CHECK, `post_polls_unique_topic` UNIQUE, `idx_post_polls_topic` | Delete topic-poll rows (options and votes cascade). Drop the FK, then the constraint, unique and index, then the column. `opinion_id SET NOT NULL` keeps the "always has a parent" rule. |
| `forum_reports.forum_post_id`, `forum_reports.topic_id` (FKs `forum_reports_forum_post_id_fkey`, `forum_reports_topic_id_fkey`), `forum_reports_check`, `forum_reports_unique_reporter_forum_post`, `forum_reports_unique_reporter_topic`, `idx_forum_reports_forum_post_id`, `idx_forum_reports_topic_id` | Delete rows that target only a forum post or topic. Drop the FKs, the CHECK, the two unique indexes and the two indexes, then the two columns. Add `forum_reports_target_check CHECK (opinion_id IS NOT NULL OR comment_id IS NOT NULL)`. Opinion and comment columns, dedup indexes, RLS and grants are unchanged. |
| `idx_scheduled_notifications_forum_activity` (partial index on `metadata->>'type' = 'forum_activity'`) | Drop |
| `scheduled_notifications` rows with `metadata->>'type'` in the three retired types | W2: `pending` → `cancelled`. W3: deleted. |

**Grants revoked in W2 (so old builds fail closed):**
- EXECUTE on the 29 functions;
- ALL on the 8 tables and 2 views, from PUBLIC, anon, authenticated and service_role. **Not** revoked: `get_post_poll` (V3) and every function in §4.

### 3.10 Data export and account deletion

| Item | Today | Action |
|---|---|---|
| Account deletion (`delete-account` edge function) | Forum rows cascade from `auth.users` (`submitted_by` / `user_id ON DELETE CASCADE`); the function names no forum table | **none.** After W3 there is nothing to cascade. `account_deletion_contracts.sql` must stay green. |
| Data export (`build-data-exports`, `20261018120000_data_export.sql`) | No forum section; the contract forbids one (`data_export_contracts.sql:229-233`) | **none.** The contract stays as it is. |

### 3.11 Explicitly not touched
- Games: all of `lib/features/games/**`, `lib/features/community/**`, the game routes in `app_router.dart`, `ChatScreen`'s game entry points, `game_message_bubble.dart`, `report_custom_question` and `DocumentationRegistry`'s `games` related topics.
- `home_screen.dart` (the redirect latch), `home_widget.dart`, `main.dart`, `OnboardingStore`, `onesignal_service.dart`.
- `opinion_*` screens, cards and repositories other than the files in §3.2.
- `profiles.relationship_status`, `profiles.banned_until`, `profiles.confirmed_violation_count`, `opinion_author_handle`, `private.is_priority_reason`. Spec 1 W1 guards the last two profile columns against client writes (cross-spec S-1); `admin_confirm_content_removal` writes them as a definer under service role, so contract E's ban ladder keeps passing, and W3 re-runs it to prove that.

---

## 4. Keep list (Opinions, chat or Games use these)

| Kept object | Who uses it | Why it stays |
|---|---|---|
| `forum_reports` table (opinion and comment columns, `reason`, `priority`, `status`, dedup indexes `forum_reports_unique_reporter_opinion` and `_comment`, RLS `forum_reports_insert_own` / `forum_reports_no_read`) | `report_opinion`, `report_opinion_comment` | It holds every Opinions report. Only its forum columns go (W3). |
| `public.admin_confirm_content_removal(text, uuid)`, `profiles.banned_until`, `profiles.confirmed_violation_count` | Moderation (service role, SQL editor) | Opinions removals and the 3-strike 7-day ban. Only the `forum_post` branch goes. |
| `private.assert_can_post(uuid, text)` | `create_opinion`, `create_opinion_comment`, and through them the poll and quote variants | Opinions rate limits and ban gate. Only the `topic` branch goes. |
| `private.enqueue_forum_notification(…)` | Every Opinions notification (like, comment, reply, repost, quote, moderation) | Renaming it would touch every caller |
| Notification types `forum_content_removed`, `forum_posting_banned` and their tap cases (`notification_config.dart:185-192`) | Opinions moderation notices | Opinions |
| `post_polls`, `poll_options`, `poll_votes`; `cast_poll_vote`, `retract_poll_vote`, `get_post_poll` (**with its anon grant**), `get_polls_for_opinions`, `create_opinion_with_poll`, `private.create_poll_for_post` | Polls on opinions, including for guests | Polls are the successor to debates. In W1–W2 the topic handling is kept untouched; W3 removes only the topic column and branches. |
| `PollCard`, `PollComposer`, `PollModel`, `PollRepository`, `pollProvider`, `PollTarget` | Opinions UI | `PollTarget.topic` and `getPollForTopic` stay as inert code (they reference kept objects). Only `getPollIdsForTopics`, whose RPC W3 drops, goes in W3. |
| `tags`, `opinion_tags`, `tag_follows`; `get_all_tags`, `attach_opinion_tags`, `get_opinion_tags`, `get_tags_for_opinions`, `get_opinions_by_tag`, `follow_tag`, `unfollow_tag`, `get_followed_tags`; `TagChipRow`, `TagPicker`, `TagSearchScreen`, `TagBrowseScreen` | Opinion tags, guest tag browse | Opinions |
| `opinion_mutes`, `opinion_hides`, `MutedAuthorsScreen`, the Settings "Muted accounts" entry | Mute and hide | Opinions (only its subtitle copy changes) |
| `FeedCacheStore` (`lib/core/cache/feed_cache_store.dart`) | Opinion, Reflection Journal and Reminders caches | Shared |
| `ListviewLoadingShimmer` / `ForumSchimmer` (`shop_listview_loading_shimmer.dart`, `forum_shimmer.dart`) | 6 Opinions screens (11 call sites today, 10 after W1) | Shared; the name is cosmetic |
| `relationship_status_display.dart` | Opinion cards, comment threads, the chat locked screen | Shared |
| `count_broadcast_channel.dart`, `opinion-counts` broadcasts | Live opinion counts | Shared |
| `relative_time.dart`, `format_compact_count.dart`, `reply_avatar_stack.dart`, `card_inkwell.dart`, `bottom_sheet_header.dart`, `profile_avatar.dart`, `nav_visibility_provider.dart`, `semantic_container_widget.dart` | Opinions and chat | Each has non-forum users (grep count ≥ 1) |
| `ThemeColors.against`, `LightColors.against` | `couple_map/widget/presentation/region_map_painter.dart:17` | The couple map |
| `UniversalBubble` and `ChatTextField`, including their forum-only optional parameters | Chat, comments, **Games** (`game_message_bubble.dart`) | Don't clean them (synthesis §11) |
| `process-scheduled-notifications` allowlist keys `forum_post_id`, `topic_id` | Dispatcher | Inert after W3; not worth a redeploy |
| `CreateContentChooser` and `CreateContentFab` (class names) | Opinions "+" entry points | Kept as the single compose entry; any later compose option builds on it |
| `lib/architecture/FORUM.md` | §4, §7 and §8 document Opinions | Banners only |
| `public.invoke_edge_function`, `public.scheduled_jobs_health()` | Every cron | Shared |

---

## 5. Notification routing after removal

**Rule:** a tap on any retired forum push goes to **home**, never to a removed route, whatever its payload. This change is made **first** in W1, so the routes are removed only after nothing points at them.

New body for `notification_config.dart:163-172`. This is the load-bearing part:

```dart
case 'forum_topic_activated':
case 'forum_activity':
case 'forum_quiet':
  // Forums were retired (Spec 3, 2026-10-24). A push sent before the
  // producers stopped can still be tapped from the tray: home, never a
  // removed route.
  GoRouter.of(context).go(RouteNames.home);
  return;
```

**Why explicit cases instead of falling through to `default`:** the intent stays readable, a test can pin it, and a future type with a similar name can't silently land elsewhere.

**Every entry point uses this handler:** the OneSignal tap (`onesignal_service.dart:100`), the in-app banner and the inbox (`notification_inbox_screen.dart:158`) all call `config.onNotificationTap`. Forum producers never wrote `in_app_notifications` (V14), so the inbox has nothing to clean up.

| Situation | What happens |
|---|---|
| W1 build; a forum push already in the tray, sent before W2 | Tap → home |
| W1 build; a forum push queued between the W1 release and W2 (producers still running) | Delivered by the dispatcher; tap → home. W2 follows within the same week to stop this. |
| After W2 | No forum push is produced. Pending rows are `cancelled`, and the health check proves none are queued. |
| Pre-W1 build still installed, after W2 | Its Forums tab and its forum push target (`ForumInsightScreen`) open, and every forum read fails closed (permission denied → `ErrorStateWidget`). No data, no crash. Fix: install the W1 build. W3 is gated on every device having it. |
| Cold start from a tapped push | The same handler runs after the router has settled (existing OneSignal logic, unchanged); `go(home)` |
| `forum_content_removed` / `forum_posting_banned` | Unchanged: home |
| `opinion_*` | Unchanged: `push(/opinionLoader, extra: opinionId)` |

No redirect stubs for `/debateRoom`, `/sideSelection` or `/forumInsight` (D5): nothing outside compiled code can reach those paths (V15), and a stub would keep forum path strings alive.

---

## 6. The three waves

### 6.1 W1: client removal (one app release, no server change)

**Gate before starting:** none.

**Four tasks** (each a review unit, in this order): **T1** push routing and router (steps 1-2); **T2** Opinions shell, compose entry and tags (steps 3-5); **T3** manual, copy, l10n and FORUM.md (steps 6-7); **T4** deletions, remaining tests and the full run (steps 8-10).

**Steps, in this order:**
1. **Notification taps → home** (§5). Write `retired_forum_push_routing_test.dart` first, see it fail (a pushed `/forumInsight` instead of `/home`), then change lines 163-172. In the same step delete the forum payload group in `notification_tap_routing_test.dart`, since it asserts the old route.
2. **Router:** remove `app_router.dart:35-38, 245-247, 549-599`. Nothing else in the file changes.
3. **Opinions shell:** edit `opinions_tab.dart` as in §3.2. The visible result is that the Opinions/Forums tab row under the app bar disappears and Following/Discover sit directly under the app bar. Nothing else moves.
4. **Compose entry:** edit `create_content_chooser.dart` and `create_content_fab.dart`. Tapping "+" (FAB or app bar) opens the opinion composer directly. `onOpinionPosted` still invalidates the right feed and scrolls to top. The guest FAB still shows "Sign in to perform this action". The app-bar "+" keeps its current behaviour (it has no guest check today, and this spec doesn't add one).
5. **Tags:** edit `tag_browse_screen.dart` (one list) and `tag_search_screen.dart:57`.
6. **Manual:** unregister `ForumDocs` (registry lines 22 and 133), delete `forum_docs.dart`, edit `chat_docs.dart:56`, and add the FORUM.md banners.
7. **Copy:** `profile_setup_step.dart:22`; `mutedItemSubtitle` in the 6 ARB files and the 7 generated files.
8. **Delete** `lib/features/forums/**` (18 files), `lib/home/widgets/forum_home.dart` and `test/features/forums/forum_feed_cache_test.dart`.
9. **Tests:** edit `test/widget_test.dart` and add `no_forum_references_test.dart` (§7). The four regression tests are written test-first inside their tasks (push routing in T1; shell, chooser and tag browse in T2).
10. `flutter analyze` must show zero errors; run the full `flutter test`. The forum folder still names the removed route constants until step 8, so `flutter analyze` is clean only at the end of T4; T1-T3 are gated by their own targeted tests.

**Visible changes on the device (and only these):**
- No Forums tab.
- "+" goes straight to the composer.
- Tag pages show one list without tabs.
- No Forums manual topic or carousel card.
- Three copy lines: onboarding, tag search, Muted accounts.
- One manual sentence (Chat).

**Rollback:** revert the W1 change and ship a build. There is no data or server state to undo. After W2 has run, a rolled-back build shows Forums in its fail-closed error state, so rolling W1 back after W2 also needs the W2 rollback.

**Owner checklist (W1):**
1. Build and install the W1 build on **every** test device (iOS and Android). Note each device's build number; the W3 gate needs it.
2. **Stale-push check** (before W2, while producers still run): insert one pending row for your own test account, wait for the dispatcher, and tap the push. It must land on Home.
   ```sql
   insert into public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
   values ('<your auth user id>', 'immediate', now(), 'pending',
           jsonb_build_object('type','forum_activity','title','Forum check','body','Tap me','topic_id', gen_random_uuid()::text));
   ```
3. **Screens**, in light and dark, as guest and signed in, on a phone and on the iPad (ContentWidth column), at default and largest text size:
   - Opinions header: no tab row, Following/Discover directly below, no clipped or overlapping header.
   - Guest lands on Discover. Signing in mid-session jumps to Following.
   - Scroll a feed to hide the bottom nav, switch Following ↔ Discover: the nav comes back.
   - "+" (FAB and app bar) opens the composer. Posting refreshes the feed and scrolls to the top.
   - A tag page: Follow button, one list, pull to refresh, load more.
   - Manual list and intro carousel: no Forums.
   - Onboarding name step subtitle.
   - Settings → Muted accounts subtitle.
4. **Games smoke test:** open one chat game and send a game message (the `UniversalBubble` path).
5. Release note for testers: "Forums removed. Polls and tags in Opinions are unchanged."

### 6.2 W2: stop the producers (same week, after the W1 build is on every test device)

**Gate:** the W1 build is installed on every test device.

**Three tasks:** **T1** migrations 1-3, plus deleting the two edge-function folders and the 3 operator scripts; **T2** migration 4 and `forum_retirement_contracts.sql` sections A-E; **T3** the W2 additions to `no_forum_references_test.dart` and the full test run.

**Migrations, in order** (names and order only; the timestamp prefixes are assigned when the wave is built, see House rules):

1. **`forum_retire_scheduled_jobs.sql`**
   - **By name:** `PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job` for each of `'activate-topics-sweep'`, `'forum-quiet-check'` and `'mark-quiet-forums'`. This is the same idiom as `20260907120000:30-55`, and the local stub supports it.
   - **Pattern sweep:** then unschedule any remaining job whose `command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)'`. This catches a hand-registered copy under another name.
   - `RAISE NOTICE` names every job removed.
   - No exception swallowing: if an unschedule is refused, the push fails loudly.
2. **`forum_revoke_client_access.sql`**
   - `REVOKE ALL ON FUNCTION … FROM PUBLIC, anon, authenticated, service_role` for the 29 signatures in §3.9.
   - `REVOKE ALL ON TABLE …` for the 8 tables and 2 views, from the same roles.
   - service_role is included as defence in depth: a stale edge-function deploy from an old checkout fails at its first query instead of sending pushes.
   - A header comment lists what is deliberately **not** revoked: `get_post_poll` (V3) and every §4 object.
3. **`forum_cancel_queued_pushes.sql`**
   ```sql
   UPDATE public.scheduled_notifications
   SET status = 'cancelled', source_key = NULL, last_error = 'forum_retired', updated_at = now()
   WHERE status = 'pending'
     AND metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
   ```
   This is the existing cancel idiom (`20261018140400_put_away_gently.sql:15-17`). `processing` rows are left to finish, because the dispatcher's status update requires `status = 'processing'`.
4. **`forum_retirement_health.sql`**: `public.forum_retirement_health()`.
   - Returns `(check_name text, ok boolean, detail text)`; `STABLE SECURITY DEFINER SET search_path = ''`.
   - `REVOKE ALL … FROM PUBLIC, anon, authenticated; GRANT EXECUTE … TO service_role` (the same posture as `scheduled_jobs_health()`).
   - Missing objects are resolved with `pg_catalog.to_regprocedure` and `to_regclass`, so the same function stays valid after W3.

   | check_name | ok when |
   |---|---|
   | `forum_cron_unscheduled` | No `cron.job` row has one of the 3 names or matches the step-1 pattern. `detail` lists offenders. |
   | `forum_pushes_not_queued` | No `scheduled_notifications` row with status `pending` or `processing` has one of the 3 retired types |
   | `forum_rpcs_closed_to_clients` | For each of the 29 signatures: it doesn't exist, or neither anon nor authenticated has EXECUTE |
   | `forum_tables_closed_to_clients` | For each of the 10 relations: it doesn't exist, or anon and authenticated have no SELECT, INSERT, UPDATE or DELETE |
   | `opinions_shared_objects_present` | These exist: `forum_reports`, `post_polls`, `poll_options`, `poll_votes`, `tags`, `opinion_tags` and `tag_follows`. So do `private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)`, `private.assert_can_post(uuid,text)` and `public.admin_confirm_content_removal(text,uuid)`. `public.get_post_poll(uuid,uuid)` is executable by **both** anon and authenticated, and `public.create_opinion_with_poll(text,text[])` by authenticated. |

   This is the "no forum cron" health check, plus four companions. It runs on demand, not as a cron (D9): cron failures go unread here (`20260931120000:7-12`), so the owner and the contract read it directly.

**Files:**
- **Deleted:** `supabase/functions/activate-topics/`, `supabase/functions/forum-quiet-check/` and the 3 `supabase/sql` scripts.
- **New:** the 4 migrations above and `supabase/tests/forum_retirement_contracts.sql`.
- **Extended:** `test/architecture/no_forum_references_test.dart` (server files, §7).

**Tests:**
- `forum_retirement_contracts.sql` sections A–E (§7.3) on `attune_spec3a`, after applying the 4 migrations with psql.
- The full contract loop.
- `flutter test` (the extended architecture test).

**Rollback** (only if forums had to come back, which no ruling foresees):
1. Re-grant with a new migration that replays, in file order, the last GRANT for each of the 29 functions and 10 relations. Generate the list with `grep -nE "^GRANT .*(forum|topic)" supabase/migrations/*.sql`, keeping only the §3.9 objects. Examples:
   - `20260716120000:426-441, 851-852` (tables, views, `activate_pending_topics`, `expire_old_topics`);
   - `20260716140000:591, 622, 722, 737`;
   - `20260727130000:90, 140, 355`;
   - `20260807120000:242, 354`;
   - `20260809120000:121, 187, 253`;
   - `20260821120000:25-36` (anon);
   - `20260822120000:24`;
   - `20260823130000:12`.
2. Restore the functions and redeploy. `PRE` is the commit just before the W2 deletion:
   ```
   PRE=$(git rev-list -n 1 HEAD -- supabase/functions/activate-topics/index.ts)^
   git checkout "$PRE" -- supabase/functions/activate-topics supabase/functions/forum-quiet-check supabase/sql
   supabase functions deploy activate-topics forum-quiet-check
   ```
3. Re-run the `cron.schedule` calls from `20260907120000:173-189`, and the restored `supabase/sql/patch_mark_quiet_forums_null_last_post.sql`.
4. Cancelled pushes are not restored; they're stale.
5. Roll W1 back too (§6.1).

**Owner checklist (W2):**
0. **First:** if the Stories handoff edge-function deploy (`docs/reviews/2026-10-24-stories-handoff.md` §3) hasn't been run, run it **before** this wave. Otherwise remove `activate-topics` and `forum-quiet-check` from that command: once their folders are gone the deploy fails with a missing entrypoint (V10).
1. Snapshot the crons in the SQL editor and keep the output:
   ```sql
   select jobid, jobname, schedule, active, left(command, 120) from cron.job order by jobname;
   ```
   Expect `mark-quiet-forums` (jobid 3) in production.
2. `supabase db push` (applies the 4 W2 migrations).
3. Undeploy the two functions from the repo root (the CLI uses the linked project):
   ```
   supabase functions delete activate-topics
   supabase functions delete forum-quiet-check
   supabase functions list
   ```
   Neither name may appear in the list.
4. Verify:
   - `select * from public.forum_retirement_health();` → every row has `ok = true`;
   - `select * from public.scheduled_jobs_health();` → no forum job;
   - Dashboard → Integrations → Cron: none of the three names.
5. **From now on, never run `supabase functions deploy` with no function names from a checkout older than W2.** That deploys every folder and would recreate the two functions. If it ever happens, step 3 undoes it, and the W2 revokes keep them from doing anything.

### 6.3 W3: drop (after Spec 2 W10, and after one release on every test device)

**Gate (all four must hold):**
- (a) Every test device runs a build ≥ the W1 build number recorded in the W1 checklist.
- (b) Supabase API logs for the last 7 days show **zero** requests to `/rest/v1/rpc/` for any of the 29 names, or to `/rest/v1/public_forum_*`, `/rest/v1/forum_*` (except `forum_reports`) or `/rest/v1/topic_*`. Any hit means an old build is still installed.
- (c) `forum_retirement_health()` is all `ok`.
- (d) Every Spec 1 (W1–W7, W9, W10, with their lettered sub-waves) and Spec 2 (W1–W10) migration is applied. Spec 1 W9's restored moderation notices (S1 D17) are among them.

**Three tasks:** **T1** migrations 1-3 (views, functions, tables); **T2** migrations 4-6 (kept-table columns, shared function branches, health v2); **T3** contract section F, the `security_lockdown_contracts.sql` edit, the `poll_repository.dart` tidy-up, the `FORUM.md` lines and the architecture-test change.

**Migration names:** the six migrations below are listed by name and order only. When W3 is built, give them timestamps later than every migration applied at that time (the newest file in `supabase/migrations` and `supabase migration list`), strictly increasing in the listed order (House rules). Any migration written after W3 follows the same rule.

**Coordination with Spec 1 W9:** Spec 1 W9 re-creates `admin_confirm_content_removal` (with the two moderation notices restored, S1 D17) and the two report RPCs, and adds the `'Someone may be at risk'` reason. It removes no forum branch and renames nothing (S1 §5.7). So the live bodies at W3 time differ from the migration files.
- W3 always rewrites from the **live** definition at W3 time (`pg_get_functiondef` on production and on `attune_spec3a`), never from the old migration files.
- Step 5 is always needed: the `forum_post` branch survives Spec 1 W9 inside the re-created body. The rewrite removes that branch only, so the restored notices stay.
- No rename of `forum_reports` is planned. If one happens anyway, steps 3–4 apply to the new name.

**Migrations, in order:**
1. **`forum_drop_views.sql`**: `DROP VIEW IF EXISTS public.public_forum_posts RESTRICT; DROP VIEW IF EXISTS public.public_forum_topics RESTRICT;`. RESTRICT everywhere in W3, so an unexpected dependency fails loudly instead of cascading. No function returns a view rowtype (checked).
2. **`forum_drop_functions.sql`**: `DROP FUNCTION IF EXISTS <sig> RESTRICT` for the 29 signatures in §3.9. This also removes the `topic-counts:` and `post-counts:` broadcast senders.
3. **`forum_drop_tables.sql`** (one transaction):
   - (i) `DELETE FROM public.post_polls WHERE topic_id IS NOT NULL` (poll options and votes cascade).
   - (ii) `DELETE FROM public.forum_reports WHERE opinion_id IS NULL AND comment_id IS NULL`.
   - (iii) `DELETE FROM public.scheduled_notifications WHERE metadata->>'type' IN ('forum_topic_activated','forum_activity','forum_quiet')`.
   - (iv) Drop every FK on a non-forum table whose `confrelid` is a forum table. The constraints are found through `pg_constraint`, so they're not hard-coded; expected: `post_polls_topic_id_fkey`, `forum_reports_forum_post_id_fkey`, `forum_reports_topic_id_fkey`.
   - (v) `DROP INDEX IF EXISTS public.idx_scheduled_notifications_forum_activity`.
   - (vi) `DROP TABLE IF EXISTS … RESTRICT` in this order: `forum_post_likes`, `forum_topic_tags`, `forum_topic_visits`, `topic_votes`, `topic_impressions`, `user_forum_sides`, `forum_posts`, `forum_topics`.
4. **`forum_kept_table_columns.sql`** (one transaction; this is the binding "post_polls.topic_id + CHECK" step):
   - (i) `CREATE OR REPLACE` `private.create_poll_for_post` and `public.get_post_poll` with unchanged signatures, as in §3.9. Re-assert the current ACLs explicitly: `create_poll_for_post` gets `REVOKE ALL FROM PUBLIC, anon, authenticated`; `get_post_poll` gets `REVOKE ALL FROM PUBLIC` and `GRANT EXECUTE TO anon, authenticated`.
   - (ii) `post_polls`: drop `post_polls_one_parent`, the `post_polls_unique_topic` constraint and `idx_post_polls_topic`; `DROP COLUMN topic_id RESTRICT`; `ALTER COLUMN opinion_id SET NOT NULL`.
   - (iii) `forum_reports`: drop `forum_reports_check`, `forum_reports_unique_reporter_forum_post`, `forum_reports_unique_reporter_topic`, `idx_forum_reports_forum_post_id` and `idx_forum_reports_topic_id`; `DROP COLUMN forum_post_id RESTRICT, DROP COLUMN topic_id RESTRICT`; `ADD CONSTRAINT forum_reports_target_check CHECK (opinion_id IS NOT NULL OR comment_id IS NOT NULL)`.
5. **`forum_shared_function_branches.sql`**: `CREATE OR REPLACE` `private.assert_can_post` and `public.admin_confirm_content_removal`.
   - The live bodies, minus the `topic` and `forum_post` branches only.
   - `SET search_path = ''` with fully qualified names.
   - ACLs unchanged: `REVOKE ALL … FROM PUBLIC, anon, authenticated`; service role only for the removal function.
   - The migration header quotes the "before" body it was built from, so review is a pure diff.
6. **`forum_retirement_health_v2.sql`**: redefine `forum_retirement_health()` with two more checks:
   - `forum_schema_dropped`: none of the 10 relations or 29 functions exists, and neither `post_polls.topic_id`, `forum_reports.forum_post_id` nor `forum_reports.topic_id` exists.
   - `no_code_references_forum_schema`: no `pg_proc.prosrc` in `public` or `private`, no `pg_views.definition` and no `cron.job.command` matches `\m(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum_topics|public_forum_posts)\M`.

**Also in W3:**
- `supabase/tests/security_lockdown_contracts.sql:17` drops `'public.forum_topic_tags'` from its array.
- `forum_retirement_contracts.sql` gains section F.
- `lib/architecture/FORUM.md` (Spec 3 owns this file): one status line under the W1 banner ("Schema dropped, Spec 3 W3") and one line in §4 naming Spec 1 W9's additions (content filter, at-risk reason, restored moderation notices).
- `lib/core/polls/data/repositories/poll_repository.dart`:
  - delete `getPollIdsForTopics` (lines 58-70; zero callers; it calls the dropped `get_polls_for_topics`);
  - update the class doc (6-10) and the `getPollForTopic` doc (32-33) to "topic polls retired (Spec 3); always returns null; kept so `PollTarget` never changes";
  - `poll_providers.dart` is not touched;
  - this client edit ships in the next app build and is safe with any server version.
- `no_forum_references_test.dart` drops its `get_polls_for_topics` allowance.

**Rollback:** none in place. W3 deletes data and schema. That is why it has a four-part gate and a backup. Recovery means restoring the dumps below into a scratch database and re-creating objects by hand.

**Owner checklist (W3):**
1. Confirm gate items (a)–(d).
2. Back up, and **don't commit** the files (they hold data):
   ```
   supabase db dump -f backup-before-spec3-w3-schema.sql
   supabase db dump --data-only -f backup-before-spec3-w3-data.sql
   ```
3. **Inventory:** run the scan below on production. It must list exactly the 29 functions in §3.9 plus `assert_can_post`, `admin_confirm_content_removal` and `enqueue_forum_notification`. Anything extra: stop, and add it to migration 2.
   ```sql
   select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','private') and p.prokind = 'f'
     and (p.proname ~ 'forum|topic' or p.prosrc ~ 'forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum')
   order by 1;
   ```
4. **Body check:** `select pg_get_functiondef('private.assert_can_post(uuid,text)'::regprocedure);` and the same for `public.admin_confirm_content_removal(text,uuid)`. Both must match the "before" bodies quoted in migration 5's header. If either differs, stop.
5. `supabase db push`.
6. `select * from public.forum_retirement_health();` → all 7 rows `ok`.
7. Install the W3 build (the poll tidy-up). **Opinions smoke test:**
   - Post an opinion with a poll.
   - Vote from a second account; results appear after voting.
   - As a guest, the poll shows with hidden counts.
   - Report an opinion and a comment; a second report of the same item is quietly deduplicated.
   - Edit within 15 minutes.
   - Mute an author.
   - Open a tag page.
8. In the SQL editor, as service role, confirm one test opinion removal:
   - `select * from public.admin_confirm_content_removal('opinion', '<test opinion id>');` returns `violation_count = 1` and queues one `forum_content_removed` row for the author (the notice Spec 1 W9 restored);
   - `'forum_post'` now raises `invalid_content_type`.

---

## 7. Testing

### 7.1 Full suite (every wave)
- `flutter analyze`: zero errors (the CI gate). For touched files: `flutter analyze <files> | grep -E '^\s*(error|warning) '` is empty.
- `flutter test`: the whole suite green. That includes the kept Games, chat, `universal_bubble_test.dart`, onboarding, login, manual and Stories tests.
- `dart format` only on the 5 new Dart test files.
- **SQL contracts: the non-destructive harness procedure.** This is the one rule for local SQL. `scripts/local_pg_setup.sh` is never run against `attune_spec3a`, because it runs `dropdb` and `createdb`.
  1. Confirm the target is the scratch database: `psql -X -d attune_spec3a -c 'select current_database()'`.
  2. Apply only the wave's new migrations, in their listed order, with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`. They are idempotent, so a re-run is safe. Each migration's own GRANT and REVOKE statements run with it. `scripts/local_pg_grants.sql` is not re-run, because its blanket grants would undo this spec's revokes.
  3. Run one contract: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Every contract ends in `ROLLBACK`, so nothing persists.
  4. Run every contract: `for t in supabase/tests/*.sql; do psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f "$t" || echo "FAIL $t"; done`. No `FAIL` lines.
  5. From-zero check, only into a **brand-new database name**, with `ATTUNE_TEST_DB` set explicitly: confirm the name is absent (`psql -lqt | cut -d'|' -f1 | grep -qw attune_spec3_fresh` must find nothing), run `ATTUNE_TEST_DB=attune_spec3_fresh scripts/local_pg_setup.sh --no-tests`, repeat step 4 with `-d attune_spec3_fresh`, then `dropdb attune_spec3_fresh`. Never leave `ATTUNE_TEST_DB` unset: the default is `attune_test`, which the script drops.
  6. CI's `sql-contracts` job, which builds from zero with `supabase start`, must also pass. On a fresh database `20260907120000` schedules the two crons and the W2 `forum_retire_scheduled_jobs` migration removes them, so section A holds from scratch.
- **Fixtures:** user ids with the `9f3a0000-` prefix and phones `+1555094xxxx`. Both were verified free on `attune_spec3a` (`count = 0`).

### 7.2 Opinions regression tests (Flutter, W1)

| Test | Asserts |
|---|---|
| `test/features/opinions/opinions_tab_shell_test.dart` (new) | Pump `OpinionsTab` with `currentUserIdProvider`, `userRelationshipStatusProvider`, `followingFeedProvider`, `discoverFeedProvider`, `myAuthorHandleProvider` and `sharedPreferencesProvider` overridden. **Guest:** Discover is selected, the text `Forums` is absent, exactly one `SimpleTabs` (Following/Discover), the FAB is present. **Signed in:** Following is selected. **Guest → signed in** in the same element: it jumps to Following. Tapping the app-bar "+" (tooltip `add opinions`) shows `OpinionComposeScreen` and no chooser row ("Share an opinion", "Start a forum topic"). No overflow exception at default and largest text scale. |
| `test/core/widgets/create_content_chooser_test.dart` (new) | `CreateContentChooser.show` opens `OpinionComposeScreen` directly, and its `onPosted` is the passed `onOpinionPosted`. As a guest, the `CreateContentFab` shows "Sign in to perform this action" and no composer. |
| `test/features/opinions/tag_browse_screen_test.dart` (new) | Overrides `opinionsByTagProvider` and `isTagFollowedProvider`. Shows `#slug`, the Follow button, opinion cards; empty state "No opinions tagged #slug"; no `TabBar`, `Forums` or `Opinions` tab labels; no overflow at default and largest text scale. |
| `test/core/notifications/retired_forum_push_routing_test.dart` (new) | A real `GoRouter` with routes `/`, `RouteNames.home` and `RouteNames.opinionLoader`, using `StateProbe` (`test/helpers/state_probe.dart`), as in `app_shell_keep_mounted_test.dart`. Calls `buildNanoEmbryoNotificationConfig().onNotificationTap` with an `AppNotification`. Each of `forum_topic_activated`, `forum_activity` and `forum_quiet`, with a `topic_id`, an empty one and none, lands on home. `forum_content_removed` and `forum_posting_banned` land on home. `opinion_liked` with an `opinion_id` lands on the opinion loader (pins Opinions routing). |
| `test/widget_test.dart` (edited) | The anonymous two-tab shell still renders Opinions, Chat, Following and Discover; `Forums` is absent; Chat → "Hello!" as today |
| Kept, unmodified, must stay green | `opinion_feed_cache_test.dart`, `opinion_feed_removal_test.dart`, `poll_model_test.dart`, `universal_bubble_test.dart`, the `test/app/documentations/*` tests, `onboarding_flow_test.dart`, `login_profile_test.dart`, all Games tests |

### 7.3 SQL contracts: `supabase/tests/forum_retirement_contracts.sql` (`BEGIN … ROLLBACK`, `RAISE EXCEPTION 'CONTRACT VIOLATED: …'`)

**W2 sections:**
- **A. Crons.** No `cron.job` row has one of the 3 names or matches the pattern. Then `cron.schedule('mark-quiet-forums', '0 1 * * *', 'select 1')` makes `forum_retirement_health()` report `forum_cron_unscheduled = false`; unschedule it again and it reports `true`. This proves the check itself works.
- **B. Grants.** For each of the 29 signatures, `has_function_privilege` is false for anon and for authenticated. For each of the 10 relations, `has_table_privilege` is false for SELECT, INSERT, UPDATE and DELETE.
- **C. Pushes.** Insert a pending `forum_quiet` row: the health check reports `forum_pushes_not_queued = false`. Mark it `cancelled`: `true`.
- **D. Keep-list sentinels.** `opinions_shared_objects_present = true`. `has_function_privilege('anon', 'public.get_post_poll(uuid,uuid)', 'EXECUTE')` is **true**. So is the anon EXECUTE on `get_discover_opinions(int,int,text[])`, `get_opinion_comments(uuid)`, `get_all_tags()`, `get_tags_for_opinions(uuid[])`, `get_opinions_by_tag(text,int,int)` and `get_opinion_tags(uuid)`.
- **E. Opinions behaviour.** As user A (`request.jwt.claims` and `SET LOCAL ROLE authenticated`):
  - `create_opinion` succeeds, and an immediate second one raises `cooldown` (53400; `assert_can_post` intact);
  - `create_opinion_comment` succeeds;
  - as B, `report_opinion` inserts one `forum_reports` row and a repeat adds none; `report_opinion_comment` inserts one;
  - `create_opinion_with_poll(…, ARRAY['Yes','No'])` creates a `post_polls` row with that `opinion_id`;
  - as anon, `get_post_poll(p_opinion_id => …)` returns 2 rows with `vote_count IS NULL`;
  - after B's `cast_poll_vote`, B sees counts;
  - as service role, three `admin_confirm_content_removal('opinion', …)` calls give `violation_count` 1, 2, 3 and `banned_until ≥ now() + 6 days`, and A's next `create_opinion` raises `posting_banned` (42501). The first of the three opinions comes from the RPC above; the other two are inserted directly as the owner role, so the 60-second cooldown doesn't interfere;
  - `private.enqueue_forum_notification(p_user_id => A, p_title => 't', p_body => 'b', p_type => 'opinion_liked', p_opinion_id => …)` inserts one pending `scheduled_notifications` row of type `opinion_liked` for A. The count is by type, so the removal notices Spec 1 W9 restores don't change it when E re-runs in W3.

**W3 section:**
- **F. Schema gone.**
  - `forum_retirement_health()` reports all 7 checks `ok`.
  - `to_regclass` is null for the 10 relations and `to_regprocedure` is null for the 29 functions.
  - `post_polls` has no `topic_id`, and inserting a poll with a NULL `opinion_id` raises `not_null_violation`.
  - `forum_reports` has no `forum_post_id` or `topic_id`, and a row with neither `opinion_id` nor `comment_id` raises `check_violation`.
  - `admin_confirm_content_removal('forum_post', gen_random_uuid())` raises `invalid_content_type`.
  - A confirmed opinion removal queues one `forum_content_removed` row for its author, and the third strike one `forum_posting_banned` row: the notices Spec 1 W9 restored survive step 5.
  - `private.assert_can_post(A, 'topic')` returns without error. Only the ban gate runs; no forum table is read.
  - `private.create_poll_for_post(A, NULL, gen_random_uuid(), ARRAY['a','b'])` raises `topic_polls_retired`.
  - `get_post_poll(p_topic_id => gen_random_uuid())` returns zero rows.
  - Section E re-runs unchanged.
- **Also re-run in W3:** `account_deletion_contracts.sql`, `data_export_contracts.sql`, Spec 1 W9's `opinion_moderation_notice_contracts.sql` and `security_lockdown_contracts.sql` (edited).

### 7.4 No-dangling-references test: `test/architecture/no_forum_references_test.dart`

This follows the house pattern of `no_pairing_strings_test.dart`. Full-line comments (`//`, `///`) are stripped first, as in `design_tokens_test.dart`. Each failure reports `path:line: pattern`.

- **W1, over `lib/**/*.dart` and `test/**/*.dart` (excluding this file):**
  - **Forbidden patterns:**
    - `package:attune/features/forums/`;
    - word-bounded class names: `ForumsSection`, `ForumsExploreScreen`, `ContributingForumsScreen`, `DebateRoomScreen`, `SideSelectionScreen`, `ForumInsightScreen`, `SubmitTopicScreen`, `ForumCard`, `ForumCardSubDetails`, `ForumPostBubble`, `TopicVotingCard`, `TopicImpressionTracker`, `MiniContainerIndicator`, `TopicModel`, `ForumPostModel`, `ForumRepository`, `ForumFeedCache`, `ForumHome`, `ForumDocs`;
    - the provider names in §3.4 (except the generic `supabaseClientProvider` and `currentUserStatusProvider`), and `onTopicSubmitted`;
    - `RouteNames\.(debateRoom|sideSelection|forumInsight)` and the strings `'/debateRoom'`, `'/sideSelection'`, `'/forumInsight'`;
    - any of the 29 function names or 10 relation names inside a string literal;
    - any string literal (either quote style) matching `\b[Ff]orums?\b`.
  - **Allowed:** `'get_polls_for_topics'` in `lib/core/polls/data/repositories/poll_repository.dart` (until W3).
  - **Never forbidden (keep list):** `forum_reports`, `forum_content_removed`, `forum_posting_banned`, `enqueue_forum_notification`, `ForumSchimmer`, `forum_shimmer.dart`, `Icons.forum*`. The three retired case labels in `notification_config.dart` don't match any pattern.
  - **ARB:** no value in `lib/i10n/*.arb` matches `(?i)\bforums?\b|\bforo\b|\bforen|\bfórum\b`.
  - **Manual:** `DocumentationRegistry.getById('forums')` is null; no module in `getAllModules()` has the id `forums`; `visibleModules(const {})` contains no `forums`; `getAllModules().length >= 33` (the guard's floor). **No exact count is asserted.** Spec 1 and Spec 2 register more topics, so a pinned total would go red at Spec 1 W3.
- **W2 additions:**
  - `Directory('supabase/functions/activate-topics')` and `…/forum-quiet-check` don't exist;
  - the 3 `supabase/sql` scripts don't exist;
  - no `supabase/functions/**/*.ts` and no `supabase/sql/*.sql` contains any of the 29 function names, the 10 relation names, `'forum_topic_activated'`, `'forum_activity'` or `'forum_quiet'`. The dispatcher's allowlist keys `forum_post_id` and `topic_id` match none of these.
- **W3 addition:** remove the `get_polls_for_topics` allowance.

### 7.5 Device checks
The W1 owner checklist (§6.1 step 3) on iOS and Android, phone and iPad, light and dark, guest and signed in, default and largest text, plus the Games smoke test. The W3 Opinions smoke test (§6.3 step 7).

---

## 8. Regression risks

| # | Risk | Where | Mitigation |
|---|---|---|---|
| R1 | A stale forum push throws "no route" after the routes go | `notification_config.dart:163-172` | Changed first; the compiler forbids `RouteNames.forumInsight`; behavioural test |
| R2 | Visual regression in the Opinions header (the 48.h bottom row disappears) | `opinions_tab.dart` | The outer Scaffold and background are kept; only `bottom:` goes. Shell widget test plus a screenshot pass (light/dark, guest/signed in, phone/iPad, largest text). |
| R3 | Guest landing or the sign-in flip breaks when the outer controller goes | `_OpinionsSection` `initState` and `didUpdateWidget` | Logic untouched; test covers guest, signed in and the flip |
| R4 | The bottom nav stays hidden after switching sub-tabs | Nav-visibility listeners | The inner listener and `home_widget.dart` reset are unchanged; device check |
| R5 | The "+" flow loses feed refresh or scroll-to-top | Chooser and FAB | `onOpinionPosted` passed straight through; chooser test |
| R6 | Tag browse slivers or the header overflow once the tabs go | `tag_browse_screen.dart` | `SliverOverlapInjector` kept; `preferredSize` matched; overflow test at the largest text scale |
| R7 | `widget_test` starts touching Supabase without the override | `test/widget_test.dart` | The override only served `ForumsSection`; removing a reader can't add a call. The suite proves it. |
| R8 | Guest Opinions polls break if `get_post_poll`'s anon grant is revoked along with the forum grants | W2 migration 2, W3 migration 4 | Excluded by name; signature kept; contract D; health sentinel |
| R9 | Opinions moderation or notifications break if a kept "forum" object is dropped or renamed | `forum_reports`, `enqueue_forum_notification`, `assert_can_post`, `admin_confirm_content_removal`, the two moderation types | §4 keep list; no renames (non-goal); contract E; health sentinel |
| R10 | The untracked `mark-quiet-forums` fails every night after the drop and nobody reads the failure | Production cron | Unscheduled by name and by command pattern in W2; health check; W3 contract scans `cron.job.command` |
| R11 | Old builds keep writing forum rows or running the activation sweep | Table grants, V4 and V5 | W2 revokes EXECUTE and table privileges from every client role, including service_role |
| R12 | A pending Stories deploy command or an argument-less `supabase functions deploy` fails (missing folders) or re-deploys the two functions from an old checkout | Owner deploys | W2 checklist steps 0 and 5; revokes make a re-deployed function inert |
| R13 | W3 data loss is irreversible | W3 | Four-part gate; schema and data dumps; inventory and body checks before the push |
| R14 | W3 drop order fails half-way, or cascades into kept tables | FKs from `post_polls` and `forum_reports` | Rows cleaned, FKs dropped explicitly, every DROP is RESTRICT, steps 3–4 are transactional |
| R15 | Rewriting `assert_can_post` or `admin_confirm_content_removal` changes Opinions limits or bans | W3 migration 5 | Rewrite from the live body with only the branch removed; header quotes the "before"; contract E covers cooldown, ban ladder and ban gate |
| R16 | Someone "fixes" the missing moderation notices inside W3 and changes Opinions behaviour unreviewed | V8 | Out of scope (§10 F-1); Spec 1 W9 restores them under its own review; W3 preserves live behaviour and contract F pins the notices |
| R17 | `search_path = ''` on redefined functions breaks an unqualified name | W3 migrations 4–5 | Qualify everything (`public.`, `auth.role()`, `auth.uid()`); contracts exercise every branch |
| R18 | The hand-edited generated l10n drifts from the ARB files | 7 generated files | The same six strings in both; the ARB scan in the architecture test |
| R19 | A Spec 3 migration sorts before an already-applied file (so `supabase db push` refuses it), or collides with Spec 1/2 or a hotfix | Migration ordering | Names and order only; timestamps are assigned at build time, later than every applied migration (House rules). No reserved blocks. |
| R20 | Games regress through shared widgets | `UniversalBubble`, `ChatTextField` | Not edited; `universal_bubble_test.dart` forum-shaped guards kept; Games smoke test |
| R21 | `dart format` on an edited file reflows it | Every edited Dart file | Formatting only for new files (house rule) |
| R22 | The wrong local database is wiped | `attune_spec3a` vs `attune_test` | Never run `local_pg_setup.sh` or `local_pg_grants.sql` against `attune_spec3a`; set `ATTUNE_TEST_DB` explicitly to a brand-new name for any from-zero rebuild; follow the §7.1 procedure |

**What W1 deliberately does NOT change**, and why:
- `home_screen.dart` (redirect latch, R1 of 06) and `main.dart`: Spec 1 owns them.
- `discover_feed_screen.dart`: V1.
- The app-bar "+"'s missing guest check: a pre-existing behaviour and an Opinions change.
- Comment-only mentions in untouched files: surgical diff.
- `poll_providers.dart`: `PollTarget` is part of the Opinions polls key, so it isn't touched even in W3.

---

## 9. Shared files with Spec 1 (and Spec 2): collision map

Spec 3 W1–W2 land **before** Spec 1, so Spec 1 is written against the post-W1 files. Line numbers below are pre-W1 (`a7b07e79`).

| File | Spec 3 changes exactly | Spec 1 / Spec 2 interest | Rule |
|---|---|---|---|
| `lib/features/onboarding/presentation/widgets/profile_setup_step.dart` | Line 22 (subtitle string) only | S1 W2/W3 onboarding copy | Spec 1 rebases on the new string |
| `lib/app/documentations/user_manual/data/manual_documentation_registry.dart` | Lines 22 and 133 only | S2 W3 Dating docs; any S1 manual changes | No other lines touched |
| `lib/app/documentations/user_manual/data/chat_docs.dart` | Line 56 (string) only | S1 W3 "copy without forums" | S1 W3's item becomes a check that the architecture test passes |
| `lib/features/auth/intro/intro_screen.dart`, `lib/features/auth/log_in/presentation/screens/login_profile.dart` (intro and login carousels) | **None** (the Forums card goes through the registry) | S1 W2 Welcome and previews | Spec 1 owns them; the Forums card is gone (no exact topic count is pinned) |
| `lib/home/home_screen.dart`, `lib/home/widgets/home_widget.dart`, `lib/home/widgets/tabs_with_content.dart` (home tabs) | **None** | S1 W3 path-aware home | Spec 1 owns them. `lib/home/widgets/forum_home.dart` is deleted by Spec 3; S1 W10's dead-code pass shouldn't expect it. |
| `test/widget_test.dart` | Lines 10-11, 24-47, 61, plus one `findsNothing` | S1 W3 rewrites the home-shell test | Spec 1 starts from the post-W1 file |
| `lib/features/opinions/presentation/screen/opinions_tab.dart` | Lines 9-11, 28-53, 55-83, 86-97, 129-136 (comment), 202, 332-345 | None: S1 W9 edits the compose and thread screens, not this file; W8 is deferred | Nothing to merge; the Opinions redesign (if reopened) depends on Spec 3 W1 (synthesis §11) |
| `lib/core/widgets/create_content_chooser.dart`, `create_content_fab.dart` | Whole chooser body; FAB lines 6-19, 26, 31-37, 43, 62 | None in these files: S1 builds no drafts or "keep private" option; W9 shows filter errors inside `opinion_compose_screen` | Nothing to merge; S1 W9 builds on the direct compose entry |
| `lib/features/opinions/presentation/screen/tag_browse_screen.dart`, `tag_search_screen.dart:57` | §3.2 | None: S1 builds no tag mute or new tags | Nothing to merge |
| `lib/i10n/app_*.arb` and `lib/i10n/generated/*` | Only `mutedItemSubtitle` (en 321, de 326, es 325, fr 326, it 326, pt 326; generated 541 and base 1111) | S1 l10n additions | Different keys; no conflict |
| `lib/core/notifications/config/notification_config.dart` | Lines 163-172 only | S1 W3 adds the `journal_reminder` case; S2 adds neutral Dating push cases (`me_update` in S2 W3a, `me_checkin` in S2 W6c; the old `dating_mutual_match` case is removed separately in S2 W10) | Different cases; Spec 3 lands first |
| `lib/app/routing/app_router.dart` | Lines 35-38, 245-247, 549-599 only | S1 W2/W3 pre-auth and path routes; S2 Dating routes | Different blocks; Games blocks untouched by all |
| `lib/architecture/FORUM.md` | Banners in W1; two lines in W3 (§6.3) | None: Spec 3 owns this file | Spec 1 does not edit it, W10 included. S1 W10's amendments are the Master Spec, `AUTH_ONBOARDING_ENGINE`, CR-06, the SOUL proposal and the "Forums retired" line. |
| `ATTUNE_MASTER_SPEC.md` | **None** | S1 W10 doc amendments | Spec 3 hands over one line: "Forums retired 2026-10, Spec 3" |
| `supabase/migrations` | W2: 4 new files; W3: 6 new files; names and order only (§6.2, §6.3) | All Spec 1/2 migrations | One rule for all three specs: every migration takes a timestamp later than the newest applied one, assigned when its wave is built (House rules). No reserved blocks. |
| `private.assert_can_post`, `public.admin_confirm_content_removal`, `forum_reports` | W3 removes forum branches and columns | S1 W9: the at-risk reason, the two report RPCs, and `admin_confirm_content_removal` re-created with the two notices restored (S1 D17, §5.7). No thresholds, no rule-and-appeal notice, no renames, no forum-branch removal | S1 W9 writes only `opinion_id`/`comment_id` and leaves the forum branches alone; W3 removes them, rewriting from the live body (§6.3), so the restored notices stay |

---

## 10. For the owner

**F-1 (pre-existing Opinions defect, not fixed here).** Since `20260802120000_report_dedup_and_ban_extension_fix.sql`, confirming a removal (`admin_confirm_content_removal`) no longer queues "Post removed" or "Posting paused". The `20260727120000` version queued both, and the rewrite dropped them. The ban itself still works.
- **Resolution:** Spec 1 W9 restores both notices with today's wording and nothing else changed (S1 D17). The rule-and-appeal redesign stays deferred (Q9, Q10). It isn't restored in a removal spec.
- Spec 3 W3 keeps the function's behaviour exactly as it is live, so the restored notices survive.

**Decisions taken in this spec** (each the best fit for "Opinions unchanged, Forums gone"):

| # | Decision | Why |
|---|---|---|
| D1 | "+" opens the composer directly; the chooser sheet goes | A chooser with one option is a dead tap. Same API, so callers don't change. |
| D2 | The Opinions/Forums tab row is removed; Following/Discover stay exactly as they are | The row existed only for Forums |
| D3 | Tag pages become one list | The second tab was Forums |
| D4 | Retired push types keep explicit cases that go home | Readable, testable, and robust against look-alike types |
| D5 | No redirect stubs for the old paths | Nothing outside compiled code can reach them (V15) |
| D6 | No renames of kept "forum" objects | Avoids rewriting every Opinions RPC; no spec renames them (S1 §5.7) |
| D7 | `get_post_poll` and `create_poll_for_post` keep their signatures | Keeps the anon and authenticated grants and old clients working |
| D8 | `forum_reports` loses its two forum columns in W3 | No column may point at a dropped table; the target CHECK is re-added |
| D9 | Health check is an on-demand service-role function plus a contract | Cron failures here go unread; the owner and the contract read it directly |
| D10 | W3's only client edit is removing `getPollIdsForTopics` | It is the one client call to a dropped RPC; `PollTarget` stays untouched |

**Size:**
- **Deleted:** 26 files (W1: 21; W2: 5).
- **Existing files edited:** 29 (W1: 26; W3: 3).
- **New files:** 16 (W1: 5 tests; W2: 4 migrations and 1 contract; W3: 6 migrations).
- **Server:** 3 crons unscheduled, 2 edge functions undeployed, 29 functions, 8 tables and 2 views dropped.
- **Human gates:** none. W3 waits for one release on every test device, plus the log, health and order checks.

---

## 11. Changelog: cross-spec fix pass (2026-10-24)

Per `2026-10-24-cross-spec-review.md` and its "Controller rulings for the fix pass". Findings are listed by id; only findings that touch this spec appear.

- **C-1 (manual count):** the architecture test no longer asserts `getAllModules().length == 34`. It asserts that `getById('forums')` is null, that no module has the id `forums`, that `visibleModules(const {})` has no `forums`, and that the length is at least the guard's floor of 33 (§7.4). V13, the §3.2 registry row, the "Not edited" list, the §3.5 guard row and the §9 carousel row now say "floor of 33 holds" instead of "34 remain".
- **I-1 / I-2 (migration timestamps):** every timestamped Spec 3 filename is gone. W2 (4 migrations) and W3 (6 migrations) are listed by name, purpose and order only. The reserved W2 block, the W3 default block and its renumbering rule are replaced by one house rule: the implementer assigns timestamps at build time, later than every applied migration, strictly increasing in listed order, for hotfixes too. Edited: House rules, §6.2, §6.3, the §6.2 `db push` checklist line, §7.1 item 6, risk R19, and the §9 migrations row. The build-order header now reads "Spec 1 (W1–W7, W9, W10)" and says waves may run in any dependency-valid order.
- **A-1 (local harness):** the ban on `scripts/local_pg_setup.sh` and `scripts/local_pg_grants.sql` against `attune_spec3a` stays (House rules, R22). §7.1 now holds one non-destructive procedure: confirm the database, apply only the wave's migrations with `psql -f`, run one or all contracts with `psql -f`, and do any from-zero rebuild only into a brand-new database name with `ATTUNE_TEST_DB` set explicitly (never the default `attune_test`), dropped afterwards.
- **C-7 (stale Spec 1 W9 expectations):** aligned with S1 §5.7 and D17. Spec 1 W9 restores the two moderation notices (re-creating `admin_confirm_content_removal` from its live body) and adds the at-risk reason. It builds no drafts, "keep private", tag mute, new tags, thresholds, rule-and-appeal notice, renames or forum-branch removal. Edited: §1 non-goals, V8, the §3.9 shared-function row, §6.3 coordination paragraph and gate (d), contract E (count by type) and a new contract F bullet that pins the restored notices, the W3 owner checklist step 8, risk R16, the §9 rows for `opinions_tab`, the chooser and FAB, tag browse and the shared functions, and §10 F-1 (now "Resolution"). W3 step 5 is now always needed, because the `forum_post` branch survives Spec 1 W9.
- **C-9 (Q20 ownership):** §9 states that Spec 3 owns `FORUM.md` (banners in W1, two lines in W3) and that Spec 1 does not edit it, W10 included. The Master Spec line is still handed to Spec 1 W10.
- **A-8 (name reuse):** a "Naming" line under the header separates these specs from the earlier launch program's "Spec 2" and "Spec 3a/3b/3c", and notes that `attune_spec3a` is the older program's scratch database.
- **W-3 / wave sizing:** W1 now runs as four tasks (T1 push routing and router, T2 Opinions shell, compose entry and tags, T3 manual, copy, l10n and FORUM.md, T4 deletions and tests). W2 and W3 get three tasks each. The forum payload group of `notification_tap_routing_test.dart` moves into step 1, because it asserts the route that step removes. The `flutter analyze` gate is stated as clean only after T4, since the forum folder names the removed route constants until step 8.
- **R-6 (environment):** House rules state that this spec reads and sets no `attune_environment` setting, and that "production" in the checklists means the currently linked project, which is dev/testing until the owner's launch switch.
- **F-3 (migrations):** the house rules add "no `CREATE INDEX CONCURRENTLY`". The `BEGIN; … COMMIT;` rule was already here.
- **I-9 (shared file):** the §9 `notification_config.dart` row now names S1's `journal_reminder` case and S2's neutral Dating case (`me_update`), without a wave number.
- **S-1 (Critical, owned by Spec 1 W1):** no change to the forum work. §3.11 now notes that the guard refuses client writes only, so `admin_confirm_content_removal` (service-role definer) and contract E's ban ladder keep working.
- **Own corrections:** the health-check decision was cited as D10 in §6.2 and is D9. The "Existing files edited" count is 29 (W3 now also edits `FORUM.md`). The keep-list row for `CreateContentChooser` and decision D6 no longer say Spec 1 W9 builds on or renames those objects.
- **Not applicable to this spec:** C-8 (Spec 1's `app_router.dart` line ranges; this spec's line numbers are explicitly pre-W1), and the remaining Critical, Important and Minor findings that name only Spec 1 or Spec 2.

---

## Owner approval (2026-10-24)

The owner approved Specs 1, 2 and 3 as written, together with the recommendations for the remaining open items:
- **O2 (Healing AI):** yes. Healing's AI insight gets the same pause, with the `self_disclosure` crisis check running first. It is built in S1 W9 behind `healing_ai_insights`, under the same clinician gate.
- **O3 (parked account restrictions):** no. A parked account's live Dating restrictions do **not** follow a recycled number to the fresh account. The enforcement record stays attached to the old account and its HMAC.
- **O4 (Opinions enforcement records):** yes. Opinions-scope enforcement records survive account deletion like Dating's. This is built as **S1 W9d**, after S2 W1 creates `enforcement_records`.
