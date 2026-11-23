// Spec 2 W8b Task 8 (R-80): the app icon, faked. Shared by the Dating
// page's tests and Settings' (one control behind both pages).
import 'dart:async';

import 'package:attune/core/device/app_icon.dart';

class FakeAppIcon implements AppIconControl {
  FakeAppIcon([this.icon = AppIconChoice.attune]);

  AppIconChoice? icon;
  bool refuse = false;
  final chosen = <AppIconChoice>[];

  /// While set, a choice waits for it (the phone answering later).
  Completer<void>? hold;

  @override
  Future<AppIconChoice?> current() async => icon;

  @override
  Future<bool> choose(AppIconChoice choice) async {
    chosen.add(choice);
    if (hold != null) await hold!.future;
    if (refuse) return false;
    icon = choice;
    return true;
  }
}
