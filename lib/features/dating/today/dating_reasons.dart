// Spec 2 W5b (§5.8; Fable M3): "Why you two were introduced". The server
// sends reason ids only; each is reviewed copy here, with the closing line
// always after. An id this app doesn't know, or one whose field the card
// doesn't carry, shows nothing (never free text).
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String? datingReasonLine(AppLocalizations loc, String id, DatingIntroCard c) =>
    switch (id) {
      'same_intention_timeline' => switch (c.card.timeline) {
        'within_two_years' => loc.dating_reasonMarriageSoon,
        'few_years' => loc.dating_reasonMarriageFew,
        'no_set_time' => loc.dating_reasonMarriageNone,
        _ => null,
      },
      'same_intention' => switch (c.card.intention) {
        'marriage' => loc.dating_reasonSameMarriage,
        'committed' => loc.dating_reasonSameCommitted,
        'companionship' => loc.dating_reasonSameCompanionship,
        'not_sure' => loc.dating_reasonSameNotSure,
        _ => null,
      },
      'compatible_intention' => loc.dating_reasonCompatible,
      'children_want_yes' => loc.dating_reasonChildrenYes,
      'children_want_no' => loc.dating_reasonChildrenNo,
      'children_have_both' => loc.dating_reasonChildrenHave,
      'same_faith' => switch (_name(loc, 'dating_faith_', c.card.faith)) {
        final faith? => loc.dating_reasonSameFaith(faith),
        null => null,
      },
      // Fix round 1 (T6 review M-4): only while the card shows faith.
      'faith_matters' =>
        c.card.faith == null ? null : loc.dating_reasonFaithMatters,
      'family_same_early' => loc.dating_reasonFamilyEarly,
      'family_same_when_serious' => loc.dating_reasonFamilyWhenSerious,
      'family_same_our_decision' => loc.dating_reasonFamilyOwn,
      'same_side' => switch (_name(loc, '', c.sideNameKey)) {
        final side? => loc.dating_reasonSamePlace(side),
        null => null,
      },
      'same_region' => switch (_name(loc, '', c.card.regionNameKey)) {
        final region? => loc.dating_reasonSamePlace(region),
        null => null,
      },
      'across_borders' => loc.dating_reasonAcrossBorders,
      _ => null,
    };

String? _name(AppLocalizations loc, String prefix, String? key) =>
    key == null ? null : datingListName(loc, '$prefix$key');

/// The reasons the card shows, in the server's order (at most three).
List<String> datingReasonLines(AppLocalizations loc, DatingIntroCard c) => [
  for (final id in c.reasons.take(3))
    if (datingReasonLine(loc, id, c) case final line?) line,
];
