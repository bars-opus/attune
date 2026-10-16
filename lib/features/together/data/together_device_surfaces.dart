import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';

import 'together_calendar_mirror.dart';
import 'together_live_activity.dart';
import 'together_widget_sync.dart';

/// Everything Together puts on this phone outside the app (Phase 8): the
/// home-screen card, the lock-screen plan and the calendar copy, plus the
/// couple map's distance widget (cleared first; widget spec §6.4). Quick
/// exit and sign-out empty them all (owner rule: discreet). Never throws.
Future<void> clearTogetherDeviceSurfaces() async {
  // Started first, run alongside: a slow widget call never holds these up.
  final distanceWidget = CoupleWidgetSync.clear();
  await TogetherWidgetSync.clear();
  await TogetherLiveActivity.end();
  await TogetherMirror.clear();
  await distanceWidget;
}
