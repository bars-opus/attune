// Spec 2 §3.2 D9 (Step 8 of 12). Six slots, each read as "Photo {n} of 6,
// {state}"; progress in words (R-22); every rejection names its photo and
// its reason (a CSAM hit is "can't be used", never named); Move earlier /
// Move later beside drag, as buttons and as semantic actions (R-42);
// captions only the person sees, shown back to them; the photos-after
// toggle from account day 30 (R-37); ~300 KB each.
//
// C-5 / T10 carries B, C, G: a picked photo goes through the preparer as it
// is (Task 9: its own isolate, 1600 px, EXIF gone, a neutral temp name);
// once its bytes are in memory every file of it (picked, cropped,
// prepared) is deleted, before the upload starts. Until the scan is clear
// the slot shows those in-memory bytes, never a server read: the owner's
// object is read back only for an approved photo (R-24: approved needs a
// clear scan). A photo that is rejected or waiting for a person shows a
// neutral slot, its local bytes dropped; a CSAM hit reads only "Photo {n}
// can't be used.". Every byte is memory only, decoded at the slot's size,
// evicted when the step goes, on another account (D8) and on quick exit
// (the route is disposed).
//
// Fix round 1: a failed refresh keeps the last list on screen (the provider
// is the account's own, so D8 holds) and nothing can be added before a
// list has loaded once (I-1: an add replaces what is at its position); the
// picker and the cropper fail into the slot's own line (I-3); a pending
// photo is checked every 4 s for a minute, then every 20 s, up to ten
// minutes of successful checks (a failed or offline check costs nothing),
// and again on reconnecting and on coming back to the app (M-1); an add
// whose answer was lost is settled by the next list (M-2); offline, every
// photo action is off (M-3); a failed write is said on its photo (M-4).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart'
    show flowAccent;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/dating_text_rules.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum _Phase { preparing, uploading }

/// Why an add ended without a photo.
enum _Fail { upload, pick, crop }

/// The refusals an add names beside the slot's own line (the rest are the
/// slot's "didn't upload" alone).
const _namedAddRefusals = {
  'rate_limited',
  'not_eligible',
  'reverify_device',
  'not_available',
  'consent_required',
};

/// Successful checks of a pending photo: 15 at 4 s (a minute), then 27 at
/// 20 s (nine more): ten minutes in all (M-1).
const _fastChecks = 15;
const _maxChecks = 42;

/// The thumbnail's side, in logical pixels.
const _thumb = 64.0;

/// A slot's prepared bytes while it uploads, and until the next list says
/// whether the row its add made is there.
class _Waiting {
  _Waiting(this.bytes, this.before);

  final Uint8List bytes;

  /// The ids there before the add: a replaced photo is never taken for it.
  final Set<String> before;

  /// The add answered ok (its bytes show until the row arrives); false
  /// when its answer was lost or a refusal (the next list decides, M-2).
  bool shown = true;

  /// The list on screen when the add ended; a later one decides.
  DatingPhotoList? seen;
  bool ended = false;
}

class DatingPhotosStep extends ConsumerStatefulWidget {
  const DatingPhotosStep({super.key, required this.nav});

  final DatingStepNav nav;

  /// Adds still running, the picker, the preparer, the file reads and
  /// deletes, and the upload included. Tests wait on it instead of a fixed
  /// time, because the add's real file I/O can take any time under load.
  @visibleForTesting
  static int debugAddsInFlight = 0;

  @override
  ConsumerState<DatingPhotosStep> createState() => _DatingPhotosStepState();
}

class _DatingPhotosStepState extends ConsumerState<DatingPhotosStep>
    with DatingStepState<DatingPhotosStep>, WidgetsBindingObserver {
  final _phase = <int, _Phase>{};

  /// Failed adds: the position, the id of the photo there when it failed
  /// (the line goes once that changes, M-2) and why.
  final _failed = <int, (String?, _Fail)>{};

  /// Adds started (the picker open included): a second tap adds nothing.
  final _starting = <int>{};
  final _waiting = <int, _Waiting>{};

  /// A photo's own prepared bytes, by photo id, while it is checked.
  final _local = <String, Uint8List>{};

  /// The owner's object, read back for an approved photo only.
  final _server = <String, Uint8List>{};
  final _asked = <String>{};

  /// Files of a photo being added; deleted as soon as its bytes are read.
  final _temps = <String>{};
  final _writing = <String>{};
  DatingWrite? _error;

  /// The position of the photo [_error] is about (null: the toggle), and
  /// the id of the photo there when it was said (null: an empty slot). The
  /// line stays until that slot holds another photo, or none (hardening:
  /// an empty slot's refusal was dropped by the very next list).
  int? _errorAt;
  String? _errorId;
  List<DatingProfilePhoto> _shown = const [];
  DatingPhotoList? _lastList;

  /// Bumped on every reset: work started for another account, or before
  /// the step went, lands nowhere.
  int _gen = 0;
  Timer? _poll;

  /// Checks begun that haven't failed (M-1's budget), and whether one is
  /// out now.
  int _spent = 0;
  bool _checking = false;
  int _cacheWidth = _thumb.round();

  bool _current(int gen) => mounted && gen == _gen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Final fix (M-13): a prepared photo a crash left behind goes now.
    unawaited(ref.read(datingImagePreparerProvider).sweepLeftovers());
    // Reconnected: check at once (M-1).
    ref.listenManual<AsyncValue<bool>>(datingOnlineProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        _refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  @override
  void resetAnswers() {
    _gen++;
    _phase.clear();
    _failed.clear();
    _starting.clear();
    _waiting.clear();
    _writing.clear();
    _error = null;
    _errorAt = null;
    _shown = const [];
    _lastList = null;
    _evict();
    _deleteTempsNow();
    _poll?.cancel();
    _poll = null;
    _spent = 0;
    _checking = false;
  }

  @override
  void seedAnswers(DatingMyProfile profile) {}

  /// Drops [bytes] from the image cache, at the size the slot drew them.
  void _forget(Uint8List bytes) {
    unawaited(ResizeImage(MemoryImage(bytes), width: _cacheWidth).evict());
  }

  void _evict() {
    for (final bytes in [..._local.values, ..._server.values]) {
      _forget(bytes);
    }
    for (final w in _waiting.values) {
      _forget(w.bytes);
    }
    _local.clear();
    _server.clear();
    _asked.clear();
  }

  void _deleteTempsNow() {
    for (final path in _temps) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _temps.clear();
  }

  @override
  void dispose() {
    _gen++;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _evict();
    _deleteTempsNow();
    super.dispose();
  }

  void _refresh() =>
      ref.invalidate(datingPhotosProvider(ref.read(datingAccountProvider)));

  Duration get _interval => Duration(seconds: _spent < _fastChecks ? 4 : 20);

  /// Starts the checks while a photo is pending, within the budget.
  void _keepChecking(List<DatingProfilePhoto> photos) {
    if (!photos.any((p) => p.isPending) || _spent >= _maxChecks) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer(_interval, _tick);
  }

  void _tick() {
    _poll = null;
    if (!mounted) return;
    final online = ref.read(datingOnlineProvider).valueOrNull ?? true;
    // Offline, or the last check still out: this one costs nothing.
    if (online && !_checking) {
      _spent++;
      _checking = true;
      _refresh();
    }
    if (_spent < _maxChecks && _shown.any((p) => p.isPending)) {
      _poll = Timer(_interval, _tick);
    }
  }

  /// After every frame: settles the check that was out (a failed one is
  /// given back to the budget), then, with a list, [_sync] and the checks.
  void _afterFrame(
    AsyncValue<DatingPhotoList> read,
    DatingPhotoList? list,
    List<DatingProfilePhoto> photos,
  ) {
    if (_checking && !read.isLoading) {
      if (read.hasError) {
        _checking = false;
        _spent--;
      } else if (!identical(list, _lastList)) {
        _checking = false;
      }
    }
    if (list == null) return;
    _sync(list, photos);
    _lastList = list;
    _keepChecking(photos);
  }

  /// After each list: settles finished adds (M-2), binds their bytes to
  /// their rows, drops every byte a photo may no longer show, and reads
  /// back approved ones only.
  void _sync(DatingPhotoList list, List<DatingProfilePhoto> photos) {
    _shown = photos;
    var changed = false;
    final byPosition = {for (final p in photos) p.position: p};
    for (final entry in _waiting.entries.toList()) {
      final w = entry.value;
      if (!w.ended) continue;
      final row = byPosition[entry.key];
      if (row != null && !w.before.contains(row.id)) {
        // The add's row is here (its answer may have been lost).
        _local[row.id] = w.bytes;
        _waiting.remove(entry.key);
        _failed.remove(entry.key);
        changed = true;
      } else if (!identical(list, w.seen)) {
        // A later list without it: it didn't land.
        _forget(w.bytes);
        _waiting.remove(entry.key);
        changed = true;
      }
    }
    // A failed add's line goes once its slot holds another photo, or none.
    for (final entry in _failed.entries.toList()) {
      if (_phase.containsKey(entry.key)) continue;
      if (byPosition[entry.key]?.id != entry.value.$1) {
        _failed.remove(entry.key);
        changed = true;
      }
    }
    final byId = {for (final p in photos) p.id: p};
    for (final id in _local.keys.toList()) {
      final p = byId[id];
      if (p == null || !(p.isPending || p.isApproved)) {
        _forget(_local[id]!);
        _local.remove(id);
        changed = true;
      }
    }
    final approved = {
      for (final p in photos)
        if (p.isApproved) p.storageKey,
    };
    for (final key in _server.keys.toList()) {
      if (!approved.contains(key)) {
        _forget(_server[key]!);
        _server.remove(key);
        changed = true;
      }
    }
    _asked.removeWhere((key) => !approved.contains(key));
    for (final p in photos) {
      // Never a server read before the scan is clear (carry B).
      if (!p.isApproved) continue;
      if (_local.containsKey(p.id) || _asked.contains(p.storageKey)) continue;
      _asked.add(p.storageKey);
      unawaited(_readBack(p.storageKey));
    }
    if (_errorAt != null && byPosition[_errorAt]?.id != _errorId) {
      _error = null;
      _errorAt = null;
      _errorId = null;
      changed = true;
    }
    if (changed) setState(() {});
  }

  Future<void> _readBack(String storageKey) async {
    final gen = _gen;
    Uint8List? bytes;
    try {
      bytes = await ref.read(datingPhotosGatewayProvider).bytes(storageKey);
    } catch (_) {
      // A denied read (a hit, a quarantined object): the neutral slot.
      bytes = null;
    }
    if (!_current(gen) || bytes == null || bytes.isEmpty) return;
    if (!_asked.contains(storageKey)) return;
    setState(() => _server[storageKey] = bytes!);
  }

  Future<void> _deleteFiles(List<String?> paths) async {
    for (final path in paths) {
      if (path == null) continue;
      _temps.remove(path);
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _add(int position, {bool crop = false}) async {
    if (_starting.contains(position) || _phase.containsKey(position)) return;
    if (!(ref.read(datingOnlineProvider).valueOrNull ?? true)) return;
    // Not before the list has loaded once: an add replaces what is at its
    // position, and an unread slot only looks empty (I-1).
    if (_lastList == null) return;
    DatingPhotosStep.debugAddsInFlight++;
    try {
      await _addFlow(position, crop);
    } finally {
      DatingPhotosStep.debugAddsInFlight--;
    }
  }

  Future<void> _addFlow(int position, bool crop) async {
    final gen = _gen;
    final account = ref.read(datingAccountProvider);
    final keys = this.keys;
    final action = 'add_$position';
    // The intent and the insert take no key (the intent is single-use and
    // the insert consumes it); the action is still keyed and settled like
    // every write here (carry D).
    keys.keyFor(action, '$account|$position');
    _starting.add(position);
    String? picked;
    String? cropped;
    String? prepared;
    var w = DatingWrite.failed;
    _Fail? fail;
    try {
      // The system picker and cropper can throw (access refused, already
      // open, no crop screen): the slot's own line, never the error (I-3).
      try {
        picked = await ref.read(datingPhotoPickerProvider)();
      } catch (_) {
        fail = _Fail.pick;
      }
      if (picked != null) _temps.add(picked);
      if (fail == null && crop && picked != null && _current(gen)) {
        try {
          cropped = await ref.read(datingPhotoCropperProvider)(picked);
        } catch (_) {
          fail = _Fail.crop;
        }
        if (cropped != null) _temps.add(cropped);
        // A cancelled crop is silent.
        if (fail == null && cropped == null) return;
      }
      // A cancelled pick is silent.
      if (fail == null && picked == null) return;
      if (!_current(gen)) return;
      if (fail == null) {
        setState(() {
          _phase[position] = _Phase.preparing;
          _failed.remove(position);
          _error = null;
          _errorAt = null;
        });
        try {
          final file =
              (await ref
                  .read(datingImagePreparerProvider)
                  .prepare(cropped ?? picked!)).file;
          prepared = file.path;
          _temps.add(prepared);
          if (!_current(gen)) return;
          final bytes = await file.readAsBytes();
          // C-5: nothing of the photo stays on disk once it is in memory.
          await _deleteFiles([prepared, cropped, picked]);
          if (!_current(gen) || ref.read(datingAccountProvider) != account) {
            return;
          }
          final before = {for (final p in _shown) p.id};
          setState(() {
            _phase[position] = _Phase.uploading;
            _waiting[position] = _Waiting(bytes, before);
          });
          w = await ref
              .read(datingPhotosGatewayProvider)
              .add(position, bytes, 'image/jpeg');
        } catch (_) {
          // A photo the preparer refuses, or anything else: the slot's own
          // failure line, never the error.
          w = DatingWrite.failed;
        }
        keys.settle(action, reason: w.reason);
      }
    } finally {
      _starting.remove(position);
      await _deleteFiles([prepared, cropped, picked]);
    }
    if (!_current(gen)) return;
    final ok = fail == null && w.ok;
    setState(() {
      _phase.remove(position);
      final waiting = _waiting[position];
      if (waiting != null) {
        // The next list settles it: its row, or not there (M-2).
        waiting
          ..ended = true
          ..shown = ok
          ..seen = _lastList;
      }
      if (!ok) {
        String? there;
        for (final p in _shown) {
          if (p.position == position) there = p.id;
        }
        _failed[position] = (there, fail ?? _Fail.upload);
        if (_namedAddRefusals.contains(w.reason)) {
          _error = w;
          _errorAt = position;
          _errorId = there;
        }
      }
    });
    if (fail != null) return;
    if (ok) _spent = 0;
    _refresh();
  }

  /// One write per action at a time (a double tap sends one); its key
  /// settled once its answer is final (carry D); a refusal in words, on
  /// the photo it is about ([at], M-4).
  Future<void> _write(
    String action,
    Object payload,
    int? at,
    Future<DatingWrite> Function(String key) call,
  ) async {
    if (_writing.contains(action)) return;
    final gen = _gen;
    final account = ref.read(datingAccountProvider);
    final keys = this.keys;
    final key = keys.keyFor(action, '$account|$payload');
    String? about;
    for (final p in _shown) {
      if (p.position == at) about = p.id;
    }
    setState(() {
      _writing.add(action);
      _error = null;
      _errorAt = null;
    });
    DatingWrite w;
    try {
      w = await call(key);
    } catch (_) {
      w = DatingWrite.failed;
    }
    keys.settle(action, reason: w.reason);
    if (!_current(gen)) return;
    setState(() {
      _writing.remove(action);
      _error = w.ok ? null : w;
      _errorAt = w.ok ? null : at;
      _errorId = w.ok ? null : about;
    });
    _refresh();
  }

  /// Final fix (M-16): the delete is at once and can't be undone (the
  /// object goes with the row; an approved photo added again is checked
  /// again), so Remove asks first. Keep it is the default and sends nothing.
  Future<void> _remove(DatingProfilePhoto photo, int n) async {
    final gen = _gen;
    final loc = AppLocalizations.of(context)!;
    final sure = await showDialog<bool>(
      context: context,
      builder:
          (dialog) => AllowLargeText(
            child: AlertDialog(
              title: Text(loc.dating_photoRemoveQ(n)),
              content: Text(loc.dating_photoRemoveBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(false),
                  child: Text(loc.dating_photoKeep),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(true),
                  child: Text(loc.dating_photoRemove),
                ),
              ],
            ),
          ),
    );
    // D8: an answer given for the last account removes nothing now.
    if (sure != true || !_current(gen)) return;
    await _write(
      'remove',
      photo.id,
      n,
      (_) => ref.read(datingPhotosGatewayProvider).remove(photo.id),
    );
  }

  void _move(List<DatingProfilePhoto> photos, int index, int by) {
    final ids = [for (final p in photos) p.id];
    final to = index + by;
    if (by == 0) return;
    if (to < 0 || to >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(to, id);
    _write(
      'reorder',
      ids,
      photos[index].position,
      (key) => ref.read(datingPhotosGatewayProvider).reorder(key, ids),
    );
  }

  Future<void> _caption(DatingProfilePhoto photo) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CaptionSheet(initial: photo.caption ?? ''),
    );
    if (text == null || !mounted) return;
    final caption = text.trim();
    if (caption == (photo.caption ?? '')) return;
    await _write(
      'caption',
      [photo.id, caption],
      photo.position,
      (_) => ref.read(datingPhotosGatewayProvider).caption(photo.id, caption),
    );
  }

  String _stateText(AppLocalizations loc, int n, DatingProfilePhoto? p) {
    final phase = _phase[n];
    if (phase == _Phase.preparing) return loc.dating_photoPreparing(n);
    if (phase == _Phase.uploading) return loc.dating_photoUploading(n);
    final failed = _failed[n];
    if (failed != null) {
      return switch (failed.$2) {
        _Fail.pick => loc.dating_photoPickFailed(n),
        _Fail.crop => loc.dating_photoCropFailed(n),
        _Fail.upload => loc.dating_photoFailed(n),
      };
    }
    if (_waitingShown(n, p) != null) return loc.dating_photoChecking;
    if (p == null) return loc.dating_photoAdd;
    if (p.isApproved) return loc.dating_photoReady;
    if (p.isPending) return loc.dating_photoChecking;
    if (p.needsReview) return loc.dating_photoReview;
    return switch (p.rejectionReason) {
      'face_unclear' => loc.dating_photoFaceUnclear(n),
      'too_small' => loc.dating_photoTooSmall(n),
      'contains_child' => loc.dating_photoChild(n),
      _ => loc.dating_photoCantUse(n),
    };
  }

  /// An ok add's bytes while its row hasn't arrived yet.
  _Waiting? _waitingShown(int n, DatingProfilePhoto? p) {
    final w = _waiting[n];
    if (w == null || !w.shown) return null;
    return p == null || w.before.contains(p.id) ? w : null;
  }

  /// What a slot may show: its own bytes while it uploads or is checked,
  /// the owner's object once approved, else nothing (the neutral slot).
  Uint8List? _preview(int n, DatingProfilePhoto? p) {
    final phase = _phase[n];
    if (phase == _Phase.preparing) return null;
    if (phase == _Phase.uploading) return _waiting[n]?.bytes;
    if (_failed.containsKey(n)) return null;
    final waiting = _waitingShown(n, p);
    if (waiting != null) return waiting.bytes;
    if (p == null || !(p.isPending || p.isApproved)) return null;
    return _local[p.id] ?? (p.isApproved ? _server[p.storageKey] : null);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    _cacheWidth = (_thumb * MediaQuery.devicePixelRatioOf(context)).round();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingPhotosProvider(account));
    // The last list stays through a failed refresh (I-1): the entry is
    // this account's own, so another account never sees it (D8).
    final list = read.valueOrNull;
    final loaded = list != null;
    final photos = [...?list?.photos]
      ..sort((a, b) => a.position.compareTo(b.position));
    final gen = _gen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(gen)) _afterFrame(read, list, photos);
    });
    final usable = photos.where((p) => !p.isRejected).length;
    final from = list?.afterMutualFrom;
    final afterOpen = from != null && !DateTime.now().toUtc().isBefore(from);
    final byPosition = {for (final p in photos) p.position: p};
    Widget slot(int n, {int? dragIndex}) {
      final p = byPosition[n];
      final i = p == null ? -1 : photos.indexOf(p);
      // Offline every photo action is off; the offline line says why (M-3).
      final act = online && p != null;
      return _Slot(
        n: n,
        photo: p,
        dragIndex: dragIndex,
        cacheWidth: _cacheWidth,
        thumb: _preview(n, p),
        state: _stateText(loc, n, p),
        failed: _failed.containsKey(n),
        busy: _phase.containsKey(n) || _starting.contains(n),
        canAdd: online && loaded,
        online: online,
        error:
            _error != null && _errorAt == n
                ? datingRefusalLine(loc, _error!)
                : null,
        onAdd: () => _add(n),
        onCrop: () => _add(n, crop: true),
        onEarlier: !act || i <= 0 ? null : () => _move(photos, i, -1),
        onLater:
            !act || i >= photos.length - 1 ? null : () => _move(photos, i, 1),
        onCaption: !act ? null : () => _caption(p),
        onRemove: !act ? null : () => _remove(p, n),
      );
    }

    return DatingStepFrame(
      step: 'photos',
      title: loc.dating_photosTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_photosBody, style: theme.textTheme.bodyLarge),
          if (!online) ...[
            const SizedBox(height: Spacing.sm),
            Text(loc.dating_photosOffline, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Spacing.md),
          if (read.hasError)
            DatingLoadError(busy: read.isLoading, onRetry: _refresh),
          // Drag (the thumbnail is the handle) or Move earlier / Move later
          // (§3.2 D9 "reorder by drag or by" the actions); empty slots follow.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder:
                (from, to) =>
                    _move(photos, from, (to > from ? to - 1 : to) - from),
            children: [
              for (final (i, p) in photos.indexed)
                KeyedSubtree(
                  key: ValueKey('slot_${p.id}'),
                  child: slot(p.position, dragIndex: i),
                ),
            ],
          ),
          for (var n = 1; n <= 6; n++)
            if (byPosition[n] == null) slot(n),
          if (_error != null && _errorAt == null) ...[
            datingRefusalLine(loc, _error!),
            const SizedBox(height: Spacing.sm),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_photosAfterMutual),
            subtitle:
                afterOpen || from == null
                    ? null
                    : Text(
                      loc.dating_photosAfterMutualFrom(
                        MyDateFormat.toDate(from.toLocal()),
                      ),
                    ),
            value: list?.afterMutual ?? false,
            onChanged:
                afterOpen && online
                    ? (on) => _write(
                      'after',
                      on,
                      null,
                      (key) => ref
                          .read(datingPhotosGatewayProvider)
                          .photosAfterMutual(key, on),
                    )
                    : null,
          ),
          Text(loc.dating_photosData, style: theme.textTheme.bodySmall),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed:
            online && usable >= 2 ? () => widget.nav.next('prompts') : null,
      ),
    );
  }
}

/// The caption sheet: the field's controller lives and dies with the sheet
/// (never disposed while the sheet is still closing). A caption the server
/// would refuse is said here and never sent (fix 1, I-2).
class _CaptionSheet extends StatefulWidget {
  const _CaptionSheet({required this.initial});

  final String initial;

  @override
  State<_CaptionSheet> createState() => _CaptionSheetState();
}

class _CaptionSheetState extends State<_CaptionSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _invisible = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (datingHasInvisible(_controller.text)) {
      setState(() => _invisible = true);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AllowLargeText(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The counter follows the typing (fix 2, N-1).
            ListenableBuilder(
              listenable: _controller,
              builder:
                  (context, _) => TextField(
                    controller: _controller,
                    // Final fix (M-12): the keyboard learns nothing typed here.
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    inputFormatters: const [DatingRuneLimit(100)],
                    onChanged: (_) {
                      if (_invisible) setState(() => _invisible = false);
                    },
                    decoration: InputDecoration(
                      labelText: loc.dating_photoCaptionLabel,
                      counterText: loc.dating_gentleWaitAnswerCount(
                        _controller.text.runes.length,
                        100,
                      ),
                    ),
                  ),
            ),
            if (_invisible) ...[
              FlowErrorLine(text: loc.dating_textInvisible, liveRegion: true),
              const SizedBox(height: Spacing.sm),
            ],
            FlowPrimaryButton(label: loc.dating_photoSave, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// A slot's text action: a real disabled button when it can't be used
/// (M-3: read as off, never an enabled button that does nothing).
class _SlotLink extends StatelessWidget {
  const _SlotLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: flowAccent(context),
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
      ),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.n,
    required this.photo,
    required this.cacheWidth,
    required this.thumb,
    required this.state,
    required this.failed,
    required this.busy,
    required this.canAdd,
    required this.online,
    required this.error,
    required this.onAdd,
    required this.onCrop,
    required this.onEarlier,
    required this.onLater,
    required this.onCaption,
    required this.onRemove,
    this.dragIndex,
  });

  final int n;
  final DatingProfilePhoto? photo;
  final int cacheWidth;
  final Uint8List? thumb;
  final String state;
  final bool failed;
  final bool busy;
  final bool canAdd;
  final bool online;
  final Widget? error;
  final VoidCallback onAdd;
  final VoidCallback onCrop;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;
  final VoidCallback? onCaption;
  final VoidCallback? onRemove;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final p = photo;
    final rejected = p != null && p.isRejected;
    final caption = p?.caption;
    final neutral = Icon(
      p == null ? Icons.add_a_photo_outlined : Icons.image_outlined,
      size: 32,
    );
    final bytes = thumb;
    final image =
        bytes != null && bytes.isNotEmpty
            ? Image.memory(
              bytes,
              width: _thumb,
              height: _thumb,
              // Decoded at the slot's size, not the photo's (M-7).
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Bytes that can't be drawn are the neutral slot, calmly.
              errorBuilder: (_, __, ___) => neutral,
            )
            : neutral;
    final enabled = canAdd && !busy;
    return Semantics(
      container: true,
      // A failure or a step of an add is announced (§3.15).
      liveRegion: rejected || failed || busy,
      label: loc.dating_photoSlot(n, state),
      // The caption only the person sees, read with its photo (M-8).
      value: caption,
      customSemanticsActions: {
        if (onEarlier != null)
          CustomSemanticsAction(label: loc.dating_photoMoveEarlier): onEarlier!,
        if (onLater != null)
          CustomSemanticsAction(label: loc.dating_photoMoveLater): onLater!,
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child:
                  dragIndex == null
                      ? SizedBox(
                        width: _thumb,
                        height: _thumb,
                        child: Center(child: image),
                      )
                      : ReorderableDragStartListener(
                        key: ValueKey('drag_${p!.id}'),
                        index: dragIndex!,
                        enabled: online,
                        child: SizedBox(
                          width: _thumb,
                          height: _thumb,
                          child: Center(child: image),
                        ),
                      ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child:
                        rejected || failed
                            ? FlowErrorLine(text: state)
                            : Text(state, style: theme.textTheme.bodyMedium),
                  ),
                  if (caption != null && caption.isNotEmpty)
                    ExcludeSemantics(
                      child: Text(caption, style: theme.textTheme.bodySmall),
                    ),
                  if (error != null) error!,
                  Wrap(
                    children: [
                      if (p == null || rejected)
                        _SlotLink(
                          label:
                              p == null
                                  ? loc.dating_photoAdd
                                  : loc.dating_photoReplace,
                          onPressed: enabled ? onAdd : null,
                        ),
                      if (p != null && p.rejectionReason == 'contains_child')
                        _SlotLink(
                          label: loc.dating_photoCrop,
                          onPressed: enabled ? onCrop : null,
                        ),
                      if (p != null) ...[
                        IconButton(
                          tooltip: loc.dating_photoMoveEarlier,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: onEarlier,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoMoveLater,
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: onLater,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoCaption,
                          icon: const Icon(Icons.short_text),
                          onPressed: onCaption,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoRemove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onRemove,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
