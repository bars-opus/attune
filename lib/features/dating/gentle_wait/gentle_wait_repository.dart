// Spec 2 W2 (§3.2 D0, §4.4 Gentle wait): the gentle wait's two RPCs.
// RPC-only, like every Dating read (§4.1); nothing is kept on the phone
// (§3.0, C-5): the answers live in memory while D0 is open.
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The three questions' keys, in the order D0 asks them.
const gentleWaitQuestionKeys = ['q1', 'q2', 'q3'];

/// The longest answer, in Unicode code points (the server counts with
/// char_length, so a family emoji counts as several).
const gentleWaitAnswerMax = 500;

/// What D0 shows: the wait's two dates (both null once the wait is over),
/// whether closing the shared space together can still end it sooner, and
/// the person's own saved answers.
class GentleWait {
  const GentleWait({
    this.endedAt,
    this.opensAt,
    this.canShorten = false,
    this.answers = const {},
  });

  final DateTime? endedAt;
  final DateTime? opensAt;

  /// The server's `can_shorten` (W2 final review M-4): false after the
  /// former partner deleted their account, for someone who moved on, and
  /// whenever the server didn't say so. D0 then never promises "If you both
  /// close it sooner".
  final bool canShorten;
  final Map<String, String> answers;

  factory GentleWait.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'];
    final answers = <String, String>{};
    if (raw is Map) {
      for (final key in gentleWaitQuestionKeys) {
        final value = raw[key];
        if (value is String) answers[key] = value;
      }
    }
    DateTime? at(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    return GentleWait(
      endedAt: at('ended_at'),
      opensAt: at('opens_at'),
      canShorten: json['can_shorten'] == true,
      answers: answers,
    );
  }
}

/// How saving the answers went.
/// [busy]: the server was busy (a clear answered `busy`, or a save still
/// met `dating:busy` after its one retry): a calm retry, never an error.
enum GentleWaitSave { saved, notEligible, reverifyDevice, busy, failed }

/// The server would not show D0's data (W4b: on an untrusted phone).
class GentleWaitUnavailable implements Exception {
  const GentleWaitUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'GentleWaitUnavailable($reason)';
}

/// The server was busy reading D0 (`dating:busy` after the one retry): a
/// calm retry, never an error.
class GentleWaitBusy implements Exception {
  const GentleWaitBusy();

  @override
  String toString() => 'GentleWaitBusy';
}

/// One RPC call (the Supabase client's, or a test's).
typedef GentleWaitRpc =
    Future<dynamic> Function(String fn, Map<String, dynamic>? params);

/// D0's reads and writes, behind an interface so the screen can be tested
/// without Supabase.
abstract class GentleWaitGateway {
  Future<GentleWait> read();

  Future<GentleWaitSave> save(Map<String, String> answers);

  /// Clears the answers through the server's never-gated clear branch
  /// (exposure-reducing: no setup lock, device or eligibility).
  Future<GentleWaitSave> clear();
}

class GentleWaitRepository implements GentleWaitGateway {
  GentleWaitRepository(SupabaseClient client)
    : _call = ((fn, params) => client.rpc(fn, params: params));

  /// A repository over [call] instead of Supabase (the busy mapping's tests).
  @visibleForTesting
  GentleWaitRepository.withRpc(GentleWaitRpc call) : _call = call;

  final GentleWaitRpc _call;

  /// Every call is bounded, as the other repositories' (checklist 1.2).
  static const _timeout = Duration(seconds: 30);

  /// One silent retry when the server answers `dating:busy`: it has
  /// already retried three times itself (Spec 2 W1 carried item 11).
  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _call(fn, params).timeout(_timeout);
      } on PostgrestException catch (e) {
        if (e.message == 'dating:busy' && attempt == 1) continue;
        rethrow;
      }
    }
  }

  /// [call], with a `dating:busy` that outlived [_rpc]'s one retry
  /// answered by [busy] instead.
  Future<dynamic> _busyAs(
    Future<dynamic> Function() call,
    dynamic Function() busy,
  ) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.message == 'dating:busy') return busy();
      rethrow;
    }
  }

  @override
  Future<GentleWait> read() async {
    final json = Map<String, dynamic>.from(
      await _busyAs(
            () => _rpc('get_my_gentle_wait_reflection'),
            () => throw const GentleWaitBusy(),
          )
          as Map,
    );
    if (json['ok'] != true) {
      throw GentleWaitUnavailable('${json['reason']}');
    }
    return GentleWait.fromJson(json);
  }

  /// An empty object is the server's clear branch: it takes no advisory
  /// lock and never runs the setup guard (B3 fix round 1, I-1).
  @override
  Future<GentleWaitSave> clear() => save(const {});

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    final raw = await _busyAs(
      () => _rpc('save_gentle_wait_reflection', {'p_answers': answers}),
      () => null,
    );
    if (raw == null) return GentleWaitSave.busy;
    final json = Map<String, dynamic>.from(raw as Map);
    if (json['ok'] == true) return GentleWaitSave.saved;
    return switch (json['reason']) {
      'not_eligible' => GentleWaitSave.notEligible,
      'reverify_device' => GentleWaitSave.reverifyDevice,
      // The clear's answer behind a busy row (B3 fix round 1, I-1).
      'busy' => GentleWaitSave.busy,
      _ => GentleWaitSave.failed,
    };
  }
}
