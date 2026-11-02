import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment_gate.dart';
import 'package:flutter/widgets.dart';

/// Tab 2 under flow_paths_v2 (Spec 1 §3.11): a linked couple gets the chat
/// (ChatHomeScreen, unchanged); the rest of the Relationship path gets its
/// space (R3, never Dating); Dating and Just for me get Me.
///
/// Spec 1 W4b (§3.8 R4): with [couplesV2], the chat waits behind "Welcome,
/// {couple}" the first time this phone sees the relationship linked
/// (LinkedMomentGate).
class HomeTabTwo extends StatelessWidget {
  const HomeTabTwo({
    super.key,
    required this.tab,
    required this.home,
    required this.onInviteSent,
    this.couplesV2 = false,
  });

  final AppTab tab;
  final HomeSnapshot home;
  final VoidCallback onInviteSent;

  /// flow_couples_v2, effective (read by the seam when it builds Tab 2).
  final bool couplesV2;

  @override
  Widget build(BuildContext context) {
    if (tab == AppTab.me) return MeHomeScreen(home: home);
    if (home.link == LinkState.linked) {
      final chat = AuthenticatedChatWorkspace(
        isCouples: true,
        isPendingCouples: false,
        onInviteSent: onInviteSent,
      );
      final relationshipId = home.linkDetail.relationshipId;
      if (!couplesV2 || relationshipId == null) return chat;
      return LinkedMomentGate(
        relationshipId: relationshipId,
        partnerFirstName: home.linkDetail.partnerFirstName,
        child: chat,
      );
    }
    return RelationshipSpaceScreen(home: home);
  }
}
