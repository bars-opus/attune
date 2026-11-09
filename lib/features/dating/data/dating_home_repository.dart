// Spec 2 W3a (§3.1, §2.7, §3.10): the home, the open countries and "Tell me
// when it's here", RPC-only.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';

/// [rateLimited]: the 20-a-day cap (R-45); a retry today can't help.
/// [notEligible]: the adult check refused it (T3 M-5); not a failure.
enum DatingNoticeResult {
  saved,
  alreadyOpen,
  invalid,
  rateLimited,
  notEligible,
  busy,
  failed,
}

abstract class DatingHomeGateway {
  Future<DatingHome> read();

  Future<DatingAvailability> availability();

  Future<DatingNoticeResult> requestNotice(String country, {String? region});

  /// Never gated (exposure-reducing).
  Future<DatingNoticeResult> cancelNotice();
}

class DatingHomeRepository implements DatingHomeGateway {
  DatingHomeRepository(this._rpc);

  final DatingRpc _rpc;

  /// An answer that is not an object is `unavailable` (fail closed).
  @override
  Future<DatingHome> read() async {
    final raw = await _rpc.call('get_dating_home');
    return raw is Map
        ? DatingHome.fromJson(Map<String, dynamic>.from(raw))
        : const DatingHome(state: DatingHomeState.unavailable);
  }

  /// An answer that is not an object opens nothing.
  @override
  Future<DatingAvailability> availability() async {
    final raw = await _rpc.call('get_dating_availability');
    return raw is Map
        ? DatingAvailability.fromJson(Map<String, dynamic>.from(raw))
        : const DatingAvailability();
  }

  @override
  Future<DatingNoticeResult> requestNotice(String country, {String? region}) =>
      _notice(
        () => _rpc.call('request_dating_country_notice', {
          'p_country': country,
          'p_region': region,
        }),
      );

  @override
  Future<DatingNoticeResult> cancelNotice() =>
      _notice(() => _rpc.call('cancel_dating_country_notice'));

  Future<DatingNoticeResult> _notice(Future<dynamic> Function() call) async {
    final w = await datingWrite(call);
    if (w.ok) return DatingNoticeResult.saved;
    return switch (w.reason) {
      'already_open' => DatingNoticeResult.alreadyOpen,
      'invalid' => DatingNoticeResult.invalid,
      'rate_limited' => DatingNoticeResult.rateLimited,
      'not_eligible' => DatingNoticeResult.notEligible,
      'busy' => DatingNoticeResult.busy,
      _ => DatingNoticeResult.failed,
    };
  }
}
