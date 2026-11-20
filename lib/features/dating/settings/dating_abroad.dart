// Spec 2 W5c (§2.6, §3.12; carry 17): Other countries. The read says which
// open countries the person may open to (never one whose same-gender rule
// refuses their answers) and whether they are eligible yet (verified, the
// age check holding, an account 14 days old); the write sets the list
// (narrowing it is never refused). RPC-only, one entry per account,
// memory only (D8, D20).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingAbroadOptions {
  const DatingAbroadOptions({
    this.ok = false,
    this.reason,
    this.eligible = false,
    this.countries = const [],
  });

  final bool ok;
  final String? reason;
  final bool eligible;

  /// Each open country's code and whether the person is open to it.
  final List<(String code, bool on)> countries;

  List<String> get on => [
    for (final (code, on) in countries)
      if (on) code,
  ];

  factory DatingAbroadOptions.fromJson(Object? raw) {
    if (raw is! Map) return const DatingAbroadOptions(reason: 'failed');
    if (raw['ok'] != true) {
      final reason = raw['reason'];
      return DatingAbroadOptions(reason: reason is String ? reason : 'failed');
    }
    return DatingAbroadOptions(
      ok: true,
      eligible: raw['eligible'] == true,
      countries: [
        if (raw['countries'] is List)
          for (final c in (raw['countries'] as List).whereType<Map>())
            if (c['code'] is String &&
                RegExp(r'^[A-Z]{2}$').hasMatch(c['code'] as String))
              (c['code'] as String, c['on'] == true),
      ],
    );
  }
}

abstract class DatingAbroadGateway {
  Future<DatingAbroadOptions> read();

  /// The whole list (set_dating_open_abroad).
  Future<DatingWrite> set(String key, List<String> countries);
}

class DatingAbroadRepository implements DatingAbroadGateway {
  DatingAbroadRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingAbroadOptions> read() async {
    try {
      return DatingAbroadOptions.fromJson(
        await _rpc.call('get_dating_abroad_options'),
      );
    } on DatingBusy {
      return const DatingAbroadOptions(reason: 'busy');
    } catch (_) {
      return const DatingAbroadOptions(reason: 'failed');
    }
  }

  @override
  Future<DatingWrite> set(String key, List<String> countries) => datingWrite(
    () => _rpc.call('set_dating_open_abroad', {
      'p_idempotency_key': key,
      'p_countries': countries,
    }),
  );
}

final datingAbroadGatewayProvider = Provider<DatingAbroadGateway>(
  (ref) => DatingAbroadRepository(ref.watch(datingRpcProvider)),
);

/// One entry per account: the next account starts from nothing (D8).
final datingAbroadProvider = FutureProvider.autoDispose
    .family<DatingAbroadOptions, String?>((ref, account) async {
      if (account == null) return const DatingAbroadOptions();
      return ref.read(datingAbroadGatewayProvider).read();
    });
