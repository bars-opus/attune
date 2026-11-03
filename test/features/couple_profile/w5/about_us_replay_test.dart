// Spec 1 W5, batch-3 fix round 1 (batch-3-review.md; rulings I-3, I-4 in
// progress.md): a queued About us answer never undoes a newer save (I-1),
// being offline never uses up its tries (I-2), nothing on the phone says
// Dating (I-3, D20), a draft answer replayed after the accept fills the
// shared profile's empty fields (I-4), and the minors M-1, M-3, M-4, M-5.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/home_harness.dart';

const _rel = 'rel-w5';
const _draft = AboutUsTarget.draft();
const _shared = AboutUsTarget.shared(_rel);

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

ProviderContainer _phone(
  FakeCoupleProfileServer server,
  SharedPreferences prefs,
  FakeHomeAuth auth, {
  bool enabled = true,
  String? linked,
}) {
  final c = ProviderContainer(
    overrides: [
      coupleProfileRpcProvider.overrideWithValue(server.rpc),
      sharedPreferencesProvider.overrideWithValue(prefs),
      homeAuthProvider.overrideWithValue(auth),
      coupleProfileEnabledProvider.overrideWithValue(enabled),
      aboutUsLinkedRelationshipIdProvider.overrideWithValue(() async => linked),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Map<String, Object?> _byAma() => {
  'changed_by_me': false,
  'changed_by_first_name': 'Ama',
  'changed_at': '2026-11-01T09:00:00+00:00',
};

List<Object?> _patches(FakeCoupleProfileServer server, String fn) => [
  for (final call in server.calls)
    if (call.$1 == fn) call.$2!['p_patch'],
];

void main() {
  // Fix round 2 (NI-1): the queued answers replay first, each on its own,
  // then the new answer on its own (the merged save is gone).
  Future<(ProviderContainer, CoupleProfileNotifier)> online(
    FakeCoupleProfileServer server,
    SharedPreferences prefs,
  ) async {
    final c = _phone(server, prefs, FakeHomeAuth(testUser('kofi')));
    final keep = c.listen(coupleProfileProvider(_shared), (_, __) {});
    addTearDown(keep.close);
    await c.read(coupleProfileProvider(_shared).future);
    return (c, c.read(coupleProfileProvider(_shared).notifier));
  }

  test('I-1: a newer online save is never undone by an older queued '
      'answer', () async {
    final prefs = await _prefs();
    final server = FakeCoupleProfileServer();
    final (c, notifier) = await online(server, prefs);

    server.failUpdates = TimeoutException('offline');
    expect(
      await notifier.save(
        AboutUsPatch.living(
          Living.together,
        ).merge(AboutUsPatch.stage(CoupleStage.engaged)),
      ),
      AboutUsSaveOutcome.queued,
    );
    server.failUpdates = null; // Back online, before any resume.
    expect(
      await notifier.save(AboutUsPatch.living(Living.longDistance)),
      AboutUsSaveOutcome.saved,
    );
    expect(
      _patches(server, 'update_couple_profile').skip(1),
      [
        {'living': 'together', 'stage': 'engaged', 'stage_words': null},
        {'living': 'long_distance'},
      ],
      reason: 'the queued answer first, then the new one, each on its own',
    );
    expect(
      AboutUsOutbox(prefs, userId: 'kofi').pending(_shared),
      isNull,
      reason: 'nothing owed',
    );

    await c.read(aboutUsOutboxFlushProvider)(); // The next resume.
    expect(server.profiles[_rel]!['living'], 'long_distance');
    expect(server.profiles[_rel]!['stage'], 'engaged');
    expect(
      server.count('update_couple_profile'),
      3,
      reason:
          'the failed try, the replay and the save; the resume sends '
          'nothing',
    );
  });

  test('NI-1: Married to Engaged with a ceremony and Living queued: '
      'Living survives (the review\'s probe)', () async {
    final prefs = await _prefs();
    final server = FakeCoupleProfileServer(
      profiles: {_rel: aboutUsJson(stage: 'married')},
    )..enforcesStageRules = true;
    final (_, notifier) = await online(server, prefs);
    server.failUpdates = TimeoutException('offline');
    await notifier.save(AboutUsPatch.ceremonies([const Ceremony(year: 2010)]));
    await notifier.save(AboutUsPatch.living(Living.together));
    server.failUpdates = null; // Back online mid-flow, no resume.
    expect(
      await notifier.save(AboutUsPatch.stage(CoupleStage.engaged)),
      AboutUsSaveOutcome.saved,
    );
    expect(server.profiles[_rel]!['living'], 'together');
    expect(server.profiles[_rel]!['stage'], 'engaged');
    expect(server.profiles[_rel]!['ceremonies'], isEmpty);
    expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_shared), isNull);
  });

  test('NI-1: a refusal drops only the answer refused', () async {
    final prefs = await _prefs();
    final server = FakeCoupleProfileServer(
      profiles: {_rel: aboutUsJson(stage: 'married')},
    )..enforcesStageRules = true;
    final (_, notifier) = await online(server, prefs);
    server.failUpdates = TimeoutException('offline');
    await notifier.save(AboutUsPatch.ceremonies([const Ceremony(year: 2010)]));
    await notifier.save(AboutUsPatch.living(Living.together));
    server.failUpdates = null;
    // Ama moved the stage to Engaged meanwhile: the queued ceremony can't
    // be taken any more; the queued Living can.
    server.profiles[_rel]!['stage'] = 'engaged';
    expect(
      await notifier.save(AboutUsPatch.children(Children.none)),
      AboutUsSaveOutcome.saved,
    );
    expect(server.profiles[_rel]!['living'], 'together');
    expect(server.profiles[_rel]!['children'], 'none');
    expect(server.profiles[_rel]!['ceremonies'], isEmpty);
    expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_shared), isNull);
  });

  group('NM-1: answers given offline stay separate, in order', () {
    test('each answer is its own entry, and a later replay drops only the '
        'one refused', () async {
      final prefs = await _prefs();
      final server = FakeCoupleProfileServer(
        profiles: {_rel: aboutUsJson(stage: 'married')},
      )..enforcesStageRules = true;
      final (c, notifier) = await online(server, prefs);
      server.failUpdates = TimeoutException('offline');
      await notifier.save(
        AboutUsPatch.ceremonies([const Ceremony(year: 2010)]),
      );
      await notifier.save(AboutUsPatch.living(Living.together));
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      expect(box.pendingPatches(_shared).map((p) => p.values), [
        {
          'ceremonies': [
            {'year': 2010},
          ],
        },
        {'living': 'together'},
      ]);
      server.failUpdates = null;
      server.profiles[_rel]!['stage'] = 'engaged';
      await c.read(aboutUsOutboxFlushProvider)();
      expect(server.profiles[_rel]!['living'], 'together');
      expect(box.pending(_shared), isNull);
    });

    test('the queued answer refused, the new one offline: the new one is '
        'kept alone and arrives', () async {
      final prefs = await _prefs();
      final server = FakeCoupleProfileServer(
        profiles: {_rel: aboutUsJson(stage: 'engaged')},
      )..enforcesStageRules = true;
      final (c, notifier) = await online(server, prefs);
      server.failUpdates = TimeoutException('offline');
      await notifier.save(
        AboutUsPatch.ceremonies([const Ceremony(year: 2010)]),
      );
      server.failUpdates = null;
      server.failUpdatesInOrder.addAll([null, TimeoutException('dropped')]);
      expect(
        await notifier.save(AboutUsPatch.living(Living.together)),
        AboutUsSaveOutcome.queued,
      );
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      expect(
        box.pendingPatches(_shared).map((p) => p.values),
        [
          {'living': 'together'},
        ],
        reason: 'the refused ceremony went; the new answer was never refused',
      );
      await c.read(aboutUsOutboxFlushProvider)();
      expect(server.profiles[_rel]!['living'], 'together');
      expect(box.pending(_shared), isNull);
    });

    test('a save never jumps an answer still owed: it queues behind '
        'it', () async {
      final prefs = await _prefs();
      final server = FakeCoupleProfileServer();
      final (_, notifier) = await online(server, prefs);
      server.failUpdates = TimeoutException('offline');
      await notifier.save(AboutUsPatch.living(Living.together));
      server.failUpdates = null;
      // The queued answer's replay fails once more; the new one would go.
      server.failUpdatesInOrder.add(TimeoutException('dropped'));
      expect(
        await notifier.save(AboutUsPatch.children(Children.none)),
        AboutUsSaveOutcome.queued,
      );
      expect(
        _patches(server, 'update_couple_profile'),
        [
          {'living': 'together'},
          {'living': 'together'},
        ],
        reason: 'the new answer never went ahead of the owed one',
      );
      expect(
        AboutUsOutbox(
          prefs,
          userId: 'kofi',
        ).pendingPatches(_shared).map((p) => p.values),
        [
          {'living': 'together'},
          {'children': 'none', 'child_age_bands': <String>[]},
        ],
      );
    });

    test('a replay keeps the order: an entry still owed holds the ones '
        'after it', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      await box.enqueue(_shared, AboutUsPatch.living(Living.together));
      await box.enqueue(_shared, AboutUsPatch.children(Children.none));
      final server =
          FakeCoupleProfileServer()..failUpdates = TimeoutException('offline');
      final service = CoupleProfileService(server.rpc);
      await box.flush(service);
      expect(server.count('update_couple_profile'), 1, reason: 'untried after');
      expect(box.pendingPatches(_shared), hasLength(2));
      server.failUpdates = null;
      await box.flush(service);
      expect(_patches(server, 'update_couple_profile').skip(1), [
        {'living': 'together'},
        {'children': 'none', 'child_age_bands': <String>[]},
      ]);
      expect(box.pending(_shared), isNull);
    });

    test(
      'an answer that replaces the last one wholly takes its place',
      () async {
        final prefs = await _prefs();
        final box = AboutUsOutbox(prefs, userId: 'kofi');
        await box.enqueue(_shared, AboutUsPatch.living(Living.together));
        await box.enqueue(_shared, AboutUsPatch.living(Living.longDistance));
        expect(box.pendingPatches(_shared).map((p) => p.values), [
          {'living': 'long_distance'},
        ]);
      },
    );
  });

  group('I-2', () {
    test('the service says whether the server answered', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      for (final (error, answered) in [
        (TimeoutException('slow'), false),
        (const SocketException('down'), false),
        (http.ClientException('reset'), false),
        (FakeCoupleProfileServer.refusal('internal error'), true),
      ]) {
        server.failNext = error;
        await expectLater(
          service.fetch(_draft),
          throwsA(
            isA<AboutUsOffline>().having(
              (e) => e.reachedServer,
              'reachedServer',
              answered,
            ),
          ),
          reason: '$error',
        );
      }
    });

    test('being offline never counts toward the cap; the answer '
        'arrives', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      for (var i = 0; i <= AboutUsOutbox.maxAttempts; i++) {
        server.failUpdates =
            i.isEven ? TimeoutException('offline') : const SocketException('x');
        await box.flush(service);
        expect(box.pending(_draft), isNotNull, reason: 'try ${i + 1}');
      }
      server.failUpdates = null;
      await box.flush(service);
      expect(server.profiles['draft']!['living'], 'together');
      expect(box.pending(_draft), isNull);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('NM-2: a server that is down or busy is an outage', () {
    test('5xx and 429 never count; other refusals do', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      for (final (code, answered) in [
        ('503', false),
        ('502', false),
        ('504', false),
        ('500', false),
        ('429', false),
        ('PGRST002', false),
        ('57014', false),
        ('P0001', true),
        ('42501', true),
        ('400', true),
        ('PGRST116', true),
      ]) {
        server.failNext = PostgrestException(message: 'x', code: code);
        await expectLater(
          service.fetch(_draft),
          throwsA(
            isA<AboutUsOffline>().having(
              (e) => e.reachedServer,
              'reachedServer',
              answered,
            ),
          ),
          reason: code,
        );
      }
    });

    test('an outage across many launches never drops the answer', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      for (var i = 0; i <= AboutUsOutbox.maxAttempts; i++) {
        server.failUpdates = PostgrestException(
          message: 'Service Unavailable',
          code: i.isEven ? '503' : '429',
        );
        await box.flush(service);
        expect(box.pending(_draft), isNotNull, reason: 'try ${i + 1}');
      }
      server.failUpdates = null;
      await box.flush(service);
      expect(server.profiles['draft']!['living'], 'together');
      expect(box.pending(_draft), isNull);
    });
  });

  group('I-3 (D20)', () {
    test('nothing stored on the phone says dating; the server still gets '
        'it', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      await box.enqueue(_draft, AboutUsPatch.stage(CoupleStage.dating));
      await box.enqueue(
        _shared,
        AboutUsPatch.stage(CoupleStage.other, words: 'Dating, our way'),
      );
      final disk = [
        for (final key in prefs.getKeys()) '$key=${prefs.get(key)}',
      ].join('\n');
      expect(disk.toLowerCase(), isNot(contains('dating')));
      expect(box.pending(_draft)!.values, {
        'stage': 'dating',
        'stage_words': null,
      });
      expect(box.pending(_shared)!.values, {
        'stage': 'other',
        'stage_words': 'Dating, our way',
      });

      final server = FakeCoupleProfileServer();
      await box.flush(CoupleProfileService(server.rpc));
      expect(_patches(server, 'update_my_couple_profile_draft'), [
        {'stage': 'dating', 'stage_words': null},
      ]);
      expect(_patches(server, 'update_couple_profile'), [
        {'stage': 'other', 'stage_words': 'Dating, our way'},
      ]);
    });

    test('every stage and any words come back as they were', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      final words =
          'Caf${String.fromCharCode(0xE9)} '
          '${String.fromCharCodes([0x1F469, 0x200D, 0x1F469])}';
      for (final stage in CoupleStage.values) {
        final patch = AboutUsPatch.stage(stage, words: words);
        await box.enqueue(_draft, patch);
        expect(box.pending(_draft)!.values, patch.values, reason: stage.wire);
      }
      await box.enqueue(_draft, AboutUsPatch.stage(null));
      expect(box.pending(_draft)!.values, {'stage': null, 'stage_words': null});
    });
  });

  // Fix round 3 (NI-2): draft answers queued before the accept go to the
  // shared profile together, as one answer (the latest of each wins),
  // filling only what nobody has answered there.
  group('NI-2: draft answers re-routed after the accept, together', () {
    Future<(AboutUsOutbox, FakeCoupleProfileServer, CoupleProfileService)>
    queued(Map<String, dynamic> shared, List<AboutUsPatch> answers) async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      for (final answer in answers) {
        await box.enqueue(_draft, answer);
      }
      final server = FakeCoupleProfileServer(profiles: {_rel: shared})
        ..linked = true; // Ama accepted while Kofi was offline.
      return (box, server, CoupleProfileService(server.rpc));
    }

    test('AU2 a month, then AU6 the day: the full date and the anniversary '
        'arrive', () async {
      final (box, server, service) = await queued(aboutUsJson(), [
        AboutUsPatch.togetherSince(
          TogetherSince(DateTime(2020, 3), DatePrecision.month),
        ),
        AboutUsPatch.living(Living.together),
        AboutUsPatch.anniversary(
          AnniversarySource.togetherSince,
          completedSince: TogetherSince(
            DateTime(2020, 3, 14),
            DatePrecision.day,
          ),
        ),
      ]);
      expect(box.pendingPatches(_draft), hasLength(3));
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(
        _patches(server, 'update_couple_profile'),
        [
          {
            'together_since': '2020-03-14',
            'together_since_precision': 'day',
            'living': 'together',
            'anniversary_source': 'together_since',
          },
        ],
        reason: 'one re-route, the latest of each answer',
      );
      final shared = server.profiles[_rel]!;
      expect(shared['together_since'], '2020-03-14');
      expect(shared['together_since_precision'], 'day');
      expect(shared['anniversary_source'], 'together_since');
      expect(shared['living'], 'together');
      expect(box.pending(_draft), isNull);
    });

    test(
      'Dating corrected to Engaged before linking ends as Engaged',
      () async {
        final (box, server, service) = await queued(aboutUsJson(), [
          AboutUsPatch.stage(CoupleStage.dating),
          AboutUsPatch.living(Living.together),
          AboutUsPatch.stage(CoupleStage.engaged),
        ]);
        await box.flush(service, linkedRelationshipId: () async => _rel);
        expect(server.profiles[_rel]!['stage'], 'engaged');
        expect(server.profiles[_rel]!['living'], 'together');
        expect(server.count('update_couple_profile'), 1);
        expect(box.pending(_draft), isNull);
      },
    );

    test('a field already set on the shared profile is left alone; the '
        'rest is filled', () async {
      final (box, server, service) = await queued(
        aboutUsJson(living: 'apart_nearby', changes: {'living': _byAma()}),
        [
          AboutUsPatch.living(Living.together),
          AboutUsPatch.children(Children.none),
          AboutUsPatch.living(Living.longDistance),
        ],
      );
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(_patches(server, 'update_couple_profile'), [
        {'children': 'none', 'child_age_bands': <String>[]},
      ]);
      expect(server.profiles[_rel]!['living'], 'apart_nearby');
      expect(box.pending(_draft), isNull);
    });

    test('the account changing before the send leaves them all queued, '
        'untried (F-1)', () async {
      final prefs = await _prefs();
      var signedIn = 'kofi';
      final box = AboutUsOutbox(
        prefs,
        userId: 'kofi',
        currentUserId: () => signedIn,
      );
      await box.enqueue(_draft, AboutUsPatch.stage(CoupleStage.dating));
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true;
      await box.flush(
        CoupleProfileService(server.rpc),
        linkedRelationshipId: () async {
          signedIn = 'ama'; // Ama signs in during the lookup.
          return _rel;
        },
      );
      expect(server.count('get_couple_profile'), 0);
      expect(server.count('update_couple_profile'), 0);
      expect(box.pendingPatches(_draft), hasLength(2));
      final disk = prefs.getString(AboutUsOutbox.keyFor('kofi'))!;
      expect(disk.toLowerCase(), isNot(contains('dating')), reason: 'I-3');
    });
  });

  // Fix round 4 (ruling NI-3): the re-route skips only a field the
  // partner changed last; this person's own adopted answer never blocks
  // their later queued correction.
  group('NI-3: the re-route takes over this person\'s own answers', () {
    Map<String, Object?> byMe() => {
      'changed_by_me': true,
      'changed_at': '2026-11-01T09:00:00+00:00',
    };

    // Saves [online] to the draft online, then [offline] while offline
    // (queued), then Ama accepts: the draft is adopted into the shared
    // profile as [adopted] says.
    Future<(FakeCoupleProfileServer, SharedPreferences, ProviderContainer)>
    acceptedAfter(
      AboutUsPatch online,
      AboutUsPatch offline,
      Map<String, dynamic> adopted,
    ) async {
      final prefs = await _prefs();
      final server = FakeCoupleProfileServer();
      final auth = FakeHomeAuth(testUser('kofi'));
      final c = _phone(server, prefs, auth, linked: _rel);
      final keep = c.listen(coupleProfileProvider(_draft), (_, __) {});
      addTearDown(keep.close);
      await c.read(coupleProfileProvider(_draft).future);
      final notifier = c.read(coupleProfileProvider(_draft).notifier);
      expect(await notifier.save(online), AboutUsSaveOutcome.saved);
      server.failUpdates = TimeoutException('offline');
      expect(await notifier.save(offline), AboutUsSaveOutcome.queued);
      server
        ..failUpdates = null
        ..profiles[_rel] = adopted
        ..linked = true;
      await c.read(aboutUsOutboxFlushProvider)();
      return (server, prefs, c);
    }

    test('AU2 a month online, then AU6 the day offline, then the accept: '
        'the full date and the anniversary arrive', () async {
      final (server, prefs, _) = await acceptedAfter(
        AboutUsPatch.togetherSince(
          TogetherSince(DateTime(2020, 3), DatePrecision.month),
        ),
        AboutUsPatch.anniversary(
          AnniversarySource.togetherSince,
          completedSince: TogetherSince(
            DateTime(2020, 3, 14),
            DatePrecision.day,
          ),
        ),
        aboutUsJson(
          togetherSince: '2020-03-01',
          precision: 'month',
          changes: {'together_since': byMe()},
        ),
      );
      final shared = server.profiles[_rel]!;
      expect(shared['together_since'], '2020-03-14');
      expect(shared['together_since_precision'], 'day');
      expect(shared['anniversary_source'], 'together_since');
      expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_draft), isNull);
    });

    test('Dating online, then Engaged offline, then the accept: Engaged',
        () async {
      final (server, prefs, _) = await acceptedAfter(
        AboutUsPatch.stage(CoupleStage.dating),
        AboutUsPatch.stage(CoupleStage.engaged),
        aboutUsJson(stage: 'dating', changes: {'stage': byMe()}),
      );
      expect(server.profiles[_rel]!['stage'], 'engaged');
      expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_draft), isNull);
    });

    test('a field the partner changed keeps the partner\'s answer; this '
        'person\'s own field takes the queued one', () async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      await box.enqueue(_draft, AboutUsPatch.stage(CoupleStage.engaged));
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      final server = FakeCoupleProfileServer(
        profiles: {
          _rel: aboutUsJson(
            stage: 'dating',
            living: 'apart_nearby',
            changes: {'stage': _byAma(), 'living': byMe()},
          ),
        },
      )..linked = true;
      await box.flush(
        CoupleProfileService(server.rpc),
        linkedRelationshipId: () async => _rel,
      );
      expect(_patches(server, 'update_couple_profile'), [
        {'living': 'together'},
      ]);
      expect(server.profiles[_rel]!['stage'], 'dating');
      expect(box.pending(_draft), isNull);
    });
  });

  // Fix round 4 (ruling NM-3): a refused merged re-route falls back to
  // re-routing each answer alone, so a refusal drops only that answer.
  group('NM-3: a refused merged re-route goes one by one', () {
    test('a bad value in the last answer still lets the earlier ones land',
        () async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      final later = DateTime.now().add(const Duration(days: 30));
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      await box.enqueue(_draft, AboutUsPatch.children(Children.none));
      await box.enqueue(
        _draft,
        AboutUsPatch.togetherSince(
          TogetherSince(
            DateTime(later.year, later.month, later.day),
            DatePrecision.day,
          ),
        ),
      );
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true
        ..refusesFutureDates = true;
      await box.flush(
        CoupleProfileService(server.rpc),
        linkedRelationshipId: () async => _rel,
      );
      final shared = server.profiles[_rel]!;
      expect(shared['living'], 'together');
      expect(shared['children'], 'none');
      expect(shared['together_since'], isNull);
      expect(box.pending(_draft), isNull, reason: 'only the bad one dropped');
      expect(
        server.count('update_my_couple_profile_draft'),
        1,
        reason: 'the merge is tried once, then each alone',
      );
      expect(server.count('update_couple_profile'), 4);
    });

    test('a bad value in the first answer: the rest land', () async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      final later = DateTime.now().add(const Duration(days: 30));
      await box.enqueue(
        _draft,
        AboutUsPatch.togetherSince(
          TogetherSince(
            DateTime(later.year, later.month, later.day),
            DatePrecision.day,
          ),
        ),
      );
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true
        ..refusesFutureDates = true;
      await box.flush(
        CoupleProfileService(server.rpc),
        linkedRelationshipId: () async => _rel,
      );
      expect(server.profiles[_rel]!['living'], 'together');
      expect(server.profiles[_rel]!['together_since'], isNull);
      expect(box.pending(_draft), isNull);
    });

    test('offline part-way through the one-by-one: the rest is kept, '
        'untried', () async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      await box.enqueue(_draft, AboutUsPatch.children(Children.none));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true;
      server.failUpdatesInOrder.addAll([
        FakeCoupleProfileServer.refusal('couple_profile:invalid'), // merged
        TimeoutException('offline'), // living, alone
      ]);
      final service = CoupleProfileService(server.rpc);
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(box.pendingPatches(_draft), hasLength(2));
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(server.profiles[_rel]!['living'], 'together');
      expect(server.profiles[_rel]!['children'], 'none');
      expect(box.pending(_draft), isNull);
    });
  });

  // Fix round 5 (ruling "round 5"): a save to the shared profile first
  // replays the same person's queued draft answers (re-routed), as NI-1
  // does within one target, so an older draft answer never overwrites a
  // newer shared save.
  group('Round 5: a shared save replays the draft answers first', () {
    // Kofi queued [draft] before linking; Ama has accepted since.
    Future<(FakeCoupleProfileServer, SharedPreferences, ProviderContainer)>
    linkedWith(
      AboutUsPatch draft, {
      FakeHomeAuth? auth,
      CoupleProfileRpc Function(FakeCoupleProfileServer)? rpc,
      Future<String?> Function()? lookup,
    }) async {
      final prefs = await _prefs();
      await AboutUsOutbox(prefs, userId: 'kofi').enqueue(_draft, draft);
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true;
      final c = ProviderContainer(
        overrides: [
          coupleProfileRpcProvider.overrideWithValue(
            rpc?.call(server) ?? server.rpc,
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeAuthProvider.overrideWithValue(
            auth ?? FakeHomeAuth(testUser('kofi')),
          ),
          coupleProfileEnabledProvider.overrideWithValue(true),
          aboutUsLinkedRelationshipIdProvider.overrideWithValue(
            lookup ?? () async => _rel,
          ),
        ],
      );
      addTearDown(c.dispose);
      final keep = c.listen(coupleProfileProvider(_shared), (_, __) {});
      addTearDown(keep.close);
      return (server, prefs, c);
    }

    test('the same field saved online after linking ends with the new '
        'value, and a later flush leaves it', () async {
      final (server, prefs, c) = await linkedWith(
        AboutUsPatch.living(Living.together),
      );
      await c.read(coupleProfileProvider(_shared).future);
      final notifier = c.read(coupleProfileProvider(_shared).notifier);
      expect(
        await notifier.save(AboutUsPatch.living(Living.longDistance)),
        AboutUsSaveOutcome.saved,
      );
      expect(server.profiles[_rel]!['living'], 'long_distance');
      await c.read(aboutUsOutboxFlushProvider)(); // The next resume.
      expect(server.profiles[_rel]!['living'], 'long_distance');
      expect(prefs.getKeys(), isEmpty, reason: 'nothing owed');
    });

    test('a draft answer for another field still lands, under the fill '
        'rule, before the new answer', () async {
      final (server, prefs, c) = await linkedWith(
        AboutUsPatch.children(Children.none),
      );
      await c.read(coupleProfileProvider(_shared).future);
      await c
          .read(coupleProfileProvider(_shared).notifier)
          .save(AboutUsPatch.living(Living.together));
      expect(_patches(server, 'update_couple_profile'), [
        {'children': 'none', 'child_age_bands': <String>[]},
        {'living': 'together'},
      ]);
      expect(prefs.getKeys(), isEmpty);
    });

    test('F-1: the account changing between the replay and the save sends '
        'and queues nothing more', () async {
      final auth = FakeHomeAuth(testUser('kofi'));
      final (server, prefs, c) = await linkedWith(
        AboutUsPatch.children(Children.none),
        auth: auth,
        rpc:
            (fake) => (fn, params) async {
              final result = await fake.call(fn, params);
              if (fn == 'update_couple_profile') {
                auth.currentUser = testUser('ama'); // No auth event yet.
              }
              return result;
            },
      );
      await c.read(coupleProfileProvider(_shared).future);
      await expectLater(
        c
            .read(coupleProfileProvider(_shared).notifier)
            .save(AboutUsPatch.living(Living.together)),
        throwsA(isA<AboutUsOffline>()),
      );
      expect(_patches(server, 'update_couple_profile'), [
        {'children': 'none', 'child_age_bands': <String>[]},
      ], reason: 'the re-routed draft answer only');
      expect(server.profiles[_rel]!['living'], isNull);
      expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_shared), isNull);
      expect(AboutUsOutbox(prefs, userId: 'ama').pending(_shared), isNull);
    });

    test('the draft replay offline: the new answer queues behind it, and '
        'the next flush ends with the new value', () async {
      var online = false;
      final (server, prefs, c) = await linkedWith(
        AboutUsPatch.living(Living.together),
        lookup: () async {
          if (!online) throw TimeoutException('offline');
          return _rel;
        },
      );
      await c.read(coupleProfileProvider(_shared).future);
      expect(
        await c
            .read(coupleProfileProvider(_shared).notifier)
            .save(AboutUsPatch.living(Living.longDistance)),
        AboutUsSaveOutcome.queued,
      );
      expect(server.profiles[_rel]!['living'], isNull);
      online = true;
      await c.read(aboutUsOutboxFlushProvider)();
      expect(server.profiles[_rel]!['living'], 'long_distance');
      expect(prefs.getKeys(), isEmpty);
    });

    test('the flush replays the draft before the shared answers, whatever '
        'order they were queued in', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      await box.enqueue(_shared, AboutUsPatch.living(Living.longDistance));
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true;
      await box.flush(
        CoupleProfileService(server.rpc),
        linkedRelationshipId: () async => _rel,
      );
      expect(server.profiles[_rel]!['living'], 'long_distance');
      expect(prefs.getKeys(), isEmpty);
    });

    test('the flush: a draft answer still owed holds the shared answers '
        'behind it', () async {
      final prefs = await _prefs();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      await box.enqueue(_shared, AboutUsPatch.living(Living.longDistance));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..linked = true;
      final service = CoupleProfileService(server.rpc);
      var online = false;
      Future<String?> lookup() async {
        if (!online) throw TimeoutException('offline');
        return _rel;
      }

      await box.flush(service, linkedRelationshipId: lookup);
      expect(server.count('update_couple_profile'), 0);
      expect(box.pending(_shared), isNotNull);
      online = true;
      await box.flush(service, linkedRelationshipId: lookup);
      expect(server.profiles[_rel]!['living'], 'long_distance');
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('I-4: a draft answer replayed after the invite is accepted', () {
    Future<(AboutUsOutbox, FakeCoupleProfileServer, CoupleProfileService)>
    accepted(Map<String, dynamic> shared) async {
      final box = AboutUsOutbox(await _prefs(), userId: 'kofi');
      final server = FakeCoupleProfileServer(profiles: {_rel: shared})
        ..linked = true; // Ama accepted while Kofi was offline.
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      return (box, server, CoupleProfileService(server.rpc));
    }

    test('fills a shared field nobody has answered', () async {
      final (box, server, service) = await accepted(aboutUsJson());
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(server.calls.map((c) => c.$1), [
        'update_my_couple_profile_draft',
        'get_couple_profile',
        'update_couple_profile',
      ]);
      expect(server.calls.last.$2, {
        'p_relationship_id': _rel,
        'p_patch': {'living': 'together'},
      });
      expect(server.profiles[_rel]!['living'], 'together');
      expect(box.pending(_draft), isNull);
    });

    test('leaves a field the partner or the adoption set', () async {
      final (box, server, service) = await accepted(
        aboutUsJson(living: 'apart_nearby', changes: {'living': _byAma()}),
      );
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(server.count('update_couple_profile'), 0);
      expect(server.profiles[_rel]!['living'], 'apart_nearby');
      expect(box.pending(_draft), isNull, reason: 'dropped: it was answered');
    });

    test('leaves a field the partner cleared', () async {
      final (box, server, service) = await accepted(
        aboutUsJson(changes: {'living': _byAma()}),
      );
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(server.count('update_couple_profile'), 0);
      expect(box.pending(_draft), isNull);
    });

    test('offline while re-routing: kept, not counted, then sent', () async {
      final (box, server, service) = await accepted(aboutUsJson());
      server.failUpdates = TimeoutException('offline');
      for (var i = 0; i <= AboutUsOutbox.maxAttempts; i++) {
        await box.flush(service, linkedRelationshipId: () async => _rel);
        expect(box.pending(_draft), isNotNull, reason: 'try ${i + 1}');
      }
      server.failUpdates = null;
      await box.flush(service, linkedRelationshipId: () async => _rel);
      expect(server.profiles[_rel]!['living'], 'together');
      expect(box.pending(_draft), isNull);
    });

    test('only the empty fields, never an answer the shared profile '
        'can\'t take (as adoption drops it)', () {
      final married = AboutUsPatch.stage(CoupleStage.married)
          .merge(
            AboutUsPatch.ceremonies([
              const Ceremony(year: 2010, month: 5, day: 1),
            ]),
          )
          .merge(AboutUsPatch.living(Living.together))
          .merge(AboutUsPatch.anniversary(AnniversarySource.ceremony1));
      final engagedByAma = CoupleProfile.fromJson(
        aboutUsJson(stage: 'engaged', changes: {'stage': _byAma()}),
      );
      expect(
        married.onlyUnsetIn(engagedByAma)!.values,
        {'living': 'together'},
        reason: 'no ceremonies or anniversary without Married',
      );
      expect(
        married.onlyUnsetIn(CoupleProfile.fromJson(aboutUsJson()))!.values,
        married.values,
      );
      final monthOnly = AboutUsPatch.togetherSince(
        TogetherSince(DateTime(2019, 6), DatePrecision.month),
      ).merge(AboutUsPatch.anniversary(AnniversarySource.togetherSince));
      expect(
        monthOnly.onlyUnsetIn(CoupleProfile.fromJson(aboutUsJson()))!.values,
        {'together_since': '2019-06-01', 'together_since_precision': 'month'},
        reason: 'no anniversary without a full date',
      );
      expect(
        AboutUsPatch.living(Living.together).onlyUnsetIn(
          CoupleProfile.fromJson(
            aboutUsJson(living: 'together', changes: {'living': _byAma()}),
          ),
        ),
        isNull,
      );
    });

    test('through the app: the signed-in account\'s answer is re-routed to '
        'its link', () async {
      final prefs = await _prefs();
      final auth = FakeHomeAuth(testUser('kofi'));
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..caller = () => auth.currentUser?.id;
      final c = _phone(server, prefs, auth, linked: _rel);
      await c
          .read(aboutUsOutboxProvider)()!
          .enqueue(_draft, AboutUsPatch.living(Living.together));
      server.linked = true;
      await c.read(aboutUsOutboxFlushProvider)();
      expect(server.callersOf('update_couple_profile'), ['kofi']);
      expect(server.profiles[_rel]!['living'], 'together');
      expect(prefs.getKeys(), isEmpty);
    });
  });

  test('M-1: with About us off, the replay sends nothing and keeps the '
      'answer', () async {
    final prefs = await _prefs();
    final server = FakeCoupleProfileServer();
    final c = _phone(
      server,
      prefs,
      FakeHomeAuth(testUser('kofi')),
      enabled: false,
    );
    await c
        .read(aboutUsOutboxProvider)()!
        .enqueue(_draft, AboutUsPatch.living(Living.together));
    await c.read(aboutUsOutboxFlushProvider)();
    expect(server.calls, isEmpty);
    expect(AboutUsOutbox(prefs, userId: 'kofi').pending(_draft), isNotNull);
  });

  test('M-3: a load that outlives its account shows the next one '
      'nothing', () async {
    final prefs = await _prefs();
    final auth = FakeHomeAuth(testUser('kofi'));
    final server =
        FakeCoupleProfileServer()..caller = () => auth.currentUser?.id;
    final c = _phone(server, prefs, auth);
    await c
        .read(aboutUsOutboxProvider)()!
        .enqueue(_draft, AboutUsPatch.living(Living.together));
    server.failUpdates = TimeoutException('offline');
    server.hold = Completer<void>();
    final keep = c.listen(coupleProfileProvider(_draft), (_, __) {});
    addTearDown(keep.close);
    final load = c.read(coupleProfileProvider(_draft).future);
    await Future<void>.delayed(Duration.zero);
    // The session changes before any auth event reaches the notifier.
    auth.currentUser = testUser('ama');
    server.hold!.complete();
    await expectLater(load, throwsA(isA<AboutUsOffline>()));
  });

  test('M-3: a fetch that outlives its account shows the next one '
      'nothing', () async {
    final prefs = await _prefs();
    final auth = FakeHomeAuth(testUser('kofi'));
    final server = FakeCoupleProfileServer(
      profiles: {'draft:kofi': aboutUsJson(draft: true, living: 'together')},
    )..caller = () => auth.currentUser?.id;
    final c = _phone(server, prefs, auth);
    server.hold = Completer<void>();
    final keep = c.listen(coupleProfileProvider(_draft), (_, __) {});
    addTearDown(keep.close);
    final load = c.read(coupleProfileProvider(_draft).future);
    await Future<void>.delayed(Duration.zero);
    auth.currentUser = testUser('ama'); // No auth event yet.
    server.hold!.complete();
    await expectLater(load, throwsA(isA<AboutUsOffline>()));
  });

  test('M-4: 30 February and other unreal dates are refused, never rolled '
      'over', () {
    expect(civilDate(2023, 2, 30), isNull);
    expect(civilDate(2001, 2, 29), isNull);
    expect(civilDate(2024, 4, 31), isNull);
    expect(civilDate(2024, 13, 1), isNull);
    expect(civilDate(2024, 1, 0), isNull);
    expect(civilDate(2024, 2, 29), DateTime(2024, 2, 29));
    expect(const Ceremony(year: 2023, month: 2, day: 30).fullDate, isNull);
    expect(
      const Ceremony(year: 2004, month: 8, day: 14).fullDate,
      DateTime(2004, 8, 14),
    );
    expect(
      CoupleProfile.fromJson(
        aboutUsJson(togetherSince: '2023-02-30', precision: 'day'),
      ).togetherSince,
      isNull,
    );
    expect(
      CoupleProfile.fromJson(aboutUsJson())
          .applying(
            const AboutUsPatch({
              'together_since': '2023-02-30',
              'together_since_precision': 'day',
            }),
          )
          .togetherSince,
      isNull,
    );
  });

  test('M-5: the 40-character limit counts as the server does (code '
      'points, after its clean-up)', () {
    // One grapheme, five code points: char_length counts 5.
    final family = String.fromCharCodes([
      0x1F469,
      0x200D,
      0x1F469,
      0x200D,
      0x1F467,
    ]);
    expect(stageWordsMax, 40);
    expect(stageWordsFit('a' * 40), isTrue);
    expect(stageWordsFit('a' * 41), isFalse);
    expect(stageWordsFit(family * 8), isTrue);
    expect(stageWordsFit(family * 9), isFalse, reason: '45 code points');
    expect(stageWordsFit('  ${'a' * 40}  '), isTrue, reason: 'spaces trimmed');
    expect(stageWordsFit('${'a' * 19}\n${'b' * 20}'), isTrue);
    expect(normalizeStageWords('\tWe two\n'), 'We two');
    expect(normalizeStageWords('  '), isNull);
    expect(normalizeStageWords(null), isNull);
  });

  // W5 final review NM-4 (batch-3 re-review 4 probes "LOSS?"): a session
  // that ends while the draft update is in flight keeps the departing
  // account's queued draft answers, untried, for that account.
  group('NM-4: a session ending mid-replay keeps the draft answers', () {
    List<Map> draftEntries(SharedPreferences prefs, String uid) {
      final s = prefs.getString(AboutUsOutbox.keyFor(uid));
      if (s == null) return const [];
      final m = jsonDecode(s) as Map;
      return [for (final e in (m['draft'] as List? ?? const [])) e as Map];
    }

    /// As the real lookup: answers for whoever is signed in at call time.
    Future<String?> Function() realLookup(FakeHomeAuth auth) => () async {
      final id = auth.currentUser?.id;
      return id == 'kofi' ? _rel : null;
    };

    test('a passive sign-out while the draft update is in flight', () async {
      final prefs = await _prefs();
      final auth = FakeHomeAuth(testUser('kofi'));
      addTearDown(auth.changes.close);
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..caller = (() => auth.currentUser?.id)
        ..linked = true;
      Future<Object?> rpc(String fn, Map<String, dynamic>? p) async {
        if (fn == 'update_my_couple_profile_draft') {
          server.calls.add((fn, p));
          auth.signOut(); // Passive: session expiry, no device wipe.
          throw FakeCoupleProfileServer.refusal('couple_profile:not_found');
        }
        return server.call(fn, p);
      }

      final box = AboutUsOutbox(
        prefs,
        userId: 'kofi',
        currentUserId: () => auth.currentUser?.id,
      );
      await box.enqueue(_draft, AboutUsPatch.stage(CoupleStage.engaged));
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      await box.flush(
        CoupleProfileService(rpc),
        linkedRelationshipId: realLookup(auth),
      );
      expect(server.count('update_couple_profile'), 0);
      final left = draftEntries(prefs, 'kofi');
      expect(left.length, 2, reason: 'kept, untried, for Kofi');
      expect([for (final e in left) e['attempts']], [0, 0]);
    });

    test('Kofi -> Ama (no link) while the draft update is in flight',
        () async {
      final prefs = await _prefs();
      final auth = FakeHomeAuth(testUser('kofi'));
      addTearDown(auth.changes.close);
      final server = FakeCoupleProfileServer(profiles: {_rel: aboutUsJson()})
        ..caller = (() => auth.currentUser?.id)
        ..linked = true;
      Future<Object?> rpc(String fn, Map<String, dynamic>? p) async {
        if (fn == 'update_my_couple_profile_draft') {
          server.calls.add((fn, p));
          auth.currentUser = testUser('ama');
          throw FakeCoupleProfileServer.refusal('couple_profile:not_found');
        }
        return server.call(fn, p);
      }

      final box = AboutUsOutbox(
        prefs,
        userId: 'kofi',
        currentUserId: () => auth.currentUser?.id,
      );
      await box.enqueue(_draft, AboutUsPatch.living(Living.together));
      await box.flush(
        CoupleProfileService(rpc),
        linkedRelationshipId: realLookup(auth), // Ama has no link.
      );
      expect(server.count('update_couple_profile'), 0);
      expect(prefs.getString(AboutUsOutbox.keyFor('ama')), isNull);
      expect(draftEntries(prefs, 'kofi').length, 1,
          reason: 'kept, untried, for Kofi');
    });
  });
}
