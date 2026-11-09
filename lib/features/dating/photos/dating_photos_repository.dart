// Spec 2 W3c (§3.2 D9, §4.4 Photos): the person's own photos, RPC-only,
// the bytes uploaded under an intent and read back by their owner only
// (storage policies, R-2). Nothing is written to disk here.
//
// T10 (carry A): the photo RPCs as Task 8's fix rounds left them. The
// intent, the insert, the reorder and the caption retry their locks and
// then raise `dating:busy` (DatingRpc retries once more, then busy); the
// delete catches a cancel and answers `{ok:false, reason:'busy'}`. Every
// raised error is read by its code only (datingSetupRaised): never its
// text. A storage read the policies deny (a CSAM hit, a quarantined
// object) is null, calmly.
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart'
    show datingSetupRaised;
import 'package:supabase_flutter/supabase_flutter.dart';

const datingPhotoBucket = 'dating-profile-photos';

class DatingPhotoList {
  const DatingPhotoList({
    this.photos = const [],
    this.afterMutual = false,
    this.afterMutualFrom,
  });

  final List<DatingProfilePhoto> photos;
  final bool afterMutual;
  final DateTime? afterMutualFrom;

  factory DatingPhotoList.fromJson(Map<String, dynamic> json) =>
      DatingPhotoList(
        photos: [
          if (json['photos'] is List)
            for (final p in (json['photos'] as List).whereType<Map>())
              DatingProfilePhoto.fromJson(Map<String, dynamic>.from(p)),
        ],
        afterMutual: json['after_mutual'] == true,
        afterMutualFrom:
            json['after_mutual_from'] is String
                ? DateTime.tryParse(json['after_mutual_from'] as String)
                : null,
      );

  /// Never printed: the list holds captions and storage keys.
  @override
  String toString() => 'DatingPhotoList(…)';
}

abstract class DatingPhotosGateway {
  Future<DatingPhotoList> list();
  Future<DatingWrite> add(int position, Uint8List bytes, String mime);
  Future<DatingWrite> remove(String id);
  Future<DatingWrite> reorder(String key, List<String> ids);
  Future<DatingWrite> caption(String id, String text);
  Future<DatingWrite> photosAfterMutual(String key, bool on);
  Future<Uint8List?> bytes(String storageKey);
}

/// A photo writer's answer; a raised error by its code only.
Future<DatingWrite> _photoWrite(Future<dynamic> Function() write) async {
  try {
    return DatingWrite.fromJson(await write());
  } catch (e) {
    return datingSetupRaised(e);
  }
}

class DatingPhotosRepository implements DatingPhotosGateway {
  DatingPhotosRepository(this._rpc, this._storage);

  final DatingRpc _rpc;
  final SupabaseStorageClient _storage;

  @override
  Future<DatingPhotoList> list() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('list_dating_profile_photos') as Map,
    );
    if (json['ok'] != true) throw StateError('photos:${json['reason']}');
    return DatingPhotoList.fromJson(json);
  }

  @override
  Future<DatingWrite> add(int position, Uint8List bytes, String mime) async {
    Object? raw;
    try {
      raw = await _rpc.call('create_dating_photo_upload_intent', {
        'p_mime_type': mime,
      });
    } catch (e) {
      return datingSetupRaised(e);
    }
    if (raw is! Map || raw['ok'] != true) return DatingWrite.fromJson(raw);
    final key = raw['storage_key'];
    final intent = raw['intent_id'];
    if (key is! String || intent is! String) return DatingWrite.failed;
    try {
      await _storage
          .from(datingPhotoBucket)
          .uploadBinary(
            key,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } catch (_) {
      // An object that landed under an intent never used is swept, CSAM
      // first (R-46).
      return DatingWrite.failed;
    }
    return _photoWrite(
      () => _rpc.call('insert_dating_profile_photo', {
        'p_intent_id': intent,
        'p_position': position,
      }),
    );
  }

  @override
  Future<DatingWrite> remove(String id) => _photoWrite(
    () => _rpc.call('delete_dating_profile_photo', {'p_photo_id': id}),
  );

  @override
  Future<DatingWrite> reorder(String key, List<String> ids) => _photoWrite(
    () => _rpc.call('reorder_dating_photos', {
      'p_idempotency_key': key,
      'p_order': ids,
    }),
  );

  @override
  Future<DatingWrite> caption(String id, String text) => _photoWrite(
    () => _rpc.call('set_dating_photo_caption', {
      'p_photo_id': id,
      'p_caption': text,
    }),
  );

  @override
  Future<DatingWrite> photosAfterMutual(String key, bool on) => _photoWrite(
    () => _rpc.call('set_dating_photos_after_mutual', {
      'p_idempotency_key': key,
      'p_on': on,
    }),
  );

  /// The owner's own object, only ever asked for a photo scanned clear
  /// (D9 asks for approved photos only; R-24: approved needs a clear
  /// scan). A denied read (a hit, a quarantined object) is null.
  @override
  Future<Uint8List?> bytes(String storageKey) async {
    try {
      return await _storage.from(datingPhotoBucket).download(storageKey);
    } catch (_) {
      return null;
    }
  }
}
