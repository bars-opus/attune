// Spec 1 W10b (§2.2, §2.3): every Spec 1 screen and widget lays out by
// direction (start/end), never by physical side, so right-to-left text
// mirrors it; and every one that animates reads the phone's reduce-motion
// setting. The list is the presentation files Spec 1 created (W1-W9e); a
// file added to it later is checked the same way.
//
// Limit (batch 7 review M-4): the motion check is per file, so one
// reduce-motion read passes a file with several animations. The per-widget
// checks are behavioural: test/accessibility/w10/deck_advance_motion_test.dart
// and spec1_motion_direction_test.dart (the deck, R4, the three selection
// animations), each with a mutant.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const spec1Presentation = <String>[
  'lib/core/notifications/presentation/widgets/push_ask_row.dart',
  'lib/core/ui/motion/shared_axis_step.dart',
  'lib/core/ui/text/allow_large_text.dart',
  'lib/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/invite_landing_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart',
  'lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/welcome_screen.dart',
  'lib/features/auth/sign_up/presentation/sign_up_flags.dart',
  'lib/features/auth/sign_up/presentation/steps/account_check_step.dart',
  'lib/features/auth/sign_up/presentation/steps/birth_date_step.dart',
  'lib/features/auth/sign_up/presentation/steps/code_step.dart',
  'lib/features/auth/sign_up/presentation/steps/consent_step.dart',
  'lib/features/auth/sign_up/presentation/steps/dormant_step.dart',
  'lib/features/auth/sign_up/presentation/steps/fresh_start_step.dart',
  'lib/features/auth/sign_up/presentation/steps/name_step.dart',
  'lib/features/auth/sign_up/presentation/steps/no_account_step.dart',
  'lib/features/auth/sign_up/presentation/steps/phone_step.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_buttons.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_colors.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_frame.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_text_field.dart',
  'lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart',
  'lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart',
  'lib/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart',
  'lib/features/auth/sign_up/presentation/widgets/submit_once.dart',
  'lib/features/couple_profile/presentation/about_us_copy.dart',
  'lib/features/couple_profile/presentation/about_us_entry.dart',
  'lib/features/couple_profile/presentation/couple_profile_providers.dart',
  'lib/features/couple_profile/presentation/screens/about_us_question_flow.dart',
  'lib/features/couple_profile/presentation/screens/about_us_screen.dart',
  'lib/features/couple_profile/presentation/widgets/about_us_card.dart',
  'lib/features/couple_profile/presentation/widgets/about_us_choice.dart',
  'lib/features/couple_profile/presentation/widgets/changed_by_line.dart',
  'lib/features/healing/presentation/providers/healing_support_providers.dart',
  'lib/features/healing/presentation/widgets/healing_support.dart',
  'lib/features/me/presentation/me_providers.dart',
  'lib/features/me/presentation/path_switch.dart',
  'lib/features/me/presentation/screens/me_home_screen.dart',
  'lib/features/me/presentation/widgets/dating_lock_setting.dart',
  'lib/features/me/presentation/widgets/dating_slot.dart',
  'lib/features/me/presentation/widgets/first_action_card.dart',
  'lib/features/me/presentation/widgets/healing_choice_sheet.dart',
  'lib/features/me/presentation/widgets/journal_reminder_row.dart',
  'lib/features/me/presentation/widgets/more_ways_sheet.dart',
  'lib/features/me/presentation/widgets/your_space_section.dart',
  'lib/features/onboarding/presentation/path_chooser.dart',
  'lib/features/onboarding/presentation/providers/flow_flags.dart',
  'lib/features/onboarding/presentation/providers/home_state_providers.dart',
  'lib/features/onboarding/presentation/screens/invite_partner_screen.dart',
  'lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart',
  'lib/features/onboarding/presentation/widgets/catch_up_steps.dart',
  'lib/features/onboarding/presentation/widgets/invite_partner_step.dart',
  'lib/features/onboarding/presentation/widgets/path_step.dart',
  'lib/features/opinions/presentation/providers/opinions_safety_provider.dart',
  'lib/features/opinions/presentation/widgets/content_filter_notice.dart',
  'lib/features/opinions/presentation/widgets/need_support_link.dart',
  'lib/features/reflection_journal/presentation/providers/journal_support_providers.dart',
  'lib/features/reflection_journal/presentation/widgets/journal_support_card.dart',
  'lib/features/relationships/presentation/invite_error_copy.dart',
  'lib/features/relationships/presentation/invite_share_actions.dart',
  'lib/features/relationships/presentation/screens/join_invite_screen.dart',
  'lib/features/relationships/presentation/screens/relationship_space_screen.dart',
  'lib/features/relationships/presentation/widgets/linked_moment.dart',
  'lib/features/relationships/presentation/widgets/linked_moment_gate.dart',
  'lib/features/safety/presentation/providers/support_resources_providers.dart',
  'lib/features/safety/presentation/screens/report_child_concern_screen.dart',
  'lib/features/safety/presentation/screens/support_resources_v2_screen.dart',
  'lib/features/settings/presentation/screens/birth_date_settings_screen.dart',
  'lib/features/settings/presentation/screens/how_you_use_attune_screen.dart',
  'lib/home/widgets/home_tab_two.dart',
];

/// Physical-side layout that does not mirror under RTL.
final _physical = <String, RegExp>{
  'EdgeInsets.only(left:/right:)': RegExp(
    r'EdgeInsets\.only\([^)]*\b(left|right)\s*:',
  ),
  'Alignment left/right': RegExp(
    r'\bAlignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b',
  ),
  'TextAlign.left/right': RegExp(r'\bTextAlign\.(left|right)\b'),
  'Positioned(left:/right:)': RegExp(r'Positioned\([^)]*\b(left|right)\s*:'),
};

/// EdgeInsets.fromLTRB with different left and right values.
final _ltrb = RegExp(
  r'EdgeInsets\.fromLTRB\(\s*([^,]+?)\s*,\s*[^,]+?\s*,\s*([^,]+?)\s*,',
);

final _animates = RegExp(
  r'\b(AnimationController|AnimatedContainer|AnimatedOpacity|'
  r'TweenAnimationBuilder|AnimatedSwitcher|AnimatedSize|AnimatedCrossFade|'
  r'AnimatedAlign|AnimatedPositioned|AnimatedScale|AnimatedSlide)\b',
);
final _readsReduceMotion = RegExp(
  r'reduceMotionOf\(|disableAnimations|\breduceMotion\b',
);

void main() {
  test('every listed file exists', () {
    for (final path in spec1Presentation) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('Spec 1 screens lay out by direction, not by side (RTL)', () {
    final found = <String>[];
    for (final path in spec1Presentation) {
      final src = File(path).readAsStringSync();
      for (final MapEntry(key: rule, value: re) in _physical.entries) {
        for (final m in re.allMatches(src)) {
          final line = src.substring(0, m.start).split('\n').length;
          found.add('$path:$line $rule');
        }
      }
      for (final m in _ltrb.allMatches(src)) {
        if (m.group(1) != m.group(2)) {
          final line = src.substring(0, m.start).split('\n').length;
          found.add('$path:$line EdgeInsets.fromLTRB, left != right');
        }
      }
    }
    expect(found, isEmpty);
  });

  test('Spec 1 widgets that animate read reduce motion', () {
    final found = <String>[];
    for (final path in spec1Presentation) {
      final src = File(path).readAsStringSync();
      if (_animates.hasMatch(src) && !_readsReduceMotion.hasMatch(src)) {
        found.add(path);
      }
    }
    expect(found, isEmpty);
  });
}
