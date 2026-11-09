// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'Votre application innovante';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonLogin => 'Connexion';

  @override
  String get commonLogout => 'Déconnexion';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonAccept => 'Accepter';

  @override
  String get commonReject => 'Rejeter';

  @override
  String get introGetStarted => 'Commencer';

  @override
  String get actionsBlock => 'Bloquer l\'utilisateur';

  @override
  String get actionsReport => 'Signaler l\'utilisateur';

  @override
  String get actionsSend => 'Envoyer au chat';

  @override
  String get actionsShare => 'Partager';

  @override
  String get actionsCopy => 'Copier le lien';

  @override
  String get appInfoVersion => 'Version';

  @override
  String get appInfoReleased => 'Publié';

  @override
  String get appInfoPackageName => 'Nom du Paquet';

  @override
  String get appInfoDeveloper => 'Nom du Développeur';

  @override
  String get appInfoSupportEmail => 'Email de Support';

  @override
  String get appInfoTechnicalDetails => 'Détails Techniques';

  @override
  String get appInfoBundleID => 'ID du Paquet';

  @override
  String get appInfoBuildVersion => 'Version de Compilation';

  @override
  String get appInfoBuildNumber => 'Numéro de Compilation';

  @override
  String get appInfoReleaseDate => 'Date de Publication';

  @override
  String get appInfoAppSize => 'Taille de l\'Application';

  @override
  String appInfoOverview(String appName) {
    return '$appName est une application mobile moderne construite avec une sécurité robuste et une fonctionnalité, conçue pour fournir une expérience utilisateur exceptionnelle avec une architecture propre et une optimisation des performances.';
  }

  @override
  String introTitle(String appName) {
    return 'Bienvenue sur $appName';
  }

  @override
  String get introFeature1Title => 'Voir Votre Progrès';

  @override
  String get introFeature1Description => 'Suivez vos jalons de développement avec des analyses détaillées et des insights';

  @override
  String get introFeature2Title => 'Explorer les Modèles';

  @override
  String get introFeature2Description => 'Découvrez des composants et écrans pré-construits pour un développement rapide';

  @override
  String get introFeature3Title => 'Démarrez Rapidement';

  @override
  String get introFeature3Description => 'Lancez votre projet avec une configuration zéro et les meilleures pratiques';

  @override
  String get appleSignIn => 'Se connecter avec Apple';

  @override
  String get googleSignIn => 'Se connecter avec Google';

  @override
  String get appleRegister => 'S\'inscrire avec Apple';

  @override
  String get googleRegister => 'S\'inscrire avec Google';

  @override
  String get emailAndPassword => 'Entrer e-mail et mot de passe';

  @override
  String get signInTitle => 'Se connecter';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get legalConsentPart1 => 'Veuillez lire les ';

  @override
  String get legalConsentPart2 => 'conditions générales';

  @override
  String legalConsentPart3(String appName) {
    return ' et autres documents juridiques qui régissent votre utilisation de $appName.';
  }

  @override
  String get emailTitle => 'E-mail';

  @override
  String get passwordTitle => 'Mot de passe';

  @override
  String get loginEmailLabel => 'Adresse e-mail';

  @override
  String get loginEmailHint => 'Entrez votre e-mail';

  @override
  String get loginPasswordLabel => 'Mot de passe';

  @override
  String get loginPasswordHint => 'Entrez votre mot de passe';

  @override
  String get loginForgotPasswordPart1 => 'Avez-vous oublié votre mot de passe? ';

  @override
  String get loginForgotPasswordPart2 => 'Appuyez ici';

  @override
  String get loginForgotPasswordPart3 => ' pour réinitialiser votre mot de passe?';

  @override
  String get commonConfirmPasswordLabel => 'Confirmer le mot de passe';

  @override
  String get commonConfirmPasswordHint => 'Veuillez confirmer votre mot de passe';

  @override
  String get commonPasswordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get commonPasswordConfirmRequired => 'Veuillez confirmer votre mot de passe';

  @override
  String commonFieldIsValid(String field) {
    return '$field est valide';
  }

  @override
  String get commonPleaseWait => 'Veuillez patienter jusqu\'à la fin de l\'opération en cours';

  @override
  String get commonUnexpectedError => 'Une erreur inattendue s\'est produite. Veuillez réessayer.';

  @override
  String get commonSomethingWentWrong => 'Quelque chose s\'est mal passé. Veuillez réessayer.';

  @override
  String get commonEnterEmailAndRetry => 'Veuillez entrer votre adresse e-mail et réessayer';

  @override
  String get commonLearnMore => 'En savoir plus';

  @override
  String get authSignUpVerificationSent => 'E-mail de vérification envoyé ! Veuillez vérifier votre boîte de réception.';

  @override
  String authSignUpFailed(String error) {
    return 'Inscription échouée : $error';
  }

  @override
  String get authForgotPasswordTitle => 'Mot de passe oublié ?';

  @override
  String get authForgotPasswordSubtitle => 'Entrez votre e-mail et nous vous enverrons un lien pour réinitialiser votre mot de passe.';

  @override
  String get authSendResetLink => 'Envoyer le lien de réinitialisation';

  @override
  String get authBackToSignIn => 'Retour à la connexion';

  @override
  String get authUsernameScreenTitle => 'Choisissez votre nom d\'utilisateur';

  @override
  String get authUsernameScreenSubtitle => 'C\'est ainsi que les autres vous voient. Vous pouvez le changer plus tard.';

  @override
  String get authUsernameLabel => 'Nom d\'utilisateur';

  @override
  String get authUsernameHint => 'Entrez un nom d\'utilisateur';

  @override
  String authUsernameMinLength(int min) {
    return 'Le nom d\'utilisateur doit comporter au moins $min caractères';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'Le nom d\'utilisateur doit comporter au maximum $max caractères';
  }

  @override
  String get authUsernameFormatError => 'Seules les lettres, les chiffres et les traits de soulignement sont autorisés';

  @override
  String get authUsernameTaken => 'Ce nom d\'utilisateur est déjà pris';

  @override
  String get authUsernameCheckError => 'Impossible de vérifier la disponibilité. Veuillez réessayer.';

  @override
  String get authUsernameSaveError => 'Impossible d\'enregistrer votre nom d\'utilisateur. Veuillez réessayer.';

  @override
  String get authUsernameSavedSuccess => 'Nom d\'utilisateur enregistré avec succès !';

  @override
  String get authUpdatePasswordTitle => 'Créer un nouveau mot de passe';

  @override
  String get authUpdatePasswordButton => 'Mettre à jour le mot de passe';

  @override
  String get authUpdatePasswordSuccess => 'Mot de passe mis à jour avec succès. Veuillez vous reconnecter.';

  @override
  String get authPasswordResetSentTitle => 'Vérifiez votre e-mail';

  @override
  String get authPasswordResetSentBody => 'Nous avons envoyé un lien de réinitialisation de mot de passe à';

  @override
  String get authPasswordResetSentNote => 'Appuyez sur le lien dans l\'e-mail pour définir un nouveau mot de passe. Le lien expire dans 1 heure.';

  @override
  String get authGuestHello => 'Bonjour !';

  @override
  String authGuestOverview(String appName) {
    return 'Vous naviguez sur $appName en tant qu\'invité. Connectez-vous avec votre numéro de téléphone pour commencer votre espace partagé avec votre partenaire – cela ne prend que quelques secondes.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Bienvenue sur\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Bienvenue sur la plateforme que nous avons créée pour vous. Profitez et amusez-vous – le meilleur vous attend.';

  @override
  String get authReadLegalities => 'Lire les mentions légales';

  @override
  String get authPasswordRequired => 'Veuillez entrer votre mot de passe';

  @override
  String get authCreatingAccount => 'Création du compte...';

  @override
  String get authAccountCreatedSuccess => 'Compte créé avec succès !';

  @override
  String get authCheckEmailToConfirm => 'Veuillez vérifier votre e-mail pour confirmer votre compte';

  @override
  String get authSigningInWithGoogle => 'Connexion avec Google...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Échec de la connexion Google : $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Authentification avec Apple...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Échec de la connexion Apple : $error';
  }

  @override
  String get authSendingResetEmail => 'Envoi de l\'e-mail de réinitialisation...';

  @override
  String get authResetEmailSent => 'E-mail de réinitialisation envoyé. Vérifiez votre boîte de réception.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Échec de la réinitialisation du mot de passe : $error';
  }

  @override
  String get authVerifyEmailTitle => 'Vérifiez votre e-mail';

  @override
  String get authVerifyEmailSubtitle => 'Nous avons envoyé un lien de confirmation à';

  @override
  String get authVerifyEmailNote => 'Appuyez sur le lien dans l\'e-mail pour vérifier votre compte et continuer.';

  @override
  String get authConfirmationResent => 'E-mail de confirmation renvoyé. Vérifiez votre boîte de réception.';

  @override
  String get authResendFailed => 'Échec de l\'envoi de l\'e-mail. Veuillez réessayer.';

  @override
  String get authResendEmailButton => 'Renvoyer l\'e-mail de confirmation';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'Renvoyer l\'e-mail (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Sélectionner une devise';

  @override
  String get currencySelectorNoSelected => 'Aucune devise sélectionnée';

  @override
  String get currencySelectorTitle => 'Sélectionner une devise';

  @override
  String get currencySelectorSearchHint => 'Rechercher par devise, code ou drapeau...';

  @override
  String get currencySelectorNoResults => 'Aucune devise trouvée';

  @override
  String get discoverScreenTitle => 'Découvrir';

  @override
  String get discoverSearchHint => 'Rechercher...';

  @override
  String get discoverAllShopsRegion => 'Tous les magasins de votre région';

  @override
  String get discoverAllFreelancers => 'Tous les freelances près de vous';

  @override
  String get discoverMarketplaceTitle => 'Marché';

  @override
  String get discoverMarketplaceSubtitle => 'Achetez des produits de beauté à la livraison à la commande';

  @override
  String get discoverBrowseProducts => 'Parcourir les produits';

  @override
  String get discoverMyOrders => 'Mes commandes';

  @override
  String get discoverCartTooltip => 'Panier';

  @override
  String get homeScheduleTabLabel => 'Calendrier';

  @override
  String get homeDashboardTabLabel => 'Tableau de bord';

  @override
  String get homeMapTabLabel => 'Carte';

  @override
  String get validationRequired => 'Ce champ est obligatoire';

  @override
  String get validationEmailInvalid => 'Veuillez entrer une adresse e-mail valide';

  @override
  String validationPasswordLength(int minLength) {
    return 'Le mot de passe doit comporter au moins $minLength caractères';
  }

  @override
  String get validationPasswordUppercase => 'Le mot de passe doit inclure au moins une lettre majuscule';

  @override
  String get loggingInIndicatorText => 'Connexion en cours...';

  @override
  String get loginSuccessful => 'Connexion réussie !\nBienvenue de retour';

  @override
  String get errorLoginFailed => 'Échec de la connexion. Veuillez vérifier vos identifiants';

  @override
  String get errorNetwork => 'Erreur réseau. Veuillez vérifier votre connexion';

  @override
  String get homeTitle => 'Accueil';

  @override
  String get profileTitle => 'Profil';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Nom';

  @override
  String get editProfileNameFieldLabel => 'Nom complet';

  @override
  String get editProfileUserFieldNameTitle => 'Nom d\'utilisateur';

  @override
  String get editProfileUsernameFieldLabel => '@nomdutilisateur';

  @override
  String get editProfileBioFieldTitle => 'Biographie';

  @override
  String get editProfileBioFieldLabel => 'Parlez-nous de vous';

  @override
  String get editProfileScreenTitle => 'Modifier le profil';

  @override
  String get editProfileSettingTitle => 'Paramètres du compte';

  @override
  String get editProfileSettingSubtitle => 'Gérez votre compte';

  @override
  String get editProfileScreenEditShopTitle => 'Modifier la boutique';

  @override
  String get editProfileScreenEditShopSubtitle => 'Modifiez les informations de votre boutique';

  @override
  String get languageScreenSubtitle => 'Choisissez votre langue préférée pour l\'interface de l\'application. Cela n\'affectera pas les paramètres de votre appareil.';

  @override
  String get languageScreeUseDeviceLang => 'Utiliser la langue de l\'appareil.';

  @override
  String get languageScreeUseDeviceLangNote => 'Cela sera réinitialisé pour correspondre à la langue du système de votre appareil.';

  @override
  String get settingsScreenTitle => 'Paramètres';

  @override
  String get accountSectionTitle => 'Compte';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Profil';

  @override
  String get profileItemSubtitle => 'Gérez vos données personnelles';

  @override
  String get locationItemTitle => 'Changer l\'emplacement';

  @override
  String get locationItemSubtitle => 'Changez votre ville actuelle';

  @override
  String get saveItemTitle => 'Contenus sauvegardés';

  @override
  String get saveItemSubtitle => 'Contenus que vous avez sauvegardés';

  @override
  String get notificationsItemTitle => 'Notifications';

  @override
  String get notificationsItemSubtitle => 'Gérez les notifications push et email';

  @override
  String get blockedItemTitle => 'Comptes bloqués';

  @override
  String get blockedItemSubtitle => 'Comptes que vous avez bloqués';

  @override
  String get mutedItemTitle => 'Comptes en sourdine';

  @override
  String get mutedItemSubtitle => 'Comptes anonymes d\'Opinions que vous avez mis en sourdine';

  @override
  String get qrCodeItemTitle => 'Partager le code QR';

  @override
  String get qrCodeItemSubtitle => 'Partagez votre code QR de compte';

  @override
  String get shareProfileItemTitle => 'Partager le profil';

  @override
  String get shareProfileItemSubtitle => 'Partagez votre profil avec des amis';

  @override
  String get appSettingsSectionTitle => 'Paramètres de l\'application';

  @override
  String get appSettingsSectionSubtitle => 'Personnalisez votre expérience';

  @override
  String get themeItemTitle => 'Thème';

  @override
  String get themeItemSubtitle => 'Clair, Sombre ou Système';

  @override
  String get languageItemTitle => 'Langue';

  @override
  String get languageItemSubtitle => 'Changez la langue de l\'application';

  @override
  String get biometricItemTitle => 'Connexion biométrique';

  @override
  String get biometricItemSubtitle => 'Utilisez Face ID ou Touch ID';

  @override
  String get supportSectionTitle => 'Support';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'Guide d\'utilisation';

  @override
  String get guideItemSubtitle => 'Documentation et tutoriels';

  @override
  String get helpItemTitle => 'Contacter le support';

  @override
  String get helpItemSubtitle => 'Obtenez de l\'aide avec l\'application';

  @override
  String get feedbackItemTitle => 'Envoyer des commentaires';

  @override
  String get feedbackItemSubtitle => 'Partagez vos réflexions';

  @override
  String get rateItemTitle => 'Noter l\'application';

  @override
  String get rateItemSubtitle => 'Laissez un avis';

  @override
  String appInfoItemTitle(String appName) {
    return 'À propos de $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Informations techniques';

  @override
  String get legalSectionTitle => 'Juridique';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Conditions, confidentialité et politiques';

  @override
  String get termsItemSubtitle => 'Lisez nos conditions';

  @override
  String get licensesItemTitle => 'Licences open source';

  @override
  String get licensesItemSubtitle => 'Bibliothèques et licences tierces';

  @override
  String get accountActionsSectionTitle => 'Actions du compte';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Désactiver';

  @override
  String get deactivateItemSubtitle => 'Désactivez votre compte';

  @override
  String get deleteItemTitle => 'Supprimer le compte';

  @override
  String get deleteItemSubtitle => 'Supprimez définitivement votre compte';

  @override
  String get logoutItemTitle => 'Déconnexion';

  @override
  String get logoutItemSubtitle => 'Déconnectez-vous de votre compte';

  @override
  String get loadingDefaultMessage => 'Chargement...';

  @override
  String get emptyStateNoDataTitle => 'Rien ici pour le moment';

  @override
  String get emptyStateNoDataSubtitle => 'Dès qu\'il y aura quelque chose à afficher, cela apparaîtra ici.';

  @override
  String get emptyStateNoResultsTitle => 'Aucune correspondance';

  @override
  String get emptyStateNoResultsSubtitle => 'Essayez un autre mot ou un autre filtre.';

  @override
  String get emptyStateNoInternetTitle => 'Vous êtes hors ligne';

  @override
  String get emptyStateNoInternetSubtitle => 'Vérifiez votre connexion et réessayez.';

  @override
  String get emptyStateNoMessagesTitle => 'Pas encore de messages';

  @override
  String get emptyStateNoMessagesSubtitle => 'Dites bonjour pour commencer votre conversation.';

  @override
  String get emptyStateRefresh => 'Actualiser';

  @override
  String get emptyStateClearFilters => 'Effacer les filtres';

  @override
  String get emptyStateRetry => 'Réessayer';

  @override
  String get emptyStateStartChat => 'Dire bonjour';

  @override
  String get errorNetworkTitle => 'Erreur de connexion';

  @override
  String get errorNetworkSubtitle => 'Impossible de se connecter au serveur. Vérifiez votre connexion internet.';

  @override
  String get errorServerTitle => 'Erreur serveur';

  @override
  String get errorServerSubtitle => 'Quelque chose s\'est mal passé de notre côté. Veuillez réessayer plus tard.';

  @override
  String get errorClientTitle => 'Erreur de requête';

  @override
  String get errorClientSubtitle => 'Il y a eu un problème avec votre requête. Veuillez vérifier et réessayer.';

  @override
  String get errorParsingTitle => 'Erreur de données';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'Impossible de traiter le/la $dataType. Cela pourrait être un problème temporaire.';
  }

  @override
  String get errorPermissionTitle => 'Accès refusé';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'Vous n\'avez pas l\'autorisation d\'accéder à ce/cette $dataType.';
  }

  @override
  String get errorGenericTitle => 'Quelque chose s\'est mal passé';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'Une erreur inattendue s\'est produite lors du chargement de $dataType. Veuillez réessayer.';
  }

  @override
  String get errorRetry => 'Réessayer';

  @override
  String get errorCheckSettings => 'Vérifier les paramètres';

  @override
  String get errorReport => 'Signaler un problème';

  @override
  String get errorGoBack => 'Retour';

  @override
  String get errorRefresh => 'Actualiser';

  @override
  String get errorRequestAccess => 'Demander l\'accès';

  @override
  String get errorContactSupport => 'Contacter le support';

  @override
  String get eulaTitle => 'Contrat de Licence Utilisateur Final';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'Ce Contrat de Licence Utilisateur Final (\"CLUF\") est un accord juridique entre vous et Bars Opus, Ltd. pour $appName.\n\nEn installant, accédant ou utilisant $appName, vous acceptez d\'être lié par les termes de ce CLUF. $appName est licencié, non vendu, à vous pour une utilisation uniquement sous les termes de cette licence. Bars Opus, Ltd. se réserve tous les droits non expressément accordés à vous dans ce CLUF.\n\nVous ne pouvez pas modifier, rétro-concevoir, décompiler ou désassembler $appName. Cette licence est valable jusqu\'à ce qu\'elle soit résiliée par vous ou Bars Opus, Ltd. Vos droits en vertu de cette licence cesseront automatiquement sans préavis si vous ne respectez aucun terme.\n\nTous les droits de propriété intellectuelle sur $appName appartiennent à Bars Opus, Ltd. Ce CLUF est régi par les lois de l\'Angleterre et du Pays de Galles.\n\nPour toute question concernant ce CLUF, veuillez contacter : $supportEmail.';
  }

  @override
  String get eulaFooter => 'En acceptant, vous reconnaissez avoir lu et compris ce Contrat de Licence Utilisateur Final.';

  @override
  String get privacyPolicyTitle => 'Politique de Confidentialité';

  @override
  String privacyPolicyContent(String appName) {
    return 'Cette Politique de Confidentialité explique comment Bars Opus, Ltd. (\"nous\", \"notre\") collecte, utilise et protège vos informations lorsque vous utilisez $appName.\n\nNous collectons les informations que vous fournissez directement, comme lorsque vous créez un compte, complétez votre profil ou contactez le support. Nous collectons automatiquement certaines informations sur votre appareil et la façon dont vous utilisez $appName. Nous utilisons des cookies et des technologies de suivi similaires pour suivre l\'activité et conserver certaines informations.\n\nNous utilisons les informations que nous collectons pour fournir, maintenir et améliorer $appName. Nous pouvons partager vos informations avec des prestataires de services tiers qui effectuent des services en notre nom. Nous pouvons divulguer vos informations si la loi l\'exige ou pour protéger nos droits et notre sécurité.\n\nVous avez le droit d\'accéder, de corriger ou de supprimer vos informations personnelles. Nous mettons en œuvre des mesures techniques et organisationnelles appropriées pour protéger vos informations. Nous pouvons mettre à jour cette Politique de Confidentialité de temps à autre. Nous vous informerons de tout changement.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return 'Politique de Confidentialité de $appName - Dernière mise à jour : $currentDateString';
  }

  @override
  String get termsTitle => 'Conditions d\'Utilisation';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'Ces Conditions d\'Utilisation (\"Conditions\") régissent votre accès et votre utilisation de $appName. En accédant ou en utilisant $appName, vous acceptez d\'être lié par ces Conditions.\n\nVous devez avoir au moins 13 ans pour utiliser $appName. Vous êtes responsable de la sécurité de vos identifiants de compte et de toutes les activités sous votre compte. Vous ne pouvez pas utiliser $appName à des fins illégales ou non autorisées.\n\nNous nous réservons le droit de modifier, suspendre ou interrompre $appName à tout moment. Tout le contenu inclus dans $appName est la propriété de Bars Opus, Ltd. ou de ses concédants de licence.\n\nNous pouvons résilier ou suspendre votre accès à $appName immédiatement si vous violez ces Conditions. Ces Conditions seront régies et interprétées conformément aux lois de l\'Angleterre et du Pays de Galles.\n\nPour toute question concernant ces Conditions, veuillez nous contacter à $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Accord de Partage des Données';

  @override
  String dataSharingContent(String appName) {
    return 'Cet Accord de Partage des Données décrit comment vos informations peuvent être partagées lorsque vous utilisez les fonctionnalités sociales de $appName.\n\nLorsque vous vous connectez avec des amis sur $appName, certaines données d\'activité peuvent leur être visibles. Les données d\'activité partagées peuvent inclure la durée de l\'entraînement, les calories brûlées, les minutes d\'exercice et les badges de réussite. Vos informations de profil (nom d\'affichage et photo de profil) sont visibles pour les amis avec lesquels vous vous connectez.\n\nVotre adresse e-mail et vos informations de contact restent privées et ne sont jamais partagées avec d\'autres utilisateurs. Vous contrôlez quelles données sont partagées via vos paramètres de confidentialité de $appName. Vous pouvez révoquer les autorisations de partage à tout moment dans les paramètres de l\'application.\n\nLes données partagées avec des amis sont chiffrées pendant la transmission et le stockage. Nous conservons les données partagées uniquement aussi longtemps que nécessaire pour fournir la fonctionnalité de partage. Les intégrations tierces peuvent avoir leurs propres pratiques de partage de données, que nous recommandons de consulter.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'Le partage de données dans $appName aide à créer une communauté de soutien tout en respectant vos choix de confidentialité.';
  }

  @override
  String get dashboardTitle => 'Tableau de Bord';

  @override
  String get dashboardSubtitle => 'Gérez les activités de votre boutique efficacement';

  @override
  String get dashboardSectionTitle => 'Tableau de Bord';

  @override
  String get dashboardSectionSubtitle => 'Aperçu des performances et des indicateurs clés de votre boutique';

  @override
  String get dashboardPayoutTitle => 'Demander un Paiement';

  @override
  String get dashboardPayoutContent => 'Les propriétaires de boutique peuvent demander des paiements hebdomadaires. Naviguez vers la section Gains, vérifiez votre solde et soumettez une demande de paiement. Les fonds sont généralement traités dans un délai de 3 à 5 jours ouvrables.';

  @override
  String get dashboardAnalyticsTitle => 'Tableau de Bord Analytique';

  @override
  String get dashboardAnalyticsContent => 'Suivez les performances de votre boutique avec des analyses en temps réel. Surveillez les tendances des ventes, l\'engagement des clients et les niveaux de stock grâce à des graphiques interactifs et des rapports.';

  @override
  String get dashboardScreenshotTitle => 'Vue d\'ensemble du Tableau de Bord';

  @override
  String get dashboardScreenshotContent => 'Le tableau de bord principal offre une vue complète des indicateurs clés de votre boutique, des activités récentes et un accès rapide aux fonctionnalités essentielles.';

  @override
  String get categoryFeatures => 'Fonctionnalités';

  @override
  String get categoryDashboard => 'Tableau de Bord';

  @override
  String get faqDashboard1Question => 'Quand puis-je demander un paiement?';

  @override
  String get faqDashboard1Answer => 'Vous pouvez demander votre paiement une fois par semaine, chaque samedi. La coupure hebdomadaire est le vendredi à 23h59. Les paiements sont traités dans un délai de 3 à 5 jours ouvrables.';

  @override
  String get faqDashboard2Question => 'Où puis-je demander mon paiement?';

  @override
  String get faqDashboard2Answer => 'Naviguez vers votre tableau de bord et cliquez sur la section \'Gains\'. De là, vous verrez votre solde actuel et un bouton \'Demander Paiement\'. Suivez les invites pour compléter votre demande.';

  @override
  String get profileScreenCantChatWithYourself => 'Vous ne pouvez pas discuter avec vous-même';

  @override
  String get profileScreenStartingConversation => 'Démarrage de la conversation...';

  @override
  String get profileScreenNoActiveSession => 'Aucune session active — veuillez vous reconnecter.';

  @override
  String get profileScreenSignInToChatMessage => 'Vous devez vous connecter pour envoyer un message';

  @override
  String get profileScreenFollowFeatureComingSoon => 'La fonction de suivi arrive bientôt';

  @override
  String get profileScreenEnterBioPlaceholder => 'Entrez une biographie pour que les gens vous connaissent';

  @override
  String get profileScreenNoBioYet => 'Pas encore de biographie';

  @override
  String get profileScreenErrorLoadingProfileBody => 'Impossible de charger le profil. Vérifiez votre connexion Internet et réessayez.';

  @override
  String get profileScreenLoadingNotifications => 'Chargement...';

  @override
  String get profileHeaderBookingsStatLabel => 'Réservations';

  @override
  String get profileHeaderOrdersStatLabel => 'Commandes';

  @override
  String get profileHeaderEditProfileButton => 'Modifier le profil';

  @override
  String get profileHeaderMessageButton => 'Message';

  @override
  String get editableProfileAvatarTakePhoto => 'Prendre une photo';

  @override
  String get editableProfileAvatarChooseGallery => 'Choisir dans la galerie';

  @override
  String get editProfileScreenAccountTypeLabel => 'Type de compte';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Sélectionnez comment vous souhaitez utiliser cette application. Cela détermine les fonctionnalités disponibles pour vous.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Mise à jour du type de compte...';

  @override
  String get editProfileScreenPleaseLogIn => 'Veuillez vous connecter';

  @override
  String get editProfileScreenNameLabel => 'Nom';

  @override
  String get editProfileScreenNameHint => 'Entrez votre nom';

  @override
  String get editProfileScreenUsernameLabel => 'Nom d\'utilisateur';

  @override
  String get editProfileScreenUsernameHint => 'Entrez le nom d\'utilisateur';

  @override
  String get editProfileScreenBioLabel => 'Biographie';

  @override
  String get editProfileScreenBioHint => 'Parlez-nous de vous';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Modifier le profil de travail';

  @override
  String get profileTabsAppointments => 'Rendez-vous';

  @override
  String get profileTabsBuys => 'Achats';

  @override
  String get profileTabsSaves => 'Enregistrements';

  @override
  String get searchScreenSearchHint => 'Rechercher des boutiques, des professionnels, des produits...';

  @override
  String get searchScreenNoResultsFound => 'Aucun résultat trouvé';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'Aucun $category trouvé';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Recherché: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Une erreur s\'est produite';

  @override
  String get searchAppBarSearchHint => 'Rechercher...';

  @override
  String get searchSuggestionsHint => 'Recherchez des boutiques, des professionnels de services à domicile ou des produits capillaires à acheter';

  @override
  String get searchSuggestionsRecentSearches => 'Recherches récentes';

  @override
  String get searchSuggestionsClearAll => 'Effacer tout';

  @override
  String get searchEmptyStateNoResults => 'Aucun résultat trouvé';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'Nous n\'avons rien trouvé pour \"$query\"';
  }

  @override
  String get searchEmptyStateTryThese => 'Essayez ceux-ci:';

  @override
  String get searchResultsShopsHeader => 'Boutiques';

  @override
  String get searchResultsSeeAll => 'Voir tout';

  @override
  String searchResultsTitle(String category) {
    return 'Résultats pour $category';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Recherche de \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Essayez des mots-clés différents ou supprimez les filtres';

  @override
  String get searchResultsSomethingWentWrong => 'Une erreur s\'est produite';

  @override
  String nearYouShopsTitle(int km) {
    return 'Près de vous\nà ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Magasins situés à $km km de votre localisation actuelle, affichés du plus proche au plus éloigné. Définissez simplement votre localisation une fois, et nous vous montrerons ce qui est à proximité—que ce soit à la maison, au travail ou en explorant un nouveau quartier. Pratique pour les réservations de dernière minute ou si vous préférez marcher.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'Aucun magasin trouvé à proximité';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'Aucun magasin $luxury trouvé à proximité';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'Les magasins à $location s\'afficheraient ici une fois qu\'ils seront disponibles';
  }

  @override
  String get premiumShopsScreenTitle => 'Magasins Premium';

  @override
  String get premiumShopsEmpty => 'Aucun magasin premium trouvé';

  @override
  String get premiumShopsHorizontalTitle => 'Magasins premium\npour des looks premium';

  @override
  String get premiumShopsHorizontalBody => 'Salons et spas haut de gamme sélectionnés offrant des expériences luxueuses. Ces magasins sont classés comme Luxe ou Ultra-Luxe en fonction de leurs services, tarifs et avis clients. Parfait quand vous recherchez cette touche supplémentaire d\'élégance.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'Aucun magasin premium disponible';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Aucun magasin premium $luxury disponible';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'Les magasins s\'afficheraient ici une fois disponibles';

  @override
  String get topRatedShopsHorizontalTitle => 'Meilleure note';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Meilleure note \nà $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Magasins avec les meilleures notes clients (4,5+ étoiles) et de nombreux avis. Ce sont les favoris de notre communauté—constamment félicités pour la qualité, le service et le professionnalisme. Un excellent point de départ si vous recherchez des options fiables et approuvées par la foule.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'Aucun magasin mieux noté disponible';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Aucun magasin premium $luxury disponible';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'Les magasins s\'afficheraient ici une fois disponibles';

  @override
  String get topRatedShopsScreenTitle => 'Magasins Mieux Notés';

  @override
  String get topRatedShopsEmpty => 'Aucun magasin mieux noté trouvé';

  @override
  String get nearYouFreelancersScreenTitle => 'Freelances près de vous';

  @override
  String get nearYouFreelancersEmpty => 'Aucun freelance trouvé à proximité';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Essayez d\'étendre votre zone de recherche ou changez d\'emplacement';

  @override
  String get topRatedFreelancersScreenTitle => 'Freelances mieux notés';

  @override
  String get topRatedFreelancersEmpty => 'Aucun freelance mieux noté trouvé';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Essayez d\'ajuster votre zone de recherche';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Mieux notés \nà $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Professionnels de haut niveau sélectionnés offrant des expériences luxueuses. Ces freelances sont classés comme mieux notés en fonction de la qualité de leur travail, de leurs tarifs et des avis clients. Parfait pour cette touche supplémentaire d\'excellence.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freelances Près de Vous à $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Professionnels qualifiés situés près de vous. Ces freelances sont disponibles pour des réservations rapides et offrent un service local pratique. Parfait quand vous recherchez la fiabilité et la proximité.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'Aucun freelance mieux noté disponible';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'Les freelances s\'afficheraient ici une fois disponibles';

  @override
  String get shopNoLocationSetTitle => 'Définissez votre localisation pour découvrir';

  @override
  String get shopNoLocationSetContent => 'Définissez votre localisation pour découvrir des magasins premium et mieux notés près de vous.';

  @override
  String get providerTypeShops => 'Magasins';

  @override
  String get providerTypeFreelancers => 'Freelances';

  @override
  String get providerTypeBuy => 'Acheter';

  @override
  String get luxuryLevelChipsAll => 'Tous';

  @override
  String get searchRadiusSliderTitle => 'Rayon d\'exploration';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Affichage des résultats dans un rayon de ${km}km de votre localisation';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'Le mot de passe ne doit pas dépasser $max caractères';
  }

  @override
  String get validationPasswordRepeatingChars => 'Le mot de passe contient trop de caractères répétés';

  @override
  String get validationPasswordSequential => 'Le mot de passe contient des caractères séquentiels';

  @override
  String validationPhoneDigits(int digits) {
    return 'Le numéro de téléphone doit contenir $digits chiffres';
  }

  @override
  String get validationPhoneUK => 'Numéro de téléphone britannique invalide';

  @override
  String validationUrlScheme(String schemes) {
    return 'L\'URL doit commencer par $schemes';
  }

  @override
  String get validationUrlDomain => 'Nom de domaine invalide';

  @override
  String get validationUrlPublicAddress => 'L\'URL doit pointer vers une adresse publique';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field ne doit pas dépasser $max caractères';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field ne peut pas contenir de tirets ou d\'espaces consécutifs';
  }

  @override
  String get validationCreditCardFormat => 'Veuillez entrer un numéro de carte bancaire valide';

  @override
  String get validationCreditCardInvalid => 'Numéro de carte bancaire invalide';

  @override
  String get validationDatePastNotAllowed => 'La date ne peut pas être dans le passé';

  @override
  String get validationPostalCodeZip => 'Veuillez entrer un code postal valide (ex. 12345 ou 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Veuillez entrer un code postal canadien valide (ex. A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Veuillez entrer un code postal valide';

  @override
  String get validationSSNFormat => 'Veuillez entrer un SSN valide (ex. 123-45-6789)';

  @override
  String get validationSSNInvalid => 'SSN invalide';

  @override
  String get validationEmailTooLong => 'L\'adresse e-mail est trop longue (max. 254 caractères)';

  @override
  String get validationEmailLocalPartTooLong => 'La partie locale de l\'adresse e-mail est trop longue';

  @override
  String get categoriesAll => 'Tous';

  @override
  String get categoriesSalon => 'Salons';

  @override
  String get categoriesBarbershop => 'Barbiers';

  @override
  String get categoriesSpa => 'Spas';

  @override
  String get categoriesNailSalon => 'Salons d\'Ongles';

  @override
  String get categoriesLashStudio => 'Studios de Cils';

  @override
  String get categoriesWaxing => 'Épilation';

  @override
  String get categoriesMassage => 'Massage';

  @override
  String get categoriesMakeup => 'Maquillage';

  @override
  String get categoriesSkincare => 'Soins de la Peau';

  @override
  String get luxuryLevelModerate => 'Modéré';

  @override
  String get luxuryLevelLuxury => 'Luxe';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Luxe';

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
