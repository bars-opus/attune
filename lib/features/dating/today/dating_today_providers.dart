// Spec 2 W5b (D8, C-5): Today, one entry per account, memory only; the
// photo bytes are fetched from their 60-second URLs (a seam tests
// replace) into DatingPhotoMemory. The one raw http use in Dating: a
// signed storage URL needs no session or device header (an architecture
// test pins it).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/device/dating_device_check.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final datingTodayGatewayProvider = Provider<DatingTodayGateway>(
  (ref) => DatingTodayRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
    // Spec 2 W8b (R-T4-9): the account signed in at each call (D8).
    showSameGender:
        () => DatingTripPhone.showFor(ref.read(datingAccountProvider)),
  ),
);

/// Today, one entry per account: the next account's entry starts as a
/// plain loading value, never holding the last one's cards (D8). Fix round
/// 1 (T6 review I-1): an ok read gives every introduction's photos fresh
/// tries.
final datingTodayProvider = FutureProvider.autoDispose
    .family<DatingToday, String?>((ref, account) async {
      if (account == null) return DatingToday.failed;
      // Final client fix (I-1): a device check due or under way is waited
      // for (at most 3 s), so a trip that began is hidden from this read.
      // An answer that changed what the phone knew has asked Today again:
      // this read is then not sent. (Read, not watched: the checker asks
      // Today again itself; Today's page keeps it alive.)
      final checker = ref.read(datingDeviceCheckerProvider.notifier);
      final asked = checker.changesFor(account);
      await checker.settled(account);
      if (checker.changesFor(account) != asked) return DatingToday.failed;
      final today = await ref.read(datingTodayGatewayProvider).today();
      if (today.ok) {
        DatingPhotoMemory.resetMisses();
        // Spec 2 W8b (Task 5 review carry a): an introduction this read no
        // longer lists (a trip hides it, on either phone) leaves memory
        // with its photos.
        DatingPhotoMemory.keepOnly('introduction', {
          for (final c in [...today.cards, ...today.waiting]) c.id,
        });
      }
      return today;
    });

/// Fix round 1 (T6 review M-7): one photo's download is abandoned after
/// this (its client is closed, which aborts the socket).
const datingPhotoFetchTimeout = Duration(seconds: 20);

/// A card's photos are fetched together, at most this many at once (a
/// profile has at most 6), so all start within their URLs' 60 seconds.
const datingPhotoFetchParallel = 6;

/// One photo's bytes from its signed URL; null when it can't be read. Its
/// own client (dart:io: no disk cache), closed when done or timed out, so a
/// stalled download stops using data.
Future<Uint8List?> datingFetchPhoto(
  String url, {
  http.Client Function() newClient = http.Client.new,
  Duration timeout = datingPhotoFetchTimeout,
}) async {
  final client = newClient();
  try {
    final r = await client.get(Uri.parse(url)).timeout(timeout);
    return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

final datingPhotoFetchProvider = Provider<Future<Uint8List?> Function(String)>(
  (ref) => datingFetchPhoto,
);

/// The other person's photos on [kind] [id], in card order, through
/// [DatingPhotoMemory]; an empty list when none can be read.
///
/// Task 6 rulings: with the card's [positions] (DatingIntroCard
/// .photoPositions) the answer has one slot per position, matched by
/// position, so a photo that fails to sign or fetch leaves its own slot
/// empty; when every slot is already in memory nothing is asked; and an
/// introduction or match that came back without its photos is asked at
/// most [DatingPhotoMemory.maxMisses] times (never a loop on `busy`).
/// Fix round 1: the downloads run together ([datingPhotoFetchParallel]);
/// a load that a wipe overtook (M-1: the memory's epoch moved) writes
/// nothing back, neither a photo nor a miss. W5 final fix (M-2): nor does
/// one overtaken by a [DatingPhotoMemory.forget] of this [kind] [id] (a
/// block while the photos download).
Future<List<Uint8List>> loadDatingPhotos(
  DatingTodayGateway gateway,
  Future<Uint8List?> Function(String) fetch,
  String kind,
  String id, {
  List<int>? positions,
}) async {
  final epoch = DatingPhotoMemory.epoch;
  final generation = DatingPhotoMemory.generation(kind, id);
  bool wiped() =>
      DatingPhotoMemory.epoch != epoch ||
      DatingPhotoMemory.generation(kind, id) != generation;
  List<Uint8List> kept(List<int> order) => [
    for (final p in order)
      DatingPhotoMemory.get(DatingPhotoMemory.key(kind, id, p)) ?? Uint8List(0),
  ];
  List<Uint8List> none() =>
      positions == null ? const [] : [for (final _ in positions) Uint8List(0)];
  Future<Uint8List?> one(String url) async {
    try {
      return await fetch(url);
    } catch (_) {
      return null;
    }
  }

  if (positions != null) {
    final inMemory = kept(positions);
    if (positions.isEmpty || inMemory.every((b) => b.isNotEmpty)) {
      return inMemory;
    }
    if (!DatingPhotoMemory.mayAsk(kind, id)) return inMemory;
  } else if (!DatingPhotoMemory.mayAsk(kind, id)) {
    return const [];
  }
  final urls = await gateway.photoUrls(kind, id);
  if (wiped()) return none();
  if (urls == null) {
    DatingPhotoMemory.missed(kind, id);
    return positions == null ? const [] : kept(positions);
  }
  final wanted = [
    for (final u in urls)
      if (DatingPhotoMemory.get(DatingPhotoMemory.key(kind, id, u.position)) ==
          null)
        u,
  ];
  for (var i = 0; i < wanted.length; i += datingPhotoFetchParallel) {
    final batch = wanted.skip(i).take(datingPhotoFetchParallel).toList();
    final got = await Future.wait([for (final u in batch) one(u.url)]);
    if (wiped()) return none();
    for (var j = 0; j < batch.length; j++) {
      final bytes = got[j];
      if (bytes != null && bytes.isNotEmpty) {
        DatingPhotoMemory.put(
          DatingPhotoMemory.key(kind, id, batch[j].position),
          bytes,
        );
      }
    }
  }
  final out = kept(positions ?? [for (final u in urls) u.position]);
  if (out.any((b) => b.isEmpty)) DatingPhotoMemory.missed(kind, id);
  return out;
}
