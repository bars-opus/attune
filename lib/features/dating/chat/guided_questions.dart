// Spec 2 W6c (§3.6): the guided first conversation's reviewed questions,
// by the server's ids (nothing written by AI).
import 'package:attune/i10n/generated/app_localizations.dart';

String datingGuidedQuestion(AppLocalizations loc, String id) => switch (id) {
  'good_saturday' => loc.dating_guided_good_saturday,
  'food_every_week' => loc.dating_guided_food_every_week,
  'looking_forward' => loc.dating_guided_looking_forward,
  'proud_of' => loc.dating_guided_proud_of,
  'laugh_with' => loc.dating_guided_laugh_with,
  'where_you_grew_up' => loc.dating_guided_where_you_grew_up,
  'good_relationship' => loc.dating_guided_good_relationship,
  'time_with_family' => loc.dating_guided_time_with_family,
  'before_first_meeting' => loc.dating_guided_before_first_meeting,
  _ => '',
};
