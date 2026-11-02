// Spec 1 W3: today's invite service, scripted.
import 'package:attune/features/relationships/data/relationship_invite_service.dart';

class FakeInvites extends RelationshipInviteService {
  FakeInvites({this.acceptError, this.createError});

  RelationshipInviteException? acceptError;
  RelationshipInviteException? createError;

  /// Spec 1 W4b: what previewInvite answers (or throws).
  InvitePreview preview = const InvitePreview(
    state: InvitePreviewState.ok,
    inviterFirstName: 'Yaw',
  );
  RelationshipInviteException? previewError;
  final previewed = <String>[];
  final accepted = <String>[];
  int creates = 0;
  int withdrawals = 0;
  Duration? age;

  @override
  bool get isConfigured => true;

  @override
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    creates++;
    if (createError != null) throw createError!;
    return RelationshipInvite(
      relationshipId: 'r-new',
      code: 'K7P2QM',
      expiresAt: DateTime.utc(2026, 11, 2),
    );
  }

  @override
  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    accepted.add(inviteCode);
    if (acceptError != null) throw acceptError!;
    return const InviteAcceptance(
      relationshipId: 'r-joined',
      status: 'active',
      idempotent: false,
    );
  }

  @override
  Future<Duration?> inviteAge() async => age;

  @override
  Future<InvitePreview> previewInvite(String inviteCode) async {
    previewed.add(inviteCode);
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<void> withdrawPendingInvites() async => withdrawals++;
}
