// Spec 2 W5b (§3.4 payload rules, §6.7, C-5): the other person's photos,
// as bytes, in memory only: at most 20 images, the oldest dropped first;
// cleared when Dating is left (Today's route closes), on quick exit and on
// sign-out (Dating's entry in Spec 1's device wipe registry). Never the
// disk, never the image cache's disk, never a URL kept past its use.
//
// Task 6 rulings: a photo is kept under its (kind, id, position), never
// its URL (a signed URL is a 60-second bearer link and changes every
// call); a dropped or cleared photo's decoded copy leaves Flutter's
// in-memory image cache too; and dating-photo-urls is asked at most
// [maxMisses] times per introduction or match that came back without its
// photos (a photo that can never be signed answers `busy` on every call),
// after which the card shows its empty slots calmly until Dating is left.
//
// Fix round 1 (T6 review I-1, M-1): every ok Today read gives each
// introduction fresh tries ([resetMisses]: a re-verification or a return
// from offline shows the photos again), [clearForLeave] is the hook the
// Dating routes call when Dating is left (§3.4), and an [epoch] (as
// stories' last-known store) stops a load in flight across a wipe from
// writing anything back: no photo, no miss.
//
// W5 final fix (M-2, T7b N-1): [forget] moves that person's own
// [generation] too, so a load already under way for them (a block on a
// slow network) writes nothing back either.
import 'dart:typed_data';

import 'package:flutter/painting.dart';

abstract final class DatingPhotoMemory {
  static const max = 20;

  /// Answers without every photo, per (kind, id), before no more are asked.
  static const maxMisses = 2;

  // A map literal keeps insertion order: the first key is the oldest.
  static final _bytes = <String, Uint8List>{};
  static final _misses = <String, int>{};
  static final _generations = <String, int>{};
  static int _epoch = 0;

  /// Bumped by every clear; a load that started under an older epoch
  /// writes nothing.
  static int get epoch => _epoch;

  /// M-2: moved by every [forget] of [kind] [id]; a load for them that
  /// started under an older generation writes nothing.
  static int generation(String kind, String id) =>
      _generations['$kind:$id'] ?? 0;

  /// One photo's key: (kind, id, position), never its URL.
  static String key(String kind, String id, int position) =>
      '$kind:$id:$position';

  static Uint8List? get(String key) {
    final b = _bytes.remove(key);
    if (b != null) _bytes[key] = b;
    return b;
  }

  static void put(String key, Uint8List bytes) {
    final old = _bytes.remove(key);
    if (old != null && !identical(old, bytes)) _evict(old);
    _bytes[key] = bytes;
    while (_bytes.length > max) {
      _evict(_bytes.remove(_bytes.keys.first)!);
    }
  }

  static int get length => _bytes.length;

  /// Whether dating-photo-urls may still be asked for [kind] [id].
  static bool mayAsk(String kind, String id) =>
      (_misses['$kind:$id'] ?? 0) < maxMisses;

  /// [kind] [id] came back without all of its photos.
  static void missed(String kind, String id) =>
      _misses.update('$kind:$id', (n) => n + 1, ifAbsent: () => 1);

  /// T7b fix 1 (M-2): every photo kept for [kind] [id] goes (a block
  /// ends that person's card), its decoded copy too.
  static void forget(String kind, String id) {
    final prefix = '$kind:$id:';
    _bytes.removeWhere((k, b) {
      if (!k.startsWith(prefix)) return false;
      _evict(b);
      return true;
    });
    _misses.remove('$kind:$id');
    _generations.update('$kind:$id', (n) => n + 1, ifAbsent: () => 1);
  }

  /// An ok Today read: every introduction and match may be asked again.
  static void resetMisses() => _misses.clear();

  /// §3.4: "cleared when Dating is left". Task 7's Dating routes call this
  /// when the last of them closes; the same as the device wipe's [clear].
  static Future<void> clearForLeave() => clear();

  /// Async for Spec 1's wipe registry (it awaits each entry, bounded).
  static Future<void> clear() async {
    _epoch++;
    _bytes.values.forEach(_evict);
    _bytes.clear();
    _misses.clear();
    // M-2: no id outlives a wipe (the epoch stops every older load).
    _generations.clear();
  }

  // Image.memory decodes into the in-memory image cache under
  // MemoryImage(bytes) (same bytes, scale 1): its copy goes with ours.
  static void _evict(Uint8List bytes) {
    try {
      PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
    } catch (_) {
      // No binding (a plain Dart test): there is no image cache either.
    }
  }
}
