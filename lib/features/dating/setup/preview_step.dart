// Spec 2 §3.2 D12 (Step 11 of 12): the person's own card from
// get_dating_profile_preview(), the "Never shown" line, edit links per part
// (R-40), the first-name editor, and the notification ask in context (R-27:
// the OS prompt, no metric). Photos are the person's own bytes, in memory,
// evicted when the step goes; with data saver on they wait for a tap.
//
// T11 carries: the photos follow Task 10's rule (datingCardPhotoIds): the
// server's copy only for an approved photo, a pending one as a neutral slot,
// anything else not at all; no read before the person's list says approved
// (carry D). The typed name is seeded only where the person hasn't typed,
// and Save waits for the saved answers (carry C). Every write settles its
// key (carry A, through the frame's write). Another account sees nothing of
// the last one's card, photos or typed name (D8).
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The card's photos D12 may show (Task 10's rule, T11 carry D): until the
/// person's own list has loaded, each is a neutral slot; then an approved
/// photo (scanned clear, R-24) or a pending one (a neutral slot: D12 holds
/// no local copy) stays, and a rejected one, one waiting for a person or a
/// CSAM hit never shows.
List<String> datingCardPhotoIds(DatingCard card, DatingPhotoList? list) {
  if (list == null) return card.photoIds;
  final byId = {for (final p in list.photos) p.id: p};
  return [
    for (final id in card.photoIds)
      if (byId[id] case final p? when p.isApproved || p.isPending) id,
  ];
}

class DatingPreviewStep extends ConsumerStatefulWidget {
  const DatingPreviewStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPreviewStep> createState() => _DatingPreviewStepState();
}

class _DatingPreviewStepState extends ConsumerState<DatingPreviewStep>
    with DatingStepState<DatingPreviewStep> {
  final _name = TextEditingController();
  final _bytes = <String, Uint8List>{};
  bool _editingName = false;
  bool _nameInvalid = false;
  bool _showPhotos = false;
  bool _asking = false;
  late bool _granted;

  /// Bumped on every reset: a photo read started for another account, or
  /// before the step went, lands nowhere.
  int _gen = 0;

  /// Photos whose read failed once and was given back (M-2): tried again
  /// on the next sync, once per visit.
  final _retried = <String>{};

  @override
  void initState() {
    super.initState();
    _granted = ref.read(pushAskerProvider).permissionGranted;
  }

  @override
  void resetAnswers() {
    _gen++;
    _name.clear();
    _editingName = false;
    _nameInvalid = false;
    _showPhotos = false;
    _asking = false;
    _retried.clear();
    _evict();
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    if (!isTouched('name')) _name.text = p.displayName ?? '';
  }

  void _forget(Uint8List b) {
    if (b.isNotEmpty) {
      PaintingBinding.instance.imageCache.evict(MemoryImage(b));
    }
  }

  void _evict() {
    _bytes.values.forEach(_forget);
    _bytes.clear();
  }

  @override
  void dispose() {
    _gen++;
    _name.dispose();
    _evict();
    super.dispose();
  }

  void _edit(String step) => widget.nav.next('$step?from=preview');

  void _saveName() {
    final name = _name.text.trim();
    final n = name.runes.length;
    if (n < 1 || n > 30) {
      setState(() => _nameInvalid = true);
      return;
    }
    setState(() => _nameInvalid = false);
    write(
      'd12name',
      name,
      (key) => ref.read(datingSetupGatewayProvider).saveDisplayName(key, name),
      // The saved name re-reads the card through the profile (M-9: once).
      (_) => setState(() => _editingName = false),
    );
  }

  Future<void> _turnOn() async {
    if (_asking || saving) return;
    final account = ref.read(datingAccountProvider);
    setState(() => _asking = true);
    PushAskOutcome? outcome;
    try {
      outcome = await ref
          .read(pushAskerProvider)
          .askInContext(PushAskContext.j3);
    } catch (_) {
      outcome = null;
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _asking = false;
      _granted = outcome == PushAskOutcome.granted;
    });
    if (!_granted) return;
    await write(
      'd12digest',
      true,
      (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
        'digest_push': true,
      }),
      (_) {},
    );
  }

  void _messages(bool on) => write(
    'd12chat',
    on,
    (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
      'chat_push': on,
    }),
    (_) {},
  );

  /// Reads back the approved photos only (never a pending one, never one
  /// the list doesn't name), and forgets any photo that may no longer show.
  void _syncPhotos(DatingCard card, DatingPhotoList list, bool load) {
    final approved = {
      for (final p in list.photos)
        if (p.isApproved) p.id: p.storageKey,
    };
    var changed = false;
    for (final id in _bytes.keys.toList()) {
      if (!approved.containsKey(id)) {
        _forget(_bytes.remove(id)!);
        changed = true;
      }
    }
    if (changed) setState(() {});
    if (!load) return;
    final account = ref.read(datingAccountProvider);
    final gen = _gen;
    final gateway = ref.read(datingPhotosGatewayProvider);
    for (final id in card.photoIds) {
      final key = approved[id];
      if (key == null || _bytes.containsKey(id)) continue;
      _bytes[id] = Uint8List(0);
      bool current() =>
          mounted &&
          gen == _gen &&
          _bytes.containsKey(id) &&
          ref.read(datingAccountProvider) == account;
      // M-2: a failed or empty read gives its place back once and rebuilds
      // (fix 2, M-2b), so the next sync tries again at once; after that the
      // slot stays neutral.
      void failed() {
        if (current() && _retried.add(id)) setState(() => _bytes.remove(id));
      }

      gateway
          .bytes(key)
          .then((b) {
            if (b == null || b.isEmpty) return failed();
            if (current()) setState(() => _bytes[id] = b);
          })
          .catchError((Object _) => failed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final profile = watchProfile();
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final read = ref.watch(datingPreviewProvider(account));
    final list = ref.watch(datingPhotosProvider(account)).valueOrNull;
    final card = read.hasError ? null : read.valueOrNull;
    final dataSaver = profile?.dataSaver ?? false;
    final hidden = dataSaver && !_showPhotos;
    if (card != null && card.photosAfterMutual && _bytes.isNotEmpty) {
      // M-3: photos now wait for mutual interest: none stays in memory.
      final gen = _gen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _gen && _bytes.isNotEmpty) {
          setState(_evict);
        }
      });
    }
    if (card != null && list != null && !card.photosAfterMutual) {
      // No read before the saved answers say whether data saver is on.
      final load = profile != null && !hidden;
      final gen = _gen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _gen) _syncPhotos(card, list, load);
      });
    }
    final shownCard = card?.withPhotos(datingCardPhotoIds(card, list));
    Widget? edit(String part) {
      final (label, step) = switch (part) {
        'heading' => (loc.dating_editWhere, 'where'),
        'intention' => (loc.dating_editLooking, 'looking-for'),
        'prompts' => (loc.dating_editPrompts, 'prompts'),
        'children' => (loc.dating_editChildren, 'children'),
        // I-2: each optional line has its own step. Gender and faith link
        // even when hidden (that is where they are turned on); marital only
        // beside its line (D2 is already the intention's link).
        'gender' => (loc.dating_editAbout, 'you'),
        'faith' => (loc.dating_editFaith, 'faith'),
        'marital' when card?.marital != null => (
          loc.dating_editMarital,
          'looking-for',
        ),
        'photos' => (loc.dating_editPhotos, 'photos'),
        _ => ('', ''),
      };
      if (step.isEmpty) return null;
      return DatingStartLink(label: label, onPressed: () => _edit(step));
    }

    return DatingStepFrame(
      step: 'preview',
      title: loc.dating_previewTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profileFailed)
            DatingLoadError(busy: profileRetrying, onRetry: retryProfile),
          if (read.hasError) ...[
            FlowErrorLine(
              text: loc.dating_previewUnavailable,
              liveRegion: true,
            ),
            DatingStartLink(
              label: loc.dating_tryAgain,
              onPressed: () => ref.invalidate(datingPreviewProvider(account)),
            ),
          ] else if (shownCard != null)
            DatingCardView(
              card: shownCard,
              photos: [
                for (final id in shownCard.photoIds) _bytes[id] ?? Uint8List(0),
              ],
              photosHidden: hidden,
              onShowPhotos: () => setState(() => _showPhotos = true),
              trailing: edit,
            )
          else if (read.isLoading)
            const Center(child: CircularProgressIndicator.adaptive()),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_previewNever, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          if (!_editingName)
            DatingStartLink(
              label: loc.dating_editName,
              onPressed: () => setState(() => _editingName = true),
            )
          else ...[
            TextField(
              key: const ValueKey('dating_name_field'),
              controller: _name,
              // Final fix (M-12): a shared phone: the keyboard learns and
              // suggests nothing typed here.
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              maxLength: 30,
              onChanged: (_) => answer(['name'], () {}),
              decoration: InputDecoration(
                labelText: loc.dating_nameLabel,
                helperText: loc.dating_nameHelper,
                helperMaxLines: 3,
              ),
            ),
            if (_nameInvalid)
              FlowErrorLine(text: loc.dating_nameInvalid, liveRegion: true),
            FlowSecondaryButton(
              label: loc.dating_save,
              busy: saving,
              // Never before the saved answers are on screen (T6 fix 2).
              onPressed: online && profileReady && !saving ? _saveName : null,
            ),
          ],
          if (refusal != null) datingRefusalLine(loc, refusal!),
          const SizedBox(height: Spacing.md),
          if (profile?.digestPush ?? false)
            Text(loc.dating_pushDigestOn, style: theme.textTheme.bodyMedium)
          else ...[
            Text(loc.dating_pushDigest, style: theme.textTheme.bodyMedium),
            // M-4: off (and read as off) offline or while a save or the
            // ask is running.
            DatingStartLink(
              label: loc.dating_pushTurnOn,
              onPressed: online && !saving && !_asking ? _turnOn : null,
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_pushMessages),
            value: _granted && (profile?.chatPush ?? true),
            onChanged: _granted && online ? _messages : null,
          ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: () => widget.nav.next('ready'),
      ),
    );
  }
}
