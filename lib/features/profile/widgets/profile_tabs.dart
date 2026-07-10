
import 'package:attune/features/auth/utility/auth_exports.dart';

List<AppTabItem> buildProfileTabs(
  String profileUserId,
  isCurrentUser,
  isLogin, {
  AppLocalizations? loc,
}) {
  // If loc is not provided, we're just building for tab count in initState
  // The actual labels will be used when the tabs are rendered in _buildBody
  if (loc == null) {
    // Return with placeholder labels for initialization
    return [
      const AppTabItem(label: '', icon: null, content: null),
      const AppTabItem(label: '', icon: null, content: null),
      const AppTabItem(label: '', icon: null, content: null),
    ];
  }

  final labels = loc;
  return [
    AppTabItem(
      label: labels.profileTabsAppointments,
      icon: null,
      content:
         Container(),
    ),
    AppTabItem(
      label: labels.profileTabsBuys,
      icon: null,
      content: Container(),
    ),
    AppTabItem(
      label: labels.profileTabsSaves,
      icon: null,
      content: Container(),
    ),
  ];
}
