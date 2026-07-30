// lib/core/utils/relationship_status_display.dart

/// Shared relationship-status → display/icon/color mapping.
///
/// Every status glyph in the app (opinion cards, comment threads, forum
/// posts/topics, the anonymous profile header, compose screens, quoted
/// previews) derives from the same four raw values stored on
/// `profiles.relationship_status` ('single'/'taken'/'figuring_it_out'/
/// 'open'). This used to be copy-pasted privately into ~8 different widgets;
/// consolidated here so a future status (or a color/icon tweak) only needs
/// one edit.
library;

import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Raw DB value ('single', 'taken', 'figuring_it_out', 'open') → the
/// human-readable label used both for display text and as the key
/// [statusIconFor]/[statusColorFor] switch on. Unknown/null status returns
/// '' rather than a fallback word — callers that need a fallback (e.g. "by
/// Someone" placeholder text) apply their own at the call site.
String statusDisplayFor(String? status) {
  switch (status) {
    case 'single':
      return 'Single';
    case 'taken':
      return 'Taken';
    case 'figuring_it_out':
      return 'Figuring it out';
    case 'open':
      return 'Open';
    default:
      return '';
  }
}

/// The single-letter glyph for a status label (from [statusDisplayFor]).
/// Keyed off the label's first letter rather than the raw DB value so it
/// stays in sync with [statusDisplayFor] by construction.
IconData statusIconFor(String statusDisplay) {
  if (statusDisplay.isEmpty) {
    return FontAwesomeIcons.circleQuestion;
  }
  switch (statusDisplay[0].toUpperCase()) {
    case 'S':
      return FontAwesomeIcons.s;
    case 'T':
      return FontAwesomeIcons.t;
    case 'F':
      return FontAwesomeIcons.f;
    case 'O':
      return FontAwesomeIcons.o;
    default:
      return FontAwesomeIcons.circleQuestion;
  }
}

/// The status's tint, used as both the icon color and its circular
/// background fill across every call site.
Color statusColorFor(String statusDisplay, ColorScheme colorScheme) {
  switch (statusDisplay) {
    case 'Single':
      return colorScheme.info;
    case 'Taken':
      return colorScheme.error;
    case 'Figuring it out':
      return colorScheme.warning;
    case 'Open':
      return colorScheme.neutral;
    default:
      return colorScheme.error;
  }
}
