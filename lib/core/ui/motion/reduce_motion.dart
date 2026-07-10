import 'package:flutter/widgets.dart';

/// True when the OS "reduce motion" accessibility setting is on. Every animated
/// primitive checks this and degrades to an instant end-state (Spec §2).
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;
