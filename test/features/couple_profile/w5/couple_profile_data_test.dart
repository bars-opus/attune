// Spec 1 W5 (§3.8 About us, §3.14, §4.3 W5, §5.3, §5.8): the model reads
// the server's answers (attribution as a first name, never an id), the
// patches are the server's keys, the service puts refusals in the app's
// hands, the offline outbox queues per account and replays, the effective
// flag needs flow_couples_v2, and the outbox is wiped at sign-out only.
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';

const _rel = 'rel-w5';

void main() {
  test('MyDateFormat: month name, month and year, year (W5)', () {
    expect(MyDateFormat.toMonth(DateTime(2024, 10, 9)), 'October');
    expect(MyDateFormat.toMonthYear(DateTime(2024, 10, 9)), 'October 2024');
    expect(MyDateFormat.toYear(DateTime(1999, 4, 2)), '1999');
  });

  test('a profile reads every answer and the attribution, never an id', () {
    final profile = CoupleProfile.fromJson(
      aboutUsJson(
        readOnly: true,
        readUntil: '2026-12-01T10:00:00+00:00',
        togetherSince: '2024-10-01',
        precision: 'month',
        stage: 'married',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
          {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
        ],
        living: 'apart_nearby',
        children: 'yes',
        bands: ['13to17', '18plus', 'teen'],
        anniversary: 'ceremony_2',
        reminderId: 'rem-1',
        changes: {
          'stage': {
            'changed_by_me': false,
            'changed_by_first_name': 'Yaw',
            'changed_at': '2026-11-01T09:00:00+00:00',
          },
          'living': {
            'changed_by_me': true,
            'changed_at': '2026-11-02T09:00:00+00:00',
          },
          'children': {'changed_by_me': true},
        },
      ),
    );
    expect(profile.readOnly, isTrue);
    expect(profile.readUntil, DateTime.utc(2026, 12, 1, 10).toLocal());
    expect(
      profile.togetherSince,
      TogetherSince(DateTime(2024, 10), DatePrecision.month),
    );
    expect(profile.stage, CoupleStage.married);
    expect(profile.ceremonies, [
      const Ceremony(year: 1999, label: CeremonyLabel.customary),
      const Ceremony(
        year: 2004,
        month: 8,
        day: 14,
        label: CeremonyLabel.church,
      ),
    ]);
    expect(profile.living, Living.apartNearby);
    expect(profile.children, Children.yes);
    expect(profile.childAgeBands, [
      ChildAgeBand.thirteenToSeventeen,
      ChildAgeBand.eighteenPlus,
    ], reason: 'an unknown band is dropped');
    expect(profile.anniversarySource, AnniversarySource.ceremony2);
    expect(profile.anniversaryDate, DateTime(2004, 8, 14));
    expect(profile.anniversaryReminderId, 'rem-1');
    expect(profile.changes[AboutUsField.stage]!.byFirstName, 'Yaw');
    expect(profile.changes[AboutUsField.stage]!.byMe, isFalse);
    expect(profile.changes[AboutUsField.living]!.byMe, isTrue);
    expect(
      profile.changes.containsKey(AboutUsField.children),
      isFalse,
      reason: 'no time, no line',
    );
    expect(profile.isEmpty, isFalse);
    expect(CoupleProfile.fromJson(aboutUsJson()).isEmpty, isTrue);
  });

  test('patches carry only the answered question\'s server keys', () {
    expect(AboutUsPatch.stage(CoupleStage.other, words: 'Courting').values, {
      'stage': 'other',
      'stage_words': 'Courting',
    });
    expect(AboutUsPatch.stage(CoupleStage.dating, words: 'ignored').values, {
      'stage': 'dating',
      'stage_words': null,
    });
    expect(
      AboutUsPatch.togetherSince(
        TogetherSince(DateTime(2024, 10, 9), DatePrecision.day),
      ).values,
      {'together_since': '2024-10-09', 'together_since_precision': 'day'},
    );
    expect(AboutUsPatch.togetherSince(null).values, {
      'together_since': null,
      'together_since_precision': null,
    });
    expect(
      AboutUsPatch.children(Children.none, bands: [ChildAgeBand.under2]).values,
      {'children': 'none', 'child_age_bands': <String>[]},
      reason: 'bands only with Yes',
    );
    expect(
      AboutUsPatch.anniversary(
        AnniversarySource.togetherSince,
        completedSince: TogetherSince(DateTime(2016, 3, 12), DatePrecision.day),
      ).values,
      {
        'together_since': '2016-03-12',
        'together_since_precision': 'day',
        'anniversary_source': 'together_since',
      },
    );
    final merged = AboutUsPatch.living(
      Living.together,
    ).merge(AboutUsPatch.living(Living.longDistance));
    expect(merged.values, {'living': 'long_distance'}, reason: 'last wins');
  });

  test('an answer queued offline shows the server\'s rules at once', () {
    final married = CoupleProfile.fromJson(
      aboutUsJson(
        stage: 'married',
        ceremonies: [
          {'year': 2010, 'month': 5, 'day': 1},
        ],
        anniversary: 'ceremony_1',
        children: 'yes',
        bands: ['2to5'],
      ),
    );
    final engaged = married.applying(AboutUsPatch.stage(CoupleStage.engaged));
    expect(engaged.ceremonies, isEmpty, reason: 'leaving Married');
    expect(engaged.anniversarySource, AnniversarySource.off);
    expect(engaged.pendingSync, isTrue);
    final noKids = married.applying(AboutUsPatch.children(Children.none));
    expect(noKids.childAgeBands, isEmpty);
    final month = married.applying(
      AboutUsPatch.togetherSince(
        TogetherSince(DateTime(2019, 6, 19), DatePrecision.month),
      ),
    );
    expect(month.togetherSince!.date, DateTime(2019, 6));
  });

  test('a future civil date is refused before it is sent', () {
    final today = DateTime(2026, 11, 2, 23, 59);
    expect(isFutureCivilDate(DateTime(2026, 11, 2), today), isFalse);
    expect(isFutureCivilDate(DateTime(2026, 11, 3), today), isTrue);
  });

  group('the service', () {
    test('calls the shared profile or the draft with its patch', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await service.fetch(const AboutUsTarget.shared(_rel));
      await service.fetch(const AboutUsTarget.draft());
      await service.update(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await service.update(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      expect(server.calls.map((c) => c.$1), [
        'get_couple_profile',
        'get_my_couple_profile_draft',
        'update_couple_profile',
        'update_my_couple_profile_draft',
      ]);
      expect(server.calls[0].$2, {'p_relationship_id': _rel});
      expect(server.calls[2].$2, {
        'p_relationship_id': _rel,
        'p_patch': {'living': 'together'},
      });
      expect(server.calls[3].$2, {
        'p_patch': {'living': 'together'},
      });
    });

    test('every refusal is typed; anything else is offline', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      for (final (message, reason) in [
        ('couple_profile:read_only', AboutUsRefusal.readOnly),
        ('couple_profile:not_found', AboutUsRefusal.notFound),
        ('couple_profile:not_relationship', AboutUsRefusal.notRelationship),
        ('couple_profile:future_date', AboutUsRefusal.futureDate),
        (
          'couple_profile:too_many_ceremonies',
          AboutUsRefusal.tooManyCeremonies,
        ),
        (
          'couple_profile:ceremonies_need_married',
          AboutUsRefusal.ceremoniesNeedMarried,
        ),
        ('couple_profile:bands_need_yes', AboutUsRefusal.bandsNeedYes),
        (
          'couple_profile:anniversary_needs_day',
          AboutUsRefusal.anniversaryNeedsDay,
        ),
        ('couple_profile:unknown_key', AboutUsRefusal.invalid),
      ]) {
        server.failNext = FakeCoupleProfileServer.refusal(message);
        await expectLater(
          service.update(
            const AboutUsTarget.shared(_rel),
            AboutUsPatch.living(Living.together),
          ),
          throwsA(
            isA<AboutUsRefused>().having((r) => r.reason, 'reason', reason),
          ),
          reason: message,
        );
      }
      for (final error in [
        FakeCoupleProfileServer.refusal('permission denied'),
        TimeoutException('slow'),
      ]) {
        server.failNext = error;
        await expectLater(
          service.fetch(const AboutUsTarget.draft()),
          throwsA(isA<AboutUsOffline>()),
        );
      }
    });
  });

  group('the outbox', () {
    Future<(AboutUsOutbox, SharedPreferences)> outbox(
      String userId, [
      Map<String, Object> values = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      return (AboutUsOutbox(prefs, userId: userId), prefs);
    }

    test('queues per account and target, the last write winning', () async {
      final (box, prefs) = await outbox('u-a');
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(
          Living.longDistance,
        ).merge(AboutUsPatch.stage(CoupleStage.dating)),
      );
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.apartNearby),
      );
      expect(box.pending(const AboutUsTarget.shared(_rel))!.values, {
        'living': 'long_distance',
        'stage': 'dating',
        'stage_words': null,
      });
      expect(box.pending(const AboutUsTarget.draft())!.values, {
        'living': 'apart_nearby',
      });
      expect(prefs.getKeys(), {'attune.flow.u-a.about_us_outbox'});
      expect(
        AboutUsOutbox(
          prefs,
          userId: 'u-b',
        ).pending(const AboutUsTarget.draft()),
        isNull,
        reason: 'another account on the phone sees nothing',
      );
    });

    test('a replay sends, drops a refusal, keeps what is offline', () async {
      final (box, prefs) = await outbox('u-a');
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await box.flush(service);
      expect(server.count('update_couple_profile'), 1);
      expect(prefs.getKeys(), isEmpty, reason: 'sent');

      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      server.failNext = FakeCoupleProfileServer.refusal(
        'couple_profile:read_only',
      );
      await box.flush(service);
      expect(prefs.getKeys(), isEmpty, reason: 'a refusal cannot succeed');

      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      // Fix round 1, I-2: only a server that answered counts toward the
      // cap (being offline never does: about_us_replay_test.dart).
      server.failUpdates = FakeCoupleProfileServer.refusal('internal error');
      for (var i = 1; i < AboutUsOutbox.maxAttempts; i++) {
        await box.flush(service);
        expect(
          box.pending(const AboutUsTarget.draft()),
          isNotNull,
          reason: '$i',
        );
      }
      await box.flush(service);
      expect(
        box.pending(const AboutUsTarget.draft()),
        isNull,
        reason: 'dropped after ${AboutUsOutbox.maxAttempts} tries',
      );
    });

    test('an answer queued while a replay runs is kept', () async {
      final (box, _) = await outbox('u-a');
      final server = FakeCoupleProfileServer();
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      server.hold = Completer<void>();
      final replay = box.flush(CoupleProfileService(server.rpc));
      await Future<void>.delayed(Duration.zero);
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.longDistance),
      );
      server.hold!.complete();
      await replay;
      expect(box.pending(const AboutUsTarget.draft())!.values, {
        'living': 'long_distance',
      });
    });

    test('wiped at sign-out for every account, never on quick exit', () async {
      final registry = DeviceWipeRegistry();
      registerDeviceWipes(registry);
      final entry = spec1DeviceWipes().firstWhere(
        (e) => e.id == 'spec1.about_us_outbox',
      );
      expect(entry.moments, {WipeMoment.signOut});
      expect(entry.keys.join(), isNot(contains('dating')));
      SharedPreferences.setMockInitialValues({
        'attune.flow.u-a.about_us_outbox': '{}',
        'attune.flow.u-b.about_us_outbox': '{}',
        'attune.flow.u-a.partner_first_name': 'Ama',
      });
      await registry.run(WipeMoment.signOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where(AboutUsOutbox.isOutboxKey), isEmpty);
    });
  });

  test(
    'the shared profile refetches on a together signal, not on subscribe',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = FakeCoupleProfileServer();
      final signals = StreamController<void>.broadcast();
      addTearDown(signals.close);
      final c = ProviderContainer(
        overrides: [
          coupleProfileRpcProvider.overrideWithValue(server.rpc),
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-a'))),
          togetherChangeSignalProvider.overrideWith(
            (ref, id) => signals.stream,
          ),
        ],
      );
      addTearDown(c.dispose);
      const target = AboutUsTarget.shared(_rel);
      final keep = c.listen(coupleProfileProvider(target), (_, __) {});
      addTearDown(keep.close);
      await c.read(coupleProfileProvider(target).future);
      expect(server.count('get_couple_profile'), 1);
      signals.add(null); // the subscription itself
      await Future<void>.delayed(Duration.zero);
      expect(server.count('get_couple_profile'), 1);
      server.profiles[_rel] = aboutUsJson(living: 'together');
      signals.add(null); // the partner's edit
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(server.count('get_couple_profile'), 2);
      expect(
        c.read(coupleProfileProvider(target)).value!.living,
        Living.together,
      );
    },
  );

  test('couple_profile is effective only with flow_couples_v2', () async {
    for (final (couples, profile, want) in [
      (true, true, true),
      (true, false, false),
      (false, true, false),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          signInFlowV2Provider.overrideWithValue(true),
          flowFlagsGatewayProvider.overrideWithValue(
            FakeFlowFlagsGateway(
              pathsV2: true,
              couplesV2: couples,
              coupleProfile: profile,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(flowFlagsProvider.future);
      expect(
        c.read(coupleProfileEnabledProvider),
        want,
        reason: '$couples $profile',
      );
    }
    // The cached copy carries it to the next first frame.
    SharedPreferences.setMockInitialValues({
      FlowFlagsCache.key: '{"paths":true,"couples":true,"couple_profile":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(FlowFlagsCache(prefs).read()!.coupleProfile, isTrue);
  });

  // Batch 3 carries (preflight F-1, F-2; P-17): a shared phone. Kofi
  // answers About us while his invite waits, his session ends without a
  // sign-out (no wipe runs), and Ama signs in on the same phone.
  group('a shared phone', () {
    Future<
      (
        ProviderContainer,
        FakeHomeAuth,
        FakeCoupleProfileServer,
        SharedPreferences,
      )
    >
    phone(String? userId) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = FakeHomeAuth(userId == null ? null : testUser(userId));
      addTearDown(auth.changes.close);
      final server =
          FakeCoupleProfileServer()..caller = () => auth.currentUser?.id;
      final c = ProviderContainer(
        overrides: [
          coupleProfileRpcProvider.overrideWithValue(server.rpc),
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeAuthProvider.overrideWithValue(auth),
          // Fix round 1, M-1: the replay runs only while About us is on.
          coupleProfileEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(c.dispose);
      return (c, auth, server, prefs);
    }

    test('the outbox is the account signed in now, never the first', () async {
      final (c, auth, _, _) = await phone(null);
      expect(c.read(aboutUsOutboxProvider)(), isNull, reason: 'signed out');
      auth.signIn('kofi');
      expect(c.read(aboutUsOutboxProvider)()?.userId, 'kofi');
      auth.signOut();
      expect(c.read(aboutUsOutboxProvider)(), isNull);
      auth.signIn('ama');
      expect(c.read(aboutUsOutboxProvider)()?.userId, 'ama');
    });

    test('Kofi\'s queued answer never reaches Ama after a passive '
        'sign-out', () async {
      final (c, auth, server, prefs) = await phone('kofi');
      const draft = AboutUsTarget.draft();
      server.failUpdates = TimeoutException('offline');
      final keep = c.listen(coupleProfileProvider(draft), (_, __) {});
      addTearDown(keep.close);
      await c.read(coupleProfileProvider(draft).future);
      expect(
        await c
            .read(coupleProfileProvider(draft).notifier)
            .save(AboutUsPatch.living(Living.together)),
        AboutUsSaveOutcome.queued,
      );
      expect(
        c.read(coupleProfileProvider(draft)).value!.living,
        Living.together,
      );

      // The session ends on its own (expiry, a remote revoke): no wipe.
      auth.signOut();
      auth.signIn('ama');
      server.failUpdates = null;
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getKeys(), {
        AboutUsOutbox.keyFor('kofi'),
      }, reason: 'kept for Kofi, under his own key');
      expect(c.read(aboutUsOutboxProvider)()!.pending(draft), isNull);
      await c.read(aboutUsOutboxFlushProvider)();
      final amaView = await c.read(coupleProfileProvider(draft).future);
      expect(amaView.living, isNull, reason: 'Ama sees none of it');
      expect(amaView.pendingSync, isFalse);
      expect(
        server.callersOf('update_my_couple_profile_draft'),
        ['kofi'],
        reason: 'only Kofi\'s own failed try; nothing is sent as Ama',
      );
      expect(server.profiles['draft:ama']?['living'], isNull);
      expect(
        await c
            .read(coupleProfileProvider(draft).notifier)
            .save(AboutUsPatch.children(Children.none)),
        AboutUsSaveOutcome.saved,
      );
      expect(prefs.getKeys(), {AboutUsOutbox.keyFor('kofi')});

      // Kofi again: his answer replays into his own draft.
      auth.signOut();
      auth.signIn('kofi');
      await c.read(aboutUsOutboxFlushProvider)();
      expect(server.callersOf('update_my_couple_profile_draft'), [
        'kofi',
        'ama',
        'kofi',
      ]);
      expect(server.profiles['draft:kofi']!['living'], 'together');
      expect(server.profiles['draft:ama']!['living'], isNull);
      expect(prefs.getKeys(), isEmpty, reason: 'sent');
    });

    test('a save racing an account change sends nothing', () async {
      final (c, auth, server, prefs) = await phone('kofi');
      const draft = AboutUsTarget.draft();
      final notifier = c.read(coupleProfileProvider(draft).notifier);
      final keep = c.listen(coupleProfileProvider(draft), (_, __) {});
      addTearDown(keep.close);
      await c.read(coupleProfileProvider(draft).future);
      auth.signOut();
      auth.signIn('ama');
      await expectLater(
        notifier.save(AboutUsPatch.living(Living.together)),
        throwsA(isA<AboutUsOffline>()),
      );
      expect(server.count('update_my_couple_profile_draft'), 0);
      expect(prefs.getKeys(), isEmpty, reason: 'nothing queued for anyone');
    });

    test('a replay stops when the account changes part-way', () async {
      final (c, auth, server, prefs) = await phone('kofi');
      final kofi = c.read(aboutUsOutboxProvider)()!;
      await kofi.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await kofi.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.longDistance),
      );
      server.hold = Completer<void>();
      final replay = c.read(aboutUsOutboxFlushProvider)();
      await Future<void>.delayed(Duration.zero);
      auth.signOut();
      auth.signIn('ama');
      server.hold!.complete();
      await replay;
      expect(
        server.callers,
        ['kofi'],
        reason: 'the first left as Kofi; the rest never leaves as Ama',
      );
      // Fix round 5: the draft's answers replay first.
      final left = AboutUsOutbox(prefs, userId: 'kofi');
      expect(left.pending(const AboutUsTarget.draft()), isNull);
      expect(
        left.pending(const AboutUsTarget.shared(_rel))!.values,
        {'living': 'together'},
        reason: 'kept for Kofi, untried',
      );
    });

    // Fix round 1 (ruling I-4): with a link it is re-routed to the shared
    // profile (about_us_replay_test.dart); with none, it is dropped.
    test('a draft answer refused with no link to re-route to is dropped, '
        'never an orphan draft (F-2)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final box = AboutUsOutbox(prefs, userId: 'kofi');
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      server.linked = true; // The draft is gone; no active link is found.
      await box.flush(service, linkedRelationshipId: () async => null);
      expect(server.count('update_my_couple_profile_draft'), 1);
      expect(server.count('update_couple_profile'), 0);
      expect(
        box.pending(const AboutUsTarget.draft()),
        isNull,
        reason: 'refused: dropped at once, not retried',
      );
      expect(prefs.getKeys(), isEmpty);
      expect(
        server.profiles.containsKey('draft'),
        isFalse,
        reason: 'no draft row for a later link to adopt',
      );
      await expectLater(
        service.fetch(const AboutUsTarget.draft()),
        throwsA(
          isA<AboutUsRefused>().having(
            (r) => r.reason,
            'reason',
            AboutUsRefusal.notFound,
          ),
        ),
      );
    });

    test('the queued answer survives quick exit and goes at sign-out '
        '(P-17)', () async {
      SharedPreferences.setMockInitialValues({
        AboutUsOutbox.keyFor('kofi'): '{}',
        AboutUsOutbox.keyFor('ama'): '{}',
      });
      final prefs = await SharedPreferences.getInstance();
      final registry = DeviceWipeRegistry();
      registerDeviceWipes(registry);
      await registry.run(WipeMoment.quickExit);
      expect(
        prefs.getKeys().where(AboutUsOutbox.isOutboxKey),
        hasLength(2),
        reason: 'quick exit keeps it',
      );
      await registry.run(WipeMoment.signOut);
      expect(prefs.getKeys().where(AboutUsOutbox.isOutboxKey), isEmpty);
      // Sign-out's own clear keeps none of it either.
      await prefs.setString(AboutUsOutbox.keyFor('kofi'), '{}');
      await PreferencesService(prefs).clearUserData();
      expect(prefs.getKeys().where(AboutUsOutbox.isOutboxKey), isEmpty);
      expect(
        PreferencesService.keptKeys.where(AboutUsOutbox.isOutboxKey),
        isEmpty,
      );
      expect(
        PreferencesService.keptPrefixes.where(
          (p) => AboutUsOutbox.keyFor('kofi').startsWith(p),
        ),
        isEmpty,
      );
    });
  });
}
