// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'Ihre innovative App';

  @override
  String get commonContinue => 'Weiter';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonLogin => 'Anmelden';

  @override
  String get commonLogout => 'Abmelden';

  @override
  String get commonDone => 'Erledigt';

  @override
  String get commonRetry => 'Wiederholen';

  @override
  String get commonAccept => 'Akzeptieren';

  @override
  String get commonReject => 'Ablehnen';

  @override
  String get introGetStarted => 'Starten';

  @override
  String get actionsBlock => 'Benutzer blockieren';

  @override
  String get actionsReport => 'Benutzer melden';

  @override
  String get actionsSend => 'An Chat senden';

  @override
  String get actionsShare => 'Teilen';

  @override
  String get actionsCopy => 'Link kopieren';

  @override
  String get appInfoVersion => 'Version';

  @override
  String get appInfoReleased => 'Veröffentlicht';

  @override
  String get appInfoPackageName => 'Paketname';

  @override
  String get appInfoDeveloper => 'Entwicklername';

  @override
  String get appInfoSupportEmail => 'Support-E-Mail';

  @override
  String get appInfoTechnicalDetails => 'Technische Details';

  @override
  String get appInfoBundleID => 'Bundle-ID';

  @override
  String get appInfoBuildVersion => 'Build-Version';

  @override
  String get appInfoBuildNumber => 'Build-Nummer';

  @override
  String get appInfoReleaseDate => 'Veröffentlichungsdatum';

  @override
  String get appInfoAppSize => 'App-Größe';

  @override
  String appInfoOverview(String appName) {
    return '$appName ist eine moderne mobile Anwendung, die mit robuster Sicherheit und Funktionalität entwickelt wurde und darauf ausgelegt ist, eine außergewöhnliche Benutzererfahrung mit sauberer Architektur und Leistungsoptimierung zu bieten.';
  }

  @override
  String introTitle(String appName) {
    return 'Willkommen bei $appName';
  }

  @override
  String get introFeature1Title => 'Sehen Sie Ihren Fortschritt';

  @override
  String get introFeature1Description => 'Verfolgen Sie Ihre Entwicklungsmeilensteine mit detaillierten Analysen und Einblicken';

  @override
  String get introFeature2Title => 'Vorlagen erkunden';

  @override
  String get introFeature2Description => 'Entdecken Sie vorgefertigte Komponenten und Bildschirme für schnelle Entwicklung';

  @override
  String get introFeature3Title => 'Schnell starten';

  @override
  String get introFeature3Description => 'Starten Sie Ihr Projekt mit Null-Konfiguration und Best Practices';

  @override
  String get appleSignIn => 'Mit Apple anmelden';

  @override
  String get googleSignIn => 'Mit Google anmelden';

  @override
  String get appleRegister => 'Mit Apple registrieren';

  @override
  String get googleRegister => 'Mit Google registrieren';

  @override
  String get emailAndPassword => 'E-Mail und Passwort eingeben';

  @override
  String get signInTitle => 'Anmelden';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get legalConsentPart1 => 'Bitte lesen Sie die ';

  @override
  String get legalConsentPart2 => 'Allgemeinen Geschäftsbedingungen';

  @override
  String legalConsentPart3(String appName) {
    return ' und anderen rechtlichen Dokumente, die Ihre Nutzung von $appName regeln.';
  }

  @override
  String get emailTitle => 'E-Mail';

  @override
  String get passwordTitle => 'Passwort';

  @override
  String get loginEmailLabel => 'E-Mail-Adresse';

  @override
  String get loginEmailHint => 'Geben Sie Ihre E-Mail ein';

  @override
  String get loginPasswordLabel => 'Passwort';

  @override
  String get loginPasswordHint => 'Geben Sie Ihr Passwort ein';

  @override
  String get loginForgotPasswordPart1 => 'Haben Sie Ihr Passwort vergessen? ';

  @override
  String get loginForgotPasswordPart2 => 'Hier tippen';

  @override
  String get loginForgotPasswordPart3 => ' um Ihr Passwort zurückzusetzen?';

  @override
  String get commonConfirmPasswordLabel => 'Passwort bestätigen';

  @override
  String get commonConfirmPasswordHint => 'Bitte bestätigen Sie Ihr Passwort';

  @override
  String get commonPasswordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String get commonPasswordConfirmRequired => 'Bitte bestätigen Sie Ihr Passwort';

  @override
  String commonFieldIsValid(String field) {
    return '$field ist gültig';
  }

  @override
  String get commonPleaseWait => 'Bitte warten Sie, bis der aktuelle Vorgang abgeschlossen ist';

  @override
  String get commonUnexpectedError => 'Ein unerwarteter Fehler ist aufgetreten. Bitte versuchen Sie es erneut.';

  @override
  String get commonSomethingWentWrong => 'Etwas ist schief gelaufen. Bitte versuchen Sie es erneut.';

  @override
  String get commonEnterEmailAndRetry => 'Bitte geben Sie Ihre E-Mail-Adresse ein und versuchen Sie es erneut';

  @override
  String get commonLearnMore => 'Mehr erfahren';

  @override
  String get authSignUpVerificationSent => 'Bestätigungsmail gesendet! Bitte überprüfen Sie Ihren Posteingang.';

  @override
  String authSignUpFailed(String error) {
    return 'Registrierung fehlgeschlagen: $error';
  }

  @override
  String get authForgotPasswordTitle => 'Passwort vergessen?';

  @override
  String get authForgotPasswordSubtitle => 'Geben Sie Ihre E-Mail-Adresse ein und wir senden Ihnen einen Link zum Zurücksetzen Ihres Passworts.';

  @override
  String get authSendResetLink => 'Zurücksetzen-Link senden';

  @override
  String get authBackToSignIn => 'Zurück zur Anmeldung';

  @override
  String get authUsernameScreenTitle => 'Benutzernamen wählen';

  @override
  String get authUsernameScreenSubtitle => 'So sehen dich andere. Du kannst es später ändern.';

  @override
  String get authUsernameLabel => 'Benutzername';

  @override
  String get authUsernameHint => 'Geben Sie einen Benutzernamen ein';

  @override
  String authUsernameMinLength(int min) {
    return 'Benutzername muss mindestens $min Zeichen lang sein';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'Benutzername darf höchstens $max Zeichen lang sein';
  }

  @override
  String get authUsernameFormatError => 'Nur Buchstaben, Zahlen und Unterstriche sind erlaubt';

  @override
  String get authUsernameTaken => 'Dieser Benutzername ist bereits vergeben';

  @override
  String get authUsernameCheckError => 'Verfügbarkeit konnte nicht überprüft werden. Bitte versuchen Sie es erneut.';

  @override
  String get authUsernameSaveError => 'Konnte Ihren Benutzernamen nicht speichern. Bitte versuchen Sie es erneut.';

  @override
  String get authUsernameSavedSuccess => 'Benutzername erfolgreich gespeichert!';

  @override
  String get authUpdatePasswordTitle => 'Neues Passwort erstellen';

  @override
  String get authUpdatePasswordButton => 'Passwort aktualisieren';

  @override
  String get authUpdatePasswordSuccess => 'Passwort erfolgreich aktualisiert. Bitte melden Sie sich erneut an.';

  @override
  String get authPasswordResetSentTitle => 'Überprüfen Sie Ihre E-Mail';

  @override
  String get authPasswordResetSentBody => 'Wir haben einen Link zum Zurücksetzen des Passworts gesendet an';

  @override
  String get authPasswordResetSentNote => 'Tippen Sie auf den Link in der E-Mail, um ein neues Passwort festzulegen. Der Link verfällt in 1 Stunde.';

  @override
  String get authGuestHello => 'Hallo!';

  @override
  String authGuestOverview(String appName) {
    return 'Sie sehen sich $appName als Gast an. Melden Sie sich mit Ihrer Telefonnummer an, um Ihren gemeinsamen Bereich mit Ihrem Partner zu beginnen – es dauert nur wenige Sekunden.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Willkommen bei\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Willkommen auf der Plattform, die wir für Sie gebaut haben. Genießen Sie und haben Sie Spaß – das Beste wartet auf Sie.';

  @override
  String get authReadLegalities => 'Rechtliche Bestimmungen lesen';

  @override
  String get authPasswordRequired => 'Bitte geben Sie Ihr Passwort ein';

  @override
  String get authCreatingAccount => 'Konto wird erstellt...';

  @override
  String get authAccountCreatedSuccess => 'Konto erfolgreich erstellt!';

  @override
  String get authCheckEmailToConfirm => 'Bitte überprüfen Sie Ihre E-Mail, um Ihr Konto zu bestätigen';

  @override
  String get authSigningInWithGoogle => 'Mit Google anmelden...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Google-Anmeldung fehlgeschlagen: $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Mit Apple authentifizieren...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Apple-Anmeldung fehlgeschlagen: $error';
  }

  @override
  String get authSendingResetEmail => 'Zurücksetzen-E-Mail wird gesendet...';

  @override
  String get authResetEmailSent => 'Zurücksetzen-E-Mail gesendet. Überprüfen Sie Ihren Posteingang.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Passwort zurücksetzen fehlgeschlagen: $error';
  }

  @override
  String get authVerifyEmailTitle => 'Überprüfen Sie Ihre E-Mail';

  @override
  String get authVerifyEmailSubtitle => 'Wir haben einen Bestätigungslink gesendet an';

  @override
  String get authVerifyEmailNote => 'Tippen Sie auf den Link in der E-Mail, um Ihr Konto zu bestätigen und fortzufahren.';

  @override
  String get authConfirmationResent => 'Bestätigungsmail erneut gesendet. Überprüfen Sie Ihren Posteingang.';

  @override
  String get authResendFailed => 'Fehler beim erneuten Senden der E-Mail. Bitte versuchen Sie es erneut.';

  @override
  String get authResendEmailButton => 'Bestätigungsmail erneut senden';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'E-Mail erneut senden (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Währung wählen';

  @override
  String get currencySelectorNoSelected => 'Keine Währung ausgewählt';

  @override
  String get currencySelectorTitle => 'Währung wählen';

  @override
  String get currencySelectorSearchHint => 'Nach Währung, Code oder Flagge suchen...';

  @override
  String get currencySelectorNoResults => 'Keine Währungen gefunden';

  @override
  String get discoverScreenTitle => 'Entdecken';

  @override
  String get discoverSearchHint => 'Suchen...';

  @override
  String get discoverAllShopsRegion => 'Alle Shops in Ihrer Region';

  @override
  String get discoverAllFreelancers => 'Alle Freiberufler in Ihrer Nähe';

  @override
  String get discoverMarketplaceTitle => 'Marktplatz';

  @override
  String get discoverMarketplaceSubtitle => 'Kaufen Sie Schönheitsprodukte mit Nachnahme';

  @override
  String get discoverBrowseProducts => 'Produkte durchsuchen';

  @override
  String get discoverMyOrders => 'Meine Bestellungen';

  @override
  String get discoverCartTooltip => 'Einkaufskorb';

  @override
  String get homeScheduleTabLabel => 'Zeitplan';

  @override
  String get homeDashboardTabLabel => 'Dashboard';

  @override
  String get homeMapTabLabel => 'Karte';

  @override
  String get validationRequired => 'Dieses Feld ist erforderlich';

  @override
  String get validationEmailInvalid => 'Bitte geben Sie eine gültige E-Mail-Adresse ein';

  @override
  String validationPasswordLength(int minLength) {
    return 'Das Passwort muss mindestens $minLength Zeichen lang sein';
  }

  @override
  String get validationPasswordUppercase => 'Das Passwort muss mindestens einen Großbuchstaben enthalten';

  @override
  String get loggingInIndicatorText => 'Anmeldung läuft...';

  @override
  String get loginSuccessful => 'Anmeldung erfolgreich!\nWillkommen zurück';

  @override
  String get errorLoginFailed => 'Anmeldung fehlgeschlagen. Bitte überprüfen Sie Ihre Anmeldedaten';

  @override
  String get errorNetwork => 'Netzwerkfehler. Bitte überprüfen Sie Ihre Verbindung';

  @override
  String get homeTitle => 'Startseite';

  @override
  String get profileTitle => 'Profil';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Name';

  @override
  String get editProfileNameFieldLabel => 'Vollständiger Name';

  @override
  String get editProfileUserFieldNameTitle => 'Benutzername';

  @override
  String get editProfileUsernameFieldLabel => '@benutzername';

  @override
  String get editProfileBioFieldTitle => 'Biografie';

  @override
  String get editProfileBioFieldLabel => 'Erzählen Sie uns von sich';

  @override
  String get editProfileScreenTitle => 'Profil bearbeiten';

  @override
  String get editProfileSettingTitle => 'Kontoeinstellungen';

  @override
  String get editProfileSettingSubtitle => 'Verwalten Sie Ihr Konto';

  @override
  String get editProfileScreenEditShopTitle => 'Shop bearbeiten';

  @override
  String get editProfileScreenEditShopSubtitle => 'Ändern Sie Ihre Shop-Informationen';

  @override
  String get languageScreenSubtitle => 'Wählen Sie Ihre bevorzugte Sprache für die App-Oberfläche. Dies wirkt sich nicht auf die Geräteeinstellungen aus.';

  @override
  String get languageScreeUseDeviceLang => 'Gerätsprache verwenden.';

  @override
  String get languageScreeUseDeviceLangNote => 'Dies wird auf Ihre Gerätesystemsprache zurückgesetzt.';

  @override
  String get settingsScreenTitle => 'Einstellungen';

  @override
  String get accountSectionTitle => 'Konto';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Profil';

  @override
  String get profileItemSubtitle => 'Verwalten Sie Ihre persönlichen Daten';

  @override
  String get locationItemTitle => 'Standort ändern';

  @override
  String get locationItemSubtitle => 'Ändern Sie Ihre aktuelle Stadt';

  @override
  String get saveItemTitle => 'Gespeicherte Inhalte';

  @override
  String get saveItemSubtitle => 'Inhalte, die Sie gespeichert haben';

  @override
  String get notificationsItemTitle => 'Benachrichtigungen';

  @override
  String get notificationsItemSubtitle => 'Push- und E-Mail-Benachrichtigungen verwalten';

  @override
  String get blockedItemTitle => 'Blockierte Konten';

  @override
  String get blockedItemSubtitle => 'Konten, die Sie blockiert haben';

  @override
  String get mutedItemTitle => 'Stummgeschaltete Konten';

  @override
  String get mutedItemSubtitle => 'Anonyme Opinions-Konten, die Sie stummgeschaltet haben';

  @override
  String get qrCodeItemTitle => 'QR-Code teilen';

  @override
  String get qrCodeItemSubtitle => 'Teilen Sie Ihren Konto-QR-Code';

  @override
  String get shareProfileItemTitle => 'Profil teilen';

  @override
  String get shareProfileItemSubtitle => 'Teilen Sie Ihr Profil mit Freunden';

  @override
  String get appSettingsSectionTitle => 'App-Einstellungen';

  @override
  String get appSettingsSectionSubtitle => 'Passen Sie Ihre Erfahrung an';

  @override
  String get themeItemTitle => 'Design';

  @override
  String get themeItemSubtitle => 'Hell, Dunkel oder System';

  @override
  String get languageItemTitle => 'Sprache';

  @override
  String get languageItemSubtitle => 'App-Sprache ändern';

  @override
  String get biometricItemTitle => 'Biometrische Anmeldung';

  @override
  String get biometricItemSubtitle => 'Verwenden Sie Face ID oder Touch ID';

  @override
  String get supportSectionTitle => 'Support';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'Benutzerhandbuch';

  @override
  String get guideItemSubtitle => 'Dokumentation und Tutorials';

  @override
  String get helpItemTitle => 'Support kontaktieren';

  @override
  String get helpItemSubtitle => 'Hilfe zur App erhalten';

  @override
  String get feedbackItemTitle => 'Feedback senden';

  @override
  String get feedbackItemSubtitle => 'Teilen Sie Ihre Gedanken mit';

  @override
  String get rateItemTitle => 'App bewerten';

  @override
  String get rateItemSubtitle => 'Eine Bewertung hinterlassen';

  @override
  String appInfoItemTitle(String appName) {
    return 'Über $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Technische Informationen';

  @override
  String get legalSectionTitle => 'Rechtliches';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Bedingungen, Datenschutz & Richtlinien';

  @override
  String get termsItemSubtitle => 'Lesen Sie unsere Bedingungen';

  @override
  String get licensesItemTitle => 'Open-Source-Lizenzen';

  @override
  String get licensesItemSubtitle => 'Drittanbieter-Bibliotheken und Lizenzen';

  @override
  String get accountActionsSectionTitle => 'Kontoaktionen';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Deaktivieren';

  @override
  String get deactivateItemSubtitle => 'Deaktivieren Sie Ihr Konto';

  @override
  String get deleteItemTitle => 'Konto löschen';

  @override
  String get deleteItemSubtitle => 'Ihr Konto dauerhaft entfernen';

  @override
  String get logoutItemTitle => 'Abmelden';

  @override
  String get logoutItemSubtitle => 'Von Ihrem Konto abmelden';

  @override
  String get loadingDefaultMessage => 'Laden...';

  @override
  String get emptyStateNoDataTitle => 'Noch nichts hier';

  @override
  String get emptyStateNoDataSubtitle => 'Sobald es etwas zu zeigen gibt, erscheint es hier.';

  @override
  String get emptyStateNoResultsTitle => 'Keine Treffer';

  @override
  String get emptyStateNoResultsSubtitle => 'Versuchen Sie ein anderes Wort oder einen anderen Filter.';

  @override
  String get emptyStateNoInternetTitle => 'Sie sind offline';

  @override
  String get emptyStateNoInternetSubtitle => 'Überprüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get emptyStateNoMessagesTitle => 'Noch keine Nachrichten';

  @override
  String get emptyStateNoMessagesSubtitle => 'Sagen Sie Hallo, um Ihr Gespräch zu beginnen.';

  @override
  String get emptyStateRefresh => 'Aktualisieren';

  @override
  String get emptyStateClearFilters => 'Filter löschen';

  @override
  String get emptyStateRetry => 'Erneut versuchen';

  @override
  String get emptyStateStartChat => 'Hallo sagen';

  @override
  String get errorNetworkTitle => 'Verbindungsfehler';

  @override
  String get errorNetworkSubtitle => 'Verbindung zum Server nicht möglich. Überprüfen Sie Ihre Internetverbindung.';

  @override
  String get errorServerTitle => 'Serverfehler';

  @override
  String get errorServerSubtitle => 'Auf unserer Seite ist etwas schiefgelaufen. Bitte versuchen Sie es später erneut.';

  @override
  String get errorClientTitle => 'Anfragefehler';

  @override
  String get errorClientSubtitle => 'Es gab ein Problem mit Ihrer Anfrage. Bitte überprüfen und versuchen Sie es erneut.';

  @override
  String get errorParsingTitle => 'Datenfehler';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'Die $dataType konnte nicht verarbeitet werden. Dies könnte ein vorübergehendes Problem sein.';
  }

  @override
  String get errorPermissionTitle => 'Zugriff verweigert';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'Sie haben keine Berechtigung, auf diese(n) $dataType zuzugreifen.';
  }

  @override
  String get errorGenericTitle => 'Etwas ist schiefgelaufen';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'Ein unerwarteter Fehler ist beim Laden von $dataType aufgetreten. Bitte versuchen Sie es erneut.';
  }

  @override
  String get errorRetry => 'Erneut versuchen';

  @override
  String get errorCheckSettings => 'Einstellungen prüfen';

  @override
  String get errorReport => 'Problem melden';

  @override
  String get errorGoBack => 'Zurück';

  @override
  String get errorRefresh => 'Aktualisieren';

  @override
  String get errorRequestAccess => 'Zugriff anfordern';

  @override
  String get errorContactSupport => 'Support kontaktieren';

  @override
  String get eulaTitle => 'Endbenutzer-Lizenzvereinbarung';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'Diese Endbenutzer-Lizenzvereinbarung (\"EULA\") ist eine rechtliche Vereinbarung zwischen Ihnen und der Bars Opus, Ltd. für $appName.\n\nDurch die Installation, den Zugriff oder die Verwendung von $appName erklären Sie sich mit den Bedingungen dieser EULA einverstanden. $appName wird Ihnen lizenziert, nicht verkauft, und darf nur unter den Bedingungen dieser Lizenz verwendet werden. Die Bars Opus, Ltd. behält sich alle nicht ausdrücklich in dieser EULA gewährten Rechte vor.\n\nSie dürfen $appName nicht modifizieren, reverse-engineern, dekompilieren oder disassemblieren. Diese Lizenz ist gültig, bis sie von Ihnen oder der Bars Opus, Ltd. gekündigt wird. Ihre Rechte unter dieser Lizenz erlöschen automatisch ohne Vorankündigung, wenn Sie gegen eine(n) der Bedingungen verstoßen.\n\nAlle geistigen Eigentumsrechte an $appName gehören der Bars Opus, Ltd. Diese EULA unterliegt den Gesetzen von England und Wales.\n\nBei Fragen zu dieser EULA wenden Sie sich bitte an: $supportEmail.';
  }

  @override
  String get eulaFooter => 'Durch Ihre Zustimmung bestätigen Sie, dass Sie diese Endbenutzer-Lizenzvereinbarung gelesen und verstanden haben.';

  @override
  String get privacyPolicyTitle => 'Datenschutzerklärung';

  @override
  String privacyPolicyContent(String appName) {
    return 'Diese Datenschutzerklärung erläutert, wie die Bars Opus, Ltd. (\"wir\", \"unser\") Ihre Informationen erhebt, verwendet und schützt, wenn Sie $appName verwenden.\n\nWir erheben Informationen, die Sie direkt bereitstellen, z.B. wenn Sie ein Konto erstellen, Ihr Profil vervollständigen oder den Support kontaktieren. Wir erheben automatisch bestimmte Informationen über Ihr Gerät und wie Sie $appName verwenden. Wir verwenden Cookies und ähnliche Tracking-Technologien, um Aktivitäten zu verfolgen und bestimmte Informationen zu speichern.\n\nWir verwenden die erhobenen Informationen, um $appName bereitzustellen, zu warten und zu verbessern. Wir können Ihre Informationen mit Drittanbieter-Dienstleistern teilen, die Dienstleistungen in unserem Namen erbringen. Wir können Ihre Informationen offenlegen, wenn dies gesetzlich vorgeschrieben ist oder um unsere Rechte und Sicherheit zu schützen.\n\nSie haben das Recht, auf Ihre persönlichen Informationen zuzugreifen, sie zu korrigieren oder zu löschen. Wir implementieren geeignete technische und organisatorische Maßnahmen, um Ihre Informationen zu schützen. Wir können diese Datenschutzerklärung von Zeit zu Zeit aktualisieren. Wir werden Sie über Änderungen informieren.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return 'Datenschutzerklärung von $appName - Zuletzt aktualisiert: $currentDateString';
  }

  @override
  String get termsTitle => 'Nutzungsbedingungen';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'Diese Nutzungsbedingungen (\"Bedingungen\") regeln Ihren Zugriff auf und die Nutzung von $appName. Durch den Zugriff auf oder die Nutzung von $appName erklären Sie sich mit diesen Bedingungen einverstanden.\n\nSie müssen mindestens 13 Jahre alt sein, um $appName zu verwenden. Sie sind für die Sicherung Ihrer Kontozugangsdaten und für alle Aktivitäten unter Ihrem Konto verantwortlich. Sie dürfen $appName nicht für illegale oder unbefugte Zwecke verwenden.\n\nWir behalten uns das Recht vor, $appName jederzeit zu ändern, auszusetzen oder einzustellen. Alle in $appName enthaltenen Inhalte sind Eigentum der Bars Opus, Ltd. oder ihrer Lizenzgeber.\n\nWir können Ihren Zugriff auf $appName sofort beenden oder aussetzen, wenn Sie gegen diese Bedingungen verstoßen. Diese Bedingungen unterliegen den Gesetzen von England und Wales.\n\nBei Fragen zu diesen Bedingungen wenden Sie sich bitte an $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Datenfreigabe-Vereinbarung';

  @override
  String dataSharingContent(String appName) {
    return 'Diese Datenfreigabe-Vereinbarung beschreibt, wie Ihre Informationen geteilt werden können, wenn Sie die sozialen Funktionen von $appName verwenden.\n\nWenn Sie sich mit Freunden auf $appName verbinden, können bestimmte Aktivitätsdaten für sie sichtbar sein. Gemeinsam genutzte Aktivitätsdaten können Trainingsdauer, verbrannte Kalorien, Übungsminuten und Erfolgsabzeichen umfassen. Ihre Profilinformationen (Anzeigename und Profilbild) sind für Freunde sichtbar, mit denen Sie sich verbinden.\n\nIhre E-Mail-Adresse und Kontaktinformationen bleiben privat und werden niemals mit anderen Nutzern geteilt. Sie kontrollieren, welche Daten über Ihre $appName-Datenschutzeinstellungen geteilt werden. Sie können Freigabeberechtigungen jederzeit in den App-Einstellungen widerrufen.\n\nMit Freunden geteilte Daten werden während der Übertragung und Speicherung verschlüsselt. Wir behalten gemeinsam genutzte Daten nur so lange, wie es zur Bereitstellung der Freigabefunktionalität erforderlich ist. Drittanbieter-Integrationen können eigene Datenfreigabe-Praktiken haben, die wir Ihnen zu überprüfen empfehlen.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'Die Datenfreigabe in $appName hilft dabei, eine unterstützende Community aufzubauen, während Ihre Privatsphäreneinstellungen respektiert werden.';
  }

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardSubtitle => 'Verwalten Sie Ihre Shop-Aktivitäten effizient';

  @override
  String get dashboardSectionTitle => 'Dashboard';

  @override
  String get dashboardSectionSubtitle => 'Übersicht über die Leistung und Schlüsselmetriken Ihres Shops';

  @override
  String get dashboardPayoutTitle => 'Auszahlung anfordern';

  @override
  String get dashboardPayoutContent => 'Shop-Besitzer können wöchentliche Auszahlungen anfordern. Navigieren Sie zum Abschnitt Einnahmen, überprüfen Sie Ihr Guthaben und senden Sie eine Auszahlungsanfrage. Gelder werden in der Regel innerhalb von 3-5 Werktagen bearbeitet.';

  @override
  String get dashboardAnalyticsTitle => 'Analytics-Dashboard';

  @override
  String get dashboardAnalyticsContent => 'Verfolgen Sie die Leistung Ihres Shops mit Echtzeit-Analysen. Überwachen Sie Verkaufstrends, Kundenengagement und Lagerbestände durch interaktive Diagramme und Berichte.';

  @override
  String get dashboardScreenshotTitle => 'Dashboard-Übersicht';

  @override
  String get dashboardScreenshotContent => 'Das Haupt-Dashboard bietet einen umfassenden Überblick über die Schlüsselmetriken Ihres Shops, aktuelle Aktivitäten und schnellen Zugriff auf wesentliche Funktionen.';

  @override
  String get categoryFeatures => 'Funktionen';

  @override
  String get categoryDashboard => 'Dashboard';

  @override
  String get faqDashboard1Question => 'Wann kann ich eine Auszahlung anfordern?';

  @override
  String get faqDashboard1Answer => 'Sie können Ihre Auszahlung einmal pro Woche, jeden Samstag, anfordern. Der wöchentliche Stichtag ist Freitag um 23:59 Uhr. Auszahlungen werden innerhalb von 3-5 Werktagen bearbeitet.';

  @override
  String get faqDashboard2Question => 'Wo kann ich meine Auszahlung anfordern?';

  @override
  String get faqDashboard2Answer => 'Navigieren Sie zu Ihrem Dashboard und klicken Sie auf den Abschnitt \'Einnahmen\'. Dort sehen Sie Ihr aktuelles Guthaben und eine Schaltfläche \'Auszahlung anfordern\'. Folgen Sie den Anweisungen, um Ihre Anfrage abzuschließen.';

  @override
  String get profileScreenCantChatWithYourself => 'Du kannst nicht mit dir selbst chatten';

  @override
  String get profileScreenStartingConversation => 'Unterhaltung wird gestartet...';

  @override
  String get profileScreenNoActiveSession => 'Keine aktive Sitzung — bitte melden Sie sich erneut an.';

  @override
  String get profileScreenSignInToChatMessage => 'Sie müssen sich anmelden, um eine Nachricht zu senden';

  @override
  String get profileScreenFollowFeatureComingSoon => 'Follow-Funktion kommt bald';

  @override
  String get profileScreenEnterBioPlaceholder => 'Geben Sie eine Biografie ein, damit die Leute Sie kennen';

  @override
  String get profileScreenNoBioYet => 'Noch keine Biografie';

  @override
  String get profileScreenErrorLoadingProfileBody => 'Profil konnte nicht geladen werden. Überprüfen Sie Ihre Internetverbindung und versuchen Sie es erneut.';

  @override
  String get profileScreenLoadingNotifications => 'Wird geladen...';

  @override
  String get profileHeaderBookingsStatLabel => 'Buchungen';

  @override
  String get profileHeaderOrdersStatLabel => 'Bestellungen';

  @override
  String get profileHeaderEditProfileButton => 'Profil bearbeiten';

  @override
  String get profileHeaderMessageButton => 'Nachricht';

  @override
  String get editableProfileAvatarTakePhoto => 'Ein Foto machen';

  @override
  String get editableProfileAvatarChooseGallery => 'Aus der Galerie auswählen';

  @override
  String get editProfileScreenAccountTypeLabel => 'Kontotyp';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Wählen Sie, wie Sie diese App nutzen möchten. Dies bestimmt, welche Funktionen für Sie verfügbar sind.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Kontotyp wird aktualisiert...';

  @override
  String get editProfileScreenPleaseLogIn => 'Bitte melden Sie sich an';

  @override
  String get editProfileScreenNameLabel => 'Name';

  @override
  String get editProfileScreenNameHint => 'Geben Sie Ihren Namen ein';

  @override
  String get editProfileScreenUsernameLabel => 'Benutzername';

  @override
  String get editProfileScreenUsernameHint => 'Benutzername eingeben';

  @override
  String get editProfileScreenBioLabel => 'Biografie';

  @override
  String get editProfileScreenBioHint => 'Erzählen Sie etwas über sich selbst';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Arbeitsprofil bearbeiten';

  @override
  String get profileTabsAppointments => 'Termine';

  @override
  String get profileTabsBuys => 'Käufe';

  @override
  String get profileTabsSaves => 'Speichert';

  @override
  String get searchScreenSearchHint => 'Nach Geschäften, Profis, Produkten suchen...';

  @override
  String get searchScreenNoResultsFound => 'Keine Ergebnisse gefunden';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'Keine $category gefunden';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Gesucht nach: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String get searchAppBarSearchHint => 'Suchen...';

  @override
  String get searchSuggestionsHint => 'Suchen Sie nach Geschäften, Profis für Heimservice oder Haarprodukten zum Kaufen';

  @override
  String get searchSuggestionsRecentSearches => 'Letzte Suchen';

  @override
  String get searchSuggestionsClearAll => 'Alles löschen';

  @override
  String get searchEmptyStateNoResults => 'Keine Ergebnisse gefunden';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'Wir konnten nichts für \"$query\" finden';
  }

  @override
  String get searchEmptyStateTryThese => 'Versuchen Sie stattdessen diese:';

  @override
  String get searchResultsShopsHeader => 'Geschäfte';

  @override
  String get searchResultsSeeAll => 'Alle anzeigen';

  @override
  String searchResultsTitle(String category) {
    return '$category Ergebnisse';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Suche nach \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Versuchen Sie andere Schlüsselwörter oder entfernen Sie Filter';

  @override
  String get searchResultsSomethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String nearYouShopsTitle(int km) {
    return 'In Ihrer Nähe\ninnerhalb von ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Geschäfte in einem Umkreis von $km km von Ihrem aktuellen Standort, sortiert von nächster zu ferner Entfernung. Stellen Sie Ihren Standort einfach einmal ein, und wir zeigen Ihnen, was in der Nähe ist – ob zu Hause, bei der Arbeit oder während Sie eine neue Gegend erkunden. Praktisch für kurzfristige Buchungen oder wenn Sie gerne zu Fuß gehen.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'Keine Geschäfte in der Nähe gefunden';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'Keine $luxury Geschäfte in der Nähe gefunden';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'Geschäfte in $location würden hier angezeigt, sobald sie verfügbar sind';
  }

  @override
  String get premiumShopsScreenTitle => 'Premium Geschäfte';

  @override
  String get premiumShopsEmpty => 'Keine Premium Geschäfte gefunden';

  @override
  String get premiumShopsHorizontalTitle => 'Premium-Geschäfte\nfür Premium-Looks';

  @override
  String get premiumShopsHorizontalBody => 'Handverlesene High-End-Salons und Spas mit Luxuserfahrungen. Diese Geschäfte werden basierend auf ihren Dienstleistungen, Preisen und Kundenrezensionen als Luxus oder Ultra-Luxus klassifiziert. Perfekt für die extra Prise Eleganz.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'Keine Premium Geschäfte verfügbar';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Keine $luxury Premium Geschäfte verfügbar';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'Geschäfte würden hier angezeigt, sobald sie verfügbar sind';

  @override
  String get topRatedShopsHorizontalTitle => 'Top bewertet';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Top bewertet \nin $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Geschäfte mit den höchsten Kundenbewertungen (4,5+ Sterne) und einer großen Anzahl von Rezensionen. Das sind die Favoriten unserer Community—durchgehend für Qualität, Service und Professionalität gelobt. Ein großartiger Ort zum Starten, wenn Sie zuverlässige, von der Crowd bestätigte Optionen mögen.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'Keine Top bewerteten Geschäfte verfügbar';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Keine $luxury Premium Geschäfte verfügbar';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'Geschäfte würden hier angezeigt, sobald sie verfügbar sind';

  @override
  String get topRatedShopsScreenTitle => 'Top bewertete Geschäfte';

  @override
  String get topRatedShopsEmpty => 'Keine Top bewerteten Geschäfte gefunden';

  @override
  String get nearYouFreelancersScreenTitle => 'Freiberufler in Ihrer Nähe';

  @override
  String get nearYouFreelancersEmpty => 'Keine Freiberufler in der Nähe gefunden';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Versuchen Sie, Ihren Suchbereich zu erweitern oder den Standort zu ändern';

  @override
  String get topRatedFreelancersScreenTitle => 'Top bewertete Freiberufler';

  @override
  String get topRatedFreelancersEmpty => 'Keine Top bewerteten Freiberufler gefunden';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Versuchen Sie, Ihren Suchbereich anzupassen';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Top bewertet \nin $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Handverlesene hochwertige Fachleute mit Luxuserfahrungen. Diese Freiberufler werden basierend auf ihrer Arbeitsqualität, ihren Preisen und Kundenrezensionen als Top bewertet klassifiziert. Perfekt für die Extra-Prise Exzellenz.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freiberufler in Ihrer Nähe in $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Fachleute in Ihrer Nähe. Diese Freiberufler sind für schnelle Buchungen verfügbar und bieten bequemen, lokalen Service. Perfekt, wenn Sie Zuverlässigkeit und Nähe suchen.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'Keine Top bewerteten Freiberufler verfügbar';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'Freiberufler würden hier angezeigt, sobald sie verfügbar sind';

  @override
  String get shopNoLocationSetTitle => 'Standort festlegen zum Entdecken';

  @override
  String get shopNoLocationSetContent => 'Legen Sie Ihren Standort fest, um Premium- und top bewertete Geschäfte in Ihrer Nähe zu entdecken.';

  @override
  String get providerTypeShops => 'Geschäfte';

  @override
  String get providerTypeFreelancers => 'Freiberufler';

  @override
  String get providerTypeBuy => 'Kaufen';

  @override
  String get luxuryLevelChipsAll => 'Alle';

  @override
  String get searchRadiusSliderTitle => 'Erkundungsradius';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Ergebnisse anzeigen innerhalb von ${km}km von Ihrem Standort';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'Passwort darf maximal $max Zeichen lang sein';
  }

  @override
  String get validationPasswordRepeatingChars => 'Passwort enthält zu viele wiederholte Zeichen';

  @override
  String get validationPasswordSequential => 'Passwort enthält aufeinanderfolgende Zeichen';

  @override
  String validationPhoneDigits(int digits) {
    return 'Telefonnummer muss $digits Ziffern haben';
  }

  @override
  String get validationPhoneUK => 'Ungültige britische Telefonnummer';

  @override
  String validationUrlScheme(String schemes) {
    return 'URL muss mit $schemes beginnen';
  }

  @override
  String get validationUrlDomain => 'Ungültiger Domänenname';

  @override
  String get validationUrlPublicAddress => 'URL muss auf eine öffentliche Adresse verweisen';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field darf maximal $max Zeichen lang sein';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field darf keine aufeinanderfolgenden Bindestriche oder Leerzeichen enthalten';
  }

  @override
  String get validationCreditCardFormat => 'Bitte geben Sie eine gültige Kreditkartennummer ein';

  @override
  String get validationCreditCardInvalid => 'Ungültige Kreditkartennummer';

  @override
  String get validationDatePastNotAllowed => 'Datum darf nicht in der Vergangenheit liegen';

  @override
  String get validationPostalCodeZip => 'Bitte geben Sie eine gültige Postleitzahl ein (z.B. 12345 oder 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Bitte geben Sie eine gültige kanadische Postleitzahl ein (z.B. A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Bitte geben Sie eine gültige Postleitzahl ein';

  @override
  String get validationSSNFormat => 'Bitte geben Sie eine gültige Sozialversicherungsnummer ein (z.B. 123-45-6789)';

  @override
  String get validationSSNInvalid => 'Ungültige Sozialversicherungsnummer';

  @override
  String get validationEmailTooLong => 'E-Mail ist zu lang (max. 254 Zeichen)';

  @override
  String get validationEmailLocalPartTooLong => 'Lokaler Teil der E-Mail ist zu lang';

  @override
  String get categoriesAll => 'Alle';

  @override
  String get categoriesSalon => 'Salons';

  @override
  String get categoriesBarbershop => 'Friseursalons';

  @override
  String get categoriesSpa => 'Spas';

  @override
  String get categoriesNailSalon => 'Nagelstudios';

  @override
  String get categoriesLashStudio => 'Wimpernstudios';

  @override
  String get categoriesWaxing => 'Haarentfernung';

  @override
  String get categoriesMassage => 'Massage';

  @override
  String get categoriesMakeup => 'Make-up';

  @override
  String get categoriesSkincare => 'Hautpflege';

  @override
  String get luxuryLevelModerate => 'Moderat';

  @override
  String get luxuryLevelLuxury => 'Luxus';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Luxus';

  @override
  String get flow_continue => 'Continue';

  @override
  String get flow_close => 'Close';

  @override
  String get flow_back => 'Back';

  @override
  String flow_listTwo(String first, String second) {
    return '$first and $second';
  }

  @override
  String get flow_countryUk => 'the UK';

  @override
  String get flow_countryUs => 'the US';

  @override
  String get flow_welcomeTitle => 'Love, dating and you, in one calm place.';

  @override
  String get flow_pathRelationshipTitle => 'In a relationship';

  @override
  String get flow_pathRelationshipLine => 'A private space for you and your partner.';

  @override
  String get flow_pathDatingTitle => 'Single and open to dating';

  @override
  String get flow_pathDatingLine => 'A few introductions a day. Only when it\'s mutual.';

  @override
  String get flow_pathJustMeTitle => 'Just for me';

  @override
  String get flow_pathJustMeLine => 'Your journal, quizzes and Healing.';

  @override
  String flow_welcomeCardSemantics(String title, String line) {
    return '$title. $line Opens a preview.';
  }

  @override
  String get flow_welcomeGetStarted => 'Get started';

  @override
  String get flow_welcomeHaveAccount => 'I already have an account';

  @override
  String get flow_welcomeHaveInvite => 'I have an invite';

  @override
  String get flow_welcomeReadOpinions => 'Read Opinions first';

  @override
  String get flow_welcomeFooter => 'Attune is for adults (18+) and uses your phone number to sign in.';

  @override
  String get flow_linkTerms => 'Terms';

  @override
  String get flow_linkPrivacy => 'Privacy';

  @override
  String get flow_previewRelationshipTitle => 'A space for the two of you';

  @override
  String get flow_previewRelationshipLine1 => 'Chat, plans and memories only you two can see.';

  @override
  String get flow_previewRelationshipLine2 => 'Your journal stays yours. Your partner never sees it.';

  @override
  String get flow_previewRelationshipLine3 => 'Invite your partner with a link or a code.';

  @override
  String get flow_previewDatingTitle => 'Introductions, not swiping';

  @override
  String get flow_previewDatingLine1 => 'Up to 3 introductions a day, chosen for what you both want.';

  @override
  String get flow_previewDatingLine2 => 'A match only when you both say yes.';

  @override
  String get flow_previewDatingLine3 => 'A live video selfie checks your age before your first introduction.';

  @override
  String flow_previewDatingCountries(String countries) {
    return 'Dating is open in $countries. More countries later.';
  }

  @override
  String get flow_previewJustMeTitle => 'A private space for you';

  @override
  String get flow_previewJustMeLine1 => 'A journal only you can read.';

  @override
  String get flow_previewJustMeLine2 => 'Short quizzes about how you connect.';

  @override
  String get flow_previewJustMeLine3 => 'Healing, after a breakup or a loss.';

  @override
  String get flow_previewJustMeLine4 => 'Single, partnered or in between.';

  @override
  String get flow_guestAgeTitle => 'What year were you born?';

  @override
  String get flow_guestAgeHint => 'We ask everyone. It stays on this phone.';

  @override
  String get flow_guestAgeLabel => 'Year';

  @override
  String get flow_guestAgeSemantics => 'Year you were born, 4 digits';

  @override
  String get flow_yearFourDigits => 'Enter the year with 4 digits, like 1994.';

  @override
  String get flow_yearFuture => 'That year is in the future.';

  @override
  String get flow_yearCheck => 'Check the year.';

  @override
  String get flow_ageStopTitle => 'Attune is for adults';

  @override
  String get flow_ageStopBody => 'You need to be 18 or older to use Attune. We haven\'t saved anything you entered.';

  @override
  String get flow_ageStopServerLead => 'We couldn\'t create your account.';

  @override
  String get flow_ageStopYouthLink => 'Support for young people';

  @override
  String get flow_inviteTitle => 'You\'ve been invited to Attune';

  @override
  String get flow_inviteBody => 'Someone invited you to a private space on Attune. Create your account to see who it is and to join.';

  @override
  String get flow_inviteCreate => 'Create an account';

  @override
  String get flow_inviteCodeTitle => 'Enter your invite code';

  @override
  String get flow_inviteCodeLabel => 'Invite code';

  @override
  String get flow_inviteCodeError => 'Codes have 6 letters and numbers. Check it with the person who sent it.';

  @override
  String get flow_tryAgain => 'Try again';

  @override
  String get flow_nameTitle => 'What should we call you?';

  @override
  String get flow_nameHint => 'This is the name your partner sees. Opinions never shows it.';

  @override
  String get flow_nameLabel => 'Your name';

  @override
  String get flow_nameNeedsLetter => 'Add a name with at least one letter.';

  @override
  String get flow_nameTooLong => 'Use 40 characters or fewer.';

  @override
  String get flow_dobTitle => 'What\'s your date of birth?';

  @override
  String get flow_dobHint => 'We only ever show your age, never your birthday.';

  @override
  String flow_dobExample(String example) {
    return 'For example, $example';
  }

  @override
  String get flow_dobDay => 'Day';

  @override
  String get flow_dobMonth => 'Month';

  @override
  String get flow_dobYear => 'Year';

  @override
  String get flow_dobDaySemantics => 'Day of birth';

  @override
  String get flow_dobMonthSemantics => 'Month of birth';

  @override
  String get flow_dobYearSemantics => 'Year of birth';

  @override
  String get flow_dobDayRange => 'Day must be between 1 and 31.';

  @override
  String get flow_dobMonthRange => 'Month must be between 1 and 12.';

  @override
  String get flow_dobYearDigits => 'Year must have 4 digits.';

  @override
  String get flow_dobNoSuchDate => 'That date doesn\'t exist. Check the day and month.';

  @override
  String get flow_dobFuture => 'That date is in the future.';

  @override
  String get flow_dobCheckYear => 'Check the year.';

  @override
  String flow_dobAge(int age) {
    return 'that makes you $age.';
  }

  @override
  String get flow_phoneTitle => 'What\'s your phone number?';

  @override
  String get flow_phoneHint => 'We\'ll text you a code to sign in. We never show your number to anyone.';

  @override
  String get flow_phoneLabel => 'Phone number';

  @override
  String flow_phoneCountrySemantics(String country, String code) {
    return 'Country, $country, $code';
  }

  @override
  String get flow_phoneChooseCountry => 'Choose your country';

  @override
  String get flow_phoneSend => 'Text me a code';

  @override
  String get flow_phoneTerms => 'By continuing you agree to the Terms and Privacy Policy.';

  @override
  String get flow_phoneTooShort => 'Check the number. It looks too short.';

  @override
  String get flow_phoneTooLong => 'Check the number. It looks too long.';

  @override
  String flow_phoneWrongCountry(String country) {
    return 'That doesn\'t look like a $country number. Check the country.';
  }

  @override
  String get flow_sending => 'Sending your code…';

  @override
  String get flow_sendFailed => 'We couldn\'t send a code. Try again or try WhatsApp.';

  @override
  String get flow_sendFailedSms => 'We couldn\'t send a code. Try again.';

  @override
  String flow_tooManyCodes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Too many codes. Try again in $minutes minutes.',
      one: 'Too many codes. Try again in 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String get flow_tooManyTries => 'Too many tries. Try again in a few minutes.';

  @override
  String get flow_accountChecking => 'Checking your account…';

  @override
  String get flow_accountCheckFailedTitle => 'We couldn\'t check your account';

  @override
  String get flow_accountCheckFailedBody => 'Check your connection and try again.';

  @override
  String get flow_phoneUnavailable => 'Phone sign-in is unavailable right now. Please try again later.';

  @override
  String get flow_codeTitle => 'Enter the code';

  @override
  String flow_codeSubtitle(String number) {
    return 'We sent a 6-digit code to $number.';
  }

  @override
  String get flow_codeChangeNumber => 'Wrong number? Change it';

  @override
  String flow_codeResendIn(String time) {
    return 'Send a new code in $time';
  }

  @override
  String get flow_codeResend => 'Send a new code';

  @override
  String get flow_codeNewest => 'Use the newest code.';

  @override
  String get flow_codeSemantics => 'Verification code, 6 digits';

  @override
  String get flow_codeWrong => 'That code didn\'t work. Check it and try again.';

  @override
  String get flow_codeExpired => 'That code has expired. Send a new one.';

  @override
  String get flow_codeAccepted => 'Code accepted';

  @override
  String get flow_codeCheckFailed => 'We couldn\'t check the code right now. Try again.';

  @override
  String get flow_consentTitle => 'Before you start';

  @override
  String get flow_consentUpdatedTitle => 'We\'ve updated our terms';

  @override
  String get flow_consentAdults => 'Attune is for adults. Everyone here is 18 or older.';

  @override
  String get flow_consentAi => 'Some Attune features use AI to give you private suggestions. In a shared space they can read your chat with your partner, and only after you both agree. What it suggests to one of you is never shown to the other.';

  @override
  String get flow_consentData => 'You can download everything you\'ve added, and delete your account, any time.';

  @override
  String get flow_consentTermsLink => 'Terms of use';

  @override
  String get flow_consentPrivacyLink => 'Privacy policy';

  @override
  String get flow_consentAiLink => 'More about AI in Attune';

  @override
  String get flow_consentAgree => 'Agree and continue';

  @override
  String get flow_consentNotNow => 'Not now';

  @override
  String get flow_signupPhoneRequired => 'Phone sign-in is unavailable right now.';

  @override
  String get flow_saveFailed => 'We couldn\'t save that. Try again.';

  @override
  String get flow_noAccountTitle => 'We couldn\'t find an Attune account for this number';

  @override
  String get flow_noAccountBody => 'You can create one now.';

  @override
  String get flow_noAccountCreate => 'Create an account';

  @override
  String get flow_noAccountOtherNumber => 'Use a different number';

  @override
  String flow_welcomeBack(String name) {
    return 'Welcome back, $name.';
  }

  @override
  String get flow_welcomeBackNoName => 'Welcome back.';

  @override
  String get flow_joinTitle => 'Join Attune';

  @override
  String get flow_joinBody => 'A private space for couples, a few introductions a day for singles, and a journal just for you.';

  @override
  String get flow_phoneWhatsApp => 'Send by WhatsApp instead';

  @override
  String flow_whatsAppTitle(String number) {
    return 'Is WhatsApp on $number?';
  }

  @override
  String get flow_whatsAppBody => 'We\'ll send the code to WhatsApp on this number. If WhatsApp is on a different number, we\'ll text you instead.';

  @override
  String get flow_whatsAppYes => 'Yes, send it to WhatsApp';

  @override
  String get flow_whatsAppNo => 'No, text me';

  @override
  String get flow_codeTryWhatsApp => 'Try WhatsApp';

  @override
  String get flow_codeCallMe => 'Call me with the code';

  @override
  String flow_codeCalling(String number) {
    return 'We\'re calling $number now. The code is read out twice.';
  }

  @override
  String get flow_tabMe => 'Me';

  @override
  String get flow_tabSignIn => 'Sign in';

  @override
  String get flow_pathTitle => 'What brings you to Attune?';

  @override
  String get flow_pathJustMeLineFull => 'Your journal, quizzes and Healing. Single, partnered or in between.';

  @override
  String flow_pathNotOpen(String country) {
    return 'Not open in $country yet';
  }

  @override
  String get flow_pathFooter => 'You can change this any time. Your journal and quizzes are yours whichever you choose.';

  @override
  String get flow_pathAlreadyInvited => 'My partner already invited me';

  @override
  String get flow_pathGroupSemantics => 'Choose one of three';

  @override
  String get flow_pathDatingOffline => 'Dating needs a connection. Try again when you\'re online.';

  @override
  String get flow_cancel => 'Cancel';

  @override
  String get flow_cancelInviteTitle => 'Cancel your invite?';

  @override
  String get flow_cancelInviteBody => 'Your invite code will stop working. Your partner won\'t be told.';

  @override
  String flow_cancelInviteBodyNamed(String name) {
    return 'Your invite code will stop working. $name won\'t be told.';
  }

  @override
  String get flow_cancelInviteConfirm => 'Cancel invite and switch';

  @override
  String get flow_cancelInviteKeep => 'Keep invite';

  @override
  String get flow_pauseDatingTitle => 'Inviting a partner pauses Dating';

  @override
  String get flow_pauseDatingBody => 'Your introductions stop and your Dating profile is hidden. Nobody is told.';

  @override
  String get flow_switchOffline => 'You\'re offline. Try again when you\'re connected.';

  @override
  String get flow_dobAddTitle => 'Add your date of birth';

  @override
  String get flow_holdTitle => 'We need to check your account';

  @override
  String get flow_holdBody => 'You can\'t use Attune while we do this. If you think this is a mistake, contact support.';

  @override
  String get flow_holdContact => 'Contact support';

  @override
  String get flow_signOut => 'Sign out';

  @override
  String get flow_updateTitle => 'Update Attune to continue';

  @override
  String get flow_updateBody => 'This version of Attune can\'t finish setting up your account. Update the app from your app store, then open it again.';

  @override
  String get flow_checkOfflineTitle => 'We couldn\'t check your account';

  @override
  String get flow_checkOfflineBody => 'Check your connection, then try again.';

  @override
  String get flow_invitePartnerTitle => 'Invite your partner';

  @override
  String get flow_invitePartnerBody => 'Send a link. When your partner joins, your private space opens.';

  @override
  String get flow_invitePartnerCreate => 'Create my invite';

  @override
  String get flow_invitePartnerLater => 'Invite later';

  @override
  String get flow_invitePartnerDone => 'Done';

  @override
  String get flow_pathOpenSpace => 'You\'re in a shared space. To use Attune another way, end it or pause it first.';

  @override
  String get flow_inviteCodeRefused => 'This code didn\'t work. It may have expired or been used. Ask for a new one.';

  @override
  String get flow_inviteCodeAlreadyIn => 'You\'re already in a shared space, so this invite can\'t be used.';

  @override
  String get flow_inviteCodeOffline => 'We couldn\'t check that code. Try again when you\'re online.';

  @override
  String get flow_ageStopAccountBody => 'You need to be 18 or older to use Attune. Your account is on hold.';

  @override
  String get flow_spaceTitle => 'Your space';

  @override
  String get flow_settingsTooltip => 'Settings';

  @override
  String get flow_spaceJournal => 'Journal';

  @override
  String get flow_spaceJournalLine => 'Notes only you can read';

  @override
  String get flow_spaceQuizzes => 'Quizzes';

  @override
  String get flow_spaceQuizzesLine => 'Short, private, about you';

  @override
  String get flow_spaceHealing => 'Healing';

  @override
  String get flow_spaceHealingLine => 'After a breakup or a loss';

  @override
  String get flow_firstStartHere => 'Start here';

  @override
  String get flow_firstWriteNote => 'Write your first note';

  @override
  String get flow_firstQuiz => 'Take a 3-minute look at how you connect';

  @override
  String get flow_firstSaved => 'Saved, just for you.';

  @override
  String get flow_moreWays => 'More ways to use Attune';

  @override
  String get flow_moreInvite => 'Invite a partner';

  @override
  String get flow_justMeSheetTitle => 'Use Attune just for you?';

  @override
  String get flow_justMeSheetBody => 'Dating will be paused and hidden. Nobody is told. You can delete your Dating profile from Dating settings.';

  @override
  String get flow_justMeSheetSwitch => 'Switch';

  @override
  String get flow_waitWriteNote => 'Write a first note';

  @override
  String get flow_waitQuiz => 'A quiz about you, for you';

  @override
  String get flow_waitReceipts => 'When your partner joins, read receipts start off. You can each turn them on later.';

  @override
  String get flow_inviteMenu => 'Invite options';

  @override
  String get flow_cancelThisInvite => 'Cancel this invite';

  @override
  String get flow_cancelThisInviteTitle => 'Cancel this invite?';

  @override
  String get flow_cancelThisInviteConfirm => 'Cancel invite';

  @override
  String flow_waitReceiptsNamed(String partnerFirstName) {
    return 'When your partner joins, read receipts start off. You and $partnerFirstName can each turn them on later.';
  }

  @override
  String get flow_slotDatingTitle => 'Dating';

  @override
  String get flow_slotDatingBody => 'Up to 3 introductions a day. A match only when you both say yes.';

  @override
  String get flow_slotSetUp => 'Set up Dating';

  @override
  String get flow_slotNotReady => 'Not ready? Use Attune just for me';

  @override
  String flow_slotNotOpenTitle(String country) {
    return 'Dating isn\'t open in $country yet';
  }

  @override
  String flow_slotNotOpenBody(String countries) {
    return 'Dating is open in $countries. We\'re adding countries one at a time.';
  }

  @override
  String flow_slotChangeCountry(String country) {
    return 'Not in $country? Change';
  }

  @override
  String get flow_slotChooseCountry => 'Choose your country';

  @override
  String get flow_slotClosedTitle => 'Dating isn\'t open yet';

  @override
  String get flow_slotClosedBody => 'It opens one country at a time. Your journal, quizzes and Healing are here meanwhile.';

  @override
  String flow_slotGentleWait(String date) {
    return 'Dating opens for you on $date.';
  }

  @override
  String get flow_slotGentleWaitWhy => 'This pause is because your relationship ended here. It isn\'t a judgement about you.';

  @override
  String get flow_slotHealing => 'Healing is here if you want it';

  @override
  String get flow_slotLocked => 'Dating is locked';

  @override
  String get flow_slotLockedLine => 'Enter your Safety PIN to show it';

  @override
  String get flow_lockTitle => 'Dating lock';

  @override
  String get flow_lockSubtitle => 'Ask for your Safety PIN before showing Dating.';

  @override
  String get flow_slotGentleWaitNoDate => 'Dating opens for you after a pause.';

  @override
  String get flow_pushTurnOn => 'Turn on';

  @override
  String get flow_pushAskR2 => 'Get a heads-up when your partner joins';

  @override
  String flow_pushAskR2Named(String name) {
    return 'Get a heads-up when $name joins';
  }

  @override
  String get flow_reminderTitle => 'Remind me to write';

  @override
  String get flow_reminderOff => 'Off';

  @override
  String flow_reminderWhen(String days, String time) {
    return '$days at $time';
  }

  @override
  String get flow_weekdaysMon => 'Mondays';

  @override
  String get flow_weekdaysTue => 'Tuesdays';

  @override
  String get flow_weekdaysWed => 'Wednesdays';

  @override
  String get flow_weekdaysThu => 'Thursdays';

  @override
  String get flow_weekdaysFri => 'Fridays';

  @override
  String get flow_weekdaysSat => 'Saturdays';

  @override
  String get flow_weekdaysSun => 'Sundays';

  @override
  String get flow_weekdayMon => 'Mon';

  @override
  String get flow_weekdayTue => 'Tue';

  @override
  String get flow_weekdayWed => 'Wed';

  @override
  String get flow_weekdayThu => 'Thu';

  @override
  String get flow_weekdayFri => 'Fri';

  @override
  String get flow_weekdaySat => 'Sat';

  @override
  String get flow_weekdaySun => 'Sun';

  @override
  String get flow_reminderSheetTitle => 'When should we remind you?';

  @override
  String get flow_reminderDay => 'Day';

  @override
  String get flow_reminderTime => 'Time';

  @override
  String get flow_reminderChangeTime => 'Change time';

  @override
  String get flow_reminderTurnOn => 'Turn on';

  @override
  String get flow_reminderTurnOff => 'Turn off';

  @override
  String get flow_reminderNeedsPush => 'Reminders need notifications.';

  @override
  String get flow_reminderTurnOnPush => 'Turn on notifications';

  @override
  String get flow_reminderReadFailed => 'We couldn\'t load your reminder. Try again.';

  @override
  String flow_reminderQuietHours(String start, String end) {
    return 'Reminders can be set from $start to $end.';
  }

  @override
  String get flow_howTitle => 'How you use Attune';

  @override
  String get flow_howSubtitle => 'In a relationship, dating, or just for you';

  @override
  String get flow_howFooter => 'Your journal, quizzes and Healing stay yours whichever you choose. Nobody is told when you change this.';

  @override
  String flow_sharedOpenTitle(String name) {
    return 'You\'re in a shared space with $name';
  }

  @override
  String get flow_yourPartner => 'your partner';

  @override
  String get flow_sharedOpenBody => 'To use Attune another way, end it first. Pausing keeps it, read-only, for up to 30 days.';

  @override
  String get flow_sharedPause => 'Pause our shared space';

  @override
  String get flow_sharedEnd => 'End relationship';

  @override
  String get flow_notNow => 'Not now';

  @override
  String get flow_joinAlreadyIn => 'You\'re already in a relationship on Attune. End it first to join a new one.';

  @override
  String get flow_joinNotPossible => 'We couldn\'t link these accounts. If you think this is wrong, contact support.';

  @override
  String get flow_joinOwn => 'This is your own invite. Send it to your partner instead.';

  @override
  String get flow_joinInvalid => 'We couldn\'t find that invite. Check the code with the person who sent it.';

  @override
  String get flow_joinTryLater => 'You\'ve checked a lot of codes. Try again in a little while.';

  @override
  String get flow_inviteErrorSignUp => 'Finish setting up your account first, then try again.';

  @override
  String get flow_inviteErrorCap => 'You already have 3 invites waiting. Cancel one before you send another.';

  @override
  String get flow_inviteErrorAgeRequired => 'Add your date of birth first, then send your invite.';

  @override
  String get flow_inviteErrorTryAgain => 'We couldn\'t make your invite. Try again.';

  @override
  String flow_inviteMsgSimpleOpen(String name) {
    return 'Hi $name, I\'d like us to try Attune together. It\'s a private space just for the two of us.';
  }

  @override
  String get flow_inviteMsgSimpleOpenNoName => 'Hi, I\'d like us to try Attune together. It\'s a private space just for the two of us.';

  @override
  String flow_inviteMsgSimpleGet(String link) {
    return 'Get the app: $link';
  }

  @override
  String flow_inviteMsgCasualOpen(String name) {
    return 'Hey $name! I found an app for couples and thought of us. Private, just you and me.';
  }

  @override
  String get flow_inviteMsgCasualOpenNoName => 'Hey! I found an app for couples and thought of us. Private, just you and me.';

  @override
  String flow_inviteMsgCasualGet(String link) {
    return 'Get it here: $link';
  }

  @override
  String flow_inviteMsgPidginOpen(String name) {
    return '$name, make we try Attune. Na private space for only you and me.';
  }

  @override
  String get flow_inviteMsgPidginOpenNoName => 'Make we try Attune. Na private space for only you and me.';

  @override
  String flow_inviteMsgPidginGet(String link) {
    return 'Download am: $link';
  }

  @override
  String flow_inviteMsgOpenCode(String code) {
    return 'Open Attune → I have an invite → $code';
  }

  @override
  String get flow_inviteMsgFoundMyself => 'I found this myself. I just thought it\'d be nice.';

  @override
  String get flow_inviteCodeServerError => 'Something went wrong on our side. Try again.';

  @override
  String flow_invitePartnerBodyNamed(String name) {
    return 'Send a link. When $name joins, your private space opens.';
  }

  @override
  String get flow_r1NameLabel => 'Their first name (optional)';

  @override
  String get flow_r1NameHelper => 'Used in your message and on this phone only.';

  @override
  String get flow_r1ToneTitle => 'How should it sound?';

  @override
  String get flow_r1ToneGroup => 'Choose one of the message styles';

  @override
  String get flow_r1ToneSimple => 'Simple';

  @override
  String get flow_r1ToneCasual => 'Casual';

  @override
  String get flow_r1TonePidgin => 'Pidgin';

  @override
  String get flow_r1FoundMyselfToggle => 'Add: \'I found this myself. I just thought it\'d be nice.\'';

  @override
  String get flow_r1PreviewTitle => 'What your partner will see';

  @override
  String flow_r1PreviewTitleNamed(String name) {
    return 'What $name will see';
  }

  @override
  String get flow_r1Making => 'Making your invite';

  @override
  String get flow_r1CodePending => '(your code)';

  @override
  String get flow_r1SendWhatsApp => 'Send on WhatsApp';

  @override
  String get flow_r1ShareOther => 'Share another way';

  @override
  String get flow_r1ShowQr => 'Show QR code';

  @override
  String get flow_r1CopyCode => 'Copy code';

  @override
  String get flow_r1CodeCopied => 'Code copied.';

  @override
  String get flow_r1QrTitle => 'Your invite code';

  @override
  String get flow_r1QrSemantics => 'A QR code for your invite link';

  @override
  String flow_inviteCodeSemantics(String code) {
    return 'Invite code $code';
  }

  @override
  String flow_ri3Title(String name) {
    return 'Join $name?';
  }

  @override
  String get flow_ri3TitleUnnamed => 'Join your partner?';

  @override
  String flow_ri3Body(String name) {
    return '$name invited you to a private space on Attune.';
  }

  @override
  String get flow_ri3BodyUnnamed => 'Your partner invited you to a private space on Attune.';

  @override
  String flow_ri3Button(String name) {
    return 'Join $name';
  }

  @override
  String get flow_ri3ButtonUnnamed => 'Join';

  @override
  String get flow_joinOtherWay => 'Not what you expected? Choose another way to use Attune';

  @override
  String get flow_joinEnterAgain => 'Enter the code again';

  @override
  String get flow_joinExpiredTitle => 'This invite has expired.';

  @override
  String flow_joinExpired(String name) {
    return 'Ask $name to send a new one.';
  }

  @override
  String get flow_joinExpiredUnnamed => 'Ask the person who sent it to send a new one.';

  @override
  String flow_joinAskWhatsApp(String name) {
    return 'Ask $name on WhatsApp';
  }

  @override
  String get flow_joinAskWhatsAppUnnamed => 'Ask on WhatsApp';

  @override
  String flow_joinExpiredMessage(String name) {
    return 'Hi $name, my Attune invite expired. Could you send me a new one?';
  }

  @override
  String get flow_joinExpiredMessageUnnamed => 'Hi, my Attune invite expired. Could you send me a new one?';

  @override
  String get flow_joinChecking => 'Checking your invite';

  @override
  String flow_linkedTitle(String couple) {
    return 'Welcome, $couple';
  }

  @override
  String flow_linkedBody(String name) {
    return 'Your private space with $name is open.';
  }

  @override
  String get flow_linkedBodyUnnamed => 'Your private space with your partner is open.';

  @override
  String flow_pushAskR4(String name) {
    return 'Get notified when $name messages you';
  }

  @override
  String get flow_pushAskR4Unnamed => 'Get notified when your partner messages you';

  @override
  String get flow_inviteErrorNotPossible => 'We couldn\'t make your invite. If you think this is wrong, contact support.';

  @override
  String get flow_guideWaitLine => 'We\'ll suggest a private reflection space if this takes a little while.';

  @override
  String get flow_guideReflectTitle => 'A private space while you wait';

  @override
  String get flow_guideReflectBody => 'Your reflections stay private to you.';

  @override
  String get flow_guideOpenJournal => 'Open your journal';

  @override
  String get flow_guideWeekTitle => 'It\'s been a week';

  @override
  String flow_guideWeekBody(String name) {
    return 'Your invite to $name has run its week. What would you like to do?';
  }

  @override
  String get flow_guideWeekBodyUnnamed => 'Your invite to your partner has run its week. What would you like to do?';

  @override
  String get flow_guideKeepWaiting => 'Keep waiting';

  @override
  String get flow_guideSendNew => 'Send a new invite';

  @override
  String get flow_guideSendNewHelper => 'Send it to the same number or a different one.';

  @override
  String get flow_guideOnMyOwn => 'Use Attune on my own for now';

  @override
  String flow_day30(String name) {
    return 'Want to send $name a new invite?';
  }

  @override
  String get flow_day30Unnamed => 'Want to send your partner a new invite?';

  @override
  String get flow_day30Dismiss => 'Dismiss';

  @override
  String get flow_r3SendAgain => 'Send again';

  @override
  String flow_invitePartnerNamed(String name) {
    return 'Invite $name';
  }

  @override
  String get aboutUs_title => 'About us';

  @override
  String aboutUs_step(int step, int total) {
    return '$step of $total';
  }

  @override
  String aboutUs_stepSemantics(int step, int total) {
    return 'Question $step of $total';
  }

  @override
  String get aboutUs_skip => 'Skip';

  @override
  String get aboutUs_done => 'Done';

  @override
  String get aboutUs_save => 'Save';

  @override
  String get aboutUs_moreAbout => 'More about this';

  @override
  String get aboutUs_moreAboutBody => 'Either of you can change these. It\'s never used to score or type you.';

  @override
  String aboutUs_moreAboutDraft(String name) {
    return 'Before $name joins, your answers are a draft only you can see. When $name joins, your answers become your shared About us.';
  }

  @override
  String get aboutUs_moreAboutDraftUnnamed => 'Before your partner joins, your answers are a draft only you can see. When your partner joins, your answers become your shared About us.';

  @override
  String get aboutUs_stageQuestion => 'How would you describe where you two are?';

  @override
  String get aboutUs_stageDating => 'Dating';

  @override
  String get aboutUs_stageEngaged => 'Engaged';

  @override
  String get aboutUs_stageMarried => 'Married';

  @override
  String get aboutUs_stageOther => 'Something else';

  @override
  String get aboutUs_stageEngagedHelper => 'Planning to marry, including after the knocking and before the wedding.';

  @override
  String get aboutUs_stageMarriedHelper => 'Any kind of marriage: customary, religious or civil.';

  @override
  String get aboutUs_stageWordsLabel => 'In your own words';

  @override
  String get aboutUs_stageWhy => 'So what Attune suggests fits you two. Either of you can change this. It\'s never used to score or type you.';

  @override
  String get aboutUs_sinceQuestion => 'When did you two get together?';

  @override
  String aboutUs_sinceHelper(String couple) {
    return 'Use whichever date feels right to $couple.';
  }

  @override
  String get aboutUs_sinceWhy => 'So we can remember your anniversary with you, if you\'d like.';

  @override
  String get aboutUs_monthLabel => 'Month';

  @override
  String get aboutUs_yearLabel => 'Year';

  @override
  String get aboutUs_dayLabel => 'Day';

  @override
  String get aboutUs_monthOptional => 'Month (optional)';

  @override
  String get aboutUs_dayOptional => 'Day (optional)';

  @override
  String get aboutUs_notSure => 'Not sure';

  @override
  String get aboutUs_sinceAddDay => 'Add the day';

  @override
  String get aboutUs_sinceNoMonth => 'Not sure of the month';

  @override
  String get aboutUs_sinceSuggestions => 'Suggested dates';

  @override
  String get aboutUs_errorFuture => 'That date is in the future.';

  @override
  String get aboutUs_errorNoSuchDate => 'Check the day and month.';

  @override
  String get aboutUs_errorNeedsYear => 'Choose a year.';

  @override
  String get aboutUs_marryQuestion => 'What year did you marry?';

  @override
  String aboutUs_ceremonyN(int n) {
    return 'Ceremony $n';
  }

  @override
  String get aboutUs_ceremonyLabelGroup => 'What kind of ceremony? (optional)';

  @override
  String get aboutUs_labelCustomary => 'Customary';

  @override
  String get aboutUs_labelChurch => 'Church';

  @override
  String get aboutUs_labelMosque => 'Mosque';

  @override
  String get aboutUs_labelCivil => 'Civil';

  @override
  String get aboutUs_labelOther => 'Other';

  @override
  String get aboutUs_addCeremony => 'Had more than one ceremony? Add another';

  @override
  String get aboutUs_removeCeremony => 'Remove this ceremony';

  @override
  String get aboutUs_livingQuestion => 'Where do you two live?';

  @override
  String get aboutUs_livingTogether => 'Together';

  @override
  String get aboutUs_livingApartNearby => 'Apart, nearby';

  @override
  String get aboutUs_livingLongDistance => 'Long distance';

  @override
  String get aboutUs_livingWhy => 'So plans, maps and reminders fit how you live.';

  @override
  String get aboutUs_childrenQuestion => 'Are there children in your life together?';

  @override
  String get aboutUs_childrenNo => 'No';

  @override
  String get aboutUs_childrenYes => 'Yes';

  @override
  String get aboutUs_childrenExpecting => 'We\'re expecting';

  @override
  String get aboutUs_childrenPreferNot => 'Prefer not to say';

  @override
  String get aboutUs_childrenAges => 'Their ages (optional)';

  @override
  String get aboutUs_bandUnder2 => 'Under 2';

  @override
  String get aboutUs_band2to5 => '2–5';

  @override
  String get aboutUs_band6to12 => '6–12';

  @override
  String get aboutUs_band13to17 => '13–17';

  @override
  String get aboutUs_band18plus => '18+';

  @override
  String get aboutUs_childrenWhy => 'So ideas and reminders suit your family.';

  @override
  String get aboutUs_anniversaryQuestion => 'Remember your anniversary?';

  @override
  String get aboutUs_anniversaryNo => 'No, thanks';

  @override
  String get aboutUs_anniversaryTogether => 'The day you got together';

  @override
  String aboutUs_anniversaryCeremony(String label, String year) {
    return '$label ceremony, $year';
  }

  @override
  String aboutUs_anniversaryCeremonyPlain(String year) {
    return 'Ceremony, $year';
  }

  @override
  String get aboutUs_anniversaryWhatDay => 'What day was it?';

  @override
  String get aboutUs_rowSince => 'Together since';

  @override
  String get aboutUs_rowStage => 'Where you are';

  @override
  String get aboutUs_rowCeremonies => 'Ceremonies';

  @override
  String get aboutUs_rowLiving => 'Where you live';

  @override
  String get aboutUs_rowChildren => 'Children';

  @override
  String get aboutUs_rowAnniversary => 'Anniversary';

  @override
  String get aboutUs_notAnswered => 'Not answered yet';

  @override
  String aboutUs_childrenYesBands(String bands) {
    return 'Yes ($bands)';
  }

  @override
  String get aboutUs_anniversaryOff => 'Off';

  @override
  String aboutUs_ceremonyLine(String label, String year) {
    return '$label, $year';
  }

  @override
  String aboutUs_changedBy(String name) {
    return 'Changed by $name';
  }

  @override
  String get aboutUs_changedByYou => 'Changed by you';

  @override
  String get aboutUs_changedByPartner => 'Changed by your partner';

  @override
  String get aboutUs_footer => 'Either of you can change these. It\'s never used to score or type you.';

  @override
  String aboutUs_readOnlyUntil(String date) {
    return 'You can read this until $date.';
  }

  @override
  String get aboutUs_pendingSync => 'Saved on this phone. It will be shared when you\'re back online.';

  @override
  String get aboutUs_loadFailed => 'We couldn\'t load About us. Check your connection and try again.';

  @override
  String get aboutUs_answerQuestions => 'Answer a few questions';

  @override
  String get aboutUs_rowEditHint => 'Change';

  @override
  String get aboutUs_errorAnniversaryNeedsDay => 'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.';

  @override
  String get aboutUs_errorReadOnly => 'About us can\'t be changed right now.';

  @override
  String get aboutUs_errorWordsTooLong => 'Use 40 characters or fewer.';

  @override
  String get aboutUs_cardTitle => 'About us';

  @override
  String aboutUs_cardBody(String name) {
    return 'A few easy questions about you two. Skip any of them. $name sees your answers after joining.';
  }

  @override
  String get aboutUs_cardBodyUnnamed => 'A few easy questions about you two. Skip any of them. Your partner sees your answers after joining.';

  @override
  String get aboutUs_settingsSubtitle => 'When you got together, where you live and more';

  @override
  String get aboutUs_reminderFollows => 'This reminder follows About us';

  @override
  String get aboutUs_reminderChange => 'Change in About us';

  @override
  String get aboutUs_reminderStopTitle => 'Your anniversary reminder will stop';

  @override
  String get aboutUs_reminderStopBody => 'It follows this ceremony\'s date. It can follow the day you got together instead.';

  @override
  String get aboutUs_reminderStopOff => 'Turn it off';

  @override
  String get aboutUs_sinceHelperUnnamed => 'Use whichever date feels right.';

  @override
  String get aboutUs_reminderOffline => 'We couldn\'t check this reminder. Check your connection and try again.';

  @override
  String get aboutUs_reminderTimes => 'Reminder times and note';

  @override
  String get aboutUs_reminderLocked => 'Its date, title and type follow About us.';

  @override
  String get aboutUs_anniversaryHandMade => 'You already have an anniversary reminder, so we won\'t add another.';

  @override
  String get flow_dormantTitle => 'Welcome to Attune';

  @override
  String get flow_dormantBody => 'Let\'s get you set up.';

  @override
  String get flow_dormantNew => 'I\'m new to Attune';

  @override
  String get flow_dormantUsedBefore => 'Used Attune before on this number? Contact support';

  @override
  String get flow_dormantFailed => 'We couldn\'t reach Attune. Check your connection and try again.';

  @override
  String get flow_dormantTryLater => 'Too many tries. Try again in an hour.';

  @override
  String get flow_dormantExpired => 'That took too long. Enter your number again.';

  @override
  String get flow_freshStartTitle => 'One more code to finish';

  @override
  String flow_freshStartBody(String phone) {
    return 'We\'ll send a new code to $phone.';
  }

  @override
  String get flow_freshStartSend => 'Send code';

  @override
  String get flow_dobSettingsTitle => 'Date of birth';

  @override
  String get flow_dobSettingsSubtitle => 'Only your age is shown, never the date';

  @override
  String flow_dobSettingsAge(int age) {
    return 'Your age: $age';
  }

  @override
  String get flow_dobSettingsNoAge => 'We don\'t have your date of birth yet.';

  @override
  String flow_dobSettingsFixUntil(String date) {
    return 'If it\'s wrong, you can fix it once, until $date.';
  }

  @override
  String get flow_dobSettingsContact => 'To change this, contact support.';

  @override
  String get flow_dobSettingsFix => 'Fix a mistake';

  @override
  String get flow_dobFixTitle => 'Fix your date of birth';

  @override
  String get flow_dobFixSaved => 'Saved.';

  @override
  String get flow_dobSettingsLoadFailed => 'We couldn\'t load this. Check your connection and try again.';

  @override
  String get support_childReportTitle => 'Report a concern about a child';

  @override
  String get support_childReportSubtitle => 'A person on our team reads every report';

  @override
  String get support_childReportBody => 'Tell us what you saw and where. A person on our team reads every report. If a child is in danger right now, call your local emergency number.';

  @override
  String get support_childReportWhere => 'Where did you see it?';

  @override
  String get support_childReportChat => 'Chat';

  @override
  String get support_childReportStories => 'Stories';

  @override
  String get support_childReportOpinions => 'Opinions';

  @override
  String get support_childReportDating => 'Dating';

  @override
  String get support_childReportElsewhere => 'Somewhere else';

  @override
  String get support_childReportDetails => 'What did you see?';

  @override
  String support_childReportCount(int count, int max) {
    return '$count of $max';
  }

  @override
  String get support_childReportSend => 'Send report';

  @override
  String get support_childReportThanks => 'Thank you. We\'ve received your report.';

  @override
  String support_childReportLimit(String email) {
    return 'You\'ve sent 5 reports today. To tell us more, email $email.';
  }

  @override
  String get support_childReportFailed => 'We couldn\'t send this. Check your connection and try again.';

  @override
  String get support_childReportDone => 'Done';

  @override
  String get support_childReportTooLong => 'This is too long. Keep it to 2,000 characters or fewer.';

  @override
  String support_childReportInvalid(String email) {
    return 'We couldn\'t send this as written. Make it shorter and try again, or email $email.';
  }

  @override
  String get support_resourcesTitle => 'Support resources';

  @override
  String get support_resourcesIntro => 'If something does not feel safe, these contacts and planning resources may be useful.';

  @override
  String get support_resourcesNoEmergencyService => 'Attune cannot assess an emergency or contact help for you.';

  @override
  String get support_quickExit => 'Quick exit';

  @override
  String get support_quickExitBody => 'Tap to exit the app and show a neutral screen.';

  @override
  String get support_exitNow => 'Exit now';

  @override
  String get support_notNow => 'Not relevant right now';

  @override
  String support_helpFor(String country) {
    return 'Help for $country';
  }

  @override
  String get support_changeCountry => 'Change';

  @override
  String support_changeCountryLabel(String country) {
    return 'Change country. Now showing $country';
  }

  @override
  String get support_chooseCountry => 'Choose your country to see help near you.';

  @override
  String get support_chooseCountryButton => 'Choose a country';

  @override
  String get support_loading => 'Looking for help near you';

  @override
  String get support_emergencyHeading => 'In an emergency';

  @override
  String get support_anywhereHeading => 'Anywhere in the world';

  @override
  String get support_categoryEmergency => 'Emergency';

  @override
  String get support_categoryDv => 'Domestic abuse';

  @override
  String get support_categoryCrisis => 'Someone to talk to now';

  @override
  String get support_categorySexualAssault => 'Sexual assault';

  @override
  String get support_categorySextortion => 'Threats to share images';

  @override
  String get support_categoryChildSafety => 'A child at risk';

  @override
  String get support_categoryYouth => 'For young people';

  @override
  String get support_categoryLgbtqLegal => 'LGBTQ+ and legal help';

  @override
  String get support_categoryGrief => 'Grief';

  @override
  String get support_categoryPerinatal => 'Pregnancy and after birth';

  @override
  String get support_categoryAddiction => 'Alcohol, drugs and gambling';

  @override
  String get support_categoryFinancialControl => 'Money and control';

  @override
  String get support_notPolice => 'Not the police';

  @override
  String get support_police => 'Police';

  @override
  String support_call(String number) {
    return 'Call $number';
  }

  @override
  String support_text(String number) {
    return 'Text $number';
  }

  @override
  String get support_whatsapp => 'WhatsApp';

  @override
  String get support_website => 'Website';

  @override
  String support_callConfirmTitle(String number) {
    return 'Call $number?';
  }

  @override
  String get support_callConfirmBody => 'Calls may show in your phone\'s call history.';

  @override
  String get support_callConfirmCall => 'Call';

  @override
  String support_textConfirmTitle(String number) {
    return 'Text $number?';
  }

  @override
  String get support_textConfirmBody => 'Messages may stay on your phone.';

  @override
  String support_linkConfirmTitle(String site) {
    return 'Open $site?';
  }

  @override
  String get support_linkConfirmBody => 'It may show in your browser history.';

  @override
  String get support_open => 'Open';

  @override
  String get support_cancel => 'Cancel';

  @override
  String support_unsupported(String country) {
    return 'We don\'t have a checked list for $country yet.';
  }

  @override
  String support_noFocusList(String country) {
    return 'We don\'t have a checked list for this in $country yet.';
  }

  @override
  String get support_findHelpline => 'Find a helpline';

  @override
  String get support_localEmergency => 'In an emergency, call your local emergency number.';

  @override
  String get support_griefTitle => 'Grief support';

  @override
  String get support_youthTitle => 'Support for young people';

  @override
  String get support_writeInJournal => 'Write about it in your journal';

  @override
  String get support_settingsTitle => 'Find support';

  @override
  String get support_settingsSubtitle => 'Helplines for where you are';

  @override
  String get support_cannotOpen => 'That didn\'t open here. Try it from another phone or computer.';

  @override
  String get flow_healingChoiceTitle => 'What happened?';

  @override
  String get flow_healingBreakup => 'A breakup';

  @override
  String get flow_healingLoss => 'Someone I love died';

  @override
  String get support_whatsappConfirmBody => 'The chat may stay in WhatsApp on your phone.';

  @override
  String get support_back => 'Back';

  @override
  String get opinions_filterContactInfo => 'Phone numbers, emails, links and usernames can\'t go in Opinions. They can identify you or someone else. Take it out and post again.';

  @override
  String get opinions_filterSlur => 'This includes a word that attacks people for who they are. Opinions doesn\'t allow it.';

  @override
  String get opinions_filterExplicit => 'Opinions doesn\'t allow sexual content. You can describe what happened without explicit words.';

  @override
  String get opinions_filterQuoted => 'The comment you\'re replying to can\'t be quoted in Opinions. Your own words are fine. Close the reply and post again.';

  @override
  String get opinions_filterPollOption => 'It\'s in one of your poll options.';

  @override
  String get support_needSupportNow => 'Need support now?';

  @override
  String get opinions_reportAtRisk => 'Someone may be at risk';

  @override
  String get opinions_atRiskThanks => 'Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.';

  @override
  String get opinions_atRiskSeeNumbers => 'See emergency numbers';

  @override
  String get opinions_atRiskClose => 'Close';

  @override
  String get opinions_reportFailed => 'Couldn\'t send your report. Please try again.';

  @override
  String get opinions_reportSent => 'Thank you. Your report has been sent.';

  @override
  String get opinions_reportSending => 'Sending your report';

  @override
  String get journal_supportCardBody => 'If things feel heavy right now, you don\'t have to carry it alone. Support is here if you want it.';

  @override
  String get journal_supportSeeSupport => 'See support';

  @override
  String get journal_supportNotNow => 'Not now';

  @override
  String get journal_supportPatternsAway => 'Patterns will show here again later';

  @override
  String get journal_supportPatternsAwayBody => 'Your entries are saved and stay private to you.';

  @override
  String get dating_gentleWaitTitle => 'Before you begin';

  @override
  String dating_gentleWaitBody(String endDate, String openDate) {
    return 'Your relationship on Attune ended on $endDate. Dating opens for you on $openDate, when your shared space closes. If you both close it sooner, Dating opens then.';
  }

  @override
  String get dating_gentleWaitNotJudgement => 'This pause is because your relationship ended here. It isn\'t a judgement about you.';

  @override
  String get dating_gentleWaitQuestionsTitle => 'Three questions, just for you';

  @override
  String get dating_gentleWaitQuestionsHint => 'Only you can see these, and nothing is scored.';

  @override
  String get dating_gentleWaitQuestion1 => 'What do you want to carry into your next relationship?';

  @override
  String get dating_gentleWaitQuestion2 => 'What are you hoping for now?';

  @override
  String get dating_gentleWaitQuestion3 => 'How will you know if you need more time?';

  @override
  String dating_gentleWaitAnswerCount(int count, int max) {
    return '$count of $max characters';
  }

  @override
  String get dating_gentleWaitSave => 'Save my answers';

  @override
  String get dating_gentleWaitSaved => 'Your answers are saved.';

  @override
  String get dating_gentleWaitHealing => 'Healing is here if you want it. It\'s there to help, and it\'s never required.';

  @override
  String get dating_gentleWaitSetUp => 'Set up Dating now';

  @override
  String get dating_offline => 'You\'re offline. Dating needs a connection.';

  @override
  String get dating_connectToSave => 'Connect to save this answer.';

  @override
  String get dating_errorGeneric => 'Something went wrong. Try again.';

  @override
  String get dating_retry => 'Retry';

  @override
  String get dating_gentleWaitClear => 'Clear my answers';

  @override
  String get dating_gentleWaitCleared => 'Your answers are cleared.';

  @override
  String get dating_gentleWaitBusy => 'This is taking a little longer than usual. Your answers are still here, so try again in a moment.';

  @override
  String get dating_busy => 'This is taking a little longer than usual. Try again in a moment.';

  @override
  String get dating_gentleWaitClearBusy => 'This is taking a little longer than usual. Try clearing again in a moment.';

  @override
  String dating_gentleWaitBodyNoShortcut(String endDate, String openDate) {
    return 'Your relationship on Attune ended on $endDate. Dating opens for you on $openDate.';
  }

  @override
  String get dating_unlockButton => 'Enter my PIN';

  @override
  String get dating_sectionReverify => 'Confirm it\'s you on this phone to see Dating.';

  @override
  String get dating_gentleWaitNotEligible => 'Dating isn\'t available on this account right now, so your answers weren\'t saved.';

  @override
  String get dating_countryUk => 'the United Kingdom';

  @override
  String dating_countryWithRegions(String country, String regions) {
    return '$country ($regions)';
  }

  @override
  String dating_sectionNotOpen(String country) {
    return 'Dating isn\'t open in $country yet.';
  }

  @override
  String dating_sectionRegionOpenOnly(String regions) {
    return 'Dating is open in $regions for now.';
  }

  @override
  String get dating_tellMe => 'Tell me when it\'s here';

  @override
  String dating_tellMeRegion(String region) {
    return 'Tell me when it\'s open in $region';
  }

  @override
  String get dating_tellMeDone => 'We\'ll let you know. You can turn this off in Settings.';

  @override
  String get dating_tellMeOff => 'Turn this off';

  @override
  String dating_notOpenTitle(String country) {
    return 'Dating isn\'t open in $country yet';
  }

  @override
  String dating_notOpenBody(String countries) {
    return 'Attune opens Dating one country at a time, so we can keep it safe and well looked after. It\'s open in $countries now.';
  }

  @override
  String dating_notOpenRegionTitle(String regions) {
    return 'Dating is open in $regions for now';
  }

  @override
  String get dating_notOpenRegionBody => 'We\'re opening other regions as soon as we can look after them well.';

  @override
  String get dating_justForMe => 'Use Attune just for me';

  @override
  String get dating_sectionNotStarted => 'Meet a few people a day. Only when it\'s mutual.';

  @override
  String get dating_sectionFinish => 'Finish setting up Dating';

  @override
  String dating_sectionFirstDrop(String date, String time) {
    return 'Your first introductions arrive $date at $time.';
  }

  @override
  String get dating_sectionActive => 'Dating is on. Your introductions will show here.';

  @override
  String get dating_sectionPaused => 'Dating is paused. Nobody new sees you.';

  @override
  String get dating_resume => 'Resume';

  @override
  String get dating_sectionPausedRelationship => 'Dating is paused while you have a shared space on Attune.';

  @override
  String dating_sectionSameGenderNote(String country) {
    return 'Introductions between people of the same gender aren\'t available in $country now. We\'ve removed that choice from your profile.';
  }

  @override
  String get dating_why => 'Why?';

  @override
  String dating_whyBody(String country) {
    return 'In $country, relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know. Until we can protect people properly here, Attune only introduces men and women to each other. Nothing you choose here is stored unless you continue. We\'ll look at this again after legal advice and talking with local groups.';
  }

  @override
  String get dating_close => 'Close';

  @override
  String get dating_chooseAgain => 'Choose again';

  @override
  String get dating_sectionAway => 'Dating is hidden while you\'re away.';

  @override
  String get dating_sectionRestricted => 'Your Dating account is restricted. The rest of Attune works as usual.';

  @override
  String get dating_sectionHold => 'Your Dating profile is paused while we look into something. This isn\'t a decision yet.';

  @override
  String get dating_sectionAgeReview => 'We need to confirm your age before you can use Dating.';

  @override
  String get dating_sectionUnavailable => 'Dating isn\'t available on this account right now.';

  @override
  String get dating_sectionLockedLabel => 'Dating, locked';

  @override
  String get dating_settingsTitle => 'Dating settings';

  @override
  String get dating_settingsNotice => 'Tell me when Dating opens';

  @override
  String get dating_settingsClearReflection => 'Clear my answers to the three questions';

  @override
  String get dating_errorPathNotDating => 'Choose Dating in How you use Attune to carry on.';

  @override
  String get dating_openHowYouUse => 'How you use Attune';

  @override
  String get dating_errorResumeGates => 'Dating can\'t resume on this account right now.';

  @override
  String get dating_errorConsent => 'Agree to Dating\'s terms again to carry on.';

  @override
  String get dating_errorIncomplete => 'Finish setting up Dating first.';

  @override
  String get dating_errorRateLimited => 'You\'ve done this a lot today. Try again tomorrow.';

  @override
  String get dating_region_gh_af => 'Ahafo';

  @override
  String get dating_region_gh_ah => 'Ashanti';

  @override
  String get dating_region_gh_bo => 'Bono';

  @override
  String get dating_region_gh_be => 'Bono East';

  @override
  String get dating_region_gh_cp => 'Central';

  @override
  String get dating_region_gh_ep => 'Eastern';

  @override
  String get dating_region_gh_aa => 'Greater Accra';

  @override
  String get dating_region_gh_ne => 'North East';

  @override
  String get dating_region_gh_np => 'Northern';

  @override
  String get dating_region_gh_ot => 'Oti';

  @override
  String get dating_region_gh_sv => 'Savannah';

  @override
  String get dating_region_gh_ue => 'Upper East';

  @override
  String get dating_region_gh_uw => 'Upper West';

  @override
  String get dating_region_gh_tv => 'Volta';

  @override
  String get dating_region_gh_wp => 'Western';

  @override
  String get dating_region_gh_wn => 'Western North';

  @override
  String get dating_side_gh_accra => 'Accra';

  @override
  String get dating_side_gh_tema => 'Tema and Ashaiman';

  @override
  String get dating_side_gh_kumasi => 'Kumasi';

  @override
  String get dating_side_gh_outside_kumasi => 'Outside Kumasi';

  @override
  String get dating_region_gb_tlc => 'North East';

  @override
  String get dating_region_gb_tld => 'North West';

  @override
  String get dating_region_gb_tle => 'Yorkshire and the Humber';

  @override
  String get dating_region_gb_tlf => 'East Midlands';

  @override
  String get dating_region_gb_tlg => 'West Midlands';

  @override
  String get dating_region_gb_tlh => 'East of England';

  @override
  String get dating_region_gb_tli => 'London';

  @override
  String get dating_region_gb_tlj => 'South East';

  @override
  String get dating_region_gb_tlk => 'South West';

  @override
  String get dating_region_gb_tll => 'Wales';

  @override
  String get dating_region_gb_tlm => 'Scotland';

  @override
  String get dating_region_gb_tln => 'Northern Ireland';

  @override
  String get dating_noticeNotEligible => 'We can\'t set this up on this account.';

  @override
  String get dating_faith_christian => 'Christian';

  @override
  String get dating_faith_muslim => 'Muslim';

  @override
  String get dating_faith_traditional => 'Traditional';

  @override
  String get dating_faith_hindu => 'Hindu';

  @override
  String get dating_faith_sikh => 'Sikh';

  @override
  String get dating_faith_jewish => 'Jewish';

  @override
  String get dating_faith_buddhist => 'Buddhist';

  @override
  String get dating_faith_other => 'Other';

  @override
  String get dating_faith_none => 'None';

  @override
  String get dating_faith_prefer_not_to_say => 'Prefer not to say';

  @override
  String get dating_denomination_catholic => 'Catholic';

  @override
  String get dating_denomination_anglican => 'Anglican';

  @override
  String get dating_denomination_methodist => 'Methodist';

  @override
  String get dating_denomination_presbyterian => 'Presbyterian';

  @override
  String get dating_denomination_pentecostal_charismatic => 'Pentecostal or Charismatic';

  @override
  String get dating_denomination_seventh_day_adventist => 'Seventh-day Adventist';

  @override
  String get dating_denomination_other_christian => 'Other Christian';

  @override
  String get dating_denomination_church_of_england_anglican => 'Church of England or Anglican';

  @override
  String get dating_denomination_orthodox => 'Orthodox';

  @override
  String dating_stepOf(int n, int total) {
    return 'Step $n of $total';
  }

  @override
  String get dating_skip => 'Skip';

  @override
  String get dating_continue => 'Continue';

  @override
  String get dating_notAvailableHere => 'This choice isn\'t available here.';

  @override
  String get dating_contactFilter => 'Contact details can\'t go on your profile. You can swap them in a chat when you\'re both ready.';

  @override
  String get dating_kindnessFilter => 'Please rephrase this so it\'s kind to everyone.';

  @override
  String get dating_countryChangeLimited => 'You can change your Dating country once every 30 days.';

  @override
  String get dating_howTitle => 'How Dating works';

  @override
  String get dating_how1 => 'Up to 3 introductions a day, at a time you choose.';

  @override
  String get dating_how2 => 'Saying \'Interested\' is private. You only match when you\'re both interested.';

  @override
  String get dating_how3 => 'Dating chats are separate from the rest of Attune. Phone numbers stay hidden until you both choose to swap.';

  @override
  String get dating_how4 => 'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.';

  @override
  String get dating_how5 => 'You\'ll add at least 2 photos and answer 2 short questions.';

  @override
  String dating_how6(String date) {
    return 'Your first introductions can arrive from $date.';
  }

  @override
  String dating_how7(String countries) {
    return 'Dating is open in $countries.';
  }

  @override
  String get dating_how8 => 'Setting up uses about 15 MB of data, mostly for the video check.';

  @override
  String get dating_setUpLater => 'Set up later';

  @override
  String get dating_justMeDone => 'You\'re on \'Just for me\'.';

  @override
  String get dating_undo => 'Undo';

  @override
  String get dating_lookingTitle => 'What are you looking for?';

  @override
  String get dating_intentMarriage => 'Marriage';

  @override
  String get dating_intentCommitted => 'A committed relationship';

  @override
  String get dating_intentCompanionship => 'Companionship, at my own pace';

  @override
  String get dating_intentNotSure => 'Not sure yet';

  @override
  String get dating_timelineQ => 'When would you like to marry?';

  @override
  String get dating_timelineSoon => 'In the next year or two';

  @override
  String get dating_timelineFew => 'In a few years';

  @override
  String get dating_timelineNone => 'No set time';

  @override
  String get dating_timelineShow => 'Show this on my profile';

  @override
  String get dating_attestation => 'I\'m not married in any form (customary, religious or civil), I\'m not separated from a spouse, and I\'m not in a relationship.';

  @override
  String get dating_attestationHelper => 'Dating on Attune is for people who are free to start a relationship.';

  @override
  String get dating_attestationError => 'Please confirm you\'re free to start a relationship.';

  @override
  String get dating_separatedLink => 'I\'m separated but not divorced';

  @override
  String get dating_separatedSheet => 'Dating isn\'t open to you yet. Once your divorce is final, you\'re welcome here. Attune just for me is open to you now.';

  @override
  String get dating_marriedBefore => 'Married before? (optional)';

  @override
  String get dating_maritalNever => 'Never';

  @override
  String get dating_maritalDivorced => 'Divorced';

  @override
  String get dating_maritalWidowed => 'Widowed';

  @override
  String get dating_maritalShow => 'Show on my profile';

  @override
  String get dating_whereTitle => 'Where are you?';

  @override
  String get dating_countryLabel => 'Country';

  @override
  String get dating_regionLabel => 'Region';

  @override
  String get dating_countryNotListed => 'My country isn\'t listed';

  @override
  String dating_regionClosed(String regions) {
    return 'Dating is open in $regions for now. We\'re opening other regions as soon as we can look after them well.';
  }

  @override
  String dating_sideLabel(String region) {
    return 'Which side of $region? (optional)';
  }

  @override
  String get dating_sideEither => 'Either side';

  @override
  String get dating_scopeQ => 'How far would you like to meet people?';

  @override
  String get dating_scopeSide => 'My side';

  @override
  String get dating_scopeRegion => 'My region';

  @override
  String dating_scopeCountry(String country) {
    return 'Anywhere in $country';
  }

  @override
  String get dating_abroadRow => 'Also open to people in other countries';

  @override
  String get dating_abroadDisabled => 'Available once you\'re verified and your account is 14 days old.';

  @override
  String get dating_whereHelper => 'We never use your exact location. Others see your region only.';

  @override
  String get dating_search => 'Search';

  @override
  String get dating_choose => 'Choose';

  @override
  String get dating_privacyTitle => 'Your answers stay private';

  @override
  String get dating_privacyWhyHead => 'Why we ask';

  @override
  String get dating_privacyWhoHead => 'Who sees what';

  @override
  String get dating_privacyNeverHead => 'What we never do';

  @override
  String get dating_privacyProtectedHead => 'How it\'s protected';

  @override
  String get dating_privacyLeavingHead => 'Leaving';

  @override
  String get dating_privacyWhy => 'The next questions are about you and who you\'d like to meet. We use your answers only to introduce you to people who\'d like to meet you too.';

  @override
  String get dating_privacyWho => 'Nobody ever sees who you\'d like to meet. Your gender, faith and marriage history appear on your profile only if you choose. We never collect your exact location.';

  @override
  String get dating_privacyNever => 'Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.';

  @override
  String get dating_privacyProtected => 'These answers are stored encrypted. The people who review reports can\'t see them.';

  @override
  String get dating_privacyLeaving => 'You can leave Dating at any time, and these answers are deleted.';

  @override
  String get dating_privacyConsent => 'I agree that Attune can use my answers about my gender and who I\'d like to meet to introduce me.';

  @override
  String get dating_datingTerms => 'Dating terms';

  @override
  String get dating_privacyNotice => 'Privacy notice';

  @override
  String get dating_agreeContinue => 'Agree and continue';

  @override
  String get dating_youTitle => 'Which best describes you?';

  @override
  String get dating_identityWoman => 'Woman';

  @override
  String get dating_identityMan => 'Man';

  @override
  String get dating_identityNonBinary => 'Non-binary';

  @override
  String get dating_moreSpecific => 'Add something more specific';

  @override
  String get dating_specificTransWoman => 'Trans woman';

  @override
  String get dating_specificTransMan => 'Trans man';

  @override
  String get dating_specificGenderfluid => 'Genderfluid';

  @override
  String get dating_specificGenderqueer => 'Genderqueer';

  @override
  String get dating_specificAgender => 'Agender';

  @override
  String get dating_specificIntersex => 'Intersex';

  @override
  String get dating_specificOwnWords => 'In my own words';

  @override
  String get dating_specificInvalid => 'Use letters, spaces and hyphens only, up to 30.';

  @override
  String get dating_nbPoolsQ => 'Should we also introduce you to people looking for:';

  @override
  String get dating_poolWomen => 'Women';

  @override
  String get dating_poolMen => 'Men';

  @override
  String get dating_nbPoolsHelper => 'People open to everyone can always be introduced to you.';

  @override
  String get dating_pronouns => 'Pronouns (optional)';

  @override
  String get dating_genderShow => 'Show my gender on my profile';

  @override
  String get dating_youHelper => 'We use this only to introduce you to people who want to meet someone like you.';

  @override
  String dating_offCountryLine(String country) {
    return 'In $country, Dating introduces men and women to each other for now. If neither of these fits you, Dating can\'t introduce you safely here yet.';
  }

  @override
  String get dating_supportForYou => 'Support for you';

  @override
  String get dating_meetTitle => 'Who would you like to meet?';

  @override
  String get dating_seekMen => 'Men';

  @override
  String get dating_seekWomen => 'Women';

  @override
  String get dating_seekEveryone => 'Everyone';

  @override
  String get dating_meetPrivate => 'Only you can see this. It\'s never on your profile.';

  @override
  String get dating_offMeetMen => 'You\'ll be introduced to men.';

  @override
  String get dating_offMeetWomen => 'You\'ll be introduced to women.';

  @override
  String dating_offMeetLine(String country) {
    return 'In $country, Attune introduces men and women to each other for now.';
  }

  @override
  String dating_ages(int min, int max) {
    return 'Ages $min to $max';
  }

  @override
  String dating_agesYoungest(int age) {
    return 'Youngest $age';
  }

  @override
  String dating_agesOldest(int age) {
    return 'Oldest $age';
  }

  @override
  String get dating_noteTitle => 'Before you save this';

  @override
  String dating_notePhone(String country) {
    return 'Your phone number is from $country, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know.';
  }

  @override
  String get dating_noteThen => 'Attune never shows who you\'d like to meet, never shows distance, and keeps Dating out of your notifications. You can also set a PIN, use a plain app icon, and leave Dating at any time to delete these answers.';

  @override
  String get dating_noteSave => 'Save';

  @override
  String get dating_noteSetPin => 'Set a PIN first';

  @override
  String get dating_noteBack => 'Go back';

  @override
  String get dating_childrenTitle => 'Children';

  @override
  String get dating_childrenHaveQ => 'Do you have children?';

  @override
  String get dating_yes => 'Yes';

  @override
  String get dating_no => 'No';

  @override
  String get dating_childrenWantQ => 'Do you want children (or more children)?';

  @override
  String get dating_openToIt => 'Open to it';

  @override
  String get dating_childrenMustMatch => 'Only introduce me to people whose answer fits mine';

  @override
  String get dating_childrenExcludeParents => 'I\'d rather not meet people who have children';

  @override
  String get dating_childrenHelper => 'We never ask for your children\'s names or ages, and photos with children can\'t be used.';

  @override
  String get dating_faithTitle => 'Faith';

  @override
  String get dating_optional => 'Optional';

  @override
  String get dating_denomination => 'Denomination (optional)';

  @override
  String get dating_importanceQ => 'How much does sharing a faith matter to you?';

  @override
  String get dating_importanceNo => 'It doesn\'t matter';

  @override
  String get dating_importanceNice => 'Nice if we share';

  @override
  String get dating_importanceMust => 'We must share it';

  @override
  String get dating_faithShow => 'Show my faith on my profile';

  @override
  String get dating_faithConsent => 'Faith is sensitive information. I agree that Attune can use it to introduce me.';

  @override
  String get dating_faithConsentError => 'Please agree, or choose Skip.';

  @override
  String get dating_agesYoungestLabel => 'Youngest';

  @override
  String get dating_agesOldestLabel => 'Oldest';

  @override
  String get dating_photosTitle => 'Add your photos';

  @override
  String get dating_photosBody => 'Add 2 to 6 photos. Clear, recent photos of just you work best.';

  @override
  String get dating_photoAdd => 'Add photo';

  @override
  String dating_photoPreparing(int n) {
    return 'Preparing photo $n…';
  }

  @override
  String dating_photoUploading(int n) {
    return 'Uploading photo $n…';
  }

  @override
  String get dating_photoChecking => 'Checking…';

  @override
  String get dating_photoReady => 'Ready';

  @override
  String get dating_photoReview => 'Needs a person to check it. That usually takes less than a day.';

  @override
  String dating_photoFaceUnclear(int n) {
    return 'Photo $n: we couldn\'t see your face clearly.';
  }

  @override
  String dating_photoTooSmall(int n) {
    return 'Photo $n is too small.';
  }

  @override
  String dating_photoChild(int n) {
    return 'Photo $n: photos with children can\'t be used on Dating. Crop to just you?';
  }

  @override
  String get dating_photoCrop => 'Crop';

  @override
  String dating_photoCantUse(int n) {
    return 'Photo $n can\'t be used.';
  }

  @override
  String dating_photoFailed(int n) {
    return 'Photo $n didn\'t upload. Try again.';
  }

  @override
  String dating_photoSlot(int n, String state) {
    return 'Photo $n of 6, $state';
  }

  @override
  String get dating_photoMoveEarlier => 'Move earlier';

  @override
  String get dating_photoMoveLater => 'Move later';

  @override
  String get dating_photoRemove => 'Remove';

  @override
  String get dating_photoReplace => 'Replace';

  @override
  String get dating_photoCaption => 'Add a caption (only you see it)';

  @override
  String get dating_photoCaptionLabel => 'Caption';

  @override
  String get dating_photoSave => 'Save';

  @override
  String get dating_photosAfterMutual => 'Show my photos only after we\'re both interested';

  @override
  String dating_photosAfterMutualFrom(String date) {
    return 'Available from $date. New accounts show their photos for the first 30 days, which helps stop fake profiles.';
  }

  @override
  String get dating_photosData => 'Each photo uses about 300 KB.';

  @override
  String get dating_photosOffline => 'You\'re offline. Add photos when you\'re connected.';

  @override
  String get dating_promptsTitle => 'A little about you';

  @override
  String get dating_promptsBody => 'Answer 2 of these. Short is fine.';

  @override
  String get dating_prompt_perfect_sunday => 'A perfect Sunday for me looks like…';

  @override
  String get dating_prompt_feel_at_home => 'I feel most at home when…';

  @override
  String get dating_prompt_friends_say => 'My friends would say I\'m…';

  @override
  String get dating_prompt_looking_for => 'I\'m looking for someone who…';

  @override
  String get dating_prompt_small_thing => 'A small thing that makes my day…';

  @override
  String get dating_prompt_win_me_over => 'The way to win me over is…';

  @override
  String get dating_prompt_learning_to => 'I\'m learning to…';

  @override
  String get dating_prompt_family_describe => 'My family would describe me as…';

  @override
  String get dating_prompt_place_love => 'A kind of place I love spending time…';

  @override
  String get dating_prompt_ask_me_about => 'Ask me about…';

  @override
  String get dating_promptTooShort => 'At least 10 characters.';

  @override
  String dating_photoPickFailed(int n) {
    return 'Photo $n: your photos couldn\'t be opened. Check that Attune can use them in Settings, then try again.';
  }

  @override
  String dating_photoCropFailed(int n) {
    return 'Photo $n couldn\'t be cropped. Try again.';
  }

  @override
  String get dating_textInvisible => 'Some emoji and symbols can\'t be used here. Try taking them out.';

  @override
  String get dating_promptNeedsWords => 'Add a few words, not just emoji or symbols.';

  @override
  String get dating_verifyTitle => 'Verify it\'s you';

  @override
  String get dating_verifyBody => 'A short video selfie checks that you\'re a real person, that your photos are you, and that you\'re over 18. The video is deleted at once. We keep only whether it passed.';

  @override
  String get dating_verifyLater => 'You\'ll do this check before your first introduction.';

  @override
  String get dating_previewTitle => 'This is what others see';

  @override
  String get dating_previewNever => 'Never shown: who you\'d like to meet, your exact location, your date of birth.';

  @override
  String get dating_previewUnavailable => 'Your preview can\'t be shown right now.';

  @override
  String get dating_tryAgain => 'Try again';

  @override
  String get dating_nameLabel => 'First name';

  @override
  String get dating_nameHelper => 'Use your first name or what friends call you.';

  @override
  String get dating_nameInvalid => 'Use 1 to 30 characters.';

  @override
  String get dating_save => 'Save';

  @override
  String get dating_editName => 'Edit first name';

  @override
  String get dating_editLooking => 'Edit what you\'re looking for';

  @override
  String get dating_editWhere => 'Edit where you are';

  @override
  String get dating_editPrompts => 'Edit your answers';

  @override
  String get dating_editChildren => 'Edit children';

  @override
  String get dating_editAbout => 'Edit what you show about yourself';

  @override
  String get dating_editPhotos => 'Edit photos';

  @override
  String get dating_pushDigest => 'Tell me about new introductions and matches, at most once a day.';

  @override
  String get dating_pushTurnOn => 'Turn on';

  @override
  String get dating_pushDigestOn => 'We\'ll tell you about new introductions and matches, at most once a day.';

  @override
  String get dating_pushMessages => 'Tell me when someone messages me';

  @override
  String dating_cardHeading(String name, int age) {
    return '$name, $age';
  }

  @override
  String get dating_cardMarriage => 'Looking for marriage';

  @override
  String get dating_cardMarriageSoon => 'Looking for marriage, in the next year or two';

  @override
  String get dating_cardMarriageFew => 'Looking for marriage, in a few years';

  @override
  String get dating_cardMarriageNone => 'Looking for marriage, with no set time';

  @override
  String get dating_cardCommitted => 'Looking for a committed relationship';

  @override
  String get dating_cardCompanionship => 'Looking for companionship, at a comfortable pace';

  @override
  String get dating_cardNotSure => 'Not sure yet';

  @override
  String get dating_cardHasChildren => 'Has children';

  @override
  String get dating_cardNoChildren => 'No children';

  @override
  String get dating_cardWantsChildren => 'Wants children';

  @override
  String get dating_cardNoWantChildren => 'Doesn\'t want children';

  @override
  String get dating_cardOpenChildren => 'Open to children';

  @override
  String get dating_cardPhotosLater => 'Photos appear after you\'re both interested.';

  @override
  String get dating_cardShowPhotos => 'Show photos (about 1 MB)';

  @override
  String dating_cardPhoto(int n, int count) {
    return 'Photo $n of $count';
  }

  @override
  String get dating_readyTitle => 'You\'re all set';

  @override
  String dating_readyFirst(String date, String time) {
    return 'Your first introductions arrive $date at $time.';
  }

  @override
  String get dating_readyChangeTime => 'Change time';

  @override
  String get dating_readyTimeTitle => 'Pick a time when you have a few quiet minutes.';

  @override
  String get dating_readyWhile => 'While you wait';

  @override
  String get dating_readyJournal => 'Write in your journal';

  @override
  String get dating_readySharedQ => 'Does anyone else use this phone?';

  @override
  String get dating_readyLock => 'Lock Dating with your PIN';

  @override
  String get dating_readyEveryOpen => 'Ask for my PIN every time Attune opens';

  @override
  String get dating_done => 'Done';

  @override
  String get dating_readyGates => 'We still need to check it\'s you before introductions start.';

  @override
  String get dating_editFaith => 'Edit faith';

  @override
  String get dating_editMarital => 'Edit marital status';

  @override
  String dating_cardPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get dating_settingsTime => 'Introduction time';

  @override
  String get dating_settingsWho => 'Who I\'d like to meet';

  @override
  String get dating_settingsAges => 'Ages';

  @override
  String dating_settingsAgesValue(int min, int max) {
    return '$min to $max';
  }

  @override
  String get dating_settingsHowFar => 'How far';

  @override
  String get dating_settingsPhotosAfter => 'Photos after mutual interest';

  @override
  String get dating_settingsDataSaver => 'Data saver';

  @override
  String get dating_settingsDataSaverSub => 'Show photos only when I tap';

  @override
  String get dating_settingsNotifications => 'Notifications';

  @override
  String get dating_settingsPause => 'Pause Dating';

  @override
  String get dating_pausedLine => 'Dating is paused. Nobody new sees you, and your conversations stay open.';

  @override
  String get dating_settingsResume => 'Resume Dating';

  @override
  String get dating_settingsLeave => 'Leave Dating and delete my data';

  @override
  String get dating_leaveTitle => 'Leave Dating?';

  @override
  String get dating_leaveNow => 'Deleted now: your Dating profile, photos, prompts, who you\'d like to meet, your gender and faith answers, your settings and your private notes.';

  @override
  String get dating_leave30 => 'Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.';

  @override
  String get dating_leaveSafety => 'Kept for safety, for up to 2 years, only if your account is restricted or you\'ve blocked someone: a code made from your phone number, never the number itself.';

  @override
  String get dating_leaveRecord => 'Kept as a record: when you agreed to Dating\'s terms and when you left.';

  @override
  String get dating_leaveKeepList => 'Keep my \'Never introduce me\' list in case I come back. It holds codes, not numbers.';

  @override
  String get dating_leaveConfirm => 'Leave and delete';

  @override
  String get dating_leavePause => 'Pause instead';

  @override
  String get dating_leftDone => 'You\'ve left Dating. You can set it up again any time.';

  @override
  String get dating_leftSuspended => 'You\'ve left Dating.';

  @override
  String dating_photoRemoveQ(int n) {
    return 'Remove photo $n?';
  }

  @override
  String get dating_photoRemoveBody => 'It\'s deleted at once. A photo you add later is checked again before anyone sees it.';

  @override
  String get dating_photoKeep => 'Keep it';
}
