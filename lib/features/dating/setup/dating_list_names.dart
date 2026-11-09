// Spec 2 W3 (§2.2 region_list, faith_list): the app's name for every
// name_key the country config can send. A key with no name here is not
// offered (Task 5's test proves every seeded key has one).
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String? datingListName(AppLocalizations loc, String key) => switch (key) {
  'dating_region_gh_af' => loc.dating_region_gh_af,
  'dating_region_gh_ah' => loc.dating_region_gh_ah,
  'dating_region_gh_bo' => loc.dating_region_gh_bo,
  'dating_region_gh_be' => loc.dating_region_gh_be,
  'dating_region_gh_cp' => loc.dating_region_gh_cp,
  'dating_region_gh_ep' => loc.dating_region_gh_ep,
  'dating_region_gh_aa' => loc.dating_region_gh_aa,
  'dating_region_gh_ne' => loc.dating_region_gh_ne,
  'dating_region_gh_np' => loc.dating_region_gh_np,
  'dating_region_gh_ot' => loc.dating_region_gh_ot,
  'dating_region_gh_sv' => loc.dating_region_gh_sv,
  'dating_region_gh_ue' => loc.dating_region_gh_ue,
  'dating_region_gh_uw' => loc.dating_region_gh_uw,
  'dating_region_gh_tv' => loc.dating_region_gh_tv,
  'dating_region_gh_wp' => loc.dating_region_gh_wp,
  'dating_region_gh_wn' => loc.dating_region_gh_wn,
  'dating_side_gh_accra' => loc.dating_side_gh_accra,
  'dating_side_gh_tema' => loc.dating_side_gh_tema,
  'dating_side_gh_kumasi' => loc.dating_side_gh_kumasi,
  'dating_side_gh_outside_kumasi' => loc.dating_side_gh_outside_kumasi,
  'dating_region_gb_tlc' => loc.dating_region_gb_tlc,
  'dating_region_gb_tld' => loc.dating_region_gb_tld,
  'dating_region_gb_tle' => loc.dating_region_gb_tle,
  'dating_region_gb_tlf' => loc.dating_region_gb_tlf,
  'dating_region_gb_tlg' => loc.dating_region_gb_tlg,
  'dating_region_gb_tlh' => loc.dating_region_gb_tlh,
  'dating_region_gb_tli' => loc.dating_region_gb_tli,
  'dating_region_gb_tlj' => loc.dating_region_gb_tlj,
  'dating_region_gb_tlk' => loc.dating_region_gb_tlk,
  'dating_region_gb_tll' => loc.dating_region_gb_tll,
  'dating_region_gb_tlm' => loc.dating_region_gb_tlm,
  'dating_region_gb_tln' => loc.dating_region_gb_tln,
  'dating_faith_christian' => loc.dating_faith_christian,
  'dating_faith_muslim' => loc.dating_faith_muslim,
  'dating_faith_traditional' => loc.dating_faith_traditional,
  'dating_faith_hindu' => loc.dating_faith_hindu,
  'dating_faith_sikh' => loc.dating_faith_sikh,
  'dating_faith_jewish' => loc.dating_faith_jewish,
  'dating_faith_buddhist' => loc.dating_faith_buddhist,
  'dating_faith_other' => loc.dating_faith_other,
  'dating_faith_none' => loc.dating_faith_none,
  'dating_faith_prefer_not_to_say' => loc.dating_faith_prefer_not_to_say,
  'dating_denomination_catholic' => loc.dating_denomination_catholic,
  'dating_denomination_anglican' => loc.dating_denomination_anglican,
  'dating_denomination_methodist' => loc.dating_denomination_methodist,
  'dating_denomination_presbyterian' => loc.dating_denomination_presbyterian,
  'dating_denomination_pentecostal_charismatic' => loc.dating_denomination_pentecostal_charismatic,
  'dating_denomination_seventh_day_adventist' => loc.dating_denomination_seventh_day_adventist,
  'dating_denomination_other_christian' => loc.dating_denomination_other_christian,
  'dating_denomination_church_of_england_anglican' => loc.dating_denomination_church_of_england_anglican,
  'dating_denomination_orthodox' => loc.dating_denomination_orthodox,
  _ => null,
};

/// A region by code, through W1b's key convention; an unknown code reads as
/// itself (a sentence about where Dating is open must still read).
String datingRegionName(AppLocalizations loc, String country, String code) =>
    datingListName(
      loc,
      'dating_region_${country.toLowerCase()}_${code.toLowerCase()}',
    ) ??
    code.toUpperCase();

String datingRegionList(
  AppLocalizations loc,
  String country,
  List<String> codes,
) => formatCountryList(
  codes,
  nameOf: (code) => datingRegionName(loc, country, code),
  pair: loc.flow_listTwo,
);
