import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/together_widget.dart';

const togetherWidgetAppGroup = 'group.com.barsopus.attune';
const _payloadKey = 'together_widget_v1';

/// This phone's opt-in (Phase 8a R2); off unless set.
const enabledKey = 'together_widget_enabled';

/// Whether the card may show plan titles on this phone (Spec 1b). Off by
/// default; read from storage at every publish, like [enabledKey].
const widgetTitlesKey = 'together_widget_titles';

/// Where receive_sharing_intent's iOS share extension leaves the shared text
/// in the App Group; the plugin never removes it (Phase 8b R7).
const shareExtensionKeys = ['ShareKey', 'ShareMessageKey'];

/// Where the widget reads from (a seam so tests and quick exit stay simple).
abstract class WidgetStore {
  Future<void> save(String? payload);
  Future<void> remove(String key);
}

class HomeWidgetStore implements WidgetStore {
  const HomeWidgetStore();

  @override
  Future<void> save(String? payload) async {
    await HomeWidget.setAppGroupId(togetherWidgetAppGroup);
    await HomeWidget.saveWidgetData<String>(_payloadKey, payload);
    await HomeWidget.updateWidget(
      iOSName: 'TogetherWidget',
      qualifiedAndroidName: 'com.barsopus.attune.TogetherWidgetProvider',
    );
  }

  @override
  Future<void> remove(String key) async {
    await HomeWidget.setAppGroupId(togetherWidgetAppGroup);
    await HomeWidget.saveWidgetData<String>(key, null);
  }
}

/// Fills or empties the home-screen card. Never throws: a phone without
/// the widget (or a test without the plugin) must not break the caller.
class TogetherWidgetSync {
  static WidgetStore store = const HomeWidgetStore();

  static Future<void> publish(List<WidgetLine> lines) async {
    try {
      await store.save(encodeWidgetPayload(lines));
    } catch (_) {}
  }

  /// Publishes only if this phone has opted in, read from storage itself, so
  /// a stale in-memory "on" (say, after someone signs out) never publishes.
  static Future<void> publishIfEnabled(List<WidgetLine> lines) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(enabledKey) ?? false)) return;
      await publish(
        widgetLinesForCard(
          lines,
          showTitles: prefs.getBool(widgetTitlesKey) ?? false,
        ),
      );
    } catch (_) {}
  }

  /// Quick exit, sign-out and "off": nothing readable is left behind.
  static Future<void> clear() async {
    try {
      await store.save(null);
    } catch (_) {}
    await forgetShare();
  }

  /// Removes the App Group copy of a share once it's handled (or on exit).
  static Future<void> forgetShare() async {
    for (final key in shareExtensionKeys) {
      try {
        await store.remove(key);
      } catch (_) {}
    }
  }
}
