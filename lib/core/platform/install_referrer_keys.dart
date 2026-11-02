/// Set once the Play Install Referrer has been read on this install (Spec 1
/// §3.8 RI, W4b); never cleared: sign-out keeps it, as an app setting
/// (PreferencesService.keptKeys). Its own file so the core prefs service
/// doesn't import the plugin (preflight F-11).
const kInstallReferrerReadKey = 'attune.install_referrer.read';

/// The Play Install Referrer's code, kept only to fill RI-1's code field
/// (final review #1): never the claimable invite slot, so nothing joins
/// without the person's tap. `{code, stored_at}`, good for a day; wiped at
/// sign-out and on quick exit (`spec1.install_referrer_code`).
const kInstallReferrerCodeKey = 'attune.install_referrer.code';
