import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R4 on the inviter's phone (Spec 1 §3.8, W4b): the first time this phone
/// sees [relationshipId] linked, "Welcome, {couple}" comes before [child]
/// (the chat), on the next open if the phone wasn't open at link time.
/// Closing it records it for this relationship on this phone and deletes
/// the partner name R1 kept (§4.8: until linking).
class LinkedMomentGate extends ConsumerStatefulWidget {
  const LinkedMomentGate({
    super.key,
    required this.relationshipId,
    required this.child,
    this.partnerFirstName,
  });

  final String relationshipId;
  final String? partnerFirstName;
  final Widget child;

  @override
  ConsumerState<LinkedMomentGate> createState() => _LinkedMomentGateState();
}

class _LinkedMomentGateState extends ConsumerState<LinkedMomentGate> {
  /// The relationship whose R4 was closed in this visit.
  String? _closed;

  InviteDeviceStore? _device() {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    try {
      return InviteDeviceStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
      );
    } catch (_) {
      return null;
    }
  }

  void _close() {
    final device = _device();
    if (device != null) {
      unawaited(device.markLinkedMomentSeen(widget.relationshipId));
      unawaited(device.clearPartnerFirstName());
    }
    setState(() => _closed = widget.relationshipId);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.relationshipId;
    if (_closed == id) return widget.child;
    final device = _device();
    if (device == null || device.linkedMomentSeen(id)) return widget.child;
    return LinkedMoment(
      relationshipId: id,
      partnerFirstName: widget.partnerFirstName,
      onContinue: _close,
    );
  }
}
