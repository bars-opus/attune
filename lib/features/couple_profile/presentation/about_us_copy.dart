import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

/// About us's words for every answer (Spec 1 §3.8), one place for the
/// question flow and the About us screen. Dates only through MyDateFormat.

String stageText(AppLocalizations loc, CoupleStage stage, {String? words}) =>
    switch (stage) {
      CoupleStage.dating => loc.aboutUs_stageDating,
      CoupleStage.engaged => loc.aboutUs_stageEngaged,
      CoupleStage.married => loc.aboutUs_stageMarried,
      CoupleStage.other =>
        (words == null || words.trim().isEmpty)
            ? loc.aboutUs_stageOther
            : words.trim(),
    };

String livingText(AppLocalizations loc, Living living) => switch (living) {
  Living.together => loc.aboutUs_livingTogether,
  Living.apartNearby => loc.aboutUs_livingApartNearby,
  Living.longDistance => loc.aboutUs_livingLongDistance,
};

String childrenChoiceText(AppLocalizations loc, Children children) =>
    switch (children) {
      Children.none => loc.aboutUs_childrenNo,
      Children.yes => loc.aboutUs_childrenYes,
      Children.expecting => loc.aboutUs_childrenExpecting,
      Children.preferNotToSay => loc.aboutUs_childrenPreferNot,
    };

String bandText(AppLocalizations loc, ChildAgeBand band) => switch (band) {
  ChildAgeBand.under2 => loc.aboutUs_bandUnder2,
  ChildAgeBand.twoToFive => loc.aboutUs_band2to5,
  ChildAgeBand.sixToTwelve => loc.aboutUs_band6to12,
  ChildAgeBand.thirteenToSeventeen => loc.aboutUs_band13to17,
  ChildAgeBand.eighteenPlus => loc.aboutUs_band18plus,
};

/// "Yes (13-17, 18+)", "Yes", "No", "We're expecting", "Prefer not to say".
String childrenText(
  AppLocalizations loc,
  Children children,
  List<ChildAgeBand> bands,
) {
  if (children == Children.yes && bands.isNotEmpty) {
    return loc.aboutUs_childrenYesBands(
      [for (final band in bands) bandText(loc, band)].join(', '),
    );
  }
  return childrenChoiceText(loc, children);
}

String ceremonyLabelText(AppLocalizations loc, CeremonyLabel label) =>
    switch (label) {
      CeremonyLabel.customary => loc.aboutUs_labelCustomary,
      CeremonyLabel.church => loc.aboutUs_labelChurch,
      CeremonyLabel.mosque => loc.aboutUs_labelMosque,
      CeremonyLabel.civil => loc.aboutUs_labelCivil,
      CeremonyLabel.other => loc.aboutUs_labelOther,
    };

/// One ceremony on the About us screen: "Customary, 1999", or the year.
String ceremonyText(AppLocalizations loc, Ceremony ceremony) {
  final year = MyDateFormat.toYear(DateTime(ceremony.year));
  final label = ceremony.label;
  return label == null
      ? year
      : loc.aboutUs_ceremonyLine(ceremonyLabelText(loc, label), year);
}

/// AU6's option for a ceremony: "Customary ceremony, 1999".
String ceremonyAnniversaryText(AppLocalizations loc, Ceremony ceremony) {
  final year = MyDateFormat.toYear(DateTime(ceremony.year));
  final label = ceremony.label;
  return label == null
      ? loc.aboutUs_anniversaryCeremonyPlain(year)
      : loc.aboutUs_anniversaryCeremony(ceremonyLabelText(loc, label), year);
}

/// "Together since": the date as precisely as it was given ("October
/// 2024"), never as time elapsed (§3.8: never an elapsed counter).
String sinceText(TogetherSince since) => switch (since.precision) {
  DatePrecision.day => MyDateFormat.toDate(since.date),
  DatePrecision.month => MyDateFormat.toMonthYear(since.date),
  DatePrecision.year => MyDateFormat.toYear(since.date),
};

String anniversaryText(AppLocalizations loc, CoupleProfile profile) =>
    switch (profile.anniversarySource) {
      AnniversarySource.off => loc.aboutUs_anniversaryOff,
      AnniversarySource.togetherSince => loc.aboutUs_anniversaryTogether,
      AnniversarySource.ceremony1 =>
        profile.ceremonies.isEmpty
            ? loc.aboutUs_anniversaryOff
            : ceremonyAnniversaryText(loc, profile.ceremonies[0]),
      AnniversarySource.ceremony2 =>
        profile.ceremonies.length < 2
            ? loc.aboutUs_anniversaryOff
            : ceremonyAnniversaryText(loc, profile.ceremonies[1]),
    };

/// "Changed by Yaw - Tue, 12 Nov" (D2: MyDateFormat.join, never a middle dot): the
/// short date this year, the full one otherwise.
String changedByText(AppLocalizations loc, FieldChange change, DateTime now) {
  final who =
      change.byMe
          ? loc.aboutUs_changedByYou
          : change.byFirstName == null
          ? loc.aboutUs_changedByPartner
          : loc.aboutUs_changedBy(change.byFirstName!);
  final when =
      change.at.year == now.year
          ? MyDateFormat.toDateShort(change.at)
          : MyDateFormat.toDate(change.at);
  return MyDateFormat.join([who, when]);
}

/// A refused write in the app's words (§3.8 Errors): the specific rule when
/// the screen can fix it, else "We couldn't save that. Try again."
String refusalText(
  AppLocalizations loc,
  AboutUsRefusal reason,
) => switch (reason) {
  AboutUsRefusal.futureDate => loc.aboutUs_errorFuture,
  AboutUsRefusal.anniversaryNeedsDay => loc.aboutUs_errorAnniversaryNeedsDay,
  AboutUsRefusal.readOnly => loc.aboutUs_errorReadOnly,
  _ => loc.flow_saveFailed,
};
