// Spec 2 W9 (§3.9 steps 4-6, §7.4; C-4, I-12; R20): the Relationship side
// of a couple that met in Dating. The Relationship home's one Dating card
// (link_offer, appended after Journals and Together only while the server
// reports an offer; it goes after either answer; the chat card and the
// other cards render and keep their order), About us's "The day you
// matched" chip (never pre-filled) and its How we met row and card.
import 'dart:async';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/reorderable_home_cards.dart';
import 'package:attune/features/chat/data/home_card_order_repository.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/link/link_offer_card.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/how_we_met.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../support/dating_fakes.dart';
import '../support/dating_link_fakes.dart';

class _Conversations extends ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [
    Conversation(
      id: 'c1',
      relationshipId: 'rel-1',
      partnerId: 'partner-1',
      name: 'Kofi',
      updatedAt: DateTime.utc(2026, 11, 1),
      relationshipStatus: 'active',
      availability: ConversationAvailability.active,
    ),
  ];
}

class _Journals extends JournalEntriesNotifier {
  @override
  Future<List<JournalEntry>> build() async => const [];
}

class _Reminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

class _Order implements HomeCardOrderRepository {
  _Order(this.saved);
  List<String>? saved;
  @override
  Future<List<String>?> load() async => saved;
  @override
  Future<void> save(List<String> order) async => saved = order;
}

/// Fix round 1: the offer's re-read can be held open.
class _HeldOffer extends FakeDatingLink {
  _HeldOffer(DatingPostLinkOffer answer) : super(offerAnswer: answer);
  Completer<void>? offerHold;

  @override
  Future<DatingPostLinkOffer> offer() async {
    final held = offerHold;
    if (held != null) await held.future;
    return super.offer();
  }
}

/// R-W9-16: what the app's one Dating flag read says for the account
/// (datingCoupleLinkReadProvider).
Override _flag(bool on) =>
    datingCoupleLinkReadProvider.overrideWith((ref, account) async => on);

Override _online(bool on) =>
    datingOnlineProvider.overrideWith((ref) => Stream.value(on));

/// Fix round 2 (M-2): an answer the server didn't take.
class _Refused extends FakeDatingLink {
  _Refused() : super(offerAnswer: DatingPostLinkOffer.delete);

  bool refuse = true;

  @override
  Future<bool> dismiss(DatingPostLinkOffer offer) async {
    if (!refuse) return super.dismiss(offer);
    dismissals.add(offer);
    return false;
  }
}

/// Fix round 2: the Relationship home at /home under a GoRouter, with
/// [leave] at /dating/leave (as the app's: Leave's Done goes to /home).
Future<(ProviderContainer, GoRouter)> _routed(
  WidgetTester t,
  FakeDatingLink fake,
  Widget Function() leave, {
  List<Override> more = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const ConversationsScreen()),
      GoRoute(path: DatingPaths.leave, builder: (_, __) => leave()),
    ],
  );
  addTearDown(router.dispose);
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      conversationsProvider.overrideWith(_Conversations.new),
      journalEntriesProvider.overrideWith(_Journals.new),
      remindersListProvider.overrideWith(_Reminders.new),
      homeCardOrderRepositoryProvider.overrideWithValue(_Order(null)),
      datingAccountProvider.overrideWithValue('ama'),
      _online(true),
      _flag(true),
      ...datingLinkOverrides(fake),
      ...more,
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (container, router);
}

const _keep = ValueKey('dating_link_offer_keep');
const _deleteKey = ValueKey('dating_link_offer_delete');

VoidCallback? _pressed(WidgetTester t, Key key) =>
    t.widget<ButtonStyleButton>(find.byKey(key, skipOffstage: false)).onPressed;

Future<ProviderContainer> _home(
  WidgetTester t,
  FakeDatingLink fake, {
  List<String>? saved,
  bool flagOn = true,
  bool online = true,
}) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      conversationsProvider.overrideWith(_Conversations.new),
      journalEntriesProvider.overrideWith(_Journals.new),
      remindersListProvider.overrideWith(_Reminders.new),
      homeCardOrderRepositoryProvider.overrideWithValue(_Order(saved)),
      datingAccountProvider.overrideWithValue('ama'),
      _online(online),
      _flag(flagOn),
      ...datingLinkOverrides(fake),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationsScreen(),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

List<String> _cardOrder(WidgetTester t) => [
  for (final c
      in t
          .widget<ReorderableHomeCards>(find.byType(ReorderableHomeCards))
          .cards)
    c.id,
];

void main() {
  group('the Relationship home (C-4, R20)', () {
    testWidgets(
      'no offer: Journals and Together only, the chat card above them',
      (t) async {
        final fake = FakeDatingLink();
        await _home(t, fake);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(find.text('Kofi'), findsWidgets, reason: 'the chat card');
        expect(fake.offers, 1);
      },
    );

    testWidgets(
      'R-W9-16: while the app does not know the flag is on, the offer is '
      'never asked and the card is absent',
      (t) async {
        final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
        await _home(t, fake, flagOn: false);
        expect(fake.offers, 0);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsNothing,
        );
      },
    );

    testWidgets('R-W9-16: with the flag on, asked once per home load', (
      t,
    ) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      await _home(t, fake);
      await t.pumpAndSettle();
      expect(fake.offers, 1);
      expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
    });

    testWidgets(
      'the 30-day offer is appended last; Keep for now removes it for good',
      (t) async {
        final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
        await _home(t, fake);
        expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsOneWidget,
        );
        expect(find.text('You can set up Dating again later.'), findsOneWidget);
        expect(find.text('Delete my Dating data'), findsOneWidget);
        await t.ensureVisible(find.text('Keep for now'));
        await t.tap(find.text('Keep for now'));
        await t.pumpAndSettle();
        expect(fake.dismissals, [DatingPostLinkOffer.delete]);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsNothing,
        );
      },
    );

    testWidgets('a saved order keeps its own; the card joins at the end and '
        'leaves without disturbing it', (t) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      await _home(t, fake, saved: ['together', 'journals']);
      expect(find.byType(ReorderableHomeCards), findsOneWidget);
      expect(resolveHomeCardOrder(['together', 'journals'], _cardOrder(t)), [
        'together',
        'journals',
        'link_offer',
      ]);
      expect(
        resolveHomeCardOrder(
          ['link_offer', 'together', 'journals'],
          ['journals', 'together'],
        ),
        ['together', 'journals'],
      );
    });

    testWidgets('the asker who wasn\'t there: "You decided together." once', (
      t,
    ) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.linked);
      await _home(t, fake);
      expect(find.text('You decided together.'), findsOneWidget);
      expect(find.text('Your Dating profiles are paused.'), findsOneWidget);
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
      expect(find.text('You decided together.'), findsNothing);
    });

    for (final linked in [false, true]) {
      testWidgets(
        'fix round 1: ${linked ? 'Continue' : 'Keep for now'} stays busy '
        'until the re-read lands; a second tap sends nothing',
        (t) async {
          final fake = _HeldOffer(
            linked ? DatingPostLinkOffer.linked : DatingPostLinkOffer.delete,
          );
          await _home(t, fake);
          final label = linked ? 'Continue' : 'Keep for now';
          final hold = fake.offerHold = Completer<void>();
          await t.ensureVisible(find.text(label));
          await t.tap(find.text(label));
          await t.pump();
          await t.pump();
          expect(fake.dismissals, hasLength(1));
          expect(find.text(label), findsOneWidget, reason: 'the re-read runs');
          await t.tap(find.text(label), warnIfMissed: false);
          await t.pump();
          expect(fake.dismissals, hasLength(1), reason: 'busy: sent once');
          hold.complete();
          await t.pumpAndSettle();
          expect(fake.dismissals, hasLength(1));
          expect(_cardOrder(t), ['journals', 'together']);
        },
      );
    }

    testWidgets('signed out: nothing is asked', (t) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final container = ProviderContainer(
        overrides: [
          conversationsProvider.overrideWith(_Conversations.new),
          journalEntriesProvider.overrideWith(_Journals.new),
          remindersListProvider.overrideWith(_Reminders.new),
          homeCardOrderRepositoryProvider.overrideWithValue(_Order(null)),
          datingAccountProvider.overrideWithValue(null),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => const MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ConversationsScreen(),
                ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(fake.offers, 0);
      expect(_cardOrder(t), ['journals', 'together']);
    });

    // Ruling (Task 6, R-W9-8): Leave Dating's Done goes home with
    // context.go, which never completes the card's push; the card goes when
    // Leave re-reads the Dating home after leaving, as the real screen does
    // (dating_leave_screen.dart: invalidate on ok, then go to Me).
    for (final left in [true, false]) {
      testWidgets(
        'Delete my Dating data opens Leave Dating; '
        '${left ? 'after leaving, Done goes home and the card is gone' : 'back without leaving keeps the card'}',
        (t) async {
          final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
          final home = FakeDatingHomeGateway();
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const ConversationsScreen(),
              ),
              GoRoute(
                path: DatingPaths.leave,
                builder:
                    (_, __) => Consumer(
                      builder: (context, ref, _) {
                        ref.watch(datingHomeProvider('ama'));
                        return Scaffold(
                          body: Column(
                            children: [
                              TextButton(
                                onPressed: () {
                                  fake.offerAnswer = DatingPostLinkOffer.none;
                                  ref.invalidate(datingHomeProvider('ama'));
                                },
                                child: const Text('Leave'),
                              ),
                              TextButton(
                                onPressed: () => context.go('/'),
                                child: const Text('Done'),
                              ),
                              TextButton(
                                onPressed: () => context.pop(),
                                child: const Text('Back'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              ),
            ],
          );
          addTearDown(router.dispose);
          t.view.physicalSize = const Size(390, 1600);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final container = ProviderContainer(
            overrides: [
              conversationsProvider.overrideWith(_Conversations.new),
              journalEntriesProvider.overrideWith(_Journals.new),
              remindersListProvider.overrideWith(_Reminders.new),
              homeCardOrderRepositoryProvider.overrideWithValue(_Order(null)),
              datingAccountProvider.overrideWithValue('ama'),
              datingHomeGatewayProvider.overrideWithValue(home),
              _flag(true),
              ...datingLinkOverrides(fake),
            ],
          );
          addTearDown(container.dispose);
          await t.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder:
                    (_, __) => MaterialApp.router(
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      routerConfig: router,
                    ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
          await t.ensureVisible(find.text('Delete my Dating data'));
          await t.tap(find.text('Delete my Dating data'));
          await t.pumpAndSettle();
          expect(find.text('Leave'), findsOneWidget);
          if (left) {
            await t.tap(find.text('Leave'));
            await t.pumpAndSettle();
            await t.tap(find.text('Done'));
          } else {
            await t.tap(find.text('Back'));
          }
          await t.pumpAndSettle();
          expect(find.byType(ConversationsScreen), findsOneWidget);
          expect(
            _cardOrder(t),
            left
                ? ['journals', 'together']
                : ['journals', 'together', 'link_offer'],
          );
          expect(fake.dismissals, isEmpty, reason: 'Leave is not Keep');
          expect(
            fake.offers,
            2,
            reason: 'the home load, then once on the way back',
          );
          expect(
            home.reads,
            left ? 2 : 1,
            reason: 'the leave screen\'s own reads only',
          );
        },
      );
    }
  });

  group('About us (I-12)', () {
    test(
      'the chip: "The day you matched: {date}", that day, never pre-filled',
      () async {
        final fake =
            FakeDatingLink()..originAnswer = DateTime(2026, 3, 14, 12).toUtc();
        final container = ProviderContainer(
          overrides: [
            datingAccountProvider.overrideWithValue('ama'),
            _flag(true),
            ...datingLinkOverrides(fake),
          ],
        );
        addTearDown(container.dispose);
        await container.read(datingCoupleLinkReadProvider('ama').future);
        final sub = container.listen(
          aboutUsDateSuggestionsProvider('rel-1'),
          (_, __) {},
        );
        addTearDown(sub.close);
        expect(
          sub.read(),
          isEmpty,
          reason: 'nothing before the origin is read',
        );
        await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
        final chips = sub.read();
        expect(chips, hasLength(1));
        expect(
          chips.single.label,
          'The day you matched: Saturday, March 14, 2026',
        );
        expect(chips.single.since.date, DateTime(2026, 3, 14));
        expect(fake.origins, ['rel-1']);
      },
    );

    test('no Dating origin, or signed out: no chip', () async {
      final fake = FakeDatingLink();
      final container = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWithValue('ama'),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await container.read(datingCoupleLinkReadProvider('ama').future);
      final sub = container.listen(
        aboutUsDateSuggestionsProvider('rel-1'),
        (_, __) {},
      );
      addTearDown(sub.close);
      await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
      expect(sub.read(), isEmpty);
      final out = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWithValue(null),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(out.dispose);
      expect(out.read(aboutUsDateSuggestionsProvider('rel-1')), isEmpty);
      expect(fake.origins, ['rel-1']);
    });

    testWidgets('How we met: a row only when the couple kept it, opening the '
        'messages as both saw them', (t) async {
      final fake =
          FakeDatingLink()
            ..howAnswer = [
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi Kofi!',
                at: DateTime.utc(2026, 3, 14, 9),
              ),
              DatingHowWeMetItem(
                mine: false,
                text: 'Call me on •••',
                at: DateTime.utc(2026, 3, 14, 10),
              ),
            ];
      Future<void> pump(FakeDatingLink f) async {
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              datingAccountProvider.overrideWithValue('ama'),
              _flag(true),
              ...datingLinkOverrides(f),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: DatingHowWeMetRow(relationshipId: 'rel-1')),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await pump(FakeDatingLink());
      expect(find.text('How we met'), findsNothing);
      await pump(fake);
      expect(find.text('How we met'), findsOneWidget);
      await t.tap(find.text('How we met'));
      await t.pumpAndSettle();
      expect(
        find.text('Your first messages, as you both saw them.'),
        findsOneWidget,
      );
      expect(find.text('Hi Kofi!'), findsOneWidget);
      expect(find.text('Call me on •••'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Your partner'), findsOneWidget);
    });

    for (final kept in [true, false]) {
      testWidgets(
        'About us shows How we met ${kept ? 'for a couple that kept it' : 'not at all without a card'}',
        (t) async {
          final fake = FakeDatingLink();
          if (kept) {
            fake.howAnswer = [
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi Kofi!',
                at: DateTime.utc(2026, 3, 14, 9),
              ),
            ];
          }
          await pumpFlowScreen(
            t,
            () => AboutUsScreen(
              target: const AboutUsTarget.shared('rel-1'),
              onClose: () {},
              now: DateTime(2026, 11, 20, 10),
            ),
            overrides: [
              coupleProfileEnabledProvider.overrideWithValue(true),
              coupleProfileRpcProvider.overrideWithValue(
                FakeCoupleProfileServer(
                  profiles: {
                    'rel-1': aboutUsJson(
                      togetherSince: '2026-03-14',
                      precision: 'day',
                    ),
                  },
                ).rpc,
              ),
              homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
              togetherChangeSignalProvider.overrideWith(
                (ref, id) => const Stream.empty(),
              ),
              coupleNameProvider.overrideWith((ref, id) async => null),
              datingAccountProvider.overrideWithValue('ama'),
              _flag(true),
              ...datingLinkOverrides(fake),
            ],
            size: const Size(390, 1400),
          );
          expect(find.text('How we met'), kept ? findsOneWidget : findsNothing);
          expect(
            find.text('Together since'),
            findsWidgets,
            reason: 'Spec 1 rows unchanged',
          );
        },
      );
    }
  });

  test('R-W9-16: one Dating read says both flags', () {
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'active', 'couple_link': true}),
      {DatingFeatureFlags.datingModeEnabled, DatingFeatureFlags.coupleLink},
    );
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'feature_unavailable'}),
      isEmpty,
    );
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'paused', 'couple_link': 'yes'}),
      {DatingFeatureFlags.datingModeEnabled},
    );
    expect(DatingFeatureFlags.flagsFrom(null), isEmpty);
  });

  test('R-W9-16: with the flag not known on, About us asks nothing', () async {
    final fake = FakeDatingLink()..originAnswer = DateTime.utc(2026, 3, 14, 12);
    final container = ProviderContainer(
      overrides: [
        datingAccountProvider.overrideWithValue('ama'),
        _flag(false),
        ...datingLinkOverrides(fake),
      ],
    );
    addTearDown(container.dispose);
    await container.read(datingCoupleLinkReadProvider('ama').future);
    final sub = container.listen(
      aboutUsDateSuggestionsProvider('rel-1'),
      (_, __) {},
    );
    addTearDown(sub.close);
    await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
    await container.read(datingHowWeMetProvider(('ama', 'rel-1')).future);
    expect(sub.read(), isEmpty);
    expect(fake.origins, isEmpty);
    expect(fake.hows, isEmpty);
  });

  group('fix round 2', () {
    testWidgets('M-1: Delete my Dating data opens one Leave, busy until '
        'the home is in front again', (t) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      await _routed(
        t,
        fake,
        () => Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back'),
                ),
              ),
        ),
      );
      final open = _pressed(t, _deleteKey)!;
      open();
      open();
      await t.pump();
      expect(_pressed(t, _deleteKey), isNull, reason: 'busy');
      expect(_pressed(t, _keep), isNull);
      await t.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget, reason: 'one Leave');
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
      expect(_pressed(t, _deleteKey), isNotNull);
      expect(_pressed(t, _keep), isNotNull);
      expect(fake.offers, 2, reason: 'the home load, then once on return');
    });

    testWidgets(
      'M-1: away from Leave by a go home (the Dating lock\'s Back) without '
      'leaving: the card is read again and usable',
      (t) async {
        final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
        await _routed(
          t,
          fake,
          () => Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => context.go('/home?tab=me'),
                    child: const Text('Me'),
                  ),
                ),
          ),
        );
        await t.tap(find.byKey(_deleteKey));
        await t.pumpAndSettle();
        await t.tap(find.text('Me'));
        await t.pumpAndSettle();
        expect(find.text('Me'), findsNothing);
        expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
        expect(_pressed(t, _deleteKey), isNotNull);
        expect(_pressed(t, _keep), isNotNull);
        expect(fake.offers, 2);
      },
    );

    testWidgets('M-4: the real Leave Dating: leave and delete, Done, and '
        'the card is gone', (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      final life = FakeDatingLifecycleGateway();
      final home = FakeDatingHomeGateway(
        home: const DatingHome(state: DatingHomeState.active),
      );
      await _routed(
        t,
        fake,
        () => const DatingLeaveScreen(),
        more: [
          datingHomeGatewayProvider.overrideWithValue(home),
          datingLifecycleGatewayProvider.overrideWithValue(life),
        ],
      );
      await t.tap(find.byKey(_deleteKey));
      await t.pumpAndSettle();
      expect(find.text('Leave and delete'), findsOneWidget);
      // The server: leaving removes the data the offer needs.
      fake.offerAnswer = DatingPostLinkOffer.none;
      await t.ensureVisible(find.text('Leave and delete'));
      await t.tap(find.text('Leave and delete'));
      await t.pumpAndSettle();
      expect(life.calls, ['exit']);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
      expect(_cardOrder(t), ['journals', 'together']);
      expect(fake.dismissals, isEmpty);
    });

    testWidgets('M-2: Keep for now not taken: a calm line, the card stays '
        'usable', (t) async {
      final fake = _Refused();
      await _home(t, fake);
      await t.ensureVisible(find.byKey(_keep));
      await t.tap(find.byKey(_keep));
      await t.pumpAndSettle();
      expect(fake.dismissals, [DatingPostLinkOffer.delete]);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
      expect(_pressed(t, _keep), isNotNull);
      fake.refuse = false;
      await t.tap(find.byKey(_keep));
      await t.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(_cardOrder(t), ['journals', 'together']);
      expect(fake.dismissals, hasLength(2));
    });

    for (final linked in [false, true]) {
      testWidgets('M-2: offline, ${linked ? 'Continue' : 'Keep for now'} '
          'waits and says so${linked ? '' : '; Delete still opens Leave'}', (
        t,
      ) async {
        final fake = FakeDatingLink(
          offerAnswer:
              linked ? DatingPostLinkOffer.linked : DatingPostLinkOffer.delete,
        );
        await _home(t, fake, online: false);
        expect(
          find.text("You're offline. Nothing has changed yet."),
          findsOneWidget,
        );
        final label = linked ? 'Continue' : 'Keep for now';
        await t.ensureVisible(find.text(label));
        await t.tap(find.text(label), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(fake.dismissals, isEmpty);
        if (!linked) expect(_pressed(t, _deleteKey), isNotNull);
      });
    }

    testWidgets('M-6 (D8): another account never sees the last one\'s card', (
      t,
    ) async {
      final who = StateProvider<String?>((ref) => 'ama');
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final container = ProviderContainer(
        overrides: [
          conversationsProvider.overrideWith(_Conversations.new),
          journalEntriesProvider.overrideWith(_Journals.new),
          remindersListProvider.overrideWith(_Reminders.new),
          homeCardOrderRepositoryProvider.overrideWithValue(_Order(null)),
          datingAccountProvider.overrideWith((ref) => ref.watch(who)),
          _online(true),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => const MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ConversationsScreen(),
                ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
      fake.offerAnswer = DatingPostLinkOffer.none;
      container.read(who.notifier).state = 'kofi';
      await t.pump();
      expect(
        find.text('Delete your Dating profile and preferences?'),
        findsNothing,
        reason: 'not one frame',
      );
      expect(_cardOrder(t), ['journals', 'together']);
      await t.pumpAndSettle();
      expect(_cardOrder(t), ['journals', 'together']);
      expect(fake.offers, 2, reason: 'once per account');
    });

    testWidgets('M-6 (D8): another account never sees the last one\'s How '
        'we met row', (t) async {
      final who = StateProvider<String?>((ref) => 'ama');
      final fake =
          FakeDatingLink()
            ..howAnswer = [
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi Kofi!',
                at: DateTime.utc(2026, 3, 14, 9),
              ),
            ];
      final container = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWith((ref) => ref.watch(who)),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DatingHowWeMetRow(relationshipId: 'rel-1')),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('How we met'), findsOneWidget);
      fake.howAnswer = null;
      container.read(who.notifier).state = 'kofi';
      await t.pump();
      expect(find.text('How we met'), findsNothing, reason: 'not one frame');
      await t.pumpAndSettle();
      expect(find.text('How we met'), findsNothing);
      expect(fake.hows, ['rel-1', 'rel-1']);
    });

    testWidgets('M-3: a guided answer shows under its question', (t) async {
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DatingHowWeMetScreen(
            items: [
              DatingHowWeMetItem(
                mine: false,
                text: 'Jollof, always',
                at: DateTime.utc(2026, 3, 14, 9),
                questionId: 'food_every_week',
              ),
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi!',
                at: DateTime.utc(2026, 3, 14, 10),
                questionId: 'not_a_question',
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      final loc = await AppLocalizations.delegate.load(const Locale('en'));
      final q = loc.dating_guided_food_every_week;
      expect(find.text(q), findsOneWidget);
      expect(find.text('Jollof, always'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Your partner. $q. Jollof, always'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('You. Hi!'), findsOneWidget);
    });

    final cardOverrides = [
      datingAccountProvider.overrideWithValue('ama'),
      _online(true),
      _flag(true),
    ];
    Widget card() => const Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingLinkOfferCard(),
        ),
      ),
    );
    // Final client fix (M-6): kept on purpose. The card is on the
    // Relationship home, which is not under AllowLargeText, so it follows
    // the home's capped text size: its 1.3 and 2.0 goldens are expected to
    // be byte-identical to 1.0. They pin that cap; a card that began to
    // scale on its own (or a home that lifted the cap) changes them.
    for (final (name, offer) in [
      ('dating_link_offer_delete', DatingPostLinkOffer.delete),
      ('dating_link_offer_linked', DatingPostLinkOffer.linked),
    ]) {
      testWidgets('M-5: goldens and the three guidelines: $name', (t) async {
        final overrides = [
          ...cardOverrides,
          ...datingLinkOverrides(FakeDatingLink(offerAnswer: offer)),
        ];
        await expectFlowGoldens(t, name, card, overrides: overrides);
        await pumpFlowScreen(t, card, overrides: overrides);
        await expectFlowGuidelines(t);
      });
    }

    testWidgets('M-5: goldens and the three guidelines: How we met', (t) async {
      Widget screen() => DatingHowWeMetScreen(
        items: [
          DatingHowWeMetItem(
            mine: true,
            text: 'Hi Kofi! I saw you like long walks by the sea too.',
            at: DateTime.utc(2026, 3, 14, 9),
          ),
          DatingHowWeMetItem(
            mine: false,
            text:
                'I do! Labadi on a Sunday morning, before it gets busy, is '
                'the best. Call me on •••',
            at: DateTime.utc(2026, 3, 14, 10),
          ),
          DatingHowWeMetItem(
            mine: false,
            text: 'Jollof, always',
            at: DateTime.utc(2026, 3, 14, 11),
            questionId: 'food_every_week',
          ),
        ],
      );
      await expectFlowGoldens(t, 'dating_how_we_met', screen);
      await pumpFlowScreen(t, screen);
      await expectFlowGuidelines(t);
    });
  });
}
