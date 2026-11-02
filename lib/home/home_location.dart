import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/onboarding/domain/home_state.dart';

int _tabRequests = 0;

/// `/home`, or `/home?tab=chat|me` to open Tab 2 (Spec 1 §3.11): the
/// journal reminder tap, Spec 2's `me_update`, the guest's way back from
/// sign-up. Each request carries its own `n`, so asking again while the
/// shell is up opens Tab 2 again.
String homeLocation({AppTab? tab}) =>
    tab == null
        ? RouteNames.home
        : '${RouteNames.home}?tab=${tab.wire}&n=${++_tabRequests}';
