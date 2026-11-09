import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';

class FakeDatingPhotosGateway implements DatingPhotosGateway {
  FakeDatingPhotosGateway({this.photos = const [], this.afterMutualFrom});

  List<DatingProfilePhoto> photos;
  DateTime? afterMutualFrom;
  bool afterMutual = false;
  final calls = <(String, Object?)>[];
  DatingWrite addAnswer = const DatingWrite(ok: true);

  /// T10 (carries B, D, E, F): the answer of reorder, caption, remove and
  /// the photos-after toggle; the keys sent; reads and writes held open or
  /// failing; the stored bytes a read answers, and every read of them.
  DatingWrite writeAnswer = const DatingWrite(ok: true);
  final keys = <(String, String)>[];
  Completer<void>? holdAdd;
  Completer<void>? holdWrite;
  Completer<DatingPhotoList>? holdList;
  Object? listError;
  Object? bytesError;
  final stored = <String, Uint8List>{};
  final byteReads = <String>[];

  /// T10 fix 1 (M-2): the insert lands but its answer is lost.
  bool insertAnyway = false;

  @override
  Future<DatingPhotoList> list() async {
    calls.add(('list', null));
    final error = listError;
    if (error != null) throw error;
    final hold = holdList;
    if (hold != null) return hold.future;
    return DatingPhotoList(
      photos: photos,
      afterMutual: afterMutual,
      afterMutualFrom: afterMutualFrom,
    );
  }

  @override
  Future<DatingWrite> add(int position, Uint8List bytes, String mime) async {
    calls.add(('add', (position, bytes.length, mime)));
    final hold = holdAdd;
    if (hold != null) await hold.future;
    if (addAnswer.ok || insertAnyway) {
      photos = [
        ...photos.where((p) => p.position != position),
        DatingProfilePhoto(
          id: 'new-$position',
          position: position,
          moderationState: 'pending',
          storageKey: 'k-$position',
          createdAt: DateTime.utc(2026, 11, 7),
        ),
      ];
    }
    return addAnswer;
  }

  Future<DatingWrite> _write() async {
    final hold = holdWrite;
    if (hold != null) await hold.future;
    return writeAnswer;
  }

  @override
  Future<DatingWrite> remove(String id) async {
    calls.add(('remove', id));
    final w = await _write();
    if (w.ok) photos = photos.where((p) => p.id != id).toList();
    return w;
  }

  @override
  Future<DatingWrite> reorder(String key, List<String> ids) async {
    calls.add(('reorder', ids));
    keys.add(('reorder', key));
    return _write();
  }

  @override
  Future<DatingWrite> caption(String id, String text) async {
    calls.add(('caption', (id, text)));
    return _write();
  }

  @override
  Future<DatingWrite> photosAfterMutual(String key, bool on) async {
    calls.add(('afterMutual', on));
    keys.add(('afterMutual', key));
    final w = await _write();
    if (w.ok) afterMutual = on;
    return w;
  }

  @override
  Future<Uint8List?> bytes(String storageKey) async {
    byteReads.add(storageKey);
    final error = bytesError;
    if (error != null) throw error;
    return stored[storageKey];
  }
}

DatingProfilePhoto photo(int position, String state, {String? reason}) =>
    DatingProfilePhoto(
      id: 'p$position',
      position: position,
      moderationState: state,
      rejectionReason: reason,
      storageKey: 'k$position',
      createdAt: DateTime.utc(2026, 11, 1),
    );


/// D12's read with no profile yet (an empty preview).
class FakeDatingPreviewGateway implements DatingPreviewGateway {
  FakeDatingPreviewGateway([this.card]);
  DatingCard? card;
  @override
  Future<DatingCard?> preview() async => card;
}
