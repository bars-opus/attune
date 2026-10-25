import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The exact keys a client may count (Spec 1 §4.3 W1b, review S-2): the
/// rows of public.metric_client_keys. Anything else is ignored by the
/// server, so only these can be passed. `anonOk` marks the pre-auth funnel.
/// Kept in step with the seed in supabase/migrations/*_metric_counters.sql by
/// test/core/metrics/metric_counter_test.dart.
enum ClientMetricKey {
  welcomePreviewRelationship('welcome_preview:relationship', anonOk: true),
  welcomePreviewDating('welcome_preview:dating', anonOk: true),
  welcomePreviewJustMe('welcome_preview:just_me', anonOk: true),
  guestAgeOk('guest_age_ok', anonOk: true),
  signupStarted('signup_started', anonOk: true),
  signupStepName('signup_step:name', anonOk: true),
  signupStepDob('signup_step:dob', anonOk: true),
  signupStepPhone('signup_step:phone', anonOk: true),
  signupAgeStop('signup_age_stop', anonOk: true),
  pushAskShownR2('push_ask_shown:r2'),
  pushAskShownR4('push_ask_shown:r4'),
  pushAskShownJ3('push_ask_shown:j3'),
  pushAskGrantedR2('push_ask_granted:r2'),
  pushAskGrantedR4('push_ask_granted:r4'),
  pushAskGrantedJ3('push_ask_granted:j3'),
  inviteSharedWhatsapp('invite_shared:whatsapp'),
  inviteSharedShare('invite_shared:share'),
  inviteSharedQr('invite_shared:qr'),
  inviteSharedCopy('invite_shared:copy'),
  inviteNewDay7('invite_new_day7'),
  inviteDay30Shown('invite_day30_shown'),
  opinionBlockedContactInfo('opinion_blocked:contact_info'),
  opinionBlockedSlur('opinion_blocked:slur'),
  opinionBlockedExplicit('opinion_blocked:explicit'),
  supportLinkOpenedOpinions('support_link_opened:opinions'),
  supportLinkOpenedJournal('support_link_opened:journal');

  const ClientMetricKey(this.key, {this.anonOk = false});

  final String key;
  final bool anonOk;
}

typedef MetricSender = Future<void> Function(String key);

/// Fire-and-forget counting: a metric never waits, blocks or throws.
/// Counts are advisory; nothing in the app or on the server decides on them.
class MetricCounter {
  MetricCounter(this._send);

  final MetricSender _send;

  void bump(ClientMetricKey key) {
    unawaited(
      Future<void>.sync(() => _send(key.key)).catchError((Object _) {}),
    );
  }
}

final metricCounterProvider = Provider<MetricCounter>(
  (ref) => MetricCounter(
    (key) => Supabase.instance.client
        .rpc('bump_metric', params: {'p_key': key})
        .timeout(const Duration(seconds: 10)),
  ),
);
