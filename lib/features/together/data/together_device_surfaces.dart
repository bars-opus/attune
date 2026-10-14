import 'together_calendar_mirror.dart';
import 'together_live_activity.dart';
import 'together_widget_sync.dart';

/// Everything Together puts on this phone outside the app (Phase 8): the
/// home-screen card, the lock-screen plan and the calendar copy. Quick exit
/// and sign-out empty them all (owner rule: discreet). Never throws.
Future<void> clearTogetherDeviceSurfaces() async {
  await TogetherWidgetSync.clear();
  await TogetherLiveActivity.end();
  await TogetherMirror.clear();
}
