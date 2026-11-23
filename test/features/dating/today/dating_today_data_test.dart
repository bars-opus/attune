// Spec 2 W5b (§3.4, §3.5, §5.8; D8, C-5; carries 13, 14): Today's answers
// read fail-closed; the repository sends exactly its RPCs and never a
// server's text; one Today entry per account; the photos in memory only
// (20 at most, emptied by Dating's wipe entry); the reasons are reviewed
// copy from ids only; a caption is its photo's spoken label.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_reasons.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../support/dating_today_fakes.dart';

void main() {
  final loc = AppLocalizationsEn();

  group('the answers, fail closed', () {
    test('anything but an ok object is unavailable, with its reason', () {
      for (final (raw, reason) in [
        (null, 'failed'),
        ('x', 'failed'),
        ({'ok': false, 'reason': 'reverify_device'}, 'reverify_device'),
        ({'ok': false, 'reason': 7}, 'failed'),
        // A refusal's other fields are never read.
        (
          {
            'ok': false,
            'today_state': 'delivered',
            'cards': [datingCardJson('x')],
          },
          'failed',
        ),
      ]) {
        final t = DatingToday.fromJson(raw);
        expect(t.ok, isFalse, reason: '$raw');
        expect(t.reason, reason, reason: '$raw');
        expect(t.cards, isEmpty, reason: '$raw');
      }
    });

    test(
      'every state; an unknown one is unavailable; malformed cards drop',
      () {
        for (final s in DatingTodayState.values) {
          expect(
            DatingToday.fromJson(
              datingTodayJson({'today_state': s.wire}),
            ).state,
            s,
          );
        }
        expect(
          DatingToday.fromJson(datingTodayJson({'today_state': 'party'})).state,
          DatingTodayState.unavailable,
        );
        final t = DatingToday.fromJson(
          datingTodayJson({
            'cards': [
              datingCardJson('a'),
              {'display_name': 'No id'},
              'x',
            ],
            'waiting': [datingCardJson('b')],
            'moments': [
              {'match_id': 'm1', 'display_name': 'Kofi'},
              {'match_id': 2},
            ],
            'family_question': true,
            'quiet_note': 'yes',
            'drop_at': '2026-11-20T19:00:00Z',
          }),
        );
        expect(t.cards.map((c) => c.id), ['a']);
        expect(t.waiting.map((c) => c.id), ['b']);
        expect(t.moments.single.name, 'Kofi');
        expect(t.familyQuestion, isTrue);
        expect(t.quietNote, isFalse);
        expect(t.dropAt, DateTime.utc(2026, 11, 20, 19));
        expect((t.minAge, t.maxAge, t.scope), (25, 40, 'region'));
      },
    );

    test('a card reads the viewer\'s own answer only, captions in order', () {
      final c =
          DatingIntroCard.fromJson(
            datingCardJson('a', {
              'acted': 'interested',
              'photos': [
                {'id': 'p2', 'position': 2, 'caption': 'Second'},
                {'id': 'p1', 'position': 1, 'caption': ''},
              ],
            }),
          )!;
      expect(c.acted, 'interested');
      expect(c.captions, [null, 'Second']);
      expect(c.card.captions, [null, 'Second']);
      expect(
        DatingIntroCard.fromJson(
          datingCardJson('b', {'acted': 'passed'}),
        )!.acted,
        isNull,
      );
      expect('$c', isNot(contains('Kofi')));
    });

    test('act: ok, matched, or a fixed refusal', () {
      expect(
        DatingActAnswer.fromJson({
          'ok': true,
          'action': 'interested',
          'matched': true,
        }).matched,
        isTrue,
      );
      expect(
        DatingActAnswer.fromJson({
          'ok': false,
          'reason': 'introduction_unavailable',
        }).reason,
        'introduction_unavailable',
      );
      expect(DatingActAnswer.fromJson('x').reason, 'failed');
    });
  });

  group('the repository', () {
    test('sends exactly its RPCs; busy and errors are fixed answers', () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      Object? Function(String fn) reply =
          (fn) => {'ok': true, 'today_state': 'empty'};
      final repo = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add((fn, p));
          return reply(fn);
        }),
        (body) async => {
          'ok': true,
          'photos': [
            {'position': 1, 'url': 'https://s.test/a'},
            {'position': 'x'},
          ],
        },
      );
      expect((await repo.today()).state, DatingTodayState.empty);
      await repo.act('k' * 20, 'i1', 'interested');
      await repo.momentSeen('m1');
      await repo.dismissNote('family');
      await repo.saveFamily('f' * 20, 'early');
      expect(calls.map((c) => c.$1), [
        'get_my_dating_today',
        'act_on_dating_introduction',
        'mark_dating_match_moment_seen',
        'dismiss_dating_today_note',
        'save_dating_family_involvement',
      ]);
      // Spec 2 W8b (R-T5-1): the phone's choice, always explicit.
      expect(calls[0].$2, {'p_show_same_gender': false});
      expect(calls[1].$2, {
        'p_idempotency_key': 'k' * 20,
        'p_introduction_id': 'i1',
        'p_action': 'interested',
        'p_show_same_gender': false,
      });
      expect(calls[4].$2, {'p_idempotency_key': 'f' * 20, 'p_value': 'early'});
      expect((await repo.photoUrls('introduction', 'i1'))!.map((u) => u.url), [
        'https://s.test/a',
      ]);
      reply = (fn) => throw PostgrestException(message: 'dating:busy');
      expect((await repo.today()).reason, 'busy');
      expect((await repo.act('k' * 20, 'i1', 'passed')).reason, 'busy');
      reply =
          (fn) => throw PostgrestException(message: 'a server\'s own words');
      expect((await repo.today()).reason, 'failed');
      expect((await repo.act('k' * 20, 'i1', 'passed')).reason, 'failed');
      await repo.momentSeen('m1'); // never throws
    });

    test('photo URLs: a refusal or an error is null', () async {
      for (final answer in <Object?>[
        {
          'ok': false,
          'reason': 'reverify_device',
          'photos': [
            {'position': 1, 'url': 'https://s.test/x'},
          ],
        },
        'x',
        null,
      ]) {
        final repo = DatingTodayRepository(
          DatingRpc.withCall((fn, p) async => null),
          (body) async => answer,
        );
        expect(await repo.photoUrls('match', 'm1'), isNull, reason: '$answer');
      }
      final throws = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async => null),
        (body) => throw StateError('down'),
      );
      expect(await throws.photoUrls('match', 'm1'), isNull);
    });
  });

  group('D8, memory only', () {
    test(
      'D8: the next account reads its own Today, nothing of the last',
      () async {
        final fake = FakeDatingToday();
        final account = StateProvider<String?>((ref) => 'ama');
        final c = ProviderContainer(
          overrides: [
            datingAccountProvider.overrideWith((ref) => ref.watch(account)),
            datingTodayGatewayProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(c.dispose);
        final sub = c.listen(
          datingTodayProvider(c.read(datingAccountProvider)),
          (_, __) {},
        );
        expect(
          (await c.read(datingTodayProvider('ama').future)).cards,
          hasLength(1),
        );
        fake.hold = Completer<DatingToday>();
        c.read(account.notifier).state = 'kwame';
        final next = c.read(datingTodayProvider('kwame'));
        expect(next.isLoading, isTrue);
        expect(next.valueOrNull, isNull);
        fake.hold!.complete(
          DatingToday.fromJson(datingTodayJson({'cards': <Object?>[]})),
        );
        expect(
          (await c.read(datingTodayProvider('kwame').future)).cards,
          isEmpty,
        );
        sub.close();
      },
    );

    test(
      'at most 20 photos, the oldest out first; Dating\'s wipe empties them',
      () async {
        await DatingPhotoMemory.clear();
        for (var i = 0; i < 25; i++) {
          DatingPhotoMemory.put('k$i', Uint8List.fromList([i]));
        }
        expect(DatingPhotoMemory.length, 20);
        expect(DatingPhotoMemory.get('k4'), isNull);
        expect(DatingPhotoMemory.get('k5'), isNotNull);
        final registry = DeviceWipeRegistry();
        registerDatingDeviceWipes(registry);
        await registry.run(WipeMoment.quickExit);
        expect(DatingPhotoMemory.length, 0);
        // Fix round 1 (M-2): sign-out empties them too.
        DatingPhotoMemory.put('k', Uint8List.fromList([1]));
        await registry.run(WipeMoment.signOut);
        expect(DatingPhotoMemory.length, 0);
      },
    );

    test('photos load through memory: each URL fetched once', () async {
      await DatingPhotoMemory.clear();
      final fake = FakeDatingToday();
      final fetched = <String>[];
      Future<Uint8List?> fetch(String url) async {
        fetched.add(url);
        return Uint8List.fromList([1]);
      }

      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i1'),
        hasLength(2),
      );
      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i1'),
        hasLength(2),
      );
      expect(fetched, ['https://s.test/1', 'https://s.test/2']);
      fake.urls = null;
      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i2'),
        isEmpty,
      );
    });
  });

  group('the reasons (§5.8)', () {
    DatingIntroCard card(
      List<String> reasons, [
      Map<String, Object?> over = const {},
    ]) =>
        DatingIntroCard.fromJson(
          datingCardJson('a', {'reasons': reasons, ...over}),
        )!;

    test(
      'each id is its reviewed copy; at most three; unknown ids show nothing',
      () {
        expect(
          datingReasonLines(
            loc,
            card([
              'same_intention',
              'children_want_yes',
              'same_region',
              'compatible_intention',
            ]),
          ),
          [
            loc.dating_reasonSameCommitted,
            loc.dating_reasonChildrenYes,
            loc.dating_reasonSamePlace(loc.dating_region_gh_aa),
          ],
        );
        // Fix round 1 (M-4): faith_matters needs the card to show faith.
        expect(
          datingReasonLines(
            loc,
            card(
              ['made_up', 'faith_matters'],
              {
                'faith': {'faith': 'christian'},
              },
            ),
          ),
          [loc.dating_reasonFaithMatters],
        );
        expect(
          datingReasonLine(
            loc,
            'same_intention_timeline',
            card([], {
              'intention': 'marriage',
              'marriage_timeline': 'few_years',
            }),
          ),
          loc.dating_reasonMarriageFew,
        );
        expect(
          datingReasonLine(
            loc,
            'same_faith',
            card([], {
              'faith': {'faith': 'christian'},
            }),
          ),
          contains('Christian'),
        );
        expect(datingReasonLine(loc, 'same_faith', card([])), isNull);
        expect(datingReasonLine(loc, 'same_side', card([])), isNull);
        for (final (id, line) in [
          ('children_want_no', loc.dating_reasonChildrenNo),
          ('children_have_both', loc.dating_reasonChildrenHave),
          ('family_same_early', loc.dating_reasonFamilyEarly),
          ('family_same_when_serious', loc.dating_reasonFamilyWhenSerious),
          ('family_same_our_decision', loc.dating_reasonFamilyOwn),
          ('across_borders', loc.dating_reasonAcrossBorders),
        ]) {
          expect(datingReasonLine(loc, id, card([])), line, reason: id);
        }
      },
    );
  });

  testWidgets(
    'a caption is its photo\'s spoken label, never printed (carry 13)',
    (t) async {
      final c = DatingIntroCard.fromJson(datingCardJson('a'))!;
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DatingCardView(
                card: c.card,
                photos: [Uint8List(0), Uint8List(0)],
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Photo 1 of 2. At the beach in Busua'),
        findsOneWidget,
      );
      await t.drag(find.byType(PageView), const Offset(-400, 0));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 2'), findsOneWidget);
      expect(find.text('At the beach in Busua'), findsNothing);
      handle.dispose();
    },
  );
}
