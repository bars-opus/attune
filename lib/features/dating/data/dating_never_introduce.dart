// Spec 2 W4b (§3.12; Task 5 C-1 and I-6 rulings): the person's "Never
// introduce me" list as the server shows it. Entries kept from before
// (Start again, or a Leave that kept the list) are never shown and can't
// be removed one by one: the server sends only how many there are, and
// only Leave Dating and delete my data removes them. Adding a number that
// is already kept answers exactly as adding any number does. W4b reads the
// count (Dating settings); W5c builds the list screen on this read.
// RPC-only, one entry per account, memory only (D8, D20).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One entry the person can see (a code and its last two digits, never
/// the number).
class DatingNeverIntroduceItem {
  const DatingNeverIntroduceItem({
    required this.id,
    this.label,
    required this.lastTwo,
  });

  final String id;

  /// The name only the person sees; optional (§3.12), so often null.
  final String? label;
  final String lastTwo;
}

/// list_dating_never_introduce(): `{ok, items, kept_count}` or a refusal
/// (`reverify_device` on a phone Dating doesn't trust). Anything else is
/// an empty list with nothing kept (fail closed: no row, no count).
class DatingNeverIntroduceList {
  const DatingNeverIntroduceList({
    this.ok = false,
    this.items = const [],
    this.keptCount = 0,
    this.reason,
  });

  final bool ok;
  final List<DatingNeverIntroduceItem> items;

  /// How many entries are kept from before (never which).
  final int keptCount;
  final String? reason;

  factory DatingNeverIntroduceList.fromJson(Object? raw) {
    if (raw is! Map) return const DatingNeverIntroduceList(reason: 'failed');
    if (raw['ok'] != true) {
      final reason = raw['reason'];
      return DatingNeverIntroduceList(
        reason: reason is String ? reason : 'failed',
      );
    }
    final items = raw['items'];
    final kept = raw['kept_count'];
    return DatingNeverIntroduceList(
      ok: true,
      items: [
        if (items is List)
          for (final i in items.whereType<Map>())
            // Fix round 1 (I-1): an entry without a name is still shown.
            if (i['id'] is String &&
                (i['label'] == null || i['label'] is String) &&
                i['last_two'] is String)
              DatingNeverIntroduceItem(
                id: i['id'] as String,
                label: i['label'] as String?,
                lastTwo: i['last_two'] as String,
              ),
      ],
      keptCount: kept is int && kept > 0 ? kept : 0,
    );
  }
}

abstract class DatingNeverIntroduceGateway {
  Future<DatingNeverIntroduceList> list();

  /// Spec 2 W5c (§3.12): `{ok, message: 'added'}` for any number (it can't
  /// be used to test whether someone uses Attune), or a refusal.
  Future<DatingWrite> add(String key, String phoneE164, String? label);

  /// Spec 2 W5c: removes one shown entry (a kept one is never shown).
  Future<DatingWrite> remove(String id);
}

class DatingNeverIntroduceRepository implements DatingNeverIntroduceGateway {
  DatingNeverIntroduceRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingNeverIntroduceList> list() async {
    try {
      return DatingNeverIntroduceList.fromJson(
        await _rpc.call('list_dating_never_introduce'),
      );
    } on DatingBusy {
      return const DatingNeverIntroduceList(reason: 'busy');
    }
  }

  @override
  Future<DatingWrite> add(String key, String phoneE164, String? label) =>
      datingWrite(
        () => _rpc.call('add_dating_never_introduce', {
          'p_idempotency_key': key,
          'p_phone_e164': phoneE164,
          'p_label': label,
        }),
      );

  @override
  Future<DatingWrite> remove(String id) => datingWrite(
    () => _rpc.call('remove_dating_never_introduce', {'p_id': id}),
  );
}

final datingNeverIntroduceGatewayProvider =
    Provider<DatingNeverIntroduceGateway>(
      (ref) => DatingNeverIntroduceRepository(ref.watch(datingRpcProvider)),
    );

/// The list, one entry per account (the next account starts from nothing).
final datingNeverIntroduceProvider = FutureProvider.autoDispose
    .family<DatingNeverIntroduceList, String?>((ref, account) async {
      if (account == null) return const DatingNeverIntroduceList();
      return ref.read(datingNeverIntroduceGatewayProvider).list();
    });
