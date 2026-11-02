import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:flutter/widgets.dart';

/// Tab 2 under flow_paths_v2 (Spec 1 §3.11): a linked couple gets the chat
/// (ChatHomeScreen, unchanged); the rest of the Relationship path gets its
/// space (R3, never Dating); Dating and Just for me get Me.
class HomeTabTwo extends StatelessWidget {
  const HomeTabTwo({
    super.key,
    required this.tab,
    required this.home,
    required this.onInviteSent,
  });

  final AppTab tab;
  final HomeSnapshot home;
  final VoidCallback onInviteSent;

  @override
  Widget build(BuildContext context) {
    if (tab == AppTab.me) return MeHomeScreen(home: home);
    if (home.link == LinkState.linked) {
      return AuthenticatedChatWorkspace(
        isCouples: true,
        isPendingCouples: false,
        onInviteSent: onInviteSent,
      );
    }
    return RelationshipSpaceScreen(home: home);
  }
}
