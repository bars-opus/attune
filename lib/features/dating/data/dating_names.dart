// Spec 2 W3a: country and open-place names inside Dating sentences. The
// open lists are always built from get_dating_availability (R-36).
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String datingCountryName(AppLocalizations loc, String iso) =>
    countryNameFor(iso, special: {'GB': loc.dating_countryUk});

String _list(AppLocalizations loc, List<String> names) =>
    formatCountryList(names, nameOf: (name) => name, pair: loc.flow_listTwo);

/// "the United Kingdom and Ghana (Greater Accra and Ashanti)".
String datingOpenList(AppLocalizations loc, DatingAvailability open) =>
    _list(loc, [
      for (final c in open.countries)
        c.openRegionKeys == null
            ? datingCountryName(loc, c.code)
            : loc.dating_countryWithRegions(
              datingCountryName(loc, c.code),
              _list(loc, [
                for (final key in c.openRegionKeys!)
                  datingListName(loc, key) ?? key,
              ]),
            ),
    ]);

/// The open regions of [country] ("Greater Accra and Ashanti"), else its name.
String datingOpenRegionNames(
  AppLocalizations loc,
  DatingAvailability open,
  String country,
) {
  for (final c in open.countries) {
    if (c.code == country && c.openRegionKeys != null) {
      return _list(loc, [
        for (final key in c.openRegionKeys!) datingListName(loc, key) ?? key,
      ]);
    }
  }
  return datingCountryName(loc, country);
}
