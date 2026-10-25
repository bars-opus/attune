// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'La tua app innovativa';

  @override
  String get commonContinue => 'Continua';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonSave => 'Salva';

  @override
  String get commonLogin => 'Accedi';

  @override
  String get commonLogout => 'Esci';

  @override
  String get commonDone => 'Fatto';

  @override
  String get commonRetry => 'Riprova';

  @override
  String get commonAccept => 'Accetta';

  @override
  String get commonReject => 'Rifiuta';

  @override
  String get introGetStarted => 'Inizia';

  @override
  String get actionsBlock => 'Blocca utente';

  @override
  String get actionsReport => 'Segnala utente';

  @override
  String get actionsSend => 'Invia alla chat';

  @override
  String get actionsShare => 'Condividi';

  @override
  String get actionsCopy => 'Copia link';

  @override
  String get appInfoVersion => 'Versione';

  @override
  String get appInfoReleased => 'Pubblicato';

  @override
  String get appInfoPackageName => 'Nome del Pacchetto';

  @override
  String get appInfoDeveloper => 'Nome dello Sviluppatore';

  @override
  String get appInfoSupportEmail => 'Email di Supporto';

  @override
  String get appInfoTechnicalDetails => 'Dettagli Tecnici';

  @override
  String get appInfoBundleID => 'ID del Pacchetto';

  @override
  String get appInfoBuildVersion => 'Versione di Compilazione';

  @override
  String get appInfoBuildNumber => 'Numero di Compilazione';

  @override
  String get appInfoReleaseDate => 'Data di Rilascio';

  @override
  String get appInfoAppSize => 'Dimensione dell\'App';

  @override
  String appInfoOverview(String appName) {
    return '$appName è un\'applicazione mobile moderna costruita con sicurezza robusta e funzionalità, progettata per fornire un\'esperienza utente eccezionale con un\'architettura pulita e ottimizzazione delle prestazioni.';
  }

  @override
  String introTitle(String appName) {
    return 'Benvenuto su $appName';
  }

  @override
  String get introFeature1Title => 'Vedi il Tuo Progresso';

  @override
  String get introFeature1Description => 'Traccia le tue pietre miliari di sviluppo con analisi dettagliate e approfondimenti';

  @override
  String get introFeature2Title => 'Esplora i Modelli';

  @override
  String get introFeature2Description => 'Scopri componenti e schermate pre-costruiti per uno sviluppo rapido';

  @override
  String get introFeature3Title => 'Inizia Rapidamente';

  @override
  String get introFeature3Description => 'Avvia il tuo progetto con configurazione zero e best practice';

  @override
  String get appleSignIn => 'Accedi con Apple';

  @override
  String get googleSignIn => 'Accedi con Google';

  @override
  String get appleRegister => 'Registrati con Apple';

  @override
  String get googleRegister => 'Registrati con Google';

  @override
  String get emailAndPassword => 'Inserisci email e password';

  @override
  String get signInTitle => 'Accedi';

  @override
  String get createAccount => 'Crea account';

  @override
  String get legalConsentPart1 => 'Si prega di leggere i ';

  @override
  String get legalConsentPart2 => 'termini e condizioni';

  @override
  String legalConsentPart3(String appName) {
    return ' e altri documenti legali che disciplinano il tuo utilizzo di $appName.';
  }

  @override
  String get emailTitle => 'Email';

  @override
  String get passwordTitle => 'Password';

  @override
  String get loginEmailLabel => 'Indirizzo email';

  @override
  String get loginEmailHint => 'Inserisci la tua email';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHint => 'Inserisci la tua password';

  @override
  String get loginForgotPasswordPart1 => 'Hai dimenticato la tua password? ';

  @override
  String get loginForgotPasswordPart2 => 'Tocca qui';

  @override
  String get loginForgotPasswordPart3 => ' per reimpostare la tua password?';

  @override
  String get commonConfirmPasswordLabel => 'Conferma password';

  @override
  String get commonConfirmPasswordHint => 'Conferma la tua password';

  @override
  String get commonPasswordsDoNotMatch => 'Le password non coincidono';

  @override
  String get commonPasswordConfirmRequired => 'Conferma la tua password';

  @override
  String commonFieldIsValid(String field) {
    return '$field è valido';
  }

  @override
  String get commonPleaseWait => 'Attendi il completamento dell\'operazione corrente';

  @override
  String get commonUnexpectedError => 'Si è verificato un errore imprevisto. Per favore riprova.';

  @override
  String get commonSomethingWentWrong => 'Qualcosa è andato storto. Per favore riprova.';

  @override
  String get commonEnterEmailAndRetry => 'Inserisci il tuo indirizzo email e riprova';

  @override
  String get commonLearnMore => 'Scopri di più';

  @override
  String get authSignUpVerificationSent => 'Email di verifica inviata! Controlla la tua posta in arrivo.';

  @override
  String authSignUpFailed(String error) {
    return 'Registrazione fallita: $error';
  }

  @override
  String get authForgotPasswordTitle => 'Password dimenticata?';

  @override
  String get authForgotPasswordSubtitle => 'Inserisci la tua email e ti invieremo un collegamento per ripristinare la tua password.';

  @override
  String get authSendResetLink => 'Invia link di ripristino';

  @override
  String get authBackToSignIn => 'Torna all\'accesso';

  @override
  String get authUsernameScreenTitle => 'Scegli il tuo nome utente';

  @override
  String get authUsernameScreenSubtitle => 'Così è come ti vedono gli altri. Puoi cambiarlo in seguito.';

  @override
  String get authUsernameLabel => 'Nome utente';

  @override
  String get authUsernameHint => 'Inserisci un nome utente';

  @override
  String authUsernameMinLength(int min) {
    return 'Il nome utente deve contenere almeno $min caratteri';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'Il nome utente deve contenere al massimo $max caratteri';
  }

  @override
  String get authUsernameFormatError => 'Sono consentiti solo lettere, numeri e trattini bassi';

  @override
  String get authUsernameTaken => 'Questo nome utente è già stato preso';

  @override
  String get authUsernameCheckError => 'Impossibile controllare la disponibilità. Per favore riprova.';

  @override
  String get authUsernameSaveError => 'Impossibile salvare il tuo nome utente. Per favore riprova.';

  @override
  String get authUsernameSavedSuccess => 'Nome utente salvato con successo!';

  @override
  String get authUpdatePasswordTitle => 'Crea una nuova password';

  @override
  String get authUpdatePasswordButton => 'Aggiorna password';

  @override
  String get authUpdatePasswordSuccess => 'Password aggiornata con successo. Per favore accedi di nuovo.';

  @override
  String get authPasswordResetSentTitle => 'Controlla la tua email';

  @override
  String get authPasswordResetSentBody => 'Abbiamo inviato un collegamento di ripristino password a';

  @override
  String get authPasswordResetSentNote => 'Tocca il collegamento nell\'email per impostare una nuova password. Il collegamento scade in 1 ora.';

  @override
  String get authGuestHello => 'Ciao!';

  @override
  String authGuestOverview(String appName) {
    return 'Stai navigando $appName come ospite. Accedi con il tuo numero di telefono per iniziare il vostro spazio condiviso con il tuo partner – bastano pochi secondi.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Benvenuto in\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Benvenuto sulla piattaforma che abbiamo creato per te. Divertiti – il meglio ti aspetta.';

  @override
  String get authReadLegalities => 'Leggi le informazioni legali';

  @override
  String get authPasswordRequired => 'Per favore inserisci la tua password';

  @override
  String get authCreatingAccount => 'Creazione dell\'account in corso...';

  @override
  String get authAccountCreatedSuccess => 'Account creato con successo!';

  @override
  String get authCheckEmailToConfirm => 'Controlla la tua email per confermare il tuo account';

  @override
  String get authSigningInWithGoogle => 'Accesso con Google...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Accesso Google non riuscito: $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Autenticazione con Apple...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Accesso Apple non riuscito: $error';
  }

  @override
  String get authSendingResetEmail => 'Invio dell\'email di ripristino...';

  @override
  String get authResetEmailSent => 'Email di ripristino inviata. Controlla la tua posta in arrivo.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Ripristino password non riuscito: $error';
  }

  @override
  String get authVerifyEmailTitle => 'Controlla la tua email';

  @override
  String get authVerifyEmailSubtitle => 'Abbiamo inviato un collegamento di conferma a';

  @override
  String get authVerifyEmailNote => 'Tocca il collegamento nell\'email per verificare il tuo account e continuare.';

  @override
  String get authConfirmationResent => 'Email di conferma reinviata. Controlla la tua posta in arrivo.';

  @override
  String get authResendFailed => 'Impossibile inviare l\'email. Per favore riprova.';

  @override
  String get authResendEmailButton => 'Reinvia email di conferma';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'Reinvia email (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Seleziona valuta';

  @override
  String get currencySelectorNoSelected => 'Nessuna valuta selezionata';

  @override
  String get currencySelectorTitle => 'Seleziona valuta';

  @override
  String get currencySelectorSearchHint => 'Cerca per valuta, codice o bandiera...';

  @override
  String get currencySelectorNoResults => 'Nessuna valuta trovata';

  @override
  String get discoverScreenTitle => 'Scopri';

  @override
  String get discoverSearchHint => 'Cerca...';

  @override
  String get discoverAllShopsRegion => 'Tutti i negozi nella tua regione';

  @override
  String get discoverAllFreelancers => 'Tutti i freelance vicino a te';

  @override
  String get discoverMarketplaceTitle => 'Mercato';

  @override
  String get discoverMarketplaceSubtitle => 'Acquista prodotti di bellezza con consegna alla ricezione';

  @override
  String get discoverBrowseProducts => 'Sfoglia prodotti';

  @override
  String get discoverMyOrders => 'I miei ordini';

  @override
  String get discoverCartTooltip => 'Carrello';

  @override
  String get homeScheduleTabLabel => 'Calendario';

  @override
  String get homeDashboardTabLabel => 'Pannello di controllo';

  @override
  String get homeMapTabLabel => 'Mappa';

  @override
  String get validationRequired => 'Questo campo è obbligatorio';

  @override
  String get validationEmailInvalid => 'Inserisci un indirizzo email valido';

  @override
  String validationPasswordLength(int minLength) {
    return 'La password deve contenere almeno $minLength caratteri';
  }

  @override
  String get validationPasswordUppercase => 'La password deve includere almeno una lettera maiuscola';

  @override
  String get loggingInIndicatorText => 'Accesso in corso...';

  @override
  String get loginSuccessful => 'Accesso riuscito!\nBentornato';

  @override
  String get errorLoginFailed => 'Accesso fallito. Controlla le tue credenziali';

  @override
  String get errorNetwork => 'Errore di rete. Controlla la tua connessione';

  @override
  String get homeTitle => 'Home';

  @override
  String get profileTitle => 'Profilo';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Nome';

  @override
  String get editProfileNameFieldLabel => 'Nome completo';

  @override
  String get editProfileUserFieldNameTitle => 'Nome utente';

  @override
  String get editProfileUsernameFieldLabel => '@nomeutente';

  @override
  String get editProfileBioFieldTitle => 'Biografia';

  @override
  String get editProfileBioFieldLabel => 'Raccontaci di te';

  @override
  String get editProfileScreenTitle => 'Modifica profilo';

  @override
  String get editProfileSettingTitle => 'Impostazioni account';

  @override
  String get editProfileSettingSubtitle => 'Gestisci il tuo account';

  @override
  String get editProfileScreenEditShopTitle => 'Modifica Negozio';

  @override
  String get editProfileScreenEditShopSubtitle => 'Modifica le informazioni del tuo negozio';

  @override
  String get languageScreenSubtitle => 'Scegli la tua lingua preferita per l\'interfaccia dell\'app. Questo non influirà sulle impostazioni del tuo dispositivo.';

  @override
  String get languageScreeUseDeviceLang => 'Usa la lingua del dispositivo.';

  @override
  String get languageScreeUseDeviceLangNote => 'Questo verrà reimpostato per corrispondere alla lingua del sistema del tuo dispositivo.';

  @override
  String get settingsScreenTitle => 'Impostazioni';

  @override
  String get accountSectionTitle => 'Account';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Profilo';

  @override
  String get profileItemSubtitle => 'Gestisci i tuoi dati personali';

  @override
  String get locationItemTitle => 'Cambia Posizione';

  @override
  String get locationItemSubtitle => 'Cambia la tua città attuale';

  @override
  String get saveItemTitle => 'Contenuti Salvati';

  @override
  String get saveItemSubtitle => 'Contenuti che hai salvato';

  @override
  String get notificationsItemTitle => 'Notifiche';

  @override
  String get notificationsItemSubtitle => 'Gestisci notifiche push e email';

  @override
  String get blockedItemTitle => 'Account Bloccati';

  @override
  String get blockedItemSubtitle => 'Account che hai bloccato';

  @override
  String get mutedItemTitle => 'Account Silenziati';

  @override
  String get mutedItemSubtitle => 'Account anonimi di Opinions che hai silenziato';

  @override
  String get qrCodeItemTitle => 'Condividi Codice QR';

  @override
  String get qrCodeItemSubtitle => 'Condividi il tuo codice QR dell\'account';

  @override
  String get shareProfileItemTitle => 'Condividi Profilo';

  @override
  String get shareProfileItemSubtitle => 'Condividi il tuo profilo con gli amici';

  @override
  String get appSettingsSectionTitle => 'Impostazioni App';

  @override
  String get appSettingsSectionSubtitle => 'Personalizza la tua esperienza';

  @override
  String get themeItemTitle => 'Tema';

  @override
  String get themeItemSubtitle => 'Chiaro, Scuro o Sistema';

  @override
  String get languageItemTitle => 'Lingua';

  @override
  String get languageItemSubtitle => 'Cambia la lingua dell\'app';

  @override
  String get biometricItemTitle => 'Accesso Biometrico';

  @override
  String get biometricItemSubtitle => 'Usa Face ID o Touch ID';

  @override
  String get supportSectionTitle => 'Supporto';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'Guida Utente';

  @override
  String get guideItemSubtitle => 'Documentazione e tutorial';

  @override
  String get helpItemTitle => 'Contatta Supporto';

  @override
  String get helpItemSubtitle => 'Ottieni aiuto con l\'app';

  @override
  String get feedbackItemTitle => 'Invia Feedback';

  @override
  String get feedbackItemSubtitle => 'Condividi i tuoi pensieri';

  @override
  String get rateItemTitle => 'Valuta l\'App';

  @override
  String get rateItemSubtitle => 'Lascia una recensione';

  @override
  String appInfoItemTitle(String appName) {
    return 'Informazioni su $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Informazioni tecniche';

  @override
  String get legalSectionTitle => 'Legale';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Termini, Privacy e Politiche';

  @override
  String get termsItemSubtitle => 'Leggi i nostri termini';

  @override
  String get licensesItemTitle => 'Licenze Open Source';

  @override
  String get licensesItemSubtitle => 'Librerie e licenze di terze parti';

  @override
  String get accountActionsSectionTitle => 'Azioni Account';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Disattiva';

  @override
  String get deactivateItemSubtitle => 'Disattiva il tuo account';

  @override
  String get deleteItemTitle => 'Elimina Account';

  @override
  String get deleteItemSubtitle => 'Rimuovi permanentemente il tuo account';

  @override
  String get logoutItemTitle => 'Esci';

  @override
  String get logoutItemSubtitle => 'Esci dal tuo account';

  @override
  String get loadingDefaultMessage => 'Caricamento...';

  @override
  String get emptyStateNoDataTitle => 'Ancora niente qui';

  @override
  String get emptyStateNoDataSubtitle => 'Quando ci sarà qualcosa da mostrare, apparirà qui.';

  @override
  String get emptyStateNoResultsTitle => 'Nessuna corrispondenza';

  @override
  String get emptyStateNoResultsSubtitle => 'Prova con un\'altra parola o un altro filtro.';

  @override
  String get emptyStateNoInternetTitle => 'Sei offline';

  @override
  String get emptyStateNoInternetSubtitle => 'Controlla la tua connessione e riprova.';

  @override
  String get emptyStateNoMessagesTitle => 'Ancora nessun messaggio';

  @override
  String get emptyStateNoMessagesSubtitle => 'Saluta per iniziare la vostra conversazione.';

  @override
  String get emptyStateRefresh => 'Aggiorna';

  @override
  String get emptyStateClearFilters => 'Cancella filtri';

  @override
  String get emptyStateRetry => 'Riprova';

  @override
  String get emptyStateStartChat => 'Saluta';

  @override
  String get errorNetworkTitle => 'Errore di connessione';

  @override
  String get errorNetworkSubtitle => 'Impossibile connettersi al server. Controlla la tua connessione internet.';

  @override
  String get errorServerTitle => 'Errore del server';

  @override
  String get errorServerSubtitle => 'Qualcosa è andato storto dalla nostra parte. Per favore, riprova più tardi.';

  @override
  String get errorClientTitle => 'Errore della richiesta';

  @override
  String get errorClientSubtitle => 'C\'è stato un problema con la tua richiesta. Per favore, controlla e riprova.';

  @override
  String get errorParsingTitle => 'Errore dati';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'Impossibile elaborare il/la $dataType. Potrebbe essere un problema temporaneo.';
  }

  @override
  String get errorPermissionTitle => 'Accesso negato';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'Non hai il permesso di accedere a questo/questa $dataType.';
  }

  @override
  String get errorGenericTitle => 'Qualcosa è andato storto';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'Si è verificato un errore imprevisto durante il caricamento di $dataType. Per favore, riprova.';
  }

  @override
  String get errorRetry => 'Riprova';

  @override
  String get errorCheckSettings => 'Controlla impostazioni';

  @override
  String get errorReport => 'Segnala problema';

  @override
  String get errorGoBack => 'Indietro';

  @override
  String get errorRefresh => 'Aggiorna';

  @override
  String get errorRequestAccess => 'Richiedi accesso';

  @override
  String get errorContactSupport => 'Contatta supporto';

  @override
  String get eulaTitle => 'Contratto di Licenza per l\'Utente Finale';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'Questo Contratto di Licenza per l\'Utente Finale (\"EULA\") è un accordo legale tra te e Bars Opus, Ltd. per $appName.\n\nInstallando, accedendo o utilizzando $appName, accetti di essere vincolato dai termini di questo EULA. $appName è concesso in licenza, non venduto, per il tuo uso solo sotto i termini di questa licenza. Bars Opus, Ltd. si riserva tutti i diritti non espressamente concessi a te in questo EULA.\n\nNon puoi modificare, eseguire ingegneria inversa, decompilare o smontare $appName. Questa licenza è valida fino alla risoluzione da parte tua o di Bars Opus, Ltd. I tuoi diritti ai sensi di questa licenza termineranno automaticamente senza preavviso se non rispetti qualsiasi termine.\n\nTutti i diritti di proprietà intellettuale su $appName sono di proprietà di Bars Opus, Ltd. Questo EULA è regolato dalle leggi dell\'Inghilterra e del Galles.\n\nPer domande su questo EULA, si prega di contattare: $supportEmail.';
  }

  @override
  String get eulaFooter => 'Accettando, riconosci di aver letto e compreso questo Contratto di Licenza per l\'Utente Finale.';

  @override
  String get privacyPolicyTitle => 'Informativa sulla Privacy';

  @override
  String privacyPolicyContent(String appName) {
    return 'Questa Informativa sulla Privacy spiega come Bars Opus, Ltd. (\"noi\", \"nostro\") raccoglie, utilizza e protegge le tue informazioni quando utilizzi $appName.\n\nRaccogliamo le informazioni che fornisci direttamente, come quando crei un account, completi il tuo profilo o contatti il supporto. Raccogliamo automaticamente alcune informazioni sul tuo dispositivo e su come utilizzi $appName. Utilizziamo cookie e tecnologie di tracciamento simili per tracciare l\'attività e conservare determinate informazioni.\n\nUtilizziamo le informazioni che raccogliamo per fornire, mantenere e migliorare $appName. Possiamo condividere le tue informazioni con fornitori di servizi di terze parti che svolgono servizi per nostro conto. Possiamo divulgare le tue informazioni se richiesto dalla legge o per proteggere i nostri diritti e la nostra sicurezza.\n\nHai il diritto di accedere, correggere o cancellare le tue informazioni personali. Implementiamo misure tecniche e organizzative appropriate per proteggere le tue informazioni. Possiamo aggiornare questa Informativa sulla Privacy di volta in volta. Ti informeremo di eventuali modifiche.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return 'Informativa sulla Privacy di $appName - Ultimo aggiornamento: $currentDateString';
  }

  @override
  String get termsTitle => 'Termini di Servizio';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'Questi Termini di Servizio (\"Termini\") disciplinano il tuo accesso e utilizzo di $appName. Accedendo o utilizzando $appName, accetti di essere vincolato da questi Termini.\n\nDevi avere almeno 13 anni per utilizzare $appName. Sei responsabile della protezione delle tue credenziali dell\'account e di tutte le attività sotto il tuo account. Non puoi utilizzare $appName per scopi illegali o non autorizzati.\n\nCi riserviamo il diritto di modificare, sospendere o interrompere $appName in qualsiasi momento. Tutti i contenuti inclusi in $appName sono di proprietà di Bars Opus, Ltd. o dei suoi licenzianti.\n\nPossiamo terminare o sospendere il tuo accesso a $appName immediatamente se violi questi Termini. Questi Termini saranno regolati e interpretati in conformità con le leggi dell\'Inghilterra e del Galles.\n\nPer qualsiasi domanda su questi Termini, contattaci a $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Accordo di Condivisione Dati';

  @override
  String dataSharingContent(String appName) {
    return 'Questo Accordo di Condivisione Dati descrive come le tue informazioni possono essere condivise quando utilizzi le funzionalità social di $appName.\n\nQuando ti connetti con amici su $appName, alcuni dati di attività possono essere visibili a loro. I dati di attività condivisi possono includere durata dell\'allenamento, calorie bruciate, minuti di esercizio e badge di risultati. Le informazioni del tuo profilo (nome visualizzato e immagine del profilo) sono visibili agli amici con cui ti connetti.\n\nIl tuo indirizzo email e le informazioni di contatto rimangono private e non sono mai condivise con altri utenti. Controlli quali dati sono condivisi attraverso le impostazioni sulla privacy di $appName. Puoi revocare le autorizzazioni di condivisione in qualsiasi momento nelle impostazioni dell\'app.\n\nI dati condivisi con gli amici sono crittografati durante la trasmissione e lo storage. Conserviamo i dati condivisi solo per il tempo necessario per fornire la funzionalità di condivisione. Le integrazioni di terze parti possono avere le proprie pratiche di condivisione dei dati, che consigliamo di rivedere.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'La condivisione dei dati in $appName aiuta a creare una comunità di supporto rispettando le tue scelte sulla privacy.';
  }

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardSubtitle => 'Gestisci le attività del tuo negozio in modo efficiente';

  @override
  String get dashboardSectionTitle => 'Dashboard';

  @override
  String get dashboardSectionSubtitle => 'Panoramica delle prestazioni e delle metriche chiave del tuo negozio';

  @override
  String get dashboardPayoutTitle => 'Richiedi Pagamento';

  @override
  String get dashboardPayoutContent => 'I proprietari di negozi possono richiedere pagamenti settimanali. Naviga alla sezione Guadagni, rivedi il tuo saldo e invia una richiesta di pagamento. I fondi vengono generalmente elaborati entro 3-5 giorni lavorativi.';

  @override
  String get dashboardAnalyticsTitle => 'Dashboard Analitica';

  @override
  String get dashboardAnalyticsContent => 'Traccia le prestazioni del tuo negozio con analisi in tempo reale. Monitora le tendenze delle vendite, l\'impegno dei clienti e i livelli di inventario tramite grafici interattivi e report.';

  @override
  String get dashboardScreenshotTitle => 'Panoramica Dashboard';

  @override
  String get dashboardScreenshotContent => 'La dashboard principale fornisce una visione completa delle metriche chiave del tuo negozio, delle attività recenti e di un accesso rapido alle funzionalità essenziali.';

  @override
  String get categoryFeatures => 'Caratteristiche';

  @override
  String get categoryDashboard => 'Dashboard';

  @override
  String get faqDashboard1Question => 'Quando posso richiedere un pagamento?';

  @override
  String get faqDashboard1Answer => 'Puoi richiedere il tuo pagamento una volta alla settimana, ogni sabato. Il taglio settimanale è venerdì alle 23:59. I pagamenti vengono elaborati entro 3-5 giorni lavorativi.';

  @override
  String get faqDashboard2Question => 'Dove posso richiedere il mio pagamento?';

  @override
  String get faqDashboard2Answer => 'Naviga nella tua dashboard e fai clic sulla sezione \'Guadagni\'. Da lì vedrai il tuo saldo attuale e un pulsante \'Richiedi Pagamento\'. Segui le istruzioni per completare la tua richiesta.';

  @override
  String get profileScreenCantChatWithYourself => 'Non puoi chattare con te stesso';

  @override
  String get profileScreenStartingConversation => 'Avvio della conversazione...';

  @override
  String get profileScreenNoActiveSession => 'Nessuna sessione attiva — accedi di nuovo.';

  @override
  String get profileScreenSignInToChatMessage => 'Devi accedere per inviare un messaggio';

  @override
  String get profileScreenFollowFeatureComingSoon => 'La funzione di follow arriva presto';

  @override
  String get profileScreenEnterBioPlaceholder => 'Inserisci una biografia in modo che le persone ti conoscano';

  @override
  String get profileScreenNoBioYet => 'Nessuna biografia ancora';

  @override
  String get profileScreenErrorLoadingProfileBody => 'Impossibile caricare il profilo. Controlla la tua connessione Internet e riprova.';

  @override
  String get profileScreenLoadingNotifications => 'Caricamento...';

  @override
  String get profileHeaderBookingsStatLabel => 'Prenotazioni';

  @override
  String get profileHeaderOrdersStatLabel => 'Ordini';

  @override
  String get profileHeaderEditProfileButton => 'Modifica profilo';

  @override
  String get profileHeaderMessageButton => 'Messaggio';

  @override
  String get editableProfileAvatarTakePhoto => 'Scatta una foto';

  @override
  String get editableProfileAvatarChooseGallery => 'Scegli dalla galleria';

  @override
  String get editProfileScreenAccountTypeLabel => 'Tipo di account';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Seleziona come desideri utilizzare questa app. Questo determina quali funzionalità sono disponibili per te.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Aggiornamento del tipo di account...';

  @override
  String get editProfileScreenPleaseLogIn => 'Accedi per favore';

  @override
  String get editProfileScreenNameLabel => 'Nome';

  @override
  String get editProfileScreenNameHint => 'Inserisci il tuo nome';

  @override
  String get editProfileScreenUsernameLabel => 'Nome utente';

  @override
  String get editProfileScreenUsernameHint => 'Inserisci il nome utente';

  @override
  String get editProfileScreenBioLabel => 'Biografia';

  @override
  String get editProfileScreenBioHint => 'Raccontaci qualcosa su di te';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Modifica profilo di lavoro';

  @override
  String get profileTabsAppointments => 'Appuntamenti';

  @override
  String get profileTabsBuys => 'Acquisti';

  @override
  String get profileTabsSaves => 'Salvataggi';

  @override
  String get searchScreenSearchHint => 'Cerca negozi, professionisti, prodotti...';

  @override
  String get searchScreenNoResultsFound => 'Nessun risultato trovato';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'Nessun $category trovato';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Ricercato: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Qualcosa è andato storto';

  @override
  String get searchAppBarSearchHint => 'Cerca...';

  @override
  String get searchSuggestionsHint => 'Cerca negozi, professionisti di servizi a domicilio o prodotti per capelli da acquistare';

  @override
  String get searchSuggestionsRecentSearches => 'Ricerche recenti';

  @override
  String get searchSuggestionsClearAll => 'Cancella tutto';

  @override
  String get searchEmptyStateNoResults => 'Nessun risultato trovato';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'Non abbiamo trovato nulla per \"$query\"';
  }

  @override
  String get searchEmptyStateTryThese => 'Prova questi:';

  @override
  String get searchResultsShopsHeader => 'Negozi';

  @override
  String get searchResultsSeeAll => 'Vedi tutto';

  @override
  String searchResultsTitle(String category) {
    return 'Risultati di $category';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Ricerca di \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Prova parole chiave diverse o rimuovi i filtri';

  @override
  String get searchResultsSomethingWentWrong => 'Qualcosa è andato storto';

  @override
  String nearYouShopsTitle(int km) {
    return 'Vicino a te\nentro ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Negozi situati entro $km km dalla tua posizione attuale, mostrati dal più vicino al più lontano. Semplicemente imposta la tua posizione una volta, e ti mostreremo cosa c\'è vicino—sia che tu sia a casa, al lavoro o che stia esplorando un nuovo quartiere. Utile per prenotazioni last-minute o quando preferisci camminare.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'Nessun negozio trovato nelle vicinanze';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'Nessun negozio $luxury trovato nelle vicinanze';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'I negozi a $location verranno mostrati qui una volta che saranno disponibili';
  }

  @override
  String get premiumShopsScreenTitle => 'Negozi Premium';

  @override
  String get premiumShopsEmpty => 'Nessun negozio premium trovato';

  @override
  String get premiumShopsHorizontalTitle => 'Negozi premium\nper look premium';

  @override
  String get premiumShopsHorizontalBody => 'Saloni e spa di lusso selezionati che offrono esperienze lussuose. Questi negozi sono classificati come Lusso o Ultra-Lusso in base ai loro servizi, prezzi e recensioni dei clienti. Perfetto quando cerchi quel tocco extra di eleganza.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'Nessun negozio premium disponibile';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Nessun negozio premium $luxury disponibile';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'I negozi verranno mostrati qui una volta disponibili';

  @override
  String get topRatedShopsHorizontalTitle => 'Meglio valutati';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Meglio valutati \na $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Negozi con le valutazioni più alte dei clienti (4,5+ stelle) e molte recensioni. Questi sono i preferiti della nostra comunità—costantemente elogiati per qualità, servizio e professionalità. Un ottimo punto di partenza se cerchi opzioni affidabili e approvate dalla folla.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'Nessun negozio meglio valutato disponibile';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Nessun negozio premium $luxury disponibile';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'I negozi verranno mostrati qui una volta disponibili';

  @override
  String get topRatedShopsScreenTitle => 'Negozi Meglio Valutati';

  @override
  String get topRatedShopsEmpty => 'Nessun negozio meglio valutato trovato';

  @override
  String get nearYouFreelancersScreenTitle => 'Freelancer vicino a te';

  @override
  String get nearYouFreelancersEmpty => 'Nessun freelancer trovato nelle vicinanze';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Prova ad espandere la tua area di ricerca o cambia posizione';

  @override
  String get topRatedFreelancersScreenTitle => 'Freelancer meglio valutati';

  @override
  String get topRatedFreelancersEmpty => 'Nessun freelancer meglio valutato trovato';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Prova ad adattare la tua area di ricerca';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Meglio valutati \na $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Professionisti di alto livello selezionati che offrono esperienze lussuose. Questi freelancer sono classificati come meglio valutati in base alla qualità del loro lavoro, prezzi e recensioni dei clienti. Perfetto per quel tocco extra di eccellenza.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freelancer Vicino a Te a $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Professionisti qualificati ubicati vicino a te. Questi freelancer sono disponibili per prenotazioni rapide e offrono servizio locale conveniente. Perfetto quando cerchi affidabilità e prossimità.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'Nessun freelancer meglio valutato disponibile';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'I freelancer verranno mostrati qui una volta disponibili';

  @override
  String get shopNoLocationSetTitle => 'Imposta la tua posizione per scoprire';

  @override
  String get shopNoLocationSetContent => 'Imposta la tua posizione per scoprire negozi premium e ben valutati vicino a te.';

  @override
  String get providerTypeShops => 'Negozi';

  @override
  String get providerTypeFreelancers => 'Freelancer';

  @override
  String get providerTypeBuy => 'Acquista';

  @override
  String get luxuryLevelChipsAll => 'Tutti';

  @override
  String get searchRadiusSliderTitle => 'Raggio di esplorazione';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Visualizzazione risultati entro ${km}km dalla tua posizione';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'La password non deve superare $max caratteri';
  }

  @override
  String get validationPasswordRepeatingChars => 'La password contiene troppi caratteri ripetuti';

  @override
  String get validationPasswordSequential => 'La password contiene caratteri sequenziali';

  @override
  String validationPhoneDigits(int digits) {
    return 'Il numero di telefono deve contenere $digits cifre';
  }

  @override
  String get validationPhoneUK => 'Numero di telefono britannico non valido';

  @override
  String validationUrlScheme(String schemes) {
    return 'L\'URL deve iniziare con $schemes';
  }

  @override
  String get validationUrlDomain => 'Nome di dominio non valido';

  @override
  String get validationUrlPublicAddress => 'L\'URL deve puntare a un indirizzo pubblico';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field non deve superare $max caratteri';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field non può contenere trattini o spazi consecutivi';
  }

  @override
  String get validationCreditCardFormat => 'Per favore inserisci un numero di carta di credito valido';

  @override
  String get validationCreditCardInvalid => 'Numero di carta di credito non valido';

  @override
  String get validationDatePastNotAllowed => 'La data non può essere nel passato';

  @override
  String get validationPostalCodeZip => 'Per favore inserisci un codice postale valido (es. 12345 o 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Per favore inserisci un codice postale canadese valido (es. A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Per favore inserisci un codice postale valido';

  @override
  String get validationSSNFormat => 'Per favore inserisci un SSN valido (es. 123-45-6789)';

  @override
  String get validationSSNInvalid => 'SSN non valido';

  @override
  String get validationEmailTooLong => 'L\'indirizzo email è troppo lungo (max. 254 caratteri)';

  @override
  String get validationEmailLocalPartTooLong => 'La parte locale dell\'indirizzo email è troppo lunga';

  @override
  String get categoriesAll => 'Tutti';

  @override
  String get categoriesSalon => 'Saloni';

  @override
  String get categoriesBarbershop => 'Barberie';

  @override
  String get categoriesSpa => 'Spa';

  @override
  String get categoriesNailSalon => 'Saloni per Unghie';

  @override
  String get categoriesLashStudio => 'Studi di Ciglia';

  @override
  String get categoriesWaxing => 'Depilazione';

  @override
  String get categoriesMassage => 'Massaggio';

  @override
  String get categoriesMakeup => 'Trucco';

  @override
  String get categoriesSkincare => 'Cura della Pelle';

  @override
  String get luxuryLevelModerate => 'Moderato';

  @override
  String get luxuryLevelLuxury => 'Lusso';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Lusso';

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
}
