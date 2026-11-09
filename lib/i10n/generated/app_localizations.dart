import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('pt')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Nano Embryo'**
  String get appName;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Your innovative app'**
  String get appDescription;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get commonLogin;

  /// No description provided for @commonLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get commonLogout;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get commonAccept;

  /// No description provided for @commonReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get commonReject;

  /// No description provided for @introGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get introGetStarted;

  /// No description provided for @actionsBlock.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get actionsBlock;

  /// No description provided for @actionsReport.
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get actionsReport;

  /// No description provided for @actionsSend.
  ///
  /// In en, this message translates to:
  /// **'Send to chat'**
  String get actionsSend;

  /// No description provided for @actionsShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionsShare;

  /// No description provided for @actionsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get actionsCopy;

  /// No description provided for @appInfoVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get appInfoVersion;

  /// No description provided for @appInfoReleased.
  ///
  /// In en, this message translates to:
  /// **'Released'**
  String get appInfoReleased;

  /// No description provided for @appInfoPackageName.
  ///
  /// In en, this message translates to:
  /// **'Package Name'**
  String get appInfoPackageName;

  /// No description provided for @appInfoDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer Name'**
  String get appInfoDeveloper;

  /// No description provided for @appInfoSupportEmail.
  ///
  /// In en, this message translates to:
  /// **'Support Email'**
  String get appInfoSupportEmail;

  /// No description provided for @appInfoTechnicalDetails.
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get appInfoTechnicalDetails;

  /// No description provided for @appInfoBundleID.
  ///
  /// In en, this message translates to:
  /// **'Bundle ID'**
  String get appInfoBundleID;

  /// No description provided for @appInfoBuildVersion.
  ///
  /// In en, this message translates to:
  /// **'Build Version'**
  String get appInfoBuildVersion;

  /// No description provided for @appInfoBuildNumber.
  ///
  /// In en, this message translates to:
  /// **'Build Number'**
  String get appInfoBuildNumber;

  /// No description provided for @appInfoReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get appInfoReleaseDate;

  /// No description provided for @appInfoAppSize.
  ///
  /// In en, this message translates to:
  /// **'App Size'**
  String get appInfoAppSize;

  /// App overview description with dynamic app name
  ///
  /// In en, this message translates to:
  /// **'{appName} is a modern mobile application built with robust security and functionality, designed to provide an exceptional user experience with clean architecture and performance optimization.'**
  String appInfoOverview(String appName);

  /// Intro screen title with app name placeholder
  ///
  /// In en, this message translates to:
  /// **'Welcome to {appName}'**
  String introTitle(String appName);

  /// No description provided for @introFeature1Title.
  ///
  /// In en, this message translates to:
  /// **'See Your Progress'**
  String get introFeature1Title;

  /// No description provided for @introFeature1Description.
  ///
  /// In en, this message translates to:
  /// **'Track your development milestones with detailed analytics and insights'**
  String get introFeature1Description;

  /// No description provided for @introFeature2Title.
  ///
  /// In en, this message translates to:
  /// **'Explore Templates'**
  String get introFeature2Title;

  /// No description provided for @introFeature2Description.
  ///
  /// In en, this message translates to:
  /// **'Discover pre-built components and screens for rapid development'**
  String get introFeature2Description;

  /// No description provided for @introFeature3Title.
  ///
  /// In en, this message translates to:
  /// **'Get Started Quickly'**
  String get introFeature3Title;

  /// No description provided for @introFeature3Description.
  ///
  /// In en, this message translates to:
  /// **'Jumpstart your project with zero-config setup and best practices'**
  String get introFeature3Description;

  /// No description provided for @appleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get appleSignIn;

  /// No description provided for @googleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get googleSignIn;

  /// No description provided for @appleRegister.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get appleRegister;

  /// No description provided for @googleRegister.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get googleRegister;

  /// No description provided for @emailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter email and password'**
  String get emailAndPassword;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @legalConsentPart1.
  ///
  /// In en, this message translates to:
  /// **'Kindly read the '**
  String get legalConsentPart1;

  /// No description provided for @legalConsentPart2.
  ///
  /// In en, this message translates to:
  /// **'terms and conditions'**
  String get legalConsentPart2;

  /// Legal consent text with dynamic app name
  ///
  /// In en, this message translates to:
  /// **' and other legal documents that govern your use of {appName}.'**
  String legalConsentPart3(String appName);

  /// No description provided for @emailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailTitle;

  /// No description provided for @passwordTitle.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordTitle;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get loginEmailLabel;

  /// No description provided for @loginEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get loginEmailHint;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get loginPasswordHint;

  /// No description provided for @loginForgotPasswordPart1.
  ///
  /// In en, this message translates to:
  /// **'Have you forgotten your password? '**
  String get loginForgotPasswordPart1;

  /// No description provided for @loginForgotPasswordPart2.
  ///
  /// In en, this message translates to:
  /// **'Tap here'**
  String get loginForgotPasswordPart2;

  /// No description provided for @loginForgotPasswordPart3.
  ///
  /// In en, this message translates to:
  /// **' to reset your password?'**
  String get loginForgotPasswordPart3;

  /// No description provided for @commonConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get commonConfirmPasswordLabel;

  /// No description provided for @commonConfirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get commonConfirmPasswordHint;

  /// No description provided for @commonPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get commonPasswordsDoNotMatch;

  /// No description provided for @commonPasswordConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get commonPasswordConfirmRequired;

  /// Snackbar shown when a field passes validation
  ///
  /// In en, this message translates to:
  /// **'{field} is valid'**
  String commonFieldIsValid(String field);

  /// No description provided for @commonPleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait for the current operation to complete'**
  String get commonPleaseWait;

  /// No description provided for @commonUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get commonUnexpectedError;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonEnterEmailAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address and try again'**
  String get commonEnterEmailAndRetry;

  /// No description provided for @commonLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get commonLearnMore;

  /// No description provided for @authSignUpVerificationSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent! Please check your inbox.'**
  String get authSignUpVerificationSent;

  /// Sign-up failure message with error details
  ///
  /// In en, this message translates to:
  /// **'Sign-up failed: {error}'**
  String authSignUpFailed(String error);

  /// No description provided for @authForgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get authForgotPasswordTitle;

  /// No description provided for @authForgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a link to reset your password.'**
  String get authForgotPasswordSubtitle;

  /// No description provided for @authSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get authSendResetLink;

  /// No description provided for @authBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get authBackToSignIn;

  /// No description provided for @authUsernameScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your username'**
  String get authUsernameScreenTitle;

  /// No description provided for @authUsernameScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is how others will see you. You can change it later.'**
  String get authUsernameScreenSubtitle;

  /// No description provided for @authUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

  /// No description provided for @authUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a username'**
  String get authUsernameHint;

  /// Validation error for minimum username length
  ///
  /// In en, this message translates to:
  /// **'Username must be at least {min} characters'**
  String authUsernameMinLength(int min);

  /// Validation error for maximum username length
  ///
  /// In en, this message translates to:
  /// **'Username must be at most {max} characters'**
  String authUsernameMaxLength(int max);

  /// No description provided for @authUsernameFormatError.
  ///
  /// In en, this message translates to:
  /// **'Only letters, numbers, and underscores are allowed'**
  String get authUsernameFormatError;

  /// No description provided for @authUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'This username is already taken'**
  String get authUsernameTaken;

  /// No description provided for @authUsernameCheckError.
  ///
  /// In en, this message translates to:
  /// **'Unable to check username availability. Please try again.'**
  String get authUsernameCheckError;

  /// No description provided for @authUsernameSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your username. Please try again.'**
  String get authUsernameSaveError;

  /// No description provided for @authUsernameSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Username saved successfully!'**
  String get authUsernameSavedSuccess;

  /// No description provided for @authUpdatePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Create new password'**
  String get authUpdatePasswordTitle;

  /// No description provided for @authUpdatePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get authUpdatePasswordButton;

  /// No description provided for @authUpdatePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully. Please sign in again.'**
  String get authUpdatePasswordSuccess;

  /// No description provided for @authPasswordResetSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authPasswordResetSentTitle;

  /// No description provided for @authPasswordResetSentBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a password reset link to'**
  String get authPasswordResetSentBody;

  /// No description provided for @authPasswordResetSentNote.
  ///
  /// In en, this message translates to:
  /// **'Tap the link in the email to set a new password. The link expires in 1 hour.'**
  String get authPasswordResetSentNote;

  /// No description provided for @authGuestHello.
  ///
  /// In en, this message translates to:
  /// **'Hello!'**
  String get authGuestHello;

  /// Welcome text for guest users on the login profile screen
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing {appName} as a guest. Sign in with your phone number to start your shared space with your partner — it takes a few seconds.'**
  String authGuestOverview(String appName);

  /// Main title on the intro screen with app name
  ///
  /// In en, this message translates to:
  /// **'Welcome to\n{appName}'**
  String authIntroTitle(String appName);

  /// No description provided for @authIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the platform we built for you. Enjoy and have fun — the best is waiting.'**
  String get authIntroSubtitle;

  /// No description provided for @authReadLegalities.
  ///
  /// In en, this message translates to:
  /// **'Read legalities'**
  String get authReadLegalities;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get authPasswordRequired;

  /// No description provided for @authCreatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account...'**
  String get authCreatingAccount;

  /// No description provided for @authAccountCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully!'**
  String get authAccountCreatedSuccess;

  /// No description provided for @authCheckEmailToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Please check your email to confirm your account'**
  String get authCheckEmailToConfirm;

  /// No description provided for @authSigningInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Signing in with Google...'**
  String get authSigningInWithGoogle;

  /// No description provided for @authGoogleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed: {error}'**
  String authGoogleSignInFailed(String error);

  /// No description provided for @authAuthenticatingWithApple.
  ///
  /// In en, this message translates to:
  /// **'Authenticating with Apple...'**
  String get authAuthenticatingWithApple;

  /// No description provided for @authAppleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in failed: {error}'**
  String authAppleSignInFailed(String error);

  /// No description provided for @authSendingResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Sending reset email...'**
  String get authSendingResetEmail;

  /// No description provided for @authResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Reset email sent. Check your inbox.'**
  String get authResetEmailSent;

  /// No description provided for @authPasswordResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Password reset failed: {error}'**
  String authPasswordResetFailed(String error);

  /// No description provided for @authVerifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authVerifyEmailTitle;

  /// No description provided for @authVerifyEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to'**
  String get authVerifyEmailSubtitle;

  /// No description provided for @authVerifyEmailNote.
  ///
  /// In en, this message translates to:
  /// **'Tap the link in the email to verify your account and continue.'**
  String get authVerifyEmailNote;

  /// No description provided for @authConfirmationResent.
  ///
  /// In en, this message translates to:
  /// **'Confirmation email resent. Check your inbox.'**
  String get authConfirmationResent;

  /// No description provided for @authResendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resend email. Please try again.'**
  String get authResendFailed;

  /// No description provided for @authResendEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Resend confirmation email'**
  String get authResendEmailButton;

  /// Button label with seconds remaining for resend cooldown
  ///
  /// In en, this message translates to:
  /// **'Resend email ({seconds}s)'**
  String authResendEmailCooldown(int seconds);

  /// No description provided for @currencySelectorPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select currency'**
  String get currencySelectorPlaceholder;

  /// No description provided for @currencySelectorNoSelected.
  ///
  /// In en, this message translates to:
  /// **'No currency selected'**
  String get currencySelectorNoSelected;

  /// No description provided for @currencySelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Currency'**
  String get currencySelectorTitle;

  /// No description provided for @currencySelectorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by currency, code, or flag...'**
  String get currencySelectorSearchHint;

  /// No description provided for @currencySelectorNoResults.
  ///
  /// In en, this message translates to:
  /// **'No currencies found'**
  String get currencySelectorNoResults;

  /// No description provided for @discoverScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverScreenTitle;

  /// No description provided for @discoverSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get discoverSearchHint;

  /// No description provided for @discoverAllShopsRegion.
  ///
  /// In en, this message translates to:
  /// **'All shops in your region'**
  String get discoverAllShopsRegion;

  /// No description provided for @discoverAllFreelancers.
  ///
  /// In en, this message translates to:
  /// **'All freelancers near you'**
  String get discoverAllFreelancers;

  /// No description provided for @discoverMarketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketplace'**
  String get discoverMarketplaceTitle;

  /// No description provided for @discoverMarketplaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shop beauty products with cash on delivery'**
  String get discoverMarketplaceSubtitle;

  /// No description provided for @discoverBrowseProducts.
  ///
  /// In en, this message translates to:
  /// **'Browse products'**
  String get discoverBrowseProducts;

  /// No description provided for @discoverMyOrders.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get discoverMyOrders;

  /// No description provided for @discoverCartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get discoverCartTooltip;

  /// No description provided for @homeScheduleTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get homeScheduleTabLabel;

  /// No description provided for @homeDashboardTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get homeDashboardTabLabel;

  /// No description provided for @homeMapTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get homeMapTabLabel;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get validationRequired;

  /// No description provided for @validationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get validationEmailInvalid;

  /// Password validation error with minimum length parameter
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {minLength} characters'**
  String validationPasswordLength(int minLength);

  /// No description provided for @validationPasswordUppercase.
  ///
  /// In en, this message translates to:
  /// **'Password must include at least one uppercase letter'**
  String get validationPasswordUppercase;

  /// No description provided for @loggingInIndicatorText.
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loggingInIndicatorText;

  /// No description provided for @loginSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Login successful!\nWelcome back'**
  String get loginSuccessful;

  /// No description provided for @errorLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please check your credentials'**
  String get errorLoginFailed;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection'**
  String get errorNetwork;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @editProfileNameFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editProfileNameFieldTitle;

  /// No description provided for @editProfileNameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get editProfileNameFieldLabel;

  /// No description provided for @editProfileUserFieldNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get editProfileUserFieldNameTitle;

  /// No description provided for @editProfileUsernameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'@username'**
  String get editProfileUsernameFieldLabel;

  /// No description provided for @editProfileBioFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get editProfileBioFieldTitle;

  /// No description provided for @editProfileBioFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself'**
  String get editProfileBioFieldLabel;

  /// No description provided for @editProfileScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileScreenTitle;

  /// No description provided for @editProfileSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get editProfileSettingTitle;

  /// No description provided for @editProfileSettingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your account'**
  String get editProfileSettingSubtitle;

  /// No description provided for @editProfileScreenEditShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Shop'**
  String get editProfileScreenEditShopTitle;

  /// No description provided for @editProfileScreenEditShopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Change your shop information'**
  String get editProfileScreenEditShopSubtitle;

  /// No description provided for @languageScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred language for the app interface.\nThis will not affect your device settings.'**
  String get languageScreenSubtitle;

  /// No description provided for @languageScreeUseDeviceLang.
  ///
  /// In en, this message translates to:
  /// **'Use Device Language.'**
  String get languageScreeUseDeviceLang;

  /// No description provided for @languageScreeUseDeviceLangNote.
  ///
  /// In en, this message translates to:
  /// **'This will reset to match your device system language.'**
  String get languageScreeUseDeviceLangNote;

  /// No description provided for @settingsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// No description provided for @accountSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSectionTitle;

  /// No description provided for @accountSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **''**
  String get accountSectionSubtitle;

  /// No description provided for @profileItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileItemTitle;

  /// No description provided for @profileItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your personal data'**
  String get profileItemSubtitle;

  /// No description provided for @locationItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Location'**
  String get locationItemTitle;

  /// No description provided for @locationItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Change your current city'**
  String get locationItemSubtitle;

  /// No description provided for @saveItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Contents'**
  String get saveItemTitle;

  /// No description provided for @saveItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Contents you have saved'**
  String get saveItemSubtitle;

  /// No description provided for @notificationsItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsItemTitle;

  /// No description provided for @notificationsItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage push and email notifications'**
  String get notificationsItemSubtitle;

  /// No description provided for @blockedItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked Accounts'**
  String get blockedItemTitle;

  /// No description provided for @blockedItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts you have blocked'**
  String get blockedItemSubtitle;

  /// No description provided for @mutedItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Muted Accounts'**
  String get mutedItemTitle;

  /// No description provided for @mutedItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Anonymous Opinions accounts you\'ve muted'**
  String get mutedItemSubtitle;

  /// No description provided for @qrCodeItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Share QR Code'**
  String get qrCodeItemTitle;

  /// No description provided for @qrCodeItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share your account QR code'**
  String get qrCodeItemSubtitle;

  /// No description provided for @shareProfileItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Profile'**
  String get shareProfileItemTitle;

  /// No description provided for @shareProfileItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share your profile with friends'**
  String get shareProfileItemSubtitle;

  /// No description provided for @appSettingsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettingsSectionTitle;

  /// No description provided for @appSettingsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize your experience'**
  String get appSettingsSectionSubtitle;

  /// No description provided for @themeItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeItemTitle;

  /// No description provided for @themeItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light, Dark, or System'**
  String get themeItemSubtitle;

  /// No description provided for @languageItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageItemTitle;

  /// No description provided for @languageItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Change app language'**
  String get languageItemSubtitle;

  /// No description provided for @biometricItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Biometric Login'**
  String get biometricItemTitle;

  /// No description provided for @biometricItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use Face ID or Touch ID'**
  String get biometricItemSubtitle;

  /// No description provided for @supportSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportSectionTitle;

  /// No description provided for @supportSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **''**
  String get supportSectionSubtitle;

  /// No description provided for @guideItemTitle.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get guideItemTitle;

  /// No description provided for @guideItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Documentation and tutorials'**
  String get guideItemSubtitle;

  /// No description provided for @helpItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get helpItemTitle;

  /// No description provided for @helpItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get help with the app'**
  String get helpItemSubtitle;

  /// No description provided for @feedbackItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackItemTitle;

  /// No description provided for @feedbackItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share your thoughts'**
  String get feedbackItemSubtitle;

  /// No description provided for @rateItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate the App'**
  String get rateItemTitle;

  /// No description provided for @rateItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Leave a review'**
  String get rateItemSubtitle;

  /// About app title with dynamic app name
  ///
  /// In en, this message translates to:
  /// **'About {appName}'**
  String appInfoItemTitle(String appName);

  /// No description provided for @appInfoItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Technical information'**
  String get appInfoItemSubtitle;

  /// No description provided for @legalSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalSectionTitle;

  /// No description provided for @legalSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **''**
  String get legalSectionSubtitle;

  /// No description provided for @termsItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms, Privacy & Policies'**
  String get termsItemTitle;

  /// No description provided for @termsItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read our terms'**
  String get termsItemSubtitle;

  /// No description provided for @licensesItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get licensesItemTitle;

  /// No description provided for @licensesItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Third-party libraries and licenses'**
  String get licensesItemSubtitle;

  /// No description provided for @accountActionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Actions'**
  String get accountActionsSectionTitle;

  /// No description provided for @accountActionsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **''**
  String get accountActionsSectionSubtitle;

  /// No description provided for @deactivateItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivateItemTitle;

  /// No description provided for @deactivateItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate out of your account'**
  String get deactivateItemSubtitle;

  /// No description provided for @deleteItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteItemTitle;

  /// No description provided for @deleteItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently remove your account'**
  String get deleteItemSubtitle;

  /// No description provided for @logoutItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logoutItemTitle;

  /// No description provided for @logoutItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of your account'**
  String get logoutItemSubtitle;

  /// No description provided for @loadingDefaultMessage.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingDefaultMessage;

  /// No description provided for @emptyStateNoDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyStateNoDataTitle;

  /// No description provided for @emptyStateNoDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When there\'s something to show, it\'ll appear here.'**
  String get emptyStateNoDataSubtitle;

  /// No description provided for @emptyStateNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get emptyStateNoResultsTitle;

  /// No description provided for @emptyStateNoResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try a different word or filter.'**
  String get emptyStateNoResultsSubtitle;

  /// No description provided for @emptyStateNoInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get emptyStateNoInternetTitle;

  /// No description provided for @emptyStateNoInternetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get emptyStateNoInternetSubtitle;

  /// No description provided for @emptyStateNoMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get emptyStateNoMessagesTitle;

  /// No description provided for @emptyStateNoMessagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Say hello to start your conversation.'**
  String get emptyStateNoMessagesSubtitle;

  /// No description provided for @emptyStateRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get emptyStateRefresh;

  /// No description provided for @emptyStateClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get emptyStateClearFilters;

  /// No description provided for @emptyStateRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get emptyStateRetry;

  /// No description provided for @emptyStateStartChat.
  ///
  /// In en, this message translates to:
  /// **'Say hello'**
  String get emptyStateStartChat;

  /// No description provided for @errorNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get errorNetworkTitle;

  /// No description provided for @errorNetworkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the server. Check your internet connection.'**
  String get errorNetworkSubtitle;

  /// No description provided for @errorServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Server Error'**
  String get errorServerTitle;

  /// No description provided for @errorServerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our end. Please try again later.'**
  String get errorServerSubtitle;

  /// No description provided for @errorClientTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Error'**
  String get errorClientTitle;

  /// No description provided for @errorClientSubtitle.
  ///
  /// In en, this message translates to:
  /// **'There was a problem with your request. Please check and try again.'**
  String get errorClientSubtitle;

  /// No description provided for @errorParsingTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Error'**
  String get errorParsingTitle;

  /// Error when failing to parse specific data type
  ///
  /// In en, this message translates to:
  /// **'Unable to process the {dataType}. This might be a temporary issue.'**
  String errorParsingSubtitle(String dataType);

  /// No description provided for @errorPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Access Denied'**
  String get errorPermissionTitle;

  /// Error for permission denial on specific content
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to access this {dataType}.'**
  String errorPermissionSubtitle(String dataType);

  /// No description provided for @errorGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// Generic error message with data type context
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred while loading {dataType}. Please try again.'**
  String errorGenericSubtitle(String dataType);

  /// No description provided for @errorRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get errorRetry;

  /// No description provided for @errorCheckSettings.
  ///
  /// In en, this message translates to:
  /// **'Check settings'**
  String get errorCheckSettings;

  /// No description provided for @errorReport.
  ///
  /// In en, this message translates to:
  /// **'Report issue'**
  String get errorReport;

  /// No description provided for @errorGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get errorGoBack;

  /// No description provided for @errorRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get errorRefresh;

  /// No description provided for @errorRequestAccess.
  ///
  /// In en, this message translates to:
  /// **'Request access'**
  String get errorRequestAccess;

  /// No description provided for @errorContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get errorContactSupport;

  /// No description provided for @eulaTitle.
  ///
  /// In en, this message translates to:
  /// **'End User License Agreement'**
  String get eulaTitle;

  /// EULA content with app name and support email placeholders
  ///
  /// In en, this message translates to:
  /// **'This End User License Agreement (\"EULA\") is a legal agreement between you and Bars Opus, Ltd. for {appName}.\n\nBy installing, accessing, or using {appName}, you agree to be bound by the terms of this EULA. {appName} is licensed, not sold, to you for use only under the terms of this license. Bars Opus, Ltd. reserves all rights not expressly granted to you in this EULA.\n\nYou may not modify, reverse engineer, decompile, or disassemble {appName}. This license is valid until terminated by you or Bars Opus, Ltd. Your rights under this license will terminate automatically without notice if you fail to comply with any term(s).\n\nAll intellectual property rights in and to {appName} are owned by Bars Opus, Ltd. This EULA is governed by the laws of England and Wales.\n\nFor questions about this EULA, please contact: {supportEmail}.'**
  String eulaContent(String appName, String supportEmail);

  /// No description provided for @eulaFooter.
  ///
  /// In en, this message translates to:
  /// **'By agreeing, you acknowledge that you have read and understood this End User License Agreement.'**
  String get eulaFooter;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// Privacy policy content with app name placeholder
  ///
  /// In en, this message translates to:
  /// **'This Privacy Policy explains how Bars Opus, Ltd. (\"we\", \"us\", \"our\") collects, uses, and protects your information when you use {appName}.\n\nWe collect information you provide directly, such as when you create an account, complete your profile, or contact support. We automatically collect certain information about your device and how you use {appName}. We use cookies and similar tracking technologies to track activity and hold certain information.\n\nWe use the information we collect to provide, maintain, and improve {appName}. We may share your information with third-party service providers who perform services on our behalf. We may disclose your information if required by law or to protect our rights and safety.\n\nYou have the right to access, correct, or delete your personal information. We implement appropriate technical and organizational measures to protect your information. We may update this Privacy Policy from time to time. We will notify you of any changes.'**
  String privacyPolicyContent(String appName);

  /// Privacy policy footer with app name and current date
  ///
  /// In en, this message translates to:
  /// **'{appName} Privacy Policy - Last updated: {currentDate}'**
  String privacyPolicyFooter(String appName, DateTime currentDate);

  /// No description provided for @termsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsTitle;

  /// Terms of service content with app name and support email
  ///
  /// In en, this message translates to:
  /// **'These Terms of Service (\"Terms\") govern your access to and use of {appName}. By accessing or using {appName}, you agree to be bound by these Terms.\n\nYou must be at least 13 years old to use {appName}. You are responsible for safeguarding your account credentials and for all activities under your account. You may not use {appName} for any illegal or unauthorized purpose.\n\nWe reserve the right to modify, suspend, or discontinue {appName} at any time. All content included in {appName} is the property of Bars Opus, Ltd. or its licensors.\n\nWe may terminate or suspend your access to {appName} immediately if you violate these Terms. These Terms shall be governed by and construed in accordance with the laws of England and Wales.\n\nFor any questions about these Terms, please contact us at {supportEmail}.'**
  String termsContent(String appName, String supportEmail);

  /// No description provided for @dataSharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Sharing Agreement'**
  String get dataSharingTitle;

  /// Data sharing content with app name placeholder
  ///
  /// In en, this message translates to:
  /// **'This Data Sharing Agreement outlines how your information may be shared when you use {appName} social features.\n\nWhen you connect with friends on {appName}, certain activity data may be visible to them. Shared activity data may include workout duration, calories burned, exercise minutes, and achievement badges. Your profile information (display name and profile picture) is visible to friends you connect with.\n\nYour email address and contact information remain private and are never shared with other users. You control what data is shared through your {appName} privacy settings. You can revoke sharing permissions at any time in the app settings.\n\nData shared with friends is encrypted during transmission and storage. We retain shared data only as long as necessary to provide the sharing functionality. Third-party integrations may have their own data sharing practices, which we recommend reviewing.'**
  String dataSharingContent(String appName);

  /// Data sharing footer with app name placeholder
  ///
  /// In en, this message translates to:
  /// **'Data sharing in {appName} helps create a supportive community while respecting your privacy choices.'**
  String dataSharingFooter(String appName);

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your shop activities efficiently'**
  String get dashboardSubtitle;

  /// No description provided for @dashboardSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardSectionTitle;

  /// No description provided for @dashboardSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Overview of your shop\'s performance and key metrics'**
  String get dashboardSectionSubtitle;

  /// No description provided for @dashboardPayoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Payout'**
  String get dashboardPayoutTitle;

  /// No description provided for @dashboardPayoutContent.
  ///
  /// In en, this message translates to:
  /// **'Shop owners can request weekly payouts. Navigate to the Earnings section, review your balance, and submit a payout request. Funds typically process within 3-5 business days.'**
  String get dashboardPayoutContent;

  /// No description provided for @dashboardAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics Dashboard'**
  String get dashboardAnalyticsTitle;

  /// No description provided for @dashboardAnalyticsContent.
  ///
  /// In en, this message translates to:
  /// **'Track your shop\'s performance with real-time analytics. Monitor sales trends, customer engagement, and inventory levels through interactive charts and reports.'**
  String get dashboardAnalyticsContent;

  /// No description provided for @dashboardScreenshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Overview'**
  String get dashboardScreenshotTitle;

  /// No description provided for @dashboardScreenshotContent.
  ///
  /// In en, this message translates to:
  /// **'The main dashboard provides a comprehensive view of your shop\'s key metrics, recent activities, and quick access to essential features.'**
  String get dashboardScreenshotContent;

  /// No description provided for @categoryFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get categoryFeatures;

  /// No description provided for @categoryDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get categoryDashboard;

  /// No description provided for @faqDashboard1Question.
  ///
  /// In en, this message translates to:
  /// **'When can I request a payout?'**
  String get faqDashboard1Question;

  /// No description provided for @faqDashboard1Answer.
  ///
  /// In en, this message translates to:
  /// **'You can request your payout once a week, every Saturday. The weekly cutoff is Friday at 11:59 PM. Payouts are processed within 3-5 business days.'**
  String get faqDashboard1Answer;

  /// No description provided for @faqDashboard2Question.
  ///
  /// In en, this message translates to:
  /// **'Where do I request my payout?'**
  String get faqDashboard2Question;

  /// No description provided for @faqDashboard2Answer.
  ///
  /// In en, this message translates to:
  /// **'Navigate to your dashboard and click on the \'Earnings\' section. From there, you\'ll see your current balance and a \'Request Payout\' button. Follow the prompts to complete your request.'**
  String get faqDashboard2Answer;

  /// No description provided for @profileScreenCantChatWithYourself.
  ///
  /// In en, this message translates to:
  /// **'You can\'t chat with yourself'**
  String get profileScreenCantChatWithYourself;

  /// No description provided for @profileScreenStartingConversation.
  ///
  /// In en, this message translates to:
  /// **'Starting conversation...'**
  String get profileScreenStartingConversation;

  /// No description provided for @profileScreenNoActiveSession.
  ///
  /// In en, this message translates to:
  /// **'No active session — please log in again.'**
  String get profileScreenNoActiveSession;

  /// No description provided for @profileScreenSignInToChatMessage.
  ///
  /// In en, this message translates to:
  /// **'You have to sign in to send a message'**
  String get profileScreenSignInToChatMessage;

  /// No description provided for @profileScreenFollowFeatureComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Follow feature coming soon'**
  String get profileScreenFollowFeatureComingSoon;

  /// No description provided for @profileScreenEnterBioPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a bio so people can know you'**
  String get profileScreenEnterBioPlaceholder;

  /// No description provided for @profileScreenNoBioYet.
  ///
  /// In en, this message translates to:
  /// **'No bio yet'**
  String get profileScreenNoBioYet;

  /// No description provided for @profileScreenErrorLoadingProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Unable to load profile. Check your internet and try again.'**
  String get profileScreenErrorLoadingProfileBody;

  /// No description provided for @profileScreenLoadingNotifications.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get profileScreenLoadingNotifications;

  /// No description provided for @profileHeaderBookingsStatLabel.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get profileHeaderBookingsStatLabel;

  /// No description provided for @profileHeaderOrdersStatLabel.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get profileHeaderOrdersStatLabel;

  /// No description provided for @profileHeaderEditProfileButton.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileHeaderEditProfileButton;

  /// No description provided for @profileHeaderMessageButton.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get profileHeaderMessageButton;

  /// No description provided for @editableProfileAvatarTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get editableProfileAvatarTakePhoto;

  /// No description provided for @editableProfileAvatarChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get editableProfileAvatarChooseGallery;

  /// No description provided for @editProfileScreenAccountTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Account Type'**
  String get editProfileScreenAccountTypeLabel;

  /// No description provided for @editProfileScreenAccountTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select how you want to use this app. This determines what features are available to you.'**
  String get editProfileScreenAccountTypeSubtitle;

  /// No description provided for @editProfileScreenUpdatingAccountType.
  ///
  /// In en, this message translates to:
  /// **'Updating account type...'**
  String get editProfileScreenUpdatingAccountType;

  /// No description provided for @editProfileScreenPleaseLogIn.
  ///
  /// In en, this message translates to:
  /// **'Please log in'**
  String get editProfileScreenPleaseLogIn;

  /// No description provided for @editProfileScreenNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editProfileScreenNameLabel;

  /// No description provided for @editProfileScreenNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get editProfileScreenNameHint;

  /// No description provided for @editProfileScreenUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get editProfileScreenUsernameLabel;

  /// No description provided for @editProfileScreenUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter username'**
  String get editProfileScreenUsernameHint;

  /// No description provided for @editProfileScreenBioLabel.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get editProfileScreenBioLabel;

  /// No description provided for @editProfileScreenBioHint.
  ///
  /// In en, this message translates to:
  /// **'Tell something about yourself'**
  String get editProfileScreenBioHint;

  /// No description provided for @editProfileScreenEditWorkProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit work profile'**
  String get editProfileScreenEditWorkProfileTitle;

  /// No description provided for @profileTabsAppointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get profileTabsAppointments;

  /// No description provided for @profileTabsBuys.
  ///
  /// In en, this message translates to:
  /// **'Buys'**
  String get profileTabsBuys;

  /// No description provided for @profileTabsSaves.
  ///
  /// In en, this message translates to:
  /// **'Saves'**
  String get profileTabsSaves;

  /// No description provided for @searchScreenSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search shops, professionals, products...'**
  String get searchScreenSearchHint;

  /// No description provided for @searchScreenNoResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get searchScreenNoResultsFound;

  /// Empty state message for search with category placeholder
  ///
  /// In en, this message translates to:
  /// **'No {category} found'**
  String searchScreenNoResultsCategory(String category);

  /// Search query display in empty state
  ///
  /// In en, this message translates to:
  /// **'Searched for: \"{query}\"'**
  String searchScreenSearchedFor(String query);

  /// No description provided for @searchScreenSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get searchScreenSomethingWentWrong;

  /// No description provided for @searchAppBarSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchAppBarSearchHint;

  /// No description provided for @searchSuggestionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search for shops, professionals for home service, or hair products to buy'**
  String get searchSuggestionsHint;

  /// No description provided for @searchSuggestionsRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get searchSuggestionsRecentSearches;

  /// No description provided for @searchSuggestionsClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get searchSuggestionsClearAll;

  /// No description provided for @searchEmptyStateNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get searchEmptyStateNoResults;

  /// Empty state message when no search results found
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find anything for \"{query}\"'**
  String searchEmptyStateCouldNotFind(String query);

  /// No description provided for @searchEmptyStateTryThese.
  ///
  /// In en, this message translates to:
  /// **'Try these instead:'**
  String get searchEmptyStateTryThese;

  /// No description provided for @searchResultsShopsHeader.
  ///
  /// In en, this message translates to:
  /// **'Shops'**
  String get searchResultsShopsHeader;

  /// No description provided for @searchResultsSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get searchResultsSeeAll;

  /// Category results screen title
  ///
  /// In en, this message translates to:
  /// **'{category} Results'**
  String searchResultsTitle(String category);

  /// Subtitle showing search query in results screen
  ///
  /// In en, this message translates to:
  /// **'Searching for \"{query}\"'**
  String searchResultsSearchingFor(String query);

  /// No description provided for @searchResultsTryDifferent.
  ///
  /// In en, this message translates to:
  /// **'Try different keywords or remove filters'**
  String get searchResultsTryDifferent;

  /// No description provided for @searchResultsSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get searchResultsSomethingWentWrong;

  /// Title for nearby shops section showing distance radius
  ///
  /// In en, this message translates to:
  /// **'Near You\nwithin {km}km'**
  String nearYouShopsTitle(int km);

  /// Description of nearby shops feature
  ///
  /// In en, this message translates to:
  /// **'Shops located within {km} km of your current location, shown from closest to farthest. Simply set your location once, and we\'ll show you what\'s nearby—whether you\'re at home, work, or exploring a new neighborhood. Handy for last‑minute bookings or when you prefer to walk.'**
  String nearYouShopsBody(int km);

  /// No description provided for @nearYouShopsEmptyNoFilter.
  ///
  /// In en, this message translates to:
  /// **'No shops found nearby'**
  String get nearYouShopsEmptyNoFilter;

  /// Empty state message when no shops found for selected luxury level
  ///
  /// In en, this message translates to:
  /// **'No {luxury} shops found nearby'**
  String nearYouShopsEmptyWithFilter(String luxury);

  /// Empty state subtitle with location placeholder
  ///
  /// In en, this message translates to:
  /// **'Shops in {location} would be shown here once they become available'**
  String nearYouShopsEmptySubtitle(String location);

  /// No description provided for @premiumShopsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium Shops'**
  String get premiumShopsScreenTitle;

  /// No description provided for @premiumShopsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No premium shops found'**
  String get premiumShopsEmpty;

  /// No description provided for @premiumShopsHorizontalTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium shops\nfor premium looks'**
  String get premiumShopsHorizontalTitle;

  /// No description provided for @premiumShopsHorizontalBody.
  ///
  /// In en, this message translates to:
  /// **'Handpicked high‑end salons and spas offering luxury experiences. These shops are classified as Luxury or Ultra‑Luxury based on their services, pricing, and customer reviews. Perfect when you\'re looking for that extra touch of elegance.'**
  String get premiumShopsHorizontalBody;

  /// No description provided for @premiumShopsHorizontalEmptyNoFilter.
  ///
  /// In en, this message translates to:
  /// **'No premium shops available'**
  String get premiumShopsHorizontalEmptyNoFilter;

  /// Empty state for premium shops with luxury level filter
  ///
  /// In en, this message translates to:
  /// **'No {luxury} premium shops available'**
  String premiumShopsHorizontalEmptyWithFilter(String luxury);

  /// No description provided for @premiumShopsHorizontalEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shops would be shown here once they become available'**
  String get premiumShopsHorizontalEmptySubtitle;

  /// No description provided for @topRatedShopsHorizontalTitle.
  ///
  /// In en, this message translates to:
  /// **'Top Rated'**
  String get topRatedShopsHorizontalTitle;

  /// Top rated shops title with location
  ///
  /// In en, this message translates to:
  /// **'Top Rated \nin {location}'**
  String topRatedShopsHorizontalTitleWithLocation(String location);

  /// No description provided for @topRatedShopsHorizontalBody.
  ///
  /// In en, this message translates to:
  /// **'Shops with the highest customer ratings (4.5+ stars) and a solid number of reviews. These are the favorites among our community—consistently praised for quality, service, and professionalism. A great place to start if you want reliable, crowd‑approved options.'**
  String get topRatedShopsHorizontalBody;

  /// No description provided for @topRatedShopsHorizontalEmptyNoFilter.
  ///
  /// In en, this message translates to:
  /// **'No top rated shops available'**
  String get topRatedShopsHorizontalEmptyNoFilter;

  /// Empty state for top rated shops with luxury level filter
  ///
  /// In en, this message translates to:
  /// **'No {luxury} premium shops available'**
  String topRatedShopsHorizontalEmptyWithFilter(String luxury);

  /// No description provided for @topRatedShopsHorizontalEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shops would be shown here once they become available'**
  String get topRatedShopsHorizontalEmptySubtitle;

  /// No description provided for @topRatedShopsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Top Rated Shops'**
  String get topRatedShopsScreenTitle;

  /// No description provided for @topRatedShopsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No top rated shops found'**
  String get topRatedShopsEmpty;

  /// No description provided for @nearYouFreelancersScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Freelancers near you'**
  String get nearYouFreelancersScreenTitle;

  /// No description provided for @nearYouFreelancersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No freelancers found nearby'**
  String get nearYouFreelancersEmpty;

  /// No description provided for @nearYouFreelancersEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try expanding your search area or change location'**
  String get nearYouFreelancersEmptySubtitle;

  /// No description provided for @topRatedFreelancersScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Top rated freelancers'**
  String get topRatedFreelancersScreenTitle;

  /// No description provided for @topRatedFreelancersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No top rated freelancers found'**
  String get topRatedFreelancersEmpty;

  /// No description provided for @topRatedFreelancersEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search area'**
  String get topRatedFreelancersEmptySubtitle;

  /// Top rated freelancers title with location
  ///
  /// In en, this message translates to:
  /// **'Top Rated \nin {location}'**
  String topRatedFreelancersHorizontalTitle(String location);

  /// No description provided for @topRatedFreelancersHorizontalBody.
  ///
  /// In en, this message translates to:
  /// **'Handpicked high‑end professionals offering luxury experiences. These freelancers are classified as top rated based on their work quality, pricing, and customer reviews. Perfect when you\'re looking for that extra touch of excellence.'**
  String get topRatedFreelancersHorizontalBody;

  /// Freelancers near you title with location
  ///
  /// In en, this message translates to:
  /// **'Freelancers Near You in {location}'**
  String nearYouFreelancersHorizontalTitle(String location);

  /// No description provided for @nearYouFreelancersHorizontalBody.
  ///
  /// In en, this message translates to:
  /// **'Skilled professionals located near you. These freelancers are available for quick bookings and offer convenient, local service. Perfect when you\'re looking for reliability and proximity.'**
  String get nearYouFreelancersHorizontalBody;

  /// No description provided for @nearYouFreelancersHorizontalEmpty.
  ///
  /// In en, this message translates to:
  /// **'No top rated freelancers available'**
  String get nearYouFreelancersHorizontalEmpty;

  /// No description provided for @nearYouFreelancersHorizontalEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Freelancers would be shown here once they become available'**
  String get nearYouFreelancersHorizontalEmptySubtitle;

  /// No description provided for @shopNoLocationSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your location to discover'**
  String get shopNoLocationSetTitle;

  /// No description provided for @shopNoLocationSetContent.
  ///
  /// In en, this message translates to:
  /// **'Set your location to discover premium and top rated shops near you.'**
  String get shopNoLocationSetContent;

  /// No description provided for @providerTypeShops.
  ///
  /// In en, this message translates to:
  /// **'Shops'**
  String get providerTypeShops;

  /// No description provided for @providerTypeFreelancers.
  ///
  /// In en, this message translates to:
  /// **'Freelancers'**
  String get providerTypeFreelancers;

  /// No description provided for @providerTypeBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get providerTypeBuy;

  /// No description provided for @luxuryLevelChipsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get luxuryLevelChipsAll;

  /// No description provided for @searchRadiusSliderTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore radius'**
  String get searchRadiusSliderTitle;

  /// Subtitle showing current search radius
  ///
  /// In en, this message translates to:
  /// **'Showing results within {km}km of your location'**
  String searchRadiusSliderSubtitle(int km);

  /// Validation error for maximum password length
  ///
  /// In en, this message translates to:
  /// **'Password must be at most {max} characters'**
  String validationPasswordMaxLength(int max);

  /// No description provided for @validationPasswordRepeatingChars.
  ///
  /// In en, this message translates to:
  /// **'Password contains too many repeating characters'**
  String get validationPasswordRepeatingChars;

  /// No description provided for @validationPasswordSequential.
  ///
  /// In en, this message translates to:
  /// **'Password contains sequential characters'**
  String get validationPasswordSequential;

  /// Validation error for specific phone number digit requirement
  ///
  /// In en, this message translates to:
  /// **'Phone number must be {digits} digits'**
  String validationPhoneDigits(int digits);

  /// No description provided for @validationPhoneUK.
  ///
  /// In en, this message translates to:
  /// **'Invalid UK phone number'**
  String get validationPhoneUK;

  /// Validation error for URL scheme requirement
  ///
  /// In en, this message translates to:
  /// **'URL must start with {schemes}'**
  String validationUrlScheme(String schemes);

  /// No description provided for @validationUrlDomain.
  ///
  /// In en, this message translates to:
  /// **'Invalid domain name'**
  String get validationUrlDomain;

  /// No description provided for @validationUrlPublicAddress.
  ///
  /// In en, this message translates to:
  /// **'URL must point to a public address'**
  String get validationUrlPublicAddress;

  /// Validation error for maximum name length
  ///
  /// In en, this message translates to:
  /// **'{field} must be at most {max} characters'**
  String validationNameMaxLength(String field, int max);

  /// Validation error for consecutive special characters in name
  ///
  /// In en, this message translates to:
  /// **'{field} cannot contain consecutive hyphens or spaces'**
  String validationNameConsecutiveChars(String field);

  /// No description provided for @validationCreditCardFormat.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid credit card number'**
  String get validationCreditCardFormat;

  /// No description provided for @validationCreditCardInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid credit card number'**
  String get validationCreditCardInvalid;

  /// No description provided for @validationDatePastNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Date cannot be in the past'**
  String get validationDatePastNotAllowed;

  /// No description provided for @validationPostalCodeZip.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid ZIP code (e.g., 12345 or 12345-6789)'**
  String get validationPostalCodeZip;

  /// No description provided for @validationPostalCodeCanadian.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid Canadian postal code (e.g., A1A 1A1)'**
  String get validationPostalCodeCanadian;

  /// No description provided for @validationPostalCodeGeneric.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid postal code'**
  String get validationPostalCodeGeneric;

  /// No description provided for @validationSSNFormat.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid SSN (e.g., 123-45-6789)'**
  String get validationSSNFormat;

  /// No description provided for @validationSSNInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid SSN'**
  String get validationSSNInvalid;

  /// No description provided for @validationEmailTooLong.
  ///
  /// In en, this message translates to:
  /// **'Email is too long (max 254 characters)'**
  String get validationEmailTooLong;

  /// No description provided for @validationEmailLocalPartTooLong.
  ///
  /// In en, this message translates to:
  /// **'Local part of email is too long'**
  String get validationEmailLocalPartTooLong;

  /// No description provided for @categoriesAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get categoriesAll;

  /// No description provided for @categoriesSalon.
  ///
  /// In en, this message translates to:
  /// **'Salons'**
  String get categoriesSalon;

  /// No description provided for @categoriesBarbershop.
  ///
  /// In en, this message translates to:
  /// **'Barbershops'**
  String get categoriesBarbershop;

  /// No description provided for @categoriesSpa.
  ///
  /// In en, this message translates to:
  /// **'Spas'**
  String get categoriesSpa;

  /// No description provided for @categoriesNailSalon.
  ///
  /// In en, this message translates to:
  /// **'Nail Salons'**
  String get categoriesNailSalon;

  /// No description provided for @categoriesLashStudio.
  ///
  /// In en, this message translates to:
  /// **'Lash Studios'**
  String get categoriesLashStudio;

  /// No description provided for @categoriesWaxing.
  ///
  /// In en, this message translates to:
  /// **'Waxing'**
  String get categoriesWaxing;

  /// No description provided for @categoriesMassage.
  ///
  /// In en, this message translates to:
  /// **'Massage'**
  String get categoriesMassage;

  /// No description provided for @categoriesMakeup.
  ///
  /// In en, this message translates to:
  /// **'Makeup'**
  String get categoriesMakeup;

  /// No description provided for @categoriesSkincare.
  ///
  /// In en, this message translates to:
  /// **'Skincare'**
  String get categoriesSkincare;

  /// No description provided for @luxuryLevelModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get luxuryLevelModerate;

  /// No description provided for @luxuryLevelLuxury.
  ///
  /// In en, this message translates to:
  /// **'Luxury'**
  String get luxuryLevelLuxury;

  /// No description provided for @luxuryLevelUltraLuxury.
  ///
  /// In en, this message translates to:
  /// **'Ultra Luxury'**
  String get luxuryLevelUltraLuxury;

  /// No description provided for @flow_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get flow_continue;

  /// No description provided for @flow_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get flow_close;

  /// No description provided for @flow_back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get flow_back;

  /// No description provided for @flow_listTwo.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String flow_listTwo(String first, String second);

  /// No description provided for @flow_countryUk.
  ///
  /// In en, this message translates to:
  /// **'the UK'**
  String get flow_countryUk;

  /// No description provided for @flow_countryUs.
  ///
  /// In en, this message translates to:
  /// **'the US'**
  String get flow_countryUs;

  /// No description provided for @flow_welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Love, dating and you, in one calm place.'**
  String get flow_welcomeTitle;

  /// No description provided for @flow_pathRelationshipTitle.
  ///
  /// In en, this message translates to:
  /// **'In a relationship'**
  String get flow_pathRelationshipTitle;

  /// No description provided for @flow_pathRelationshipLine.
  ///
  /// In en, this message translates to:
  /// **'A private space for you and your partner.'**
  String get flow_pathRelationshipLine;

  /// No description provided for @flow_pathDatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Single and open to dating'**
  String get flow_pathDatingTitle;

  /// No description provided for @flow_pathDatingLine.
  ///
  /// In en, this message translates to:
  /// **'A few introductions a day. Only when it\'s mutual.'**
  String get flow_pathDatingLine;

  /// No description provided for @flow_pathJustMeTitle.
  ///
  /// In en, this message translates to:
  /// **'Just for me'**
  String get flow_pathJustMeTitle;

  /// No description provided for @flow_pathJustMeLine.
  ///
  /// In en, this message translates to:
  /// **'Your journal, quizzes and Healing.'**
  String get flow_pathJustMeLine;

  /// No description provided for @flow_welcomeCardSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title}. {line} Opens a preview.'**
  String flow_welcomeCardSemantics(String title, String line);

  /// No description provided for @flow_welcomeGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get flow_welcomeGetStarted;

  /// No description provided for @flow_welcomeHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get flow_welcomeHaveAccount;

  /// No description provided for @flow_welcomeHaveInvite.
  ///
  /// In en, this message translates to:
  /// **'I have an invite'**
  String get flow_welcomeHaveInvite;

  /// No description provided for @flow_welcomeReadOpinions.
  ///
  /// In en, this message translates to:
  /// **'Read Opinions first'**
  String get flow_welcomeReadOpinions;

  /// No description provided for @flow_welcomeFooter.
  ///
  /// In en, this message translates to:
  /// **'Attune is for adults (18+) and uses your phone number to sign in.'**
  String get flow_welcomeFooter;

  /// No description provided for @flow_linkTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get flow_linkTerms;

  /// No description provided for @flow_linkPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get flow_linkPrivacy;

  /// No description provided for @flow_previewRelationshipTitle.
  ///
  /// In en, this message translates to:
  /// **'A space for the two of you'**
  String get flow_previewRelationshipTitle;

  /// No description provided for @flow_previewRelationshipLine1.
  ///
  /// In en, this message translates to:
  /// **'Chat, plans and memories only you two can see.'**
  String get flow_previewRelationshipLine1;

  /// No description provided for @flow_previewRelationshipLine2.
  ///
  /// In en, this message translates to:
  /// **'Your journal stays yours. Your partner never sees it.'**
  String get flow_previewRelationshipLine2;

  /// No description provided for @flow_previewRelationshipLine3.
  ///
  /// In en, this message translates to:
  /// **'Invite your partner with a link or a code.'**
  String get flow_previewRelationshipLine3;

  /// No description provided for @flow_previewDatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Introductions, not swiping'**
  String get flow_previewDatingTitle;

  /// No description provided for @flow_previewDatingLine1.
  ///
  /// In en, this message translates to:
  /// **'Up to 3 introductions a day, chosen for what you both want.'**
  String get flow_previewDatingLine1;

  /// No description provided for @flow_previewDatingLine2.
  ///
  /// In en, this message translates to:
  /// **'A match only when you both say yes.'**
  String get flow_previewDatingLine2;

  /// No description provided for @flow_previewDatingLine3.
  ///
  /// In en, this message translates to:
  /// **'A live video selfie checks your age before your first introduction.'**
  String get flow_previewDatingLine3;

  /// No description provided for @flow_previewDatingCountries.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {countries}. More countries later.'**
  String flow_previewDatingCountries(String countries);

  /// No description provided for @flow_previewJustMeTitle.
  ///
  /// In en, this message translates to:
  /// **'A private space for you'**
  String get flow_previewJustMeTitle;

  /// No description provided for @flow_previewJustMeLine1.
  ///
  /// In en, this message translates to:
  /// **'A journal only you can read.'**
  String get flow_previewJustMeLine1;

  /// No description provided for @flow_previewJustMeLine2.
  ///
  /// In en, this message translates to:
  /// **'Short quizzes about how you connect.'**
  String get flow_previewJustMeLine2;

  /// No description provided for @flow_previewJustMeLine3.
  ///
  /// In en, this message translates to:
  /// **'Healing, after a breakup or a loss.'**
  String get flow_previewJustMeLine3;

  /// No description provided for @flow_previewJustMeLine4.
  ///
  /// In en, this message translates to:
  /// **'Single, partnered or in between.'**
  String get flow_previewJustMeLine4;

  /// No description provided for @flow_guestAgeTitle.
  ///
  /// In en, this message translates to:
  /// **'What year were you born?'**
  String get flow_guestAgeTitle;

  /// No description provided for @flow_guestAgeHint.
  ///
  /// In en, this message translates to:
  /// **'We ask everyone. It stays on this phone.'**
  String get flow_guestAgeHint;

  /// No description provided for @flow_guestAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get flow_guestAgeLabel;

  /// No description provided for @flow_guestAgeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Year you were born, 4 digits'**
  String get flow_guestAgeSemantics;

  /// No description provided for @flow_yearFourDigits.
  ///
  /// In en, this message translates to:
  /// **'Enter the year with 4 digits, like 1994.'**
  String get flow_yearFourDigits;

  /// No description provided for @flow_yearFuture.
  ///
  /// In en, this message translates to:
  /// **'That year is in the future.'**
  String get flow_yearFuture;

  /// No description provided for @flow_yearCheck.
  ///
  /// In en, this message translates to:
  /// **'Check the year.'**
  String get flow_yearCheck;

  /// No description provided for @flow_ageStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Attune is for adults'**
  String get flow_ageStopTitle;

  /// No description provided for @flow_ageStopBody.
  ///
  /// In en, this message translates to:
  /// **'You need to be 18 or older to use Attune. We haven\'t saved anything you entered.'**
  String get flow_ageStopBody;

  /// No description provided for @flow_ageStopServerLead.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t create your account.'**
  String get flow_ageStopServerLead;

  /// No description provided for @flow_ageStopYouthLink.
  ///
  /// In en, this message translates to:
  /// **'Support for young people'**
  String get flow_ageStopYouthLink;

  /// No description provided for @flow_inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited to Attune'**
  String get flow_inviteTitle;

  /// No description provided for @flow_inviteBody.
  ///
  /// In en, this message translates to:
  /// **'Someone invited you to a private space on Attune. Create your account to see who it is and to join.'**
  String get flow_inviteBody;

  /// No description provided for @flow_inviteCreate.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get flow_inviteCreate;

  /// No description provided for @flow_inviteCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your invite code'**
  String get flow_inviteCodeTitle;

  /// No description provided for @flow_inviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get flow_inviteCodeLabel;

  /// No description provided for @flow_inviteCodeError.
  ///
  /// In en, this message translates to:
  /// **'Codes have 6 letters and numbers. Check it with the person who sent it.'**
  String get flow_inviteCodeError;

  /// No description provided for @flow_tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get flow_tryAgain;

  /// No description provided for @flow_nameTitle.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get flow_nameTitle;

  /// No description provided for @flow_nameHint.
  ///
  /// In en, this message translates to:
  /// **'This is the name your partner sees. Opinions never shows it.'**
  String get flow_nameHint;

  /// No description provided for @flow_nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get flow_nameLabel;

  /// No description provided for @flow_nameNeedsLetter.
  ///
  /// In en, this message translates to:
  /// **'Add a name with at least one letter.'**
  String get flow_nameNeedsLetter;

  /// No description provided for @flow_nameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Use 40 characters or fewer.'**
  String get flow_nameTooLong;

  /// No description provided for @flow_dobTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s your date of birth?'**
  String get flow_dobTitle;

  /// No description provided for @flow_dobHint.
  ///
  /// In en, this message translates to:
  /// **'We only ever show your age, never your birthday.'**
  String get flow_dobHint;

  /// No description provided for @flow_dobExample.
  ///
  /// In en, this message translates to:
  /// **'For example, {example}'**
  String flow_dobExample(String example);

  /// No description provided for @flow_dobDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get flow_dobDay;

  /// No description provided for @flow_dobMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get flow_dobMonth;

  /// No description provided for @flow_dobYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get flow_dobYear;

  /// No description provided for @flow_dobDaySemantics.
  ///
  /// In en, this message translates to:
  /// **'Day of birth'**
  String get flow_dobDaySemantics;

  /// No description provided for @flow_dobMonthSemantics.
  ///
  /// In en, this message translates to:
  /// **'Month of birth'**
  String get flow_dobMonthSemantics;

  /// No description provided for @flow_dobYearSemantics.
  ///
  /// In en, this message translates to:
  /// **'Year of birth'**
  String get flow_dobYearSemantics;

  /// No description provided for @flow_dobDayRange.
  ///
  /// In en, this message translates to:
  /// **'Day must be between 1 and 31.'**
  String get flow_dobDayRange;

  /// No description provided for @flow_dobMonthRange.
  ///
  /// In en, this message translates to:
  /// **'Month must be between 1 and 12.'**
  String get flow_dobMonthRange;

  /// No description provided for @flow_dobYearDigits.
  ///
  /// In en, this message translates to:
  /// **'Year must have 4 digits.'**
  String get flow_dobYearDigits;

  /// No description provided for @flow_dobNoSuchDate.
  ///
  /// In en, this message translates to:
  /// **'That date doesn\'t exist. Check the day and month.'**
  String get flow_dobNoSuchDate;

  /// No description provided for @flow_dobFuture.
  ///
  /// In en, this message translates to:
  /// **'That date is in the future.'**
  String get flow_dobFuture;

  /// No description provided for @flow_dobCheckYear.
  ///
  /// In en, this message translates to:
  /// **'Check the year.'**
  String get flow_dobCheckYear;

  /// No description provided for @flow_dobAge.
  ///
  /// In en, this message translates to:
  /// **'that makes you {age}.'**
  String flow_dobAge(int age);

  /// No description provided for @flow_phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s your phone number?'**
  String get flow_phoneTitle;

  /// No description provided for @flow_phoneHint.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a code to sign in. We never show your number to anyone.'**
  String get flow_phoneHint;

  /// No description provided for @flow_phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get flow_phoneLabel;

  /// No description provided for @flow_phoneCountrySemantics.
  ///
  /// In en, this message translates to:
  /// **'Country, {country}, {code}'**
  String flow_phoneCountrySemantics(String country, String code);

  /// No description provided for @flow_phoneChooseCountry.
  ///
  /// In en, this message translates to:
  /// **'Choose your country'**
  String get flow_phoneChooseCountry;

  /// No description provided for @flow_phoneSend.
  ///
  /// In en, this message translates to:
  /// **'Text me a code'**
  String get flow_phoneSend;

  /// No description provided for @flow_phoneTerms.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to the Terms and Privacy Policy.'**
  String get flow_phoneTerms;

  /// No description provided for @flow_phoneTooShort.
  ///
  /// In en, this message translates to:
  /// **'Check the number. It looks too short.'**
  String get flow_phoneTooShort;

  /// No description provided for @flow_phoneTooLong.
  ///
  /// In en, this message translates to:
  /// **'Check the number. It looks too long.'**
  String get flow_phoneTooLong;

  /// No description provided for @flow_phoneWrongCountry.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a {country} number. Check the country.'**
  String flow_phoneWrongCountry(String country);

  /// No description provided for @flow_sending.
  ///
  /// In en, this message translates to:
  /// **'Sending your code…'**
  String get flow_sending;

  /// No description provided for @flow_sendFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send a code. Try again or try WhatsApp.'**
  String get flow_sendFailed;

  /// No description provided for @flow_sendFailedSms.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send a code. Try again.'**
  String get flow_sendFailedSms;

  /// No description provided for @flow_tooManyCodes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Too many codes. Try again in 1 minute.} other{Too many codes. Try again in {minutes} minutes.}}'**
  String flow_tooManyCodes(int minutes);

  /// No description provided for @flow_tooManyTries.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Try again in a few minutes.'**
  String get flow_tooManyTries;

  /// No description provided for @flow_accountChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your account…'**
  String get flow_accountChecking;

  /// No description provided for @flow_accountCheckFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check your account'**
  String get flow_accountCheckFailedTitle;

  /// No description provided for @flow_accountCheckFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get flow_accountCheckFailedBody;

  /// No description provided for @flow_phoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Phone sign-in is unavailable right now. Please try again later.'**
  String get flow_phoneUnavailable;

  /// No description provided for @flow_codeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get flow_codeTitle;

  /// No description provided for @flow_codeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {number}.'**
  String flow_codeSubtitle(String number);

  /// No description provided for @flow_codeChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Wrong number? Change it'**
  String get flow_codeChangeNumber;

  /// No description provided for @flow_codeResendIn.
  ///
  /// In en, this message translates to:
  /// **'Send a new code in {time}'**
  String flow_codeResendIn(String time);

  /// No description provided for @flow_codeResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get flow_codeResend;

  /// No description provided for @flow_codeNewest.
  ///
  /// In en, this message translates to:
  /// **'Use the newest code.'**
  String get flow_codeNewest;

  /// No description provided for @flow_codeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Verification code, 6 digits'**
  String get flow_codeSemantics;

  /// No description provided for @flow_codeWrong.
  ///
  /// In en, this message translates to:
  /// **'That code didn\'t work. Check it and try again.'**
  String get flow_codeWrong;

  /// No description provided for @flow_codeExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Send a new one.'**
  String get flow_codeExpired;

  /// No description provided for @flow_codeAccepted.
  ///
  /// In en, this message translates to:
  /// **'Code accepted'**
  String get flow_codeAccepted;

  /// No description provided for @flow_codeCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check the code right now. Try again.'**
  String get flow_codeCheckFailed;

  /// No description provided for @flow_consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get flow_consentTitle;

  /// No description provided for @flow_consentUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ve updated our terms'**
  String get flow_consentUpdatedTitle;

  /// No description provided for @flow_consentAdults.
  ///
  /// In en, this message translates to:
  /// **'Attune is for adults. Everyone here is 18 or older.'**
  String get flow_consentAdults;

  /// No description provided for @flow_consentAi.
  ///
  /// In en, this message translates to:
  /// **'Some Attune features use AI to give you private suggestions. In a shared space they can read your chat with your partner, and only after you both agree. What it suggests to one of you is never shown to the other.'**
  String get flow_consentAi;

  /// No description provided for @flow_consentData.
  ///
  /// In en, this message translates to:
  /// **'You can download everything you\'ve added, and delete your account, any time.'**
  String get flow_consentData;

  /// No description provided for @flow_consentTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get flow_consentTermsLink;

  /// No description provided for @flow_consentPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get flow_consentPrivacyLink;

  /// No description provided for @flow_consentAiLink.
  ///
  /// In en, this message translates to:
  /// **'More about AI in Attune'**
  String get flow_consentAiLink;

  /// No description provided for @flow_consentAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get flow_consentAgree;

  /// No description provided for @flow_consentNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get flow_consentNotNow;

  /// No description provided for @flow_signupPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone sign-in is unavailable right now.'**
  String get flow_signupPhoneRequired;

  /// No description provided for @flow_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save that. Try again.'**
  String get flow_saveFailed;

  /// No description provided for @flow_noAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find an Attune account for this number'**
  String get flow_noAccountTitle;

  /// No description provided for @flow_noAccountBody.
  ///
  /// In en, this message translates to:
  /// **'You can create one now.'**
  String get flow_noAccountBody;

  /// No description provided for @flow_noAccountCreate.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get flow_noAccountCreate;

  /// No description provided for @flow_noAccountOtherNumber.
  ///
  /// In en, this message translates to:
  /// **'Use a different number'**
  String get flow_noAccountOtherNumber;

  /// No description provided for @flow_welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}.'**
  String flow_welcomeBack(String name);

  /// No description provided for @flow_welcomeBackNoName.
  ///
  /// In en, this message translates to:
  /// **'Welcome back.'**
  String get flow_welcomeBackNoName;

  /// No description provided for @flow_joinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Attune'**
  String get flow_joinTitle;

  /// No description provided for @flow_joinBody.
  ///
  /// In en, this message translates to:
  /// **'A private space for couples, a few introductions a day for singles, and a journal just for you.'**
  String get flow_joinBody;

  /// No description provided for @flow_phoneWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send by WhatsApp instead'**
  String get flow_phoneWhatsApp;

  /// No description provided for @flow_whatsAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Is WhatsApp on {number}?'**
  String flow_whatsAppTitle(String number);

  /// No description provided for @flow_whatsAppBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send the code to WhatsApp on this number. If WhatsApp is on a different number, we\'ll text you instead.'**
  String get flow_whatsAppBody;

  /// No description provided for @flow_whatsAppYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, send it to WhatsApp'**
  String get flow_whatsAppYes;

  /// No description provided for @flow_whatsAppNo.
  ///
  /// In en, this message translates to:
  /// **'No, text me'**
  String get flow_whatsAppNo;

  /// No description provided for @flow_codeTryWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Try WhatsApp'**
  String get flow_codeTryWhatsApp;

  /// No description provided for @flow_codeCallMe.
  ///
  /// In en, this message translates to:
  /// **'Call me with the code'**
  String get flow_codeCallMe;

  /// No description provided for @flow_codeCalling.
  ///
  /// In en, this message translates to:
  /// **'We\'re calling {number} now. The code is read out twice.'**
  String flow_codeCalling(String number);

  /// No description provided for @flow_tabMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get flow_tabMe;

  /// No description provided for @flow_tabSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get flow_tabSignIn;

  /// No description provided for @flow_pathTitle.
  ///
  /// In en, this message translates to:
  /// **'What brings you to Attune?'**
  String get flow_pathTitle;

  /// No description provided for @flow_pathJustMeLineFull.
  ///
  /// In en, this message translates to:
  /// **'Your journal, quizzes and Healing. Single, partnered or in between.'**
  String get flow_pathJustMeLineFull;

  /// No description provided for @flow_pathNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Not open in {country} yet'**
  String flow_pathNotOpen(String country);

  /// No description provided for @flow_pathFooter.
  ///
  /// In en, this message translates to:
  /// **'You can change this any time. Your journal and quizzes are yours whichever you choose.'**
  String get flow_pathFooter;

  /// No description provided for @flow_pathAlreadyInvited.
  ///
  /// In en, this message translates to:
  /// **'My partner already invited me'**
  String get flow_pathAlreadyInvited;

  /// No description provided for @flow_pathGroupSemantics.
  ///
  /// In en, this message translates to:
  /// **'Choose one of three'**
  String get flow_pathGroupSemantics;

  /// No description provided for @flow_pathDatingOffline.
  ///
  /// In en, this message translates to:
  /// **'Dating needs a connection. Try again when you\'re online.'**
  String get flow_pathDatingOffline;

  /// No description provided for @flow_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get flow_cancel;

  /// No description provided for @flow_cancelInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel your invite?'**
  String get flow_cancelInviteTitle;

  /// No description provided for @flow_cancelInviteBody.
  ///
  /// In en, this message translates to:
  /// **'Your invite code will stop working. Your partner won\'t be told.'**
  String get flow_cancelInviteBody;

  /// No description provided for @flow_cancelInviteBodyNamed.
  ///
  /// In en, this message translates to:
  /// **'Your invite code will stop working. {name} won\'t be told.'**
  String flow_cancelInviteBodyNamed(String name);

  /// No description provided for @flow_cancelInviteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel invite and switch'**
  String get flow_cancelInviteConfirm;

  /// No description provided for @flow_cancelInviteKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep invite'**
  String get flow_cancelInviteKeep;

  /// No description provided for @flow_pauseDatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Inviting a partner pauses Dating'**
  String get flow_pauseDatingTitle;

  /// No description provided for @flow_pauseDatingBody.
  ///
  /// In en, this message translates to:
  /// **'Your introductions stop and your Dating profile is hidden. Nobody is told.'**
  String get flow_pauseDatingBody;

  /// No description provided for @flow_switchOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Try again when you\'re connected.'**
  String get flow_switchOffline;

  /// No description provided for @flow_dobAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your date of birth'**
  String get flow_dobAddTitle;

  /// No description provided for @flow_holdTitle.
  ///
  /// In en, this message translates to:
  /// **'We need to check your account'**
  String get flow_holdTitle;

  /// No description provided for @flow_holdBody.
  ///
  /// In en, this message translates to:
  /// **'You can\'t use Attune while we do this. If you think this is a mistake, contact support.'**
  String get flow_holdBody;

  /// No description provided for @flow_holdContact.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get flow_holdContact;

  /// No description provided for @flow_signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get flow_signOut;

  /// No description provided for @flow_updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Attune to continue'**
  String get flow_updateTitle;

  /// No description provided for @flow_updateBody.
  ///
  /// In en, this message translates to:
  /// **'This version of Attune can\'t finish setting up your account. Update the app from your app store, then open it again.'**
  String get flow_updateBody;

  /// No description provided for @flow_checkOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check your account'**
  String get flow_checkOfflineTitle;

  /// No description provided for @flow_checkOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection, then try again.'**
  String get flow_checkOfflineBody;

  /// No description provided for @flow_invitePartnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite your partner'**
  String get flow_invitePartnerTitle;

  /// No description provided for @flow_invitePartnerBody.
  ///
  /// In en, this message translates to:
  /// **'Send a link. When your partner joins, your private space opens.'**
  String get flow_invitePartnerBody;

  /// No description provided for @flow_invitePartnerCreate.
  ///
  /// In en, this message translates to:
  /// **'Create my invite'**
  String get flow_invitePartnerCreate;

  /// No description provided for @flow_invitePartnerLater.
  ///
  /// In en, this message translates to:
  /// **'Invite later'**
  String get flow_invitePartnerLater;

  /// No description provided for @flow_invitePartnerDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get flow_invitePartnerDone;

  /// No description provided for @flow_pathOpenSpace.
  ///
  /// In en, this message translates to:
  /// **'You\'re in a shared space. To use Attune another way, end it or pause it first.'**
  String get flow_pathOpenSpace;

  /// No description provided for @flow_inviteCodeRefused.
  ///
  /// In en, this message translates to:
  /// **'This code didn\'t work. It may have expired or been used. Ask for a new one.'**
  String get flow_inviteCodeRefused;

  /// No description provided for @flow_inviteCodeAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in a shared space, so this invite can\'t be used.'**
  String get flow_inviteCodeAlreadyIn;

  /// No description provided for @flow_inviteCodeOffline.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check that code. Try again when you\'re online.'**
  String get flow_inviteCodeOffline;

  /// No description provided for @flow_ageStopAccountBody.
  ///
  /// In en, this message translates to:
  /// **'You need to be 18 or older to use Attune. Your account is on hold.'**
  String get flow_ageStopAccountBody;

  /// No description provided for @flow_spaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your space'**
  String get flow_spaceTitle;

  /// No description provided for @flow_settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get flow_settingsTooltip;

  /// No description provided for @flow_spaceJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get flow_spaceJournal;

  /// No description provided for @flow_spaceJournalLine.
  ///
  /// In en, this message translates to:
  /// **'Notes only you can read'**
  String get flow_spaceJournalLine;

  /// No description provided for @flow_spaceQuizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get flow_spaceQuizzes;

  /// No description provided for @flow_spaceQuizzesLine.
  ///
  /// In en, this message translates to:
  /// **'Short, private, about you'**
  String get flow_spaceQuizzesLine;

  /// No description provided for @flow_spaceHealing.
  ///
  /// In en, this message translates to:
  /// **'Healing'**
  String get flow_spaceHealing;

  /// No description provided for @flow_spaceHealingLine.
  ///
  /// In en, this message translates to:
  /// **'After a breakup or a loss'**
  String get flow_spaceHealingLine;

  /// No description provided for @flow_firstStartHere.
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get flow_firstStartHere;

  /// No description provided for @flow_firstWriteNote.
  ///
  /// In en, this message translates to:
  /// **'Write your first note'**
  String get flow_firstWriteNote;

  /// No description provided for @flow_firstQuiz.
  ///
  /// In en, this message translates to:
  /// **'Take a 3-minute look at how you connect'**
  String get flow_firstQuiz;

  /// No description provided for @flow_firstSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved, just for you.'**
  String get flow_firstSaved;

  /// No description provided for @flow_moreWays.
  ///
  /// In en, this message translates to:
  /// **'More ways to use Attune'**
  String get flow_moreWays;

  /// No description provided for @flow_moreInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite a partner'**
  String get flow_moreInvite;

  /// No description provided for @flow_justMeSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Use Attune just for you?'**
  String get flow_justMeSheetTitle;

  /// No description provided for @flow_justMeSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Dating will be paused and hidden. Nobody is told. You can delete your Dating profile from Dating settings.'**
  String get flow_justMeSheetBody;

  /// No description provided for @flow_justMeSheetSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get flow_justMeSheetSwitch;

  /// No description provided for @flow_waitWriteNote.
  ///
  /// In en, this message translates to:
  /// **'Write a first note'**
  String get flow_waitWriteNote;

  /// No description provided for @flow_waitQuiz.
  ///
  /// In en, this message translates to:
  /// **'A quiz about you, for you'**
  String get flow_waitQuiz;

  /// No description provided for @flow_waitReceipts.
  ///
  /// In en, this message translates to:
  /// **'When your partner joins, read receipts start off. You can each turn them on later.'**
  String get flow_waitReceipts;

  /// No description provided for @flow_inviteMenu.
  ///
  /// In en, this message translates to:
  /// **'Invite options'**
  String get flow_inviteMenu;

  /// No description provided for @flow_cancelThisInvite.
  ///
  /// In en, this message translates to:
  /// **'Cancel this invite'**
  String get flow_cancelThisInvite;

  /// No description provided for @flow_cancelThisInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this invite?'**
  String get flow_cancelThisInviteTitle;

  /// No description provided for @flow_cancelThisInviteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel invite'**
  String get flow_cancelThisInviteConfirm;

  /// No description provided for @flow_waitReceiptsNamed.
  ///
  /// In en, this message translates to:
  /// **'When your partner joins, read receipts start off. You and {partnerFirstName} can each turn them on later.'**
  String flow_waitReceiptsNamed(String partnerFirstName);

  /// No description provided for @flow_slotDatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Dating'**
  String get flow_slotDatingTitle;

  /// No description provided for @flow_slotDatingBody.
  ///
  /// In en, this message translates to:
  /// **'Up to 3 introductions a day. A match only when you both say yes.'**
  String get flow_slotDatingBody;

  /// No description provided for @flow_slotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up Dating'**
  String get flow_slotSetUp;

  /// No description provided for @flow_slotNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not ready? Use Attune just for me'**
  String get flow_slotNotReady;

  /// No description provided for @flow_slotNotOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t open in {country} yet'**
  String flow_slotNotOpenTitle(String country);

  /// No description provided for @flow_slotNotOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {countries}. We\'re adding countries one at a time.'**
  String flow_slotNotOpenBody(String countries);

  /// No description provided for @flow_slotChangeCountry.
  ///
  /// In en, this message translates to:
  /// **'Not in {country}? Change'**
  String flow_slotChangeCountry(String country);

  /// No description provided for @flow_slotChooseCountry.
  ///
  /// In en, this message translates to:
  /// **'Choose your country'**
  String get flow_slotChooseCountry;

  /// No description provided for @flow_slotClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t open yet'**
  String get flow_slotClosedTitle;

  /// No description provided for @flow_slotClosedBody.
  ///
  /// In en, this message translates to:
  /// **'It opens one country at a time. Your journal, quizzes and Healing are here meanwhile.'**
  String get flow_slotClosedBody;

  /// No description provided for @flow_slotGentleWait.
  ///
  /// In en, this message translates to:
  /// **'Dating opens for you on {date}.'**
  String flow_slotGentleWait(String date);

  /// No description provided for @flow_slotGentleWaitWhy.
  ///
  /// In en, this message translates to:
  /// **'This pause is because your relationship ended here. It isn\'t a judgement about you.'**
  String get flow_slotGentleWaitWhy;

  /// No description provided for @flow_slotHealing.
  ///
  /// In en, this message translates to:
  /// **'Healing is here if you want it'**
  String get flow_slotHealing;

  /// No description provided for @flow_slotLocked.
  ///
  /// In en, this message translates to:
  /// **'Dating is locked'**
  String get flow_slotLocked;

  /// No description provided for @flow_slotLockedLine.
  ///
  /// In en, this message translates to:
  /// **'Enter your Safety PIN to show it'**
  String get flow_slotLockedLine;

  /// No description provided for @flow_lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Dating lock'**
  String get flow_lockTitle;

  /// No description provided for @flow_lockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for your Safety PIN before showing Dating.'**
  String get flow_lockSubtitle;

  /// No description provided for @flow_slotGentleWaitNoDate.
  ///
  /// In en, this message translates to:
  /// **'Dating opens for you after a pause.'**
  String get flow_slotGentleWaitNoDate;

  /// No description provided for @flow_pushTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get flow_pushTurnOn;

  /// No description provided for @flow_pushAskR2.
  ///
  /// In en, this message translates to:
  /// **'Get a heads-up when your partner joins'**
  String get flow_pushAskR2;

  /// No description provided for @flow_pushAskR2Named.
  ///
  /// In en, this message translates to:
  /// **'Get a heads-up when {name} joins'**
  String flow_pushAskR2Named(String name);

  /// No description provided for @flow_reminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Remind me to write'**
  String get flow_reminderTitle;

  /// No description provided for @flow_reminderOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get flow_reminderOff;

  /// No description provided for @flow_reminderWhen.
  ///
  /// In en, this message translates to:
  /// **'{days} at {time}'**
  String flow_reminderWhen(String days, String time);

  /// No description provided for @flow_weekdaysMon.
  ///
  /// In en, this message translates to:
  /// **'Mondays'**
  String get flow_weekdaysMon;

  /// No description provided for @flow_weekdaysTue.
  ///
  /// In en, this message translates to:
  /// **'Tuesdays'**
  String get flow_weekdaysTue;

  /// No description provided for @flow_weekdaysWed.
  ///
  /// In en, this message translates to:
  /// **'Wednesdays'**
  String get flow_weekdaysWed;

  /// No description provided for @flow_weekdaysThu.
  ///
  /// In en, this message translates to:
  /// **'Thursdays'**
  String get flow_weekdaysThu;

  /// No description provided for @flow_weekdaysFri.
  ///
  /// In en, this message translates to:
  /// **'Fridays'**
  String get flow_weekdaysFri;

  /// No description provided for @flow_weekdaysSat.
  ///
  /// In en, this message translates to:
  /// **'Saturdays'**
  String get flow_weekdaysSat;

  /// No description provided for @flow_weekdaysSun.
  ///
  /// In en, this message translates to:
  /// **'Sundays'**
  String get flow_weekdaysSun;

  /// No description provided for @flow_weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get flow_weekdayMon;

  /// No description provided for @flow_weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get flow_weekdayTue;

  /// No description provided for @flow_weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get flow_weekdayWed;

  /// No description provided for @flow_weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get flow_weekdayThu;

  /// No description provided for @flow_weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get flow_weekdayFri;

  /// No description provided for @flow_weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get flow_weekdaySat;

  /// No description provided for @flow_weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get flow_weekdaySun;

  /// No description provided for @flow_reminderSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'When should we remind you?'**
  String get flow_reminderSheetTitle;

  /// No description provided for @flow_reminderDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get flow_reminderDay;

  /// No description provided for @flow_reminderTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get flow_reminderTime;

  /// No description provided for @flow_reminderChangeTime.
  ///
  /// In en, this message translates to:
  /// **'Change time'**
  String get flow_reminderChangeTime;

  /// No description provided for @flow_reminderTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get flow_reminderTurnOn;

  /// No description provided for @flow_reminderTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get flow_reminderTurnOff;

  /// No description provided for @flow_reminderNeedsPush.
  ///
  /// In en, this message translates to:
  /// **'Reminders need notifications.'**
  String get flow_reminderNeedsPush;

  /// No description provided for @flow_reminderTurnOnPush.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications'**
  String get flow_reminderTurnOnPush;

  /// No description provided for @flow_reminderReadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your reminder. Try again.'**
  String get flow_reminderReadFailed;

  /// No description provided for @flow_reminderQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Reminders can be set from {start} to {end}.'**
  String flow_reminderQuietHours(String start, String end);

  /// No description provided for @flow_howTitle.
  ///
  /// In en, this message translates to:
  /// **'How you use Attune'**
  String get flow_howTitle;

  /// No description provided for @flow_howSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In a relationship, dating, or just for you'**
  String get flow_howSubtitle;

  /// No description provided for @flow_howFooter.
  ///
  /// In en, this message translates to:
  /// **'Your journal, quizzes and Healing stay yours whichever you choose. Nobody is told when you change this.'**
  String get flow_howFooter;

  /// No description provided for @flow_sharedOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re in a shared space with {name}'**
  String flow_sharedOpenTitle(String name);

  /// No description provided for @flow_yourPartner.
  ///
  /// In en, this message translates to:
  /// **'your partner'**
  String get flow_yourPartner;

  /// No description provided for @flow_sharedOpenBody.
  ///
  /// In en, this message translates to:
  /// **'To use Attune another way, end it first. Pausing keeps it, read-only, for up to 30 days.'**
  String get flow_sharedOpenBody;

  /// No description provided for @flow_sharedPause.
  ///
  /// In en, this message translates to:
  /// **'Pause our shared space'**
  String get flow_sharedPause;

  /// No description provided for @flow_sharedEnd.
  ///
  /// In en, this message translates to:
  /// **'End relationship'**
  String get flow_sharedEnd;

  /// No description provided for @flow_notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get flow_notNow;

  /// No description provided for @flow_joinAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in a relationship on Attune. End it first to join a new one.'**
  String get flow_joinAlreadyIn;

  /// No description provided for @flow_joinNotPossible.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t link these accounts. If you think this is wrong, contact support.'**
  String get flow_joinNotPossible;

  /// No description provided for @flow_joinOwn.
  ///
  /// In en, this message translates to:
  /// **'This is your own invite. Send it to your partner instead.'**
  String get flow_joinOwn;

  /// No description provided for @flow_joinInvalid.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that invite. Check the code with the person who sent it.'**
  String get flow_joinInvalid;

  /// No description provided for @flow_joinTryLater.
  ///
  /// In en, this message translates to:
  /// **'You\'ve checked a lot of codes. Try again in a little while.'**
  String get flow_joinTryLater;

  /// No description provided for @flow_inviteErrorSignUp.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your account first, then try again.'**
  String get flow_inviteErrorSignUp;

  /// No description provided for @flow_inviteErrorCap.
  ///
  /// In en, this message translates to:
  /// **'You already have 3 invites waiting. Cancel one before you send another.'**
  String get flow_inviteErrorCap;

  /// No description provided for @flow_inviteErrorAgeRequired.
  ///
  /// In en, this message translates to:
  /// **'Add your date of birth first, then send your invite.'**
  String get flow_inviteErrorAgeRequired;

  /// No description provided for @flow_inviteErrorTryAgain.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t make your invite. Try again.'**
  String get flow_inviteErrorTryAgain;

  /// No description provided for @flow_inviteMsgSimpleOpen.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}, I\'d like us to try Attune together. It\'s a private space just for the two of us.'**
  String flow_inviteMsgSimpleOpen(String name);

  /// No description provided for @flow_inviteMsgSimpleOpenNoName.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'d like us to try Attune together. It\'s a private space just for the two of us.'**
  String get flow_inviteMsgSimpleOpenNoName;

  /// No description provided for @flow_inviteMsgSimpleGet.
  ///
  /// In en, this message translates to:
  /// **'Get the app: {link}'**
  String flow_inviteMsgSimpleGet(String link);

  /// No description provided for @flow_inviteMsgCasualOpen.
  ///
  /// In en, this message translates to:
  /// **'Hey {name}! I found an app for couples and thought of us. Private, just you and me.'**
  String flow_inviteMsgCasualOpen(String name);

  /// No description provided for @flow_inviteMsgCasualOpenNoName.
  ///
  /// In en, this message translates to:
  /// **'Hey! I found an app for couples and thought of us. Private, just you and me.'**
  String get flow_inviteMsgCasualOpenNoName;

  /// No description provided for @flow_inviteMsgCasualGet.
  ///
  /// In en, this message translates to:
  /// **'Get it here: {link}'**
  String flow_inviteMsgCasualGet(String link);

  /// No description provided for @flow_inviteMsgPidginOpen.
  ///
  /// In en, this message translates to:
  /// **'{name}, make we try Attune. Na private space for only you and me.'**
  String flow_inviteMsgPidginOpen(String name);

  /// No description provided for @flow_inviteMsgPidginOpenNoName.
  ///
  /// In en, this message translates to:
  /// **'Make we try Attune. Na private space for only you and me.'**
  String get flow_inviteMsgPidginOpenNoName;

  /// No description provided for @flow_inviteMsgPidginGet.
  ///
  /// In en, this message translates to:
  /// **'Download am: {link}'**
  String flow_inviteMsgPidginGet(String link);

  /// No description provided for @flow_inviteMsgOpenCode.
  ///
  /// In en, this message translates to:
  /// **'Open Attune → I have an invite → {code}'**
  String flow_inviteMsgOpenCode(String code);

  /// No description provided for @flow_inviteMsgFoundMyself.
  ///
  /// In en, this message translates to:
  /// **'I found this myself. I just thought it\'d be nice.'**
  String get flow_inviteMsgFoundMyself;

  /// No description provided for @flow_inviteCodeServerError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Try again.'**
  String get flow_inviteCodeServerError;

  /// No description provided for @flow_invitePartnerBodyNamed.
  ///
  /// In en, this message translates to:
  /// **'Send a link. When {name} joins, your private space opens.'**
  String flow_invitePartnerBodyNamed(String name);

  /// No description provided for @flow_r1NameLabel.
  ///
  /// In en, this message translates to:
  /// **'Their first name (optional)'**
  String get flow_r1NameLabel;

  /// No description provided for @flow_r1NameHelper.
  ///
  /// In en, this message translates to:
  /// **'Used in your message and on this phone only.'**
  String get flow_r1NameHelper;

  /// No description provided for @flow_r1ToneTitle.
  ///
  /// In en, this message translates to:
  /// **'How should it sound?'**
  String get flow_r1ToneTitle;

  /// No description provided for @flow_r1ToneGroup.
  ///
  /// In en, this message translates to:
  /// **'Choose one of the message styles'**
  String get flow_r1ToneGroup;

  /// No description provided for @flow_r1ToneSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get flow_r1ToneSimple;

  /// No description provided for @flow_r1ToneCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get flow_r1ToneCasual;

  /// No description provided for @flow_r1TonePidgin.
  ///
  /// In en, this message translates to:
  /// **'Pidgin'**
  String get flow_r1TonePidgin;

  /// No description provided for @flow_r1FoundMyselfToggle.
  ///
  /// In en, this message translates to:
  /// **'Add: \'I found this myself. I just thought it\'d be nice.\''**
  String get flow_r1FoundMyselfToggle;

  /// No description provided for @flow_r1PreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What your partner will see'**
  String get flow_r1PreviewTitle;

  /// No description provided for @flow_r1PreviewTitleNamed.
  ///
  /// In en, this message translates to:
  /// **'What {name} will see'**
  String flow_r1PreviewTitleNamed(String name);

  /// No description provided for @flow_r1Making.
  ///
  /// In en, this message translates to:
  /// **'Making your invite'**
  String get flow_r1Making;

  /// No description provided for @flow_r1CodePending.
  ///
  /// In en, this message translates to:
  /// **'(your code)'**
  String get flow_r1CodePending;

  /// No description provided for @flow_r1SendWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send on WhatsApp'**
  String get flow_r1SendWhatsApp;

  /// No description provided for @flow_r1ShareOther.
  ///
  /// In en, this message translates to:
  /// **'Share another way'**
  String get flow_r1ShareOther;

  /// No description provided for @flow_r1ShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get flow_r1ShowQr;

  /// No description provided for @flow_r1CopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get flow_r1CopyCode;

  /// No description provided for @flow_r1CodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied.'**
  String get flow_r1CodeCopied;

  /// No description provided for @flow_r1QrTitle.
  ///
  /// In en, this message translates to:
  /// **'Your invite code'**
  String get flow_r1QrTitle;

  /// No description provided for @flow_r1QrSemantics.
  ///
  /// In en, this message translates to:
  /// **'A QR code for your invite link'**
  String get flow_r1QrSemantics;

  /// No description provided for @flow_inviteCodeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Invite code {code}'**
  String flow_inviteCodeSemantics(String code);

  /// No description provided for @flow_ri3Title.
  ///
  /// In en, this message translates to:
  /// **'Join {name}?'**
  String flow_ri3Title(String name);

  /// No description provided for @flow_ri3TitleUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Join your partner?'**
  String get flow_ri3TitleUnnamed;

  /// No description provided for @flow_ri3Body.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to a private space on Attune.'**
  String flow_ri3Body(String name);

  /// No description provided for @flow_ri3BodyUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Your partner invited you to a private space on Attune.'**
  String get flow_ri3BodyUnnamed;

  /// No description provided for @flow_ri3Button.
  ///
  /// In en, this message translates to:
  /// **'Join {name}'**
  String flow_ri3Button(String name);

  /// No description provided for @flow_ri3ButtonUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get flow_ri3ButtonUnnamed;

  /// No description provided for @flow_joinOtherWay.
  ///
  /// In en, this message translates to:
  /// **'Not what you expected? Choose another way to use Attune'**
  String get flow_joinOtherWay;

  /// No description provided for @flow_joinEnterAgain.
  ///
  /// In en, this message translates to:
  /// **'Enter the code again'**
  String get flow_joinEnterAgain;

  /// No description provided for @flow_joinExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'This invite has expired.'**
  String get flow_joinExpiredTitle;

  /// No description provided for @flow_joinExpired.
  ///
  /// In en, this message translates to:
  /// **'Ask {name} to send a new one.'**
  String flow_joinExpired(String name);

  /// No description provided for @flow_joinExpiredUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Ask the person who sent it to send a new one.'**
  String get flow_joinExpiredUnnamed;

  /// No description provided for @flow_joinAskWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Ask {name} on WhatsApp'**
  String flow_joinAskWhatsApp(String name);

  /// No description provided for @flow_joinAskWhatsAppUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Ask on WhatsApp'**
  String get flow_joinAskWhatsAppUnnamed;

  /// No description provided for @flow_joinExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}, my Attune invite expired. Could you send me a new one?'**
  String flow_joinExpiredMessage(String name);

  /// No description provided for @flow_joinExpiredMessageUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Hi, my Attune invite expired. Could you send me a new one?'**
  String get flow_joinExpiredMessageUnnamed;

  /// No description provided for @flow_joinChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your invite'**
  String get flow_joinChecking;

  /// No description provided for @flow_linkedTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {couple}'**
  String flow_linkedTitle(String couple);

  /// No description provided for @flow_linkedBody.
  ///
  /// In en, this message translates to:
  /// **'Your private space with {name} is open.'**
  String flow_linkedBody(String name);

  /// No description provided for @flow_linkedBodyUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Your private space with your partner is open.'**
  String get flow_linkedBodyUnnamed;

  /// No description provided for @flow_pushAskR4.
  ///
  /// In en, this message translates to:
  /// **'Get notified when {name} messages you'**
  String flow_pushAskR4(String name);

  /// No description provided for @flow_pushAskR4Unnamed.
  ///
  /// In en, this message translates to:
  /// **'Get notified when your partner messages you'**
  String get flow_pushAskR4Unnamed;

  /// No description provided for @flow_inviteErrorNotPossible.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t make your invite. If you think this is wrong, contact support.'**
  String get flow_inviteErrorNotPossible;

  /// No description provided for @flow_guideWaitLine.
  ///
  /// In en, this message translates to:
  /// **'We\'ll suggest a private reflection space if this takes a little while.'**
  String get flow_guideWaitLine;

  /// No description provided for @flow_guideReflectTitle.
  ///
  /// In en, this message translates to:
  /// **'A private space while you wait'**
  String get flow_guideReflectTitle;

  /// No description provided for @flow_guideReflectBody.
  ///
  /// In en, this message translates to:
  /// **'Your reflections stay private to you.'**
  String get flow_guideReflectBody;

  /// No description provided for @flow_guideOpenJournal.
  ///
  /// In en, this message translates to:
  /// **'Open your journal'**
  String get flow_guideOpenJournal;

  /// No description provided for @flow_guideWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'It\'s been a week'**
  String get flow_guideWeekTitle;

  /// No description provided for @flow_guideWeekBody.
  ///
  /// In en, this message translates to:
  /// **'Your invite to {name} has run its week. What would you like to do?'**
  String flow_guideWeekBody(String name);

  /// No description provided for @flow_guideWeekBodyUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Your invite to your partner has run its week. What would you like to do?'**
  String get flow_guideWeekBodyUnnamed;

  /// No description provided for @flow_guideKeepWaiting.
  ///
  /// In en, this message translates to:
  /// **'Keep waiting'**
  String get flow_guideKeepWaiting;

  /// No description provided for @flow_guideSendNew.
  ///
  /// In en, this message translates to:
  /// **'Send a new invite'**
  String get flow_guideSendNew;

  /// No description provided for @flow_guideSendNewHelper.
  ///
  /// In en, this message translates to:
  /// **'Send it to the same number or a different one.'**
  String get flow_guideSendNewHelper;

  /// No description provided for @flow_guideOnMyOwn.
  ///
  /// In en, this message translates to:
  /// **'Use Attune on my own for now'**
  String get flow_guideOnMyOwn;

  /// No description provided for @flow_day30.
  ///
  /// In en, this message translates to:
  /// **'Want to send {name} a new invite?'**
  String flow_day30(String name);

  /// No description provided for @flow_day30Unnamed.
  ///
  /// In en, this message translates to:
  /// **'Want to send your partner a new invite?'**
  String get flow_day30Unnamed;

  /// No description provided for @flow_day30Dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get flow_day30Dismiss;

  /// No description provided for @flow_r3SendAgain.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get flow_r3SendAgain;

  /// No description provided for @flow_invitePartnerNamed.
  ///
  /// In en, this message translates to:
  /// **'Invite {name}'**
  String flow_invitePartnerNamed(String name);

  /// No description provided for @aboutUs_title.
  ///
  /// In en, this message translates to:
  /// **'About us'**
  String get aboutUs_title;

  /// No description provided for @aboutUs_step.
  ///
  /// In en, this message translates to:
  /// **'{step} of {total}'**
  String aboutUs_step(int step, int total);

  /// No description provided for @aboutUs_stepSemantics.
  ///
  /// In en, this message translates to:
  /// **'Question {step} of {total}'**
  String aboutUs_stepSemantics(int step, int total);

  /// No description provided for @aboutUs_skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get aboutUs_skip;

  /// No description provided for @aboutUs_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get aboutUs_done;

  /// No description provided for @aboutUs_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get aboutUs_save;

  /// No description provided for @aboutUs_moreAbout.
  ///
  /// In en, this message translates to:
  /// **'More about this'**
  String get aboutUs_moreAbout;

  /// No description provided for @aboutUs_moreAboutBody.
  ///
  /// In en, this message translates to:
  /// **'Either of you can change these. It\'s never used to score or type you.'**
  String get aboutUs_moreAboutBody;

  /// No description provided for @aboutUs_moreAboutDraft.
  ///
  /// In en, this message translates to:
  /// **'Before {name} joins, your answers are a draft only you can see. When {name} joins, your answers become your shared About us.'**
  String aboutUs_moreAboutDraft(String name);

  /// No description provided for @aboutUs_moreAboutDraftUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Before your partner joins, your answers are a draft only you can see. When your partner joins, your answers become your shared About us.'**
  String get aboutUs_moreAboutDraftUnnamed;

  /// No description provided for @aboutUs_stageQuestion.
  ///
  /// In en, this message translates to:
  /// **'How would you describe where you two are?'**
  String get aboutUs_stageQuestion;

  /// No description provided for @aboutUs_stageDating.
  ///
  /// In en, this message translates to:
  /// **'Dating'**
  String get aboutUs_stageDating;

  /// No description provided for @aboutUs_stageEngaged.
  ///
  /// In en, this message translates to:
  /// **'Engaged'**
  String get aboutUs_stageEngaged;

  /// No description provided for @aboutUs_stageMarried.
  ///
  /// In en, this message translates to:
  /// **'Married'**
  String get aboutUs_stageMarried;

  /// No description provided for @aboutUs_stageOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get aboutUs_stageOther;

  /// No description provided for @aboutUs_stageEngagedHelper.
  ///
  /// In en, this message translates to:
  /// **'Planning to marry, including after the knocking and before the wedding.'**
  String get aboutUs_stageEngagedHelper;

  /// No description provided for @aboutUs_stageMarriedHelper.
  ///
  /// In en, this message translates to:
  /// **'Any kind of marriage: customary, religious or civil.'**
  String get aboutUs_stageMarriedHelper;

  /// No description provided for @aboutUs_stageWordsLabel.
  ///
  /// In en, this message translates to:
  /// **'In your own words'**
  String get aboutUs_stageWordsLabel;

  /// No description provided for @aboutUs_stageWhy.
  ///
  /// In en, this message translates to:
  /// **'So what Attune suggests fits you two. Either of you can change this. It\'s never used to score or type you.'**
  String get aboutUs_stageWhy;

  /// No description provided for @aboutUs_sinceQuestion.
  ///
  /// In en, this message translates to:
  /// **'When did you two get together?'**
  String get aboutUs_sinceQuestion;

  /// No description provided for @aboutUs_sinceHelper.
  ///
  /// In en, this message translates to:
  /// **'Use whichever date feels right to {couple}.'**
  String aboutUs_sinceHelper(String couple);

  /// No description provided for @aboutUs_sinceWhy.
  ///
  /// In en, this message translates to:
  /// **'So we can remember your anniversary with you, if you\'d like.'**
  String get aboutUs_sinceWhy;

  /// No description provided for @aboutUs_monthLabel.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get aboutUs_monthLabel;

  /// No description provided for @aboutUs_yearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get aboutUs_yearLabel;

  /// No description provided for @aboutUs_dayLabel.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get aboutUs_dayLabel;

  /// No description provided for @aboutUs_monthOptional.
  ///
  /// In en, this message translates to:
  /// **'Month (optional)'**
  String get aboutUs_monthOptional;

  /// No description provided for @aboutUs_dayOptional.
  ///
  /// In en, this message translates to:
  /// **'Day (optional)'**
  String get aboutUs_dayOptional;

  /// No description provided for @aboutUs_notSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get aboutUs_notSure;

  /// No description provided for @aboutUs_sinceAddDay.
  ///
  /// In en, this message translates to:
  /// **'Add the day'**
  String get aboutUs_sinceAddDay;

  /// No description provided for @aboutUs_sinceNoMonth.
  ///
  /// In en, this message translates to:
  /// **'Not sure of the month'**
  String get aboutUs_sinceNoMonth;

  /// No description provided for @aboutUs_sinceSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggested dates'**
  String get aboutUs_sinceSuggestions;

  /// No description provided for @aboutUs_errorFuture.
  ///
  /// In en, this message translates to:
  /// **'That date is in the future.'**
  String get aboutUs_errorFuture;

  /// No description provided for @aboutUs_errorNoSuchDate.
  ///
  /// In en, this message translates to:
  /// **'Check the day and month.'**
  String get aboutUs_errorNoSuchDate;

  /// No description provided for @aboutUs_errorNeedsYear.
  ///
  /// In en, this message translates to:
  /// **'Choose a year.'**
  String get aboutUs_errorNeedsYear;

  /// No description provided for @aboutUs_marryQuestion.
  ///
  /// In en, this message translates to:
  /// **'What year did you marry?'**
  String get aboutUs_marryQuestion;

  /// No description provided for @aboutUs_ceremonyN.
  ///
  /// In en, this message translates to:
  /// **'Ceremony {n}'**
  String aboutUs_ceremonyN(int n);

  /// No description provided for @aboutUs_ceremonyLabelGroup.
  ///
  /// In en, this message translates to:
  /// **'What kind of ceremony? (optional)'**
  String get aboutUs_ceremonyLabelGroup;

  /// No description provided for @aboutUs_labelCustomary.
  ///
  /// In en, this message translates to:
  /// **'Customary'**
  String get aboutUs_labelCustomary;

  /// No description provided for @aboutUs_labelChurch.
  ///
  /// In en, this message translates to:
  /// **'Church'**
  String get aboutUs_labelChurch;

  /// No description provided for @aboutUs_labelMosque.
  ///
  /// In en, this message translates to:
  /// **'Mosque'**
  String get aboutUs_labelMosque;

  /// No description provided for @aboutUs_labelCivil.
  ///
  /// In en, this message translates to:
  /// **'Civil'**
  String get aboutUs_labelCivil;

  /// No description provided for @aboutUs_labelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get aboutUs_labelOther;

  /// No description provided for @aboutUs_addCeremony.
  ///
  /// In en, this message translates to:
  /// **'Had more than one ceremony? Add another'**
  String get aboutUs_addCeremony;

  /// No description provided for @aboutUs_removeCeremony.
  ///
  /// In en, this message translates to:
  /// **'Remove this ceremony'**
  String get aboutUs_removeCeremony;

  /// No description provided for @aboutUs_livingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Where do you two live?'**
  String get aboutUs_livingQuestion;

  /// No description provided for @aboutUs_livingTogether.
  ///
  /// In en, this message translates to:
  /// **'Together'**
  String get aboutUs_livingTogether;

  /// No description provided for @aboutUs_livingApartNearby.
  ///
  /// In en, this message translates to:
  /// **'Apart, nearby'**
  String get aboutUs_livingApartNearby;

  /// No description provided for @aboutUs_livingLongDistance.
  ///
  /// In en, this message translates to:
  /// **'Long distance'**
  String get aboutUs_livingLongDistance;

  /// No description provided for @aboutUs_livingWhy.
  ///
  /// In en, this message translates to:
  /// **'So plans, maps and reminders fit how you live.'**
  String get aboutUs_livingWhy;

  /// No description provided for @aboutUs_childrenQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are there children in your life together?'**
  String get aboutUs_childrenQuestion;

  /// No description provided for @aboutUs_childrenNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get aboutUs_childrenNo;

  /// No description provided for @aboutUs_childrenYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get aboutUs_childrenYes;

  /// No description provided for @aboutUs_childrenExpecting.
  ///
  /// In en, this message translates to:
  /// **'We\'re expecting'**
  String get aboutUs_childrenExpecting;

  /// No description provided for @aboutUs_childrenPreferNot.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get aboutUs_childrenPreferNot;

  /// No description provided for @aboutUs_childrenAges.
  ///
  /// In en, this message translates to:
  /// **'Their ages (optional)'**
  String get aboutUs_childrenAges;

  /// No description provided for @aboutUs_bandUnder2.
  ///
  /// In en, this message translates to:
  /// **'Under 2'**
  String get aboutUs_bandUnder2;

  /// No description provided for @aboutUs_band2to5.
  ///
  /// In en, this message translates to:
  /// **'2–5'**
  String get aboutUs_band2to5;

  /// No description provided for @aboutUs_band6to12.
  ///
  /// In en, this message translates to:
  /// **'6–12'**
  String get aboutUs_band6to12;

  /// No description provided for @aboutUs_band13to17.
  ///
  /// In en, this message translates to:
  /// **'13–17'**
  String get aboutUs_band13to17;

  /// No description provided for @aboutUs_band18plus.
  ///
  /// In en, this message translates to:
  /// **'18+'**
  String get aboutUs_band18plus;

  /// No description provided for @aboutUs_childrenWhy.
  ///
  /// In en, this message translates to:
  /// **'So ideas and reminders suit your family.'**
  String get aboutUs_childrenWhy;

  /// No description provided for @aboutUs_anniversaryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remember your anniversary?'**
  String get aboutUs_anniversaryQuestion;

  /// No description provided for @aboutUs_anniversaryNo.
  ///
  /// In en, this message translates to:
  /// **'No, thanks'**
  String get aboutUs_anniversaryNo;

  /// No description provided for @aboutUs_anniversaryTogether.
  ///
  /// In en, this message translates to:
  /// **'The day you got together'**
  String get aboutUs_anniversaryTogether;

  /// No description provided for @aboutUs_anniversaryCeremony.
  ///
  /// In en, this message translates to:
  /// **'{label} ceremony, {year}'**
  String aboutUs_anniversaryCeremony(String label, String year);

  /// No description provided for @aboutUs_anniversaryCeremonyPlain.
  ///
  /// In en, this message translates to:
  /// **'Ceremony, {year}'**
  String aboutUs_anniversaryCeremonyPlain(String year);

  /// No description provided for @aboutUs_anniversaryWhatDay.
  ///
  /// In en, this message translates to:
  /// **'What day was it?'**
  String get aboutUs_anniversaryWhatDay;

  /// No description provided for @aboutUs_rowSince.
  ///
  /// In en, this message translates to:
  /// **'Together since'**
  String get aboutUs_rowSince;

  /// No description provided for @aboutUs_rowStage.
  ///
  /// In en, this message translates to:
  /// **'Where you are'**
  String get aboutUs_rowStage;

  /// No description provided for @aboutUs_rowCeremonies.
  ///
  /// In en, this message translates to:
  /// **'Ceremonies'**
  String get aboutUs_rowCeremonies;

  /// No description provided for @aboutUs_rowLiving.
  ///
  /// In en, this message translates to:
  /// **'Where you live'**
  String get aboutUs_rowLiving;

  /// No description provided for @aboutUs_rowChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get aboutUs_rowChildren;

  /// No description provided for @aboutUs_rowAnniversary.
  ///
  /// In en, this message translates to:
  /// **'Anniversary'**
  String get aboutUs_rowAnniversary;

  /// No description provided for @aboutUs_notAnswered.
  ///
  /// In en, this message translates to:
  /// **'Not answered yet'**
  String get aboutUs_notAnswered;

  /// No description provided for @aboutUs_childrenYesBands.
  ///
  /// In en, this message translates to:
  /// **'Yes ({bands})'**
  String aboutUs_childrenYesBands(String bands);

  /// No description provided for @aboutUs_anniversaryOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aboutUs_anniversaryOff;

  /// No description provided for @aboutUs_ceremonyLine.
  ///
  /// In en, this message translates to:
  /// **'{label}, {year}'**
  String aboutUs_ceremonyLine(String label, String year);

  /// No description provided for @aboutUs_changedBy.
  ///
  /// In en, this message translates to:
  /// **'Changed by {name}'**
  String aboutUs_changedBy(String name);

  /// No description provided for @aboutUs_changedByYou.
  ///
  /// In en, this message translates to:
  /// **'Changed by you'**
  String get aboutUs_changedByYou;

  /// No description provided for @aboutUs_changedByPartner.
  ///
  /// In en, this message translates to:
  /// **'Changed by your partner'**
  String get aboutUs_changedByPartner;

  /// No description provided for @aboutUs_footer.
  ///
  /// In en, this message translates to:
  /// **'Either of you can change these. It\'s never used to score or type you.'**
  String get aboutUs_footer;

  /// No description provided for @aboutUs_readOnlyUntil.
  ///
  /// In en, this message translates to:
  /// **'You can read this until {date}.'**
  String aboutUs_readOnlyUntil(String date);

  /// No description provided for @aboutUs_pendingSync.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. It will be shared when you\'re back online.'**
  String get aboutUs_pendingSync;

  /// No description provided for @aboutUs_loadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load About us. Check your connection and try again.'**
  String get aboutUs_loadFailed;

  /// No description provided for @aboutUs_answerQuestions.
  ///
  /// In en, this message translates to:
  /// **'Answer a few questions'**
  String get aboutUs_answerQuestions;

  /// No description provided for @aboutUs_rowEditHint.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get aboutUs_rowEditHint;

  /// No description provided for @aboutUs_errorAnniversaryNeedsDay.
  ///
  /// In en, this message translates to:
  /// **'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.'**
  String get aboutUs_errorAnniversaryNeedsDay;

  /// No description provided for @aboutUs_errorReadOnly.
  ///
  /// In en, this message translates to:
  /// **'About us can\'t be changed right now.'**
  String get aboutUs_errorReadOnly;

  /// No description provided for @aboutUs_errorWordsTooLong.
  ///
  /// In en, this message translates to:
  /// **'Use 40 characters or fewer.'**
  String get aboutUs_errorWordsTooLong;

  /// No description provided for @aboutUs_cardTitle.
  ///
  /// In en, this message translates to:
  /// **'About us'**
  String get aboutUs_cardTitle;

  /// No description provided for @aboutUs_cardBody.
  ///
  /// In en, this message translates to:
  /// **'A few easy questions about you two. Skip any of them. {name} sees your answers after joining.'**
  String aboutUs_cardBody(String name);

  /// No description provided for @aboutUs_cardBodyUnnamed.
  ///
  /// In en, this message translates to:
  /// **'A few easy questions about you two. Skip any of them. Your partner sees your answers after joining.'**
  String get aboutUs_cardBodyUnnamed;

  /// No description provided for @aboutUs_settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When you got together, where you live and more'**
  String get aboutUs_settingsSubtitle;

  /// No description provided for @aboutUs_reminderFollows.
  ///
  /// In en, this message translates to:
  /// **'This reminder follows About us'**
  String get aboutUs_reminderFollows;

  /// No description provided for @aboutUs_reminderChange.
  ///
  /// In en, this message translates to:
  /// **'Change in About us'**
  String get aboutUs_reminderChange;

  /// No description provided for @aboutUs_reminderStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Your anniversary reminder will stop'**
  String get aboutUs_reminderStopTitle;

  /// No description provided for @aboutUs_reminderStopBody.
  ///
  /// In en, this message translates to:
  /// **'It follows this ceremony\'s date. It can follow the day you got together instead.'**
  String get aboutUs_reminderStopBody;

  /// No description provided for @aboutUs_reminderStopOff.
  ///
  /// In en, this message translates to:
  /// **'Turn it off'**
  String get aboutUs_reminderStopOff;

  /// No description provided for @aboutUs_sinceHelperUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Use whichever date feels right.'**
  String get aboutUs_sinceHelperUnnamed;

  /// No description provided for @aboutUs_reminderOffline.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check this reminder. Check your connection and try again.'**
  String get aboutUs_reminderOffline;

  /// No description provided for @aboutUs_reminderTimes.
  ///
  /// In en, this message translates to:
  /// **'Reminder times and note'**
  String get aboutUs_reminderTimes;

  /// No description provided for @aboutUs_reminderLocked.
  ///
  /// In en, this message translates to:
  /// **'Its date, title and type follow About us.'**
  String get aboutUs_reminderLocked;

  /// No description provided for @aboutUs_anniversaryHandMade.
  ///
  /// In en, this message translates to:
  /// **'You already have an anniversary reminder, so we won\'t add another.'**
  String get aboutUs_anniversaryHandMade;

  /// No description provided for @flow_dormantTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Attune'**
  String get flow_dormantTitle;

  /// No description provided for @flow_dormantBody.
  ///
  /// In en, this message translates to:
  /// **'Let\'s get you set up.'**
  String get flow_dormantBody;

  /// No description provided for @flow_dormantNew.
  ///
  /// In en, this message translates to:
  /// **'I\'m new to Attune'**
  String get flow_dormantNew;

  /// No description provided for @flow_dormantUsedBefore.
  ///
  /// In en, this message translates to:
  /// **'Used Attune before on this number? Contact support'**
  String get flow_dormantUsedBefore;

  /// No description provided for @flow_dormantFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t reach Attune. Check your connection and try again.'**
  String get flow_dormantFailed;

  /// No description provided for @flow_dormantTryLater.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Try again in an hour.'**
  String get flow_dormantTryLater;

  /// No description provided for @flow_dormantExpired.
  ///
  /// In en, this message translates to:
  /// **'That took too long. Enter your number again.'**
  String get flow_dormantExpired;

  /// No description provided for @flow_freshStartTitle.
  ///
  /// In en, this message translates to:
  /// **'One more code to finish'**
  String get flow_freshStartTitle;

  /// No description provided for @flow_freshStartBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a new code to {phone}.'**
  String flow_freshStartBody(String phone);

  /// No description provided for @flow_freshStartSend.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get flow_freshStartSend;

  /// No description provided for @flow_dobSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get flow_dobSettingsTitle;

  /// No description provided for @flow_dobSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only your age is shown, never the date'**
  String get flow_dobSettingsSubtitle;

  /// No description provided for @flow_dobSettingsAge.
  ///
  /// In en, this message translates to:
  /// **'Your age: {age}'**
  String flow_dobSettingsAge(int age);

  /// No description provided for @flow_dobSettingsNoAge.
  ///
  /// In en, this message translates to:
  /// **'We don\'t have your date of birth yet.'**
  String get flow_dobSettingsNoAge;

  /// No description provided for @flow_dobSettingsFixUntil.
  ///
  /// In en, this message translates to:
  /// **'If it\'s wrong, you can fix it once, until {date}.'**
  String flow_dobSettingsFixUntil(String date);

  /// No description provided for @flow_dobSettingsContact.
  ///
  /// In en, this message translates to:
  /// **'To change this, contact support.'**
  String get flow_dobSettingsContact;

  /// No description provided for @flow_dobSettingsFix.
  ///
  /// In en, this message translates to:
  /// **'Fix a mistake'**
  String get flow_dobSettingsFix;

  /// No description provided for @flow_dobFixTitle.
  ///
  /// In en, this message translates to:
  /// **'Fix your date of birth'**
  String get flow_dobFixTitle;

  /// No description provided for @flow_dobFixSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get flow_dobFixSaved;

  /// No description provided for @flow_dobSettingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load this. Check your connection and try again.'**
  String get flow_dobSettingsLoadFailed;

  /// No description provided for @support_childReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a concern about a child'**
  String get support_childReportTitle;

  /// No description provided for @support_childReportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A person on our team reads every report'**
  String get support_childReportSubtitle;

  /// No description provided for @support_childReportBody.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you saw and where. A person on our team reads every report. If a child is in danger right now, call your local emergency number.'**
  String get support_childReportBody;

  /// No description provided for @support_childReportWhere.
  ///
  /// In en, this message translates to:
  /// **'Where did you see it?'**
  String get support_childReportWhere;

  /// No description provided for @support_childReportChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get support_childReportChat;

  /// No description provided for @support_childReportStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get support_childReportStories;

  /// No description provided for @support_childReportOpinions.
  ///
  /// In en, this message translates to:
  /// **'Opinions'**
  String get support_childReportOpinions;

  /// No description provided for @support_childReportDating.
  ///
  /// In en, this message translates to:
  /// **'Dating'**
  String get support_childReportDating;

  /// No description provided for @support_childReportElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Somewhere else'**
  String get support_childReportElsewhere;

  /// No description provided for @support_childReportDetails.
  ///
  /// In en, this message translates to:
  /// **'What did you see?'**
  String get support_childReportDetails;

  /// No description provided for @support_childReportCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max}'**
  String support_childReportCount(int count, int max);

  /// No description provided for @support_childReportSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get support_childReportSend;

  /// No description provided for @support_childReportThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you. We\'ve received your report.'**
  String get support_childReportThanks;

  /// No description provided for @support_childReportLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent 5 reports today. To tell us more, email {email}.'**
  String support_childReportLimit(String email);

  /// No description provided for @support_childReportFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send this. Check your connection and try again.'**
  String get support_childReportFailed;

  /// No description provided for @support_childReportDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get support_childReportDone;

  /// No description provided for @support_childReportTooLong.
  ///
  /// In en, this message translates to:
  /// **'This is too long. Keep it to 2,000 characters or fewer.'**
  String get support_childReportTooLong;

  /// No description provided for @support_childReportInvalid.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send this as written. Make it shorter and try again, or email {email}.'**
  String support_childReportInvalid(String email);

  /// No description provided for @support_resourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Support resources'**
  String get support_resourcesTitle;

  /// No description provided for @support_resourcesIntro.
  ///
  /// In en, this message translates to:
  /// **'If something does not feel safe, these contacts and planning resources may be useful.'**
  String get support_resourcesIntro;

  /// No description provided for @support_resourcesNoEmergencyService.
  ///
  /// In en, this message translates to:
  /// **'Attune cannot assess an emergency or contact help for you.'**
  String get support_resourcesNoEmergencyService;

  /// No description provided for @support_quickExit.
  ///
  /// In en, this message translates to:
  /// **'Quick exit'**
  String get support_quickExit;

  /// No description provided for @support_quickExitBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to exit the app and show a neutral screen.'**
  String get support_quickExitBody;

  /// No description provided for @support_exitNow.
  ///
  /// In en, this message translates to:
  /// **'Exit now'**
  String get support_exitNow;

  /// No description provided for @support_notNow.
  ///
  /// In en, this message translates to:
  /// **'Not relevant right now'**
  String get support_notNow;

  /// No description provided for @support_helpFor.
  ///
  /// In en, this message translates to:
  /// **'Help for {country}'**
  String support_helpFor(String country);

  /// No description provided for @support_changeCountry.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get support_changeCountry;

  /// No description provided for @support_changeCountryLabel.
  ///
  /// In en, this message translates to:
  /// **'Change country. Now showing {country}'**
  String support_changeCountryLabel(String country);

  /// No description provided for @support_chooseCountry.
  ///
  /// In en, this message translates to:
  /// **'Choose your country to see help near you.'**
  String get support_chooseCountry;

  /// No description provided for @support_chooseCountryButton.
  ///
  /// In en, this message translates to:
  /// **'Choose a country'**
  String get support_chooseCountryButton;

  /// No description provided for @support_loading.
  ///
  /// In en, this message translates to:
  /// **'Looking for help near you'**
  String get support_loading;

  /// No description provided for @support_emergencyHeading.
  ///
  /// In en, this message translates to:
  /// **'In an emergency'**
  String get support_emergencyHeading;

  /// No description provided for @support_anywhereHeading.
  ///
  /// In en, this message translates to:
  /// **'Anywhere in the world'**
  String get support_anywhereHeading;

  /// No description provided for @support_categoryEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get support_categoryEmergency;

  /// No description provided for @support_categoryDv.
  ///
  /// In en, this message translates to:
  /// **'Domestic abuse'**
  String get support_categoryDv;

  /// No description provided for @support_categoryCrisis.
  ///
  /// In en, this message translates to:
  /// **'Someone to talk to now'**
  String get support_categoryCrisis;

  /// No description provided for @support_categorySexualAssault.
  ///
  /// In en, this message translates to:
  /// **'Sexual assault'**
  String get support_categorySexualAssault;

  /// No description provided for @support_categorySextortion.
  ///
  /// In en, this message translates to:
  /// **'Threats to share images'**
  String get support_categorySextortion;

  /// No description provided for @support_categoryChildSafety.
  ///
  /// In en, this message translates to:
  /// **'A child at risk'**
  String get support_categoryChildSafety;

  /// No description provided for @support_categoryYouth.
  ///
  /// In en, this message translates to:
  /// **'For young people'**
  String get support_categoryYouth;

  /// No description provided for @support_categoryLgbtqLegal.
  ///
  /// In en, this message translates to:
  /// **'LGBTQ+ and legal help'**
  String get support_categoryLgbtqLegal;

  /// No description provided for @support_categoryGrief.
  ///
  /// In en, this message translates to:
  /// **'Grief'**
  String get support_categoryGrief;

  /// No description provided for @support_categoryPerinatal.
  ///
  /// In en, this message translates to:
  /// **'Pregnancy and after birth'**
  String get support_categoryPerinatal;

  /// No description provided for @support_categoryAddiction.
  ///
  /// In en, this message translates to:
  /// **'Alcohol, drugs and gambling'**
  String get support_categoryAddiction;

  /// No description provided for @support_categoryFinancialControl.
  ///
  /// In en, this message translates to:
  /// **'Money and control'**
  String get support_categoryFinancialControl;

  /// No description provided for @support_notPolice.
  ///
  /// In en, this message translates to:
  /// **'Not the police'**
  String get support_notPolice;

  /// No description provided for @support_police.
  ///
  /// In en, this message translates to:
  /// **'Police'**
  String get support_police;

  /// No description provided for @support_call.
  ///
  /// In en, this message translates to:
  /// **'Call {number}'**
  String support_call(String number);

  /// No description provided for @support_text.
  ///
  /// In en, this message translates to:
  /// **'Text {number}'**
  String support_text(String number);

  /// No description provided for @support_whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get support_whatsapp;

  /// No description provided for @support_website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get support_website;

  /// No description provided for @support_callConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Call {number}?'**
  String support_callConfirmTitle(String number);

  /// No description provided for @support_callConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Calls may show in your phone\'s call history.'**
  String get support_callConfirmBody;

  /// No description provided for @support_callConfirmCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get support_callConfirmCall;

  /// No description provided for @support_textConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Text {number}?'**
  String support_textConfirmTitle(String number);

  /// No description provided for @support_textConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Messages may stay on your phone.'**
  String get support_textConfirmBody;

  /// No description provided for @support_linkConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Open {site}?'**
  String support_linkConfirmTitle(String site);

  /// No description provided for @support_linkConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It may show in your browser history.'**
  String get support_linkConfirmBody;

  /// No description provided for @support_open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get support_open;

  /// No description provided for @support_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get support_cancel;

  /// No description provided for @support_unsupported.
  ///
  /// In en, this message translates to:
  /// **'We don\'t have a checked list for {country} yet.'**
  String support_unsupported(String country);

  /// No description provided for @support_noFocusList.
  ///
  /// In en, this message translates to:
  /// **'We don\'t have a checked list for this in {country} yet.'**
  String support_noFocusList(String country);

  /// No description provided for @support_findHelpline.
  ///
  /// In en, this message translates to:
  /// **'Find a helpline'**
  String get support_findHelpline;

  /// No description provided for @support_localEmergency.
  ///
  /// In en, this message translates to:
  /// **'In an emergency, call your local emergency number.'**
  String get support_localEmergency;

  /// No description provided for @support_griefTitle.
  ///
  /// In en, this message translates to:
  /// **'Grief support'**
  String get support_griefTitle;

  /// No description provided for @support_youthTitle.
  ///
  /// In en, this message translates to:
  /// **'Support for young people'**
  String get support_youthTitle;

  /// No description provided for @support_writeInJournal.
  ///
  /// In en, this message translates to:
  /// **'Write about it in your journal'**
  String get support_writeInJournal;

  /// No description provided for @support_settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Find support'**
  String get support_settingsTitle;

  /// No description provided for @support_settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Helplines for where you are'**
  String get support_settingsSubtitle;

  /// No description provided for @support_cannotOpen.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t open here. Try it from another phone or computer.'**
  String get support_cannotOpen;

  /// No description provided for @flow_healingChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get flow_healingChoiceTitle;

  /// No description provided for @flow_healingBreakup.
  ///
  /// In en, this message translates to:
  /// **'A breakup'**
  String get flow_healingBreakup;

  /// No description provided for @flow_healingLoss.
  ///
  /// In en, this message translates to:
  /// **'Someone I love died'**
  String get flow_healingLoss;

  /// No description provided for @support_whatsappConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The chat may stay in WhatsApp on your phone.'**
  String get support_whatsappConfirmBody;

  /// The way out of a focused support view (grief, young people): never "Not relevant right now" there (W7 final review M-7).
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get support_back;

  /// Shown under an Opinions post, comment or edit the content filter refused for contact details (Spec 1 W9a). The draft stays.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers, emails, links and usernames can\'t go in Opinions. They can identify you or someone else. Take it out and post again.'**
  String get opinions_filterContactInfo;

  /// Shown under an Opinions post, comment or edit the content filter refused for a slur (Spec 1 W9a). The draft stays.
  ///
  /// In en, this message translates to:
  /// **'This includes a word that attacks people for who they are. Opinions doesn\'t allow it.'**
  String get opinions_filterSlur;

  /// Shown under an Opinions post, comment or edit the content filter refused for explicit sexual content (Spec 1 W9a). The draft stays.
  ///
  /// In en, this message translates to:
  /// **'Opinions doesn\'t allow sexual content. You can describe what happened without explicit words.'**
  String get opinions_filterExplicit;

  /// Shown above the Opinions comment field when the content filter refused the quoted text of the comment being replied to, not the writer's own words (Spec 1 W9a, batch-3 review I-3). Replaces the reason line. The draft stays.
  ///
  /// In en, this message translates to:
  /// **'The comment you\'re replying to can\'t be quoted in Opinions. Your own words are fine. Close the reply and post again.'**
  String get opinions_filterQuoted;

  /// Shown under the reason line when the Opinions content filter refused one of a post's poll options (Spec 1 W9a, batch-3 review I-3). The draft stays.
  ///
  /// In en, this message translates to:
  /// **'It\'s in one of your poll options.'**
  String get opinions_filterPollOption;

  /// The link to Support, in Opinions compose and every post and comment menu (Spec 1 W9b), and in the journal entry menu (W9c). Shown whatever anyone typed.
  ///
  /// In en, this message translates to:
  /// **'Need support now?'**
  String get support_needSupportNow;

  /// A report reason in both Opinions report lists (Spec 1 W9b). It goes to a person and never hides the post.
  ///
  /// In en, this message translates to:
  /// **'Someone may be at risk'**
  String get opinions_reportAtRisk;

  /// Shown after an at-risk report (Spec 1 W9b).
  ///
  /// In en, this message translates to:
  /// **'Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.'**
  String get opinions_atRiskThanks;

  /// Opens Support from the at-risk report's thank-you (Spec 1 W9b).
  ///
  /// In en, this message translates to:
  /// **'See emergency numbers'**
  String get opinions_atRiskSeeNumbers;

  /// Closes the at-risk report's thank-you (Spec 1 W9b).
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get opinions_atRiskClose;

  /// An at-risk report that did not reach the server (Spec 1 W9b). With opinions_safety_v1 on, also any other report reason that did not reach the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send your report. Please try again.'**
  String get opinions_reportFailed;

  /// With opinions_safety_v1 on, shown after a post or comment report with any reason other than Someone may be at risk reached the server (Spec 1 W9b, owner ruling (c)). Promises no review time: review queue v0 lists only the priority reasons.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your report has been sent.'**
  String get opinions_reportSent;

  /// Shown when a report from Opinions takes longer than 400 ms to reach the server (Spec 1 W9b, section 2.2), at-risk always and every reason with opinions_safety_v1 on. Replaced by the thank-you or the failure.
  ///
  /// In en, this message translates to:
  /// **'Sending your report'**
  String get opinions_reportSending;

  /// The writer's card, shown instead of a reflection when an entry reads as a crisis (Spec 1 W9c). Only the writer sees it.
  ///
  /// In en, this message translates to:
  /// **'If things feel heavy right now, you don\'t have to carry it alone. Support is here if you want it.'**
  String get journal_supportCardBody;

  /// Opens Support from the journal's writer card (Spec 1 W9c).
  ///
  /// In en, this message translates to:
  /// **'See support'**
  String get journal_supportSeeSupport;

  /// Dismisses the journal's writer card (Spec 1 W9c).
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get journal_supportNotNow;

  /// The Patterns tab after the writer chose Not now on its support card (Spec 1 W9c, ruling PF-C6). Shown instead of a summary for the rest of this run; never stored.
  ///
  /// In en, this message translates to:
  /// **'Patterns will show here again later'**
  String get journal_supportPatternsAway;

  /// Under journal_supportPatternsAway, on the Patterns tab after Not now on its support card (Spec 1 W9c, ruling PF-C6; batch-8 review M-5).
  ///
  /// In en, this message translates to:
  /// **'Your entries are saved and stay private to you.'**
  String get journal_supportPatternsAwayBody;

  /// Spec 2 D0 (the gentle wait): the title. Clinician-reviewed copy (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'Before you begin'**
  String get dating_gentleWaitTitle;

  /// Spec 2 D0: when the relationship ended and when Dating opens. Both dates in full words (MyDateFormat.toDate). Clinician-reviewed copy (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'Your relationship on Attune ended on {endDate}. Dating opens for you on {openDate}, when your shared space closes. If you both close it sooner, Dating opens then.'**
  String dating_gentleWaitBody(String endDate, String openDate);

  /// Spec 2 D0: why there is a wait. Clinician-reviewed copy (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'This pause is because your relationship ended here. It isn\'t a judgement about you.'**
  String get dating_gentleWaitNotJudgement;

  /// Spec 2 D0: the heading above the private reflection.
  ///
  /// In en, this message translates to:
  /// **'Three questions, just for you'**
  String get dating_gentleWaitQuestionsTitle;

  /// Spec 2 D0: under the reflection heading.
  ///
  /// In en, this message translates to:
  /// **'Only you can see these, and nothing is scored.'**
  String get dating_gentleWaitQuestionsHint;

  /// Spec 2 D0: reflection question 1 (optional answer, up to 500 characters).
  ///
  /// In en, this message translates to:
  /// **'What do you want to carry into your next relationship?'**
  String get dating_gentleWaitQuestion1;

  /// Spec 2 D0: reflection question 2 (optional answer, up to 500 characters).
  ///
  /// In en, this message translates to:
  /// **'What are you hoping for now?'**
  String get dating_gentleWaitQuestion2;

  /// Spec 2 D0: reflection question 3 (optional answer, up to 500 characters).
  ///
  /// In en, this message translates to:
  /// **'How will you know if you need more time?'**
  String get dating_gentleWaitQuestion3;

  /// Spec 2 D0: under each answer, how many characters it holds.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} characters'**
  String dating_gentleWaitAnswerCount(int count, int max);

  /// Spec 2 D0: the secondary button that saves the three answers.
  ///
  /// In en, this message translates to:
  /// **'Save my answers'**
  String get dating_gentleWaitSave;

  /// Spec 2 D0: read out after the answers are saved.
  ///
  /// In en, this message translates to:
  /// **'Your answers are saved.'**
  String get dating_gentleWaitSaved;

  /// Spec 2 D0: the card that opens Healing. Clinician-reviewed copy (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'Healing is here if you want it. It\'s there to help, and it\'s never required.'**
  String get dating_gentleWaitHealing;

  /// Spec 2 D0: the primary button; setup runs as usual and introductions start on the open date.
  ///
  /// In en, this message translates to:
  /// **'Set up Dating now'**
  String get dating_gentleWaitSetUp;

  /// Spec 2 §3.0: the banner on a Dating screen while the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Dating needs a connection.'**
  String get dating_offline;

  /// Spec 2 §3.0: under a save button that is off while the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Connect to save this answer.'**
  String get dating_connectToSave;

  /// Spec 2 §3.0: a server failure on a Dating screen.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get dating_errorGeneric;

  /// Spec 2 §3.0: the button that tries a failed Dating read again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dating_retry;

  /// Spec 2 D0: the save button while every answer is blank and answers are saved; saving blank answers clears them (B3 carry).
  ///
  /// In en, this message translates to:
  /// **'Clear my answers'**
  String get dating_gentleWaitClear;

  /// Spec 2 D0: read out after the answers are cleared.
  ///
  /// In en, this message translates to:
  /// **'Your answers are cleared.'**
  String get dating_gentleWaitCleared;

  /// Spec 2 D0: the server was busy saving or clearing (reason busy); calm, never an error. Your answers stay in the fields. DV reviewer read (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'This is taking a little longer than usual. Your answers are still here, so try again in a moment.'**
  String get dating_gentleWaitBusy;

  /// Spec 2 §3.0: the server was busy on a Dating read; calm, never an error; a Retry button follows. DV reviewer read (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'This is taking a little longer than usual. Try again in a moment.'**
  String get dating_busy;

  /// Spec 2 D0: the server was busy clearing the answers (reason busy); calm, never an error, and never says the answers are kept. DV reviewer read (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'This is taking a little longer than usual. Try clearing again in a moment.'**
  String get dating_gentleWaitClearBusy;

  /// Spec 2 D0: when the relationship ended and when Dating opens, when closing the shared space together can no longer end the wait sooner (the former partner's account is gone, or the person moved on; W2 final review M-4). Both dates in full words (MyDateFormat.toDate). Clinician- and DV-reviewed copy (W2 gate).
  ///
  /// In en, this message translates to:
  /// **'Your relationship on Attune ended on {endDate}. Dating opens for you on {openDate}.'**
  String dating_gentleWaitBodyNoShortcut(String endDate, String openDate);

  /// The Dating lock's PIN screen: asks for the Safety PIN again after the sheet was dismissed (Spec 2 W3a, R-8).
  ///
  /// In en, this message translates to:
  /// **'Enter my PIN'**
  String get dating_unlockButton;

  /// Spec 2 §3.1 state reverify_device, and D0 when the phone isn't trusted (W2 carry M-3).
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you on this phone to see Dating.'**
  String get dating_sectionReverify;

  /// D0, after Save, when the server answers not_eligible (Spec 2 W3a, W2 carry M-3). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t available on this account right now, so your answers weren\'t saved.'**
  String get dating_gentleWaitNotEligible;

  /// The UK inside a Dating sentence (Spec 2 §3.10 copy names it in full).
  ///
  /// In en, this message translates to:
  /// **'the United Kingdom'**
  String get dating_countryUk;

  /// An open country with its open regions, e.g. Ghana (Greater Accra and Ashanti) (Spec 2 §3.2 D1 line 7, §3.10).
  ///
  /// In en, this message translates to:
  /// **'{country} ({regions})'**
  String dating_countryWithRegions(String country, String regions);

  /// Spec 2 §3.1 states feature_unavailable and country_closed.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t open in {country} yet.'**
  String dating_sectionNotOpen(String country);

  /// Spec 2 §3.1 state region_closed.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {regions} for now.'**
  String dating_sectionRegionOpenOnly(String regions);

  /// Spec 2 §3.1, §3.10 primary.
  ///
  /// In en, this message translates to:
  /// **'Tell me when it\'s here'**
  String get dating_tellMe;

  /// Spec 2 §3.1, §3.10 region variant.
  ///
  /// In en, this message translates to:
  /// **'Tell me when it\'s open in {region}'**
  String dating_tellMeRegion(String region);

  /// Spec 2 §3.10, after Tell me when it's here. Settings = Dating settings.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know. You can turn this off in Settings.'**
  String get dating_tellMeDone;

  /// Cancels Tell me when it's here (Spec 2 W3a). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Turn this off'**
  String get dating_tellMeOff;

  /// Spec 2 §3.10 title.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t open in {country} yet'**
  String dating_notOpenTitle(String country);

  /// Spec 2 §3.10 body; {countries} is built from get_dating_availability (R-36).
  ///
  /// In en, this message translates to:
  /// **'Attune opens Dating one country at a time, so we can keep it safe and well looked after. It\'s open in {countries} now.'**
  String dating_notOpenBody(String countries);

  /// Spec 2 §3.10 region variant title.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {regions} for now'**
  String dating_notOpenRegionTitle(String regions);

  /// Spec 2 §3.10 region variant body.
  ///
  /// In en, this message translates to:
  /// **'We\'re opening other regions as soon as we can look after them well.'**
  String get dating_notOpenRegionBody;

  /// Spec 2 §3.10 secondary (Dating path only).
  ///
  /// In en, this message translates to:
  /// **'Use Attune just for me'**
  String get dating_justForMe;

  /// Spec 2 §3.1 state not_started.
  ///
  /// In en, this message translates to:
  /// **'Meet a few people a day. Only when it\'s mutual.'**
  String get dating_sectionNotStarted;

  /// Spec 2 §3.1 state setup_in_progress.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up Dating'**
  String get dating_sectionFinish;

  /// Spec 2 §3.1 cool_off/ready, §3.2 D13.
  ///
  /// In en, this message translates to:
  /// **'Your first introductions arrive {date} at {time}.'**
  String dating_sectionFirstDrop(String date, String time);

  /// Spec 2 §3.1 active until W5b's Today (plan R-30). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Dating is on. Your introductions will show here.'**
  String get dating_sectionActive;

  /// Spec 2 §3.1 state paused.
  ///
  /// In en, this message translates to:
  /// **'Dating is paused. Nobody new sees you.'**
  String get dating_sectionPaused;

  /// Spec 2 §3.1 paused.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get dating_resume;

  /// Paused by the relationship guard; resume isn't offered (plan, carry 9). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Dating is paused while you have a shared space on Attune.'**
  String get dating_sectionPausedRelationship;

  /// Spec 2 §2.4 kill-switch note (then Why?). For the LGBTQ+ reviewer.
  ///
  /// In en, this message translates to:
  /// **'Introductions between people of the same gender aren\'t available in {country} now. We\'ve removed that choice from your profile.'**
  String dating_sectionSameGenderNote(String country);

  /// Spec 2 §2.4, §3.2 D5/D6 link to the static sheet.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get dating_why;

  /// Spec 2 §3.2 D5 Why? sheet (static; opening it calls nothing). For the LGBTQ+ reviewer.
  ///
  /// In en, this message translates to:
  /// **'In {country}, relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know. Until we can protect people properly here, Attune only introduces men and women to each other. Nothing you choose here is stored unless you continue. We\'ll look at this again after legal advice and talking with local groups.'**
  String dating_whyBody(String country);

  /// Closes a Dating sheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dating_close;

  /// After the same-gender kill switch: back to D5 (plan). For the LGBTQ+ reviewer.
  ///
  /// In en, this message translates to:
  /// **'Choose again'**
  String get dating_chooseAgain;

  /// Spec 2 §3.1 away.
  ///
  /// In en, this message translates to:
  /// **'Dating is hidden while you\'re away.'**
  String get dating_sectionAway;

  /// Spec 2 §3.1 restricted, before W7a's category and date (plan R-29). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Your Dating account is restricted. The rest of Attune works as usual.'**
  String get dating_sectionRestricted;

  /// Spec 2 §3.1 hold, before W7a (plan R-29). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Your Dating profile is paused while we look into something. This isn\'t a decision yet.'**
  String get dating_sectionHold;

  /// Spec 2 §3.7 age check copy.
  ///
  /// In en, this message translates to:
  /// **'We need to confirm your age before you can use Dating.'**
  String get dating_sectionAgeReview;

  /// Spec 2 home state unavailable (W2 owner decision 1).
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t available on this account right now.'**
  String get dating_sectionUnavailable;

  /// Spec 2 §3.15: the locked section's semantic label.
  ///
  /// In en, this message translates to:
  /// **'Dating, locked'**
  String get dating_sectionLockedLabel;

  /// Spec 2 §3.12.
  ///
  /// In en, this message translates to:
  /// **'Dating settings'**
  String get dating_settingsTitle;

  /// Dating settings row while a Tell me request exists (plan). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Tell me when Dating opens'**
  String get dating_settingsNotice;

  /// Dating settings: the gentle-wait reflection's clear, reachable in any state (W2 carry 5). For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'Clear my answers to the three questions'**
  String get dating_settingsClearReflection;

  /// A resume or activation refused with path_not_dating (W2 carry 1).
  ///
  /// In en, this message translates to:
  /// **'Choose Dating in How you use Attune to carry on.'**
  String get dating_errorPathNotDating;

  /// Link to Spec 1's How you use Attune.
  ///
  /// In en, this message translates to:
  /// **'How you use Attune'**
  String get dating_openHowYouUse;

  /// Resume refused (resume_gates_not_met).
  ///
  /// In en, this message translates to:
  /// **'Dating can\'t resume on this account right now.'**
  String get dating_errorResumeGates;

  /// A lifecycle call refused for consent (back to D4).
  ///
  /// In en, this message translates to:
  /// **'Agree to Dating\'s terms again to carry on.'**
  String get dating_errorConsent;

  /// A lifecycle call refused: profile incomplete.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up Dating first.'**
  String get dating_errorIncomplete;

  /// Spec 2 §3.0 rate limit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve done this a lot today. Try again tomorrow.'**
  String get dating_errorRateLimited;

  /// No description provided for @dating_region_gh_af.
  ///
  /// In en, this message translates to:
  /// **'Ahafo'**
  String get dating_region_gh_af;

  /// No description provided for @dating_region_gh_ah.
  ///
  /// In en, this message translates to:
  /// **'Ashanti'**
  String get dating_region_gh_ah;

  /// No description provided for @dating_region_gh_bo.
  ///
  /// In en, this message translates to:
  /// **'Bono'**
  String get dating_region_gh_bo;

  /// No description provided for @dating_region_gh_be.
  ///
  /// In en, this message translates to:
  /// **'Bono East'**
  String get dating_region_gh_be;

  /// No description provided for @dating_region_gh_cp.
  ///
  /// In en, this message translates to:
  /// **'Central'**
  String get dating_region_gh_cp;

  /// No description provided for @dating_region_gh_ep.
  ///
  /// In en, this message translates to:
  /// **'Eastern'**
  String get dating_region_gh_ep;

  /// No description provided for @dating_region_gh_aa.
  ///
  /// In en, this message translates to:
  /// **'Greater Accra'**
  String get dating_region_gh_aa;

  /// No description provided for @dating_region_gh_ne.
  ///
  /// In en, this message translates to:
  /// **'North East'**
  String get dating_region_gh_ne;

  /// No description provided for @dating_region_gh_np.
  ///
  /// In en, this message translates to:
  /// **'Northern'**
  String get dating_region_gh_np;

  /// No description provided for @dating_region_gh_ot.
  ///
  /// In en, this message translates to:
  /// **'Oti'**
  String get dating_region_gh_ot;

  /// No description provided for @dating_region_gh_sv.
  ///
  /// In en, this message translates to:
  /// **'Savannah'**
  String get dating_region_gh_sv;

  /// No description provided for @dating_region_gh_ue.
  ///
  /// In en, this message translates to:
  /// **'Upper East'**
  String get dating_region_gh_ue;

  /// No description provided for @dating_region_gh_uw.
  ///
  /// In en, this message translates to:
  /// **'Upper West'**
  String get dating_region_gh_uw;

  /// No description provided for @dating_region_gh_tv.
  ///
  /// In en, this message translates to:
  /// **'Volta'**
  String get dating_region_gh_tv;

  /// No description provided for @dating_region_gh_wp.
  ///
  /// In en, this message translates to:
  /// **'Western'**
  String get dating_region_gh_wp;

  /// No description provided for @dating_region_gh_wn.
  ///
  /// In en, this message translates to:
  /// **'Western North'**
  String get dating_region_gh_wn;

  /// No description provided for @dating_side_gh_accra.
  ///
  /// In en, this message translates to:
  /// **'Accra'**
  String get dating_side_gh_accra;

  /// No description provided for @dating_side_gh_tema.
  ///
  /// In en, this message translates to:
  /// **'Tema and Ashaiman'**
  String get dating_side_gh_tema;

  /// No description provided for @dating_side_gh_kumasi.
  ///
  /// In en, this message translates to:
  /// **'Kumasi'**
  String get dating_side_gh_kumasi;

  /// No description provided for @dating_side_gh_outside_kumasi.
  ///
  /// In en, this message translates to:
  /// **'Outside Kumasi'**
  String get dating_side_gh_outside_kumasi;

  /// No description provided for @dating_region_gb_tlc.
  ///
  /// In en, this message translates to:
  /// **'North East'**
  String get dating_region_gb_tlc;

  /// No description provided for @dating_region_gb_tld.
  ///
  /// In en, this message translates to:
  /// **'North West'**
  String get dating_region_gb_tld;

  /// No description provided for @dating_region_gb_tle.
  ///
  /// In en, this message translates to:
  /// **'Yorkshire and the Humber'**
  String get dating_region_gb_tle;

  /// No description provided for @dating_region_gb_tlf.
  ///
  /// In en, this message translates to:
  /// **'East Midlands'**
  String get dating_region_gb_tlf;

  /// No description provided for @dating_region_gb_tlg.
  ///
  /// In en, this message translates to:
  /// **'West Midlands'**
  String get dating_region_gb_tlg;

  /// No description provided for @dating_region_gb_tlh.
  ///
  /// In en, this message translates to:
  /// **'East of England'**
  String get dating_region_gb_tlh;

  /// No description provided for @dating_region_gb_tli.
  ///
  /// In en, this message translates to:
  /// **'London'**
  String get dating_region_gb_tli;

  /// No description provided for @dating_region_gb_tlj.
  ///
  /// In en, this message translates to:
  /// **'South East'**
  String get dating_region_gb_tlj;

  /// No description provided for @dating_region_gb_tlk.
  ///
  /// In en, this message translates to:
  /// **'South West'**
  String get dating_region_gb_tlk;

  /// No description provided for @dating_region_gb_tll.
  ///
  /// In en, this message translates to:
  /// **'Wales'**
  String get dating_region_gb_tll;

  /// No description provided for @dating_region_gb_tlm.
  ///
  /// In en, this message translates to:
  /// **'Scotland'**
  String get dating_region_gb_tlm;

  /// No description provided for @dating_region_gb_tln.
  ///
  /// In en, this message translates to:
  /// **'Northern Ireland'**
  String get dating_region_gb_tln;

  /// Tell me when it's here refused by the adult check (not_eligible, T3 M-5; carry B). Calm, never names the feature or blames the person. For the DV reviewer.
  ///
  /// In en, this message translates to:
  /// **'We can\'t set this up on this account.'**
  String get dating_noticeNotEligible;

  /// No description provided for @dating_faith_christian.
  ///
  /// In en, this message translates to:
  /// **'Christian'**
  String get dating_faith_christian;

  /// No description provided for @dating_faith_muslim.
  ///
  /// In en, this message translates to:
  /// **'Muslim'**
  String get dating_faith_muslim;

  /// No description provided for @dating_faith_traditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get dating_faith_traditional;

  /// No description provided for @dating_faith_hindu.
  ///
  /// In en, this message translates to:
  /// **'Hindu'**
  String get dating_faith_hindu;

  /// No description provided for @dating_faith_sikh.
  ///
  /// In en, this message translates to:
  /// **'Sikh'**
  String get dating_faith_sikh;

  /// No description provided for @dating_faith_jewish.
  ///
  /// In en, this message translates to:
  /// **'Jewish'**
  String get dating_faith_jewish;

  /// No description provided for @dating_faith_buddhist.
  ///
  /// In en, this message translates to:
  /// **'Buddhist'**
  String get dating_faith_buddhist;

  /// No description provided for @dating_faith_other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get dating_faith_other;

  /// No description provided for @dating_faith_none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dating_faith_none;

  /// No description provided for @dating_faith_prefer_not_to_say.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get dating_faith_prefer_not_to_say;

  /// No description provided for @dating_denomination_catholic.
  ///
  /// In en, this message translates to:
  /// **'Catholic'**
  String get dating_denomination_catholic;

  /// No description provided for @dating_denomination_anglican.
  ///
  /// In en, this message translates to:
  /// **'Anglican'**
  String get dating_denomination_anglican;

  /// No description provided for @dating_denomination_methodist.
  ///
  /// In en, this message translates to:
  /// **'Methodist'**
  String get dating_denomination_methodist;

  /// No description provided for @dating_denomination_presbyterian.
  ///
  /// In en, this message translates to:
  /// **'Presbyterian'**
  String get dating_denomination_presbyterian;

  /// No description provided for @dating_denomination_pentecostal_charismatic.
  ///
  /// In en, this message translates to:
  /// **'Pentecostal or Charismatic'**
  String get dating_denomination_pentecostal_charismatic;

  /// No description provided for @dating_denomination_seventh_day_adventist.
  ///
  /// In en, this message translates to:
  /// **'Seventh-day Adventist'**
  String get dating_denomination_seventh_day_adventist;

  /// No description provided for @dating_denomination_other_christian.
  ///
  /// In en, this message translates to:
  /// **'Other Christian'**
  String get dating_denomination_other_christian;

  /// No description provided for @dating_denomination_church_of_england_anglican.
  ///
  /// In en, this message translates to:
  /// **'Church of England or Anglican'**
  String get dating_denomination_church_of_england_anglican;

  /// No description provided for @dating_denomination_orthodox.
  ///
  /// In en, this message translates to:
  /// **'Orthodox'**
  String get dating_denomination_orthodox;

  /// Spec 2 §3.0 progress.
  ///
  /// In en, this message translates to:
  /// **'Step {n} of {total}'**
  String dating_stepOf(int n, int total);

  /// Spec 2 §3.0: bottom-left where allowed.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get dating_skip;

  /// A setup step's primary.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get dating_continue;

  /// Spec 2 §3.15 D5: a modified-client refusal.
  ///
  /// In en, this message translates to:
  /// **'This choice isn\'t available here.'**
  String get dating_notAvailableHere;

  /// Spec 2 §3.2 D10 contact filter (also D5's own words).
  ///
  /// In en, this message translates to:
  /// **'Contact details can\'t go on your profile. You can swap them in a chat when you\'re both ready.'**
  String get dating_contactFilter;

  /// Spec 2 §3.2 D10 kindness filter.
  ///
  /// In en, this message translates to:
  /// **'Please rephrase this so it\'s kind to everyone.'**
  String get dating_kindnessFilter;

  /// D3 refused: country_change_limited (plan; §3.2 D3 rule).
  ///
  /// In en, this message translates to:
  /// **'You can change your Dating country once every 30 days.'**
  String get dating_countryChangeLimited;

  /// Spec 2 §3.2 D1.
  ///
  /// In en, this message translates to:
  /// **'How Dating works'**
  String get dating_howTitle;

  /// D1 item 1.
  ///
  /// In en, this message translates to:
  /// **'Up to 3 introductions a day, at a time you choose.'**
  String get dating_how1;

  /// D1 item 2.
  ///
  /// In en, this message translates to:
  /// **'Saying \'Interested\' is private. You only match when you\'re both interested.'**
  String get dating_how2;

  /// D1 item 3.
  ///
  /// In en, this message translates to:
  /// **'Dating chats are separate from the rest of Attune. Phone numbers stay hidden until you both choose to swap.'**
  String get dating_how3;

  /// D1 item 4 (also D11's shell until W4a).
  ///
  /// In en, this message translates to:
  /// **'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.'**
  String get dating_how4;

  /// D1 item 5.
  ///
  /// In en, this message translates to:
  /// **'You\'ll add at least 2 photos and answer 2 short questions.'**
  String get dating_how5;

  /// D1 item 6; {date} in full words.
  ///
  /// In en, this message translates to:
  /// **'Your first introductions can arrive from {date}.'**
  String dating_how6(String date);

  /// D1 item 7, built from get_dating_availability.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {countries}.'**
  String dating_how7(String countries);

  /// D1 item 8 (measured on the W10 device matrix).
  ///
  /// In en, this message translates to:
  /// **'Setting up uses about 15 MB of data, mostly for the video check.'**
  String get dating_how8;

  /// D1 tertiary.
  ///
  /// In en, this message translates to:
  /// **'Set up later'**
  String get dating_setUpLater;

  /// D1 snackbar after Not ready? (with Undo).
  ///
  /// In en, this message translates to:
  /// **'You\'re on \'Just for me\'.'**
  String get dating_justMeDone;

  /// Undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get dating_undo;

  /// Spec 2 §3.2 D2.
  ///
  /// In en, this message translates to:
  /// **'What are you looking for?'**
  String get dating_lookingTitle;

  /// No description provided for @dating_intentMarriage.
  ///
  /// In en, this message translates to:
  /// **'Marriage'**
  String get dating_intentMarriage;

  /// No description provided for @dating_intentCommitted.
  ///
  /// In en, this message translates to:
  /// **'A committed relationship'**
  String get dating_intentCommitted;

  /// No description provided for @dating_intentCompanionship.
  ///
  /// In en, this message translates to:
  /// **'Companionship, at my own pace'**
  String get dating_intentCompanionship;

  /// No description provided for @dating_intentNotSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure yet'**
  String get dating_intentNotSure;

  /// No description provided for @dating_timelineQ.
  ///
  /// In en, this message translates to:
  /// **'When would you like to marry?'**
  String get dating_timelineQ;

  /// No description provided for @dating_timelineSoon.
  ///
  /// In en, this message translates to:
  /// **'In the next year or two'**
  String get dating_timelineSoon;

  /// No description provided for @dating_timelineFew.
  ///
  /// In en, this message translates to:
  /// **'In a few years'**
  String get dating_timelineFew;

  /// No description provided for @dating_timelineNone.
  ///
  /// In en, this message translates to:
  /// **'No set time'**
  String get dating_timelineNone;

  /// No description provided for @dating_timelineShow.
  ///
  /// In en, this message translates to:
  /// **'Show this on my profile'**
  String get dating_timelineShow;

  /// D2 attestation (cultural reviewer, W3 gate).
  ///
  /// In en, this message translates to:
  /// **'I\'m not married in any form (customary, religious or civil), I\'m not separated from a spouse, and I\'m not in a relationship.'**
  String get dating_attestation;

  /// No description provided for @dating_attestationHelper.
  ///
  /// In en, this message translates to:
  /// **'Dating on Attune is for people who are free to start a relationship.'**
  String get dating_attestationHelper;

  /// No description provided for @dating_attestationError.
  ///
  /// In en, this message translates to:
  /// **'Please confirm you\'re free to start a relationship.'**
  String get dating_attestationError;

  /// No description provided for @dating_separatedLink.
  ///
  /// In en, this message translates to:
  /// **'I\'m separated but not divorced'**
  String get dating_separatedLink;

  /// No description provided for @dating_separatedSheet.
  ///
  /// In en, this message translates to:
  /// **'Dating isn\'t open to you yet. Once your divorce is final, you\'re welcome here. Attune just for me is open to you now.'**
  String get dating_separatedSheet;

  /// No description provided for @dating_marriedBefore.
  ///
  /// In en, this message translates to:
  /// **'Married before? (optional)'**
  String get dating_marriedBefore;

  /// No description provided for @dating_maritalNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get dating_maritalNever;

  /// No description provided for @dating_maritalDivorced.
  ///
  /// In en, this message translates to:
  /// **'Divorced'**
  String get dating_maritalDivorced;

  /// No description provided for @dating_maritalWidowed.
  ///
  /// In en, this message translates to:
  /// **'Widowed'**
  String get dating_maritalWidowed;

  /// No description provided for @dating_maritalShow.
  ///
  /// In en, this message translates to:
  /// **'Show on my profile'**
  String get dating_maritalShow;

  /// Spec 2 §3.2 D3.
  ///
  /// In en, this message translates to:
  /// **'Where are you?'**
  String get dating_whereTitle;

  /// No description provided for @dating_countryLabel.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get dating_countryLabel;

  /// No description provided for @dating_regionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get dating_regionLabel;

  /// No description provided for @dating_countryNotListed.
  ///
  /// In en, this message translates to:
  /// **'My country isn\'t listed'**
  String get dating_countryNotListed;

  /// D3 closed region, inline.
  ///
  /// In en, this message translates to:
  /// **'Dating is open in {regions} for now. We\'re opening other regions as soon as we can look after them well.'**
  String dating_regionClosed(String regions);

  /// D3 side.
  ///
  /// In en, this message translates to:
  /// **'Which side of {region}? (optional)'**
  String dating_sideLabel(String region);

  /// D3: no side chosen (plan).
  ///
  /// In en, this message translates to:
  /// **'Either side'**
  String get dating_sideEither;

  /// No description provided for @dating_scopeQ.
  ///
  /// In en, this message translates to:
  /// **'How far would you like to meet people?'**
  String get dating_scopeQ;

  /// No description provided for @dating_scopeSide.
  ///
  /// In en, this message translates to:
  /// **'My side'**
  String get dating_scopeSide;

  /// No description provided for @dating_scopeRegion.
  ///
  /// In en, this message translates to:
  /// **'My region'**
  String get dating_scopeRegion;

  /// D3 scope.
  ///
  /// In en, this message translates to:
  /// **'Anywhere in {country}'**
  String dating_scopeCountry(String country);

  /// No description provided for @dating_abroadRow.
  ///
  /// In en, this message translates to:
  /// **'Also open to people in other countries'**
  String get dating_abroadRow;

  /// No description provided for @dating_abroadDisabled.
  ///
  /// In en, this message translates to:
  /// **'Available once you\'re verified and your account is 14 days old.'**
  String get dating_abroadDisabled;

  /// No description provided for @dating_whereHelper.
  ///
  /// In en, this message translates to:
  /// **'We never use your exact location. Others see your region only.'**
  String get dating_whereHelper;

  /// A searchable picker's field (plan).
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get dating_search;

  /// A picker row with nothing chosen yet (plan).
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get dating_choose;

  /// Spec 2 §3.2 D4.
  ///
  /// In en, this message translates to:
  /// **'Your answers stay private'**
  String get dating_privacyTitle;

  /// No description provided for @dating_privacyWhyHead.
  ///
  /// In en, this message translates to:
  /// **'Why we ask'**
  String get dating_privacyWhyHead;

  /// No description provided for @dating_privacyWhoHead.
  ///
  /// In en, this message translates to:
  /// **'Who sees what'**
  String get dating_privacyWhoHead;

  /// No description provided for @dating_privacyNeverHead.
  ///
  /// In en, this message translates to:
  /// **'What we never do'**
  String get dating_privacyNeverHead;

  /// No description provided for @dating_privacyProtectedHead.
  ///
  /// In en, this message translates to:
  /// **'How it\'s protected'**
  String get dating_privacyProtectedHead;

  /// No description provided for @dating_privacyLeavingHead.
  ///
  /// In en, this message translates to:
  /// **'Leaving'**
  String get dating_privacyLeavingHead;

  /// No description provided for @dating_privacyWhy.
  ///
  /// In en, this message translates to:
  /// **'The next questions are about you and who you\'d like to meet. We use your answers only to introduce you to people who\'d like to meet you too.'**
  String get dating_privacyWhy;

  /// No description provided for @dating_privacyWho.
  ///
  /// In en, this message translates to:
  /// **'Nobody ever sees who you\'d like to meet. Your gender, faith and marriage history appear on your profile only if you choose. We never collect your exact location.'**
  String get dating_privacyWho;

  /// No description provided for @dating_privacyNever.
  ///
  /// In en, this message translates to:
  /// **'Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.'**
  String get dating_privacyNever;

  /// No description provided for @dating_privacyProtected.
  ///
  /// In en, this message translates to:
  /// **'These answers are stored encrypted. The people who review reports can\'t see them.'**
  String get dating_privacyProtected;

  /// No description provided for @dating_privacyLeaving.
  ///
  /// In en, this message translates to:
  /// **'You can leave Dating at any time, and these answers are deleted.'**
  String get dating_privacyLeaving;

  /// No description provided for @dating_privacyConsent.
  ///
  /// In en, this message translates to:
  /// **'I agree that Attune can use my answers about my gender and who I\'d like to meet to introduce me.'**
  String get dating_privacyConsent;

  /// No description provided for @dating_datingTerms.
  ///
  /// In en, this message translates to:
  /// **'Dating terms'**
  String get dating_datingTerms;

  /// No description provided for @dating_privacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get dating_privacyNotice;

  /// No description provided for @dating_agreeContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get dating_agreeContinue;

  /// Spec 2 §3.2 D5 (LGBTQ+ reviewer, W3 gate).
  ///
  /// In en, this message translates to:
  /// **'Which best describes you?'**
  String get dating_youTitle;

  /// No description provided for @dating_identityWoman.
  ///
  /// In en, this message translates to:
  /// **'Woman'**
  String get dating_identityWoman;

  /// No description provided for @dating_identityMan.
  ///
  /// In en, this message translates to:
  /// **'Man'**
  String get dating_identityMan;

  /// No description provided for @dating_identityNonBinary.
  ///
  /// In en, this message translates to:
  /// **'Non-binary'**
  String get dating_identityNonBinary;

  /// No description provided for @dating_moreSpecific.
  ///
  /// In en, this message translates to:
  /// **'Add something more specific'**
  String get dating_moreSpecific;

  /// No description provided for @dating_specificTransWoman.
  ///
  /// In en, this message translates to:
  /// **'Trans woman'**
  String get dating_specificTransWoman;

  /// No description provided for @dating_specificTransMan.
  ///
  /// In en, this message translates to:
  /// **'Trans man'**
  String get dating_specificTransMan;

  /// No description provided for @dating_specificGenderfluid.
  ///
  /// In en, this message translates to:
  /// **'Genderfluid'**
  String get dating_specificGenderfluid;

  /// No description provided for @dating_specificGenderqueer.
  ///
  /// In en, this message translates to:
  /// **'Genderqueer'**
  String get dating_specificGenderqueer;

  /// No description provided for @dating_specificAgender.
  ///
  /// In en, this message translates to:
  /// **'Agender'**
  String get dating_specificAgender;

  /// No description provided for @dating_specificIntersex.
  ///
  /// In en, this message translates to:
  /// **'Intersex'**
  String get dating_specificIntersex;

  /// No description provided for @dating_specificOwnWords.
  ///
  /// In en, this message translates to:
  /// **'In my own words'**
  String get dating_specificOwnWords;

  /// D5 own words, refused (plan).
  ///
  /// In en, this message translates to:
  /// **'Use letters, spaces and hyphens only, up to 30.'**
  String get dating_specificInvalid;

  /// No description provided for @dating_nbPoolsQ.
  ///
  /// In en, this message translates to:
  /// **'Should we also introduce you to people looking for:'**
  String get dating_nbPoolsQ;

  /// No description provided for @dating_poolWomen.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get dating_poolWomen;

  /// No description provided for @dating_poolMen.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get dating_poolMen;

  /// No description provided for @dating_nbPoolsHelper.
  ///
  /// In en, this message translates to:
  /// **'People open to everyone can always be introduced to you.'**
  String get dating_nbPoolsHelper;

  /// No description provided for @dating_pronouns.
  ///
  /// In en, this message translates to:
  /// **'Pronouns (optional)'**
  String get dating_pronouns;

  /// No description provided for @dating_genderShow.
  ///
  /// In en, this message translates to:
  /// **'Show my gender on my profile'**
  String get dating_genderShow;

  /// No description provided for @dating_youHelper.
  ///
  /// In en, this message translates to:
  /// **'We use this only to introduce you to people who want to meet someone like you.'**
  String get dating_youHelper;

  /// D5 off-country, read before the options (LGBTQ+ reviewer).
  ///
  /// In en, this message translates to:
  /// **'In {country}, Dating introduces men and women to each other for now. If neither of these fits you, Dating can\'t introduce you safely here yet.'**
  String dating_offCountryLine(String country);

  /// D5 off-country link to support_resources (lgbtq_legal, crisis).
  ///
  /// In en, this message translates to:
  /// **'Support for you'**
  String get dating_supportForYou;

  /// Spec 2 §3.2 D6.
  ///
  /// In en, this message translates to:
  /// **'Who would you like to meet?'**
  String get dating_meetTitle;

  /// No description provided for @dating_seekMen.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get dating_seekMen;

  /// No description provided for @dating_seekWomen.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get dating_seekWomen;

  /// No description provided for @dating_seekEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get dating_seekEveryone;

  /// No description provided for @dating_meetPrivate.
  ///
  /// In en, this message translates to:
  /// **'Only you can see this. It\'s never on your profile.'**
  String get dating_meetPrivate;

  /// No description provided for @dating_offMeetMen.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be introduced to men.'**
  String get dating_offMeetMen;

  /// No description provided for @dating_offMeetWomen.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be introduced to women.'**
  String get dating_offMeetWomen;

  /// D6 off-country (LGBTQ+ reviewer).
  ///
  /// In en, this message translates to:
  /// **'In {country}, Attune introduces men and women to each other for now.'**
  String dating_offMeetLine(String country);

  /// D6.
  ///
  /// In en, this message translates to:
  /// **'Ages {min} to {max}'**
  String dating_ages(int min, int max);

  /// D6 slider semantics.
  ///
  /// In en, this message translates to:
  /// **'Youngest {age}'**
  String dating_agesYoungest(int age);

  /// D6 slider semantics.
  ///
  /// In en, this message translates to:
  /// **'Oldest {age}'**
  String dating_agesOldest(int age);

  /// D6 country note (LGBTQ+ reviewer).
  ///
  /// In en, this message translates to:
  /// **'Before you save this'**
  String get dating_noteTitle;

  /// D6 note, phone variant (R-18).
  ///
  /// In en, this message translates to:
  /// **'Your phone number is from {country}, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know.'**
  String dating_notePhone(String country);

  /// No description provided for @dating_noteThen.
  ///
  /// In en, this message translates to:
  /// **'Attune never shows who you\'d like to meet, never shows distance, and keeps Dating out of your notifications. You can also set a PIN, use a plain app icon, and leave Dating at any time to delete these answers.'**
  String get dating_noteThen;

  /// No description provided for @dating_noteSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dating_noteSave;

  /// No description provided for @dating_noteSetPin.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN first'**
  String get dating_noteSetPin;

  /// No description provided for @dating_noteBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get dating_noteBack;

  /// Spec 2 §3.2 D7.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get dating_childrenTitle;

  /// No description provided for @dating_childrenHaveQ.
  ///
  /// In en, this message translates to:
  /// **'Do you have children?'**
  String get dating_childrenHaveQ;

  /// No description provided for @dating_yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get dating_yes;

  /// No description provided for @dating_no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get dating_no;

  /// No description provided for @dating_childrenWantQ.
  ///
  /// In en, this message translates to:
  /// **'Do you want children (or more children)?'**
  String get dating_childrenWantQ;

  /// No description provided for @dating_openToIt.
  ///
  /// In en, this message translates to:
  /// **'Open to it'**
  String get dating_openToIt;

  /// No description provided for @dating_childrenMustMatch.
  ///
  /// In en, this message translates to:
  /// **'Only introduce me to people whose answer fits mine'**
  String get dating_childrenMustMatch;

  /// No description provided for @dating_childrenExcludeParents.
  ///
  /// In en, this message translates to:
  /// **'I\'d rather not meet people who have children'**
  String get dating_childrenExcludeParents;

  /// No description provided for @dating_childrenHelper.
  ///
  /// In en, this message translates to:
  /// **'We never ask for your children\'s names or ages, and photos with children can\'t be used.'**
  String get dating_childrenHelper;

  /// Spec 2 §3.2 D8 (cultural reviewer for the lists).
  ///
  /// In en, this message translates to:
  /// **'Faith'**
  String get dating_faithTitle;

  /// No description provided for @dating_optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get dating_optional;

  /// No description provided for @dating_denomination.
  ///
  /// In en, this message translates to:
  /// **'Denomination (optional)'**
  String get dating_denomination;

  /// No description provided for @dating_importanceQ.
  ///
  /// In en, this message translates to:
  /// **'How much does sharing a faith matter to you?'**
  String get dating_importanceQ;

  /// No description provided for @dating_importanceNo.
  ///
  /// In en, this message translates to:
  /// **'It doesn\'t matter'**
  String get dating_importanceNo;

  /// No description provided for @dating_importanceNice.
  ///
  /// In en, this message translates to:
  /// **'Nice if we share'**
  String get dating_importanceNice;

  /// No description provided for @dating_importanceMust.
  ///
  /// In en, this message translates to:
  /// **'We must share it'**
  String get dating_importanceMust;

  /// No description provided for @dating_faithShow.
  ///
  /// In en, this message translates to:
  /// **'Show my faith on my profile'**
  String get dating_faithShow;

  /// No description provided for @dating_faithConsent.
  ///
  /// In en, this message translates to:
  /// **'Faith is sensitive information. I agree that Attune can use it to introduce me.'**
  String get dating_faithConsent;

  /// D8: Continue with a faith but no consent (plan).
  ///
  /// In en, this message translates to:
  /// **'Please agree, or choose Skip.'**
  String get dating_faithConsentError;

  /// D6 slider semantics label; the age is its value (plan, T7 fix 1 M-2).
  ///
  /// In en, this message translates to:
  /// **'Youngest'**
  String get dating_agesYoungestLabel;

  /// D6 slider semantics label; the age is its value (plan, T7 fix 1 M-2).
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get dating_agesOldestLabel;

  /// Spec 2 §3.2 D9.
  ///
  /// In en, this message translates to:
  /// **'Add your photos'**
  String get dating_photosTitle;

  /// No description provided for @dating_photosBody.
  ///
  /// In en, this message translates to:
  /// **'Add 2 to 6 photos. Clear, recent photos of just you work best.'**
  String get dating_photosBody;

  /// No description provided for @dating_photoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get dating_photoAdd;

  /// D9 progress in words (R-22).
  ///
  /// In en, this message translates to:
  /// **'Preparing photo {n}…'**
  String dating_photoPreparing(int n);

  /// D9 progress in words (R-22).
  ///
  /// In en, this message translates to:
  /// **'Uploading photo {n}…'**
  String dating_photoUploading(int n);

  /// No description provided for @dating_photoChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get dating_photoChecking;

  /// No description provided for @dating_photoReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get dating_photoReady;

  /// No description provided for @dating_photoReview.
  ///
  /// In en, this message translates to:
  /// **'Needs a person to check it. That usually takes less than a day.'**
  String get dating_photoReview;

  /// D9 rejection.
  ///
  /// In en, this message translates to:
  /// **'Photo {n}: we couldn\'t see your face clearly.'**
  String dating_photoFaceUnclear(int n);

  /// D9 rejection.
  ///
  /// In en, this message translates to:
  /// **'Photo {n} is too small.'**
  String dating_photoTooSmall(int n);

  /// D9 rejection (then Crop).
  ///
  /// In en, this message translates to:
  /// **'Photo {n}: photos with children can\'t be used on Dating. Crop to just you?'**
  String dating_photoChild(int n);

  /// No description provided for @dating_photoCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get dating_photoCrop;

  /// D9 rejection (unsafe, and a CSAM hit, never named).
  ///
  /// In en, this message translates to:
  /// **'Photo {n} can\'t be used.'**
  String dating_photoCantUse(int n);

  /// D9: the upload failed (plan).
  ///
  /// In en, this message translates to:
  /// **'Photo {n} didn\'t upload. Try again.'**
  String dating_photoFailed(int n);

  /// D9 slot semantics.
  ///
  /// In en, this message translates to:
  /// **'Photo {n} of 6, {state}'**
  String dating_photoSlot(int n, String state);

  /// No description provided for @dating_photoMoveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get dating_photoMoveEarlier;

  /// No description provided for @dating_photoMoveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get dating_photoMoveLater;

  /// No description provided for @dating_photoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get dating_photoRemove;

  /// D9 slot action (plan).
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get dating_photoReplace;

  /// D9 caption action (plan; 09 P12).
  ///
  /// In en, this message translates to:
  /// **'Add a caption (only you see it)'**
  String get dating_photoCaption;

  /// D9 caption field (plan).
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get dating_photoCaptionLabel;

  /// D9 caption sheet (plan).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dating_photoSave;

  /// No description provided for @dating_photosAfterMutual.
  ///
  /// In en, this message translates to:
  /// **'Show my photos only after we\'re both interested'**
  String get dating_photosAfterMutual;

  /// D9 toggle before account day 30.
  ///
  /// In en, this message translates to:
  /// **'Available from {date}. New accounts show their photos for the first 30 days, which helps stop fake profiles.'**
  String dating_photosAfterMutualFrom(String date);

  /// No description provided for @dating_photosData.
  ///
  /// In en, this message translates to:
  /// **'Each photo uses about 300 KB.'**
  String get dating_photosData;

  /// No description provided for @dating_photosOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Add photos when you\'re connected.'**
  String get dating_photosOffline;

  /// Spec 2 §3.2 D10.
  ///
  /// In en, this message translates to:
  /// **'A little about you'**
  String get dating_promptsTitle;

  /// No description provided for @dating_promptsBody.
  ///
  /// In en, this message translates to:
  /// **'Answer 2 of these. Short is fine.'**
  String get dating_promptsBody;

  /// No description provided for @dating_prompt_perfect_sunday.
  ///
  /// In en, this message translates to:
  /// **'A perfect Sunday for me looks like…'**
  String get dating_prompt_perfect_sunday;

  /// No description provided for @dating_prompt_feel_at_home.
  ///
  /// In en, this message translates to:
  /// **'I feel most at home when…'**
  String get dating_prompt_feel_at_home;

  /// No description provided for @dating_prompt_friends_say.
  ///
  /// In en, this message translates to:
  /// **'My friends would say I\'m…'**
  String get dating_prompt_friends_say;

  /// No description provided for @dating_prompt_looking_for.
  ///
  /// In en, this message translates to:
  /// **'I\'m looking for someone who…'**
  String get dating_prompt_looking_for;

  /// No description provided for @dating_prompt_small_thing.
  ///
  /// In en, this message translates to:
  /// **'A small thing that makes my day…'**
  String get dating_prompt_small_thing;

  /// No description provided for @dating_prompt_win_me_over.
  ///
  /// In en, this message translates to:
  /// **'The way to win me over is…'**
  String get dating_prompt_win_me_over;

  /// No description provided for @dating_prompt_learning_to.
  ///
  /// In en, this message translates to:
  /// **'I\'m learning to…'**
  String get dating_prompt_learning_to;

  /// No description provided for @dating_prompt_family_describe.
  ///
  /// In en, this message translates to:
  /// **'My family would describe me as…'**
  String get dating_prompt_family_describe;

  /// No description provided for @dating_prompt_place_love.
  ///
  /// In en, this message translates to:
  /// **'A kind of place I love spending time…'**
  String get dating_prompt_place_love;

  /// No description provided for @dating_prompt_ask_me_about.
  ///
  /// In en, this message translates to:
  /// **'Ask me about…'**
  String get dating_prompt_ask_me_about;

  /// D10 length (plan).
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters.'**
  String get dating_promptTooShort;

  /// D9: the system picker refused or failed (plan, T10 fix 1 I-3).
  ///
  /// In en, this message translates to:
  /// **'Photo {n}: your photos couldn\'t be opened. Check that Attune can use them in Settings, then try again.'**
  String dating_photoPickFailed(int n);

  /// D9: the cropper failed (plan, T10 fix 1 I-3).
  ///
  /// In en, this message translates to:
  /// **'Photo {n} couldn\'t be cropped. Try again.'**
  String dating_photoCropFailed(int n);

  /// D9 caption / D10 answer: a character the server refuses, e.g. a joined emoji (plan, T10 fix 1 I-2).
  ///
  /// In en, this message translates to:
  /// **'Some emoji and symbols can\'t be used here. Try taking them out.'**
  String get dating_textInvisible;

  /// D10: an answer with no letter or number (plan, T10 fix 1 I-2).
  ///
  /// In en, this message translates to:
  /// **'Add a few words, not just emoji or symbols.'**
  String get dating_promptNeedsWords;

  /// Spec 2 §3.2 D11 / §3.3.2 (the shell until W4a, R-26).
  ///
  /// In en, this message translates to:
  /// **'Verify it\'s you'**
  String get dating_verifyTitle;

  /// No description provided for @dating_verifyBody.
  ///
  /// In en, this message translates to:
  /// **'A short video selfie checks that you\'re a real person, that your photos are you, and that you\'re over 18. The video is deleted at once. We keep only whether it passed.'**
  String get dating_verifyBody;

  /// D11 shell line until W4a (plan, R-26).
  ///
  /// In en, this message translates to:
  /// **'You\'ll do this check before your first introduction.'**
  String get dating_verifyLater;

  /// Spec 2 §3.2 D12.
  ///
  /// In en, this message translates to:
  /// **'This is what others see'**
  String get dating_previewTitle;

  /// No description provided for @dating_previewNever.
  ///
  /// In en, this message translates to:
  /// **'Never shown: who you\'d like to meet, your exact location, your date of birth.'**
  String get dating_previewNever;

  /// D12: the preview read failed (plan).
  ///
  /// In en, this message translates to:
  /// **'Your preview can\'t be shown right now.'**
  String get dating_previewUnavailable;

  /// Retry (plan).
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get dating_tryAgain;

  /// No description provided for @dating_nameLabel.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get dating_nameLabel;

  /// No description provided for @dating_nameHelper.
  ///
  /// In en, this message translates to:
  /// **'Use your first name or what friends call you.'**
  String get dating_nameHelper;

  /// D12 first-name length (plan).
  ///
  /// In en, this message translates to:
  /// **'Use 1 to 30 characters.'**
  String get dating_nameInvalid;

  /// Save (plan).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dating_save;

  /// D12 per-section edit links (plan; §3.2 D12 'Edit links: per section').
  ///
  /// In en, this message translates to:
  /// **'Edit first name'**
  String get dating_editName;

  /// No description provided for @dating_editLooking.
  ///
  /// In en, this message translates to:
  /// **'Edit what you\'re looking for'**
  String get dating_editLooking;

  /// No description provided for @dating_editWhere.
  ///
  /// In en, this message translates to:
  /// **'Edit where you are'**
  String get dating_editWhere;

  /// No description provided for @dating_editPrompts.
  ///
  /// In en, this message translates to:
  /// **'Edit your answers'**
  String get dating_editPrompts;

  /// No description provided for @dating_editChildren.
  ///
  /// In en, this message translates to:
  /// **'Edit children'**
  String get dating_editChildren;

  /// No description provided for @dating_editAbout.
  ///
  /// In en, this message translates to:
  /// **'Edit what you show about yourself'**
  String get dating_editAbout;

  /// No description provided for @dating_editPhotos.
  ///
  /// In en, this message translates to:
  /// **'Edit photos'**
  String get dating_editPhotos;

  /// No description provided for @dating_pushDigest.
  ///
  /// In en, this message translates to:
  /// **'Tell me about new introductions and matches, at most once a day.'**
  String get dating_pushDigest;

  /// No description provided for @dating_pushTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get dating_pushTurnOn;

  /// D12 after Turn on (plan).
  ///
  /// In en, this message translates to:
  /// **'We\'ll tell you about new introductions and matches, at most once a day.'**
  String get dating_pushDigestOn;

  /// No description provided for @dating_pushMessages.
  ///
  /// In en, this message translates to:
  /// **'Tell me when someone messages me'**
  String get dating_pushMessages;

  /// §3.4 card heading.
  ///
  /// In en, this message translates to:
  /// **'{name}, {age}'**
  String dating_cardHeading(String name, int age);

  /// §3.4 intention, timeline hidden (plan).
  ///
  /// In en, this message translates to:
  /// **'Looking for marriage'**
  String get dating_cardMarriage;

  /// No description provided for @dating_cardMarriageSoon.
  ///
  /// In en, this message translates to:
  /// **'Looking for marriage, in the next year or two'**
  String get dating_cardMarriageSoon;

  /// §3.4 intention with D2's 'In a few years' (plan; cultural reviewer).
  ///
  /// In en, this message translates to:
  /// **'Looking for marriage, in a few years'**
  String get dating_cardMarriageFew;

  /// §3.4 intention with D2's 'No set time' (plan; cultural reviewer).
  ///
  /// In en, this message translates to:
  /// **'Looking for marriage, with no set time'**
  String get dating_cardMarriageNone;

  /// No description provided for @dating_cardCommitted.
  ///
  /// In en, this message translates to:
  /// **'Looking for a committed relationship'**
  String get dating_cardCommitted;

  /// No description provided for @dating_cardCompanionship.
  ///
  /// In en, this message translates to:
  /// **'Looking for companionship, at a comfortable pace'**
  String get dating_cardCompanionship;

  /// No description provided for @dating_cardNotSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure yet'**
  String get dating_cardNotSure;

  /// No description provided for @dating_cardHasChildren.
  ///
  /// In en, this message translates to:
  /// **'Has children'**
  String get dating_cardHasChildren;

  /// No description provided for @dating_cardNoChildren.
  ///
  /// In en, this message translates to:
  /// **'No children'**
  String get dating_cardNoChildren;

  /// No description provided for @dating_cardWantsChildren.
  ///
  /// In en, this message translates to:
  /// **'Wants children'**
  String get dating_cardWantsChildren;

  /// No description provided for @dating_cardNoWantChildren.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t want children'**
  String get dating_cardNoWantChildren;

  /// No description provided for @dating_cardOpenChildren.
  ///
  /// In en, this message translates to:
  /// **'Open to children'**
  String get dating_cardOpenChildren;

  /// No description provided for @dating_cardPhotosLater.
  ///
  /// In en, this message translates to:
  /// **'Photos appear after you\'re both interested.'**
  String get dating_cardPhotosLater;

  /// No description provided for @dating_cardShowPhotos.
  ///
  /// In en, this message translates to:
  /// **'Show photos (about 1 MB)'**
  String get dating_cardShowPhotos;

  /// §3.4 carousel semantics (plan).
  ///
  /// In en, this message translates to:
  /// **'Photo {n} of {count}'**
  String dating_cardPhoto(int n, int count);

  /// Spec 2 §3.2 D13.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get dating_readyTitle;

  /// D13.
  ///
  /// In en, this message translates to:
  /// **'Your first introductions arrive {date} at {time}.'**
  String dating_readyFirst(String date, String time);

  /// No description provided for @dating_readyChangeTime.
  ///
  /// In en, this message translates to:
  /// **'Change time'**
  String get dating_readyChangeTime;

  /// No description provided for @dating_readyTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a time when you have a few quiet minutes.'**
  String get dating_readyTimeTitle;

  /// D13 heading (plan).
  ///
  /// In en, this message translates to:
  /// **'While you wait'**
  String get dating_readyWhile;

  /// No description provided for @dating_readyJournal.
  ///
  /// In en, this message translates to:
  /// **'Write in your journal'**
  String get dating_readyJournal;

  /// No description provided for @dating_readySharedQ.
  ///
  /// In en, this message translates to:
  /// **'Does anyone else use this phone?'**
  String get dating_readySharedQ;

  /// No description provided for @dating_readyLock.
  ///
  /// In en, this message translates to:
  /// **'Lock Dating with your PIN'**
  String get dating_readyLock;

  /// No description provided for @dating_readyEveryOpen.
  ///
  /// In en, this message translates to:
  /// **'Ask for my PIN every time Attune opens'**
  String get dating_readyEveryOpen;

  /// No description provided for @dating_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dating_done;

  /// D13 activation before W4a (plan, R-26).
  ///
  /// In en, this message translates to:
  /// **'We still need to check it\'s you before introductions start.'**
  String get dating_readyGates;

  /// D12 edit link beside the faith line (T11 fix 1, I-2; plan copy).
  ///
  /// In en, this message translates to:
  /// **'Edit faith'**
  String get dating_editFaith;

  /// D12 edit link beside Widowed / Divorced, opens D2 (T11 fix 1, I-2; plan copy).
  ///
  /// In en, this message translates to:
  /// **'Edit marital status'**
  String get dating_editMarital;

  /// §3.4: the card's photos announced as one group (T11 fix 1, M-6).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String dating_cardPhotos(int count);

  /// Spec 2 §3.12 row.
  ///
  /// In en, this message translates to:
  /// **'Introduction time'**
  String get dating_settingsTime;

  /// No description provided for @dating_settingsWho.
  ///
  /// In en, this message translates to:
  /// **'Who I\'d like to meet'**
  String get dating_settingsWho;

  /// No description provided for @dating_settingsAges.
  ///
  /// In en, this message translates to:
  /// **'Ages'**
  String get dating_settingsAges;

  /// §3.12 Ages row value (plan).
  ///
  /// In en, this message translates to:
  /// **'{min} to {max}'**
  String dating_settingsAgesValue(int min, int max);

  /// No description provided for @dating_settingsHowFar.
  ///
  /// In en, this message translates to:
  /// **'How far'**
  String get dating_settingsHowFar;

  /// No description provided for @dating_settingsPhotosAfter.
  ///
  /// In en, this message translates to:
  /// **'Photos after mutual interest'**
  String get dating_settingsPhotosAfter;

  /// No description provided for @dating_settingsDataSaver.
  ///
  /// In en, this message translates to:
  /// **'Data saver'**
  String get dating_settingsDataSaver;

  /// No description provided for @dating_settingsDataSaverSub.
  ///
  /// In en, this message translates to:
  /// **'Show photos only when I tap'**
  String get dating_settingsDataSaverSub;

  /// No description provided for @dating_settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get dating_settingsNotifications;

  /// No description provided for @dating_settingsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause Dating'**
  String get dating_settingsPause;

  /// §3.8 Pause.
  ///
  /// In en, this message translates to:
  /// **'Dating is paused. Nobody new sees you, and your conversations stay open.'**
  String get dating_pausedLine;

  /// No description provided for @dating_settingsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume Dating'**
  String get dating_settingsResume;

  /// No description provided for @dating_settingsLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave Dating and delete my data'**
  String get dating_settingsLeave;

  /// Spec 2 §3.8 Leave.
  ///
  /// In en, this message translates to:
  /// **'Leave Dating?'**
  String get dating_leaveTitle;

  /// No description provided for @dating_leaveNow.
  ///
  /// In en, this message translates to:
  /// **'Deleted now: your Dating profile, photos, prompts, who you\'d like to meet, your gender and faith answers, your settings and your private notes.'**
  String get dating_leaveNow;

  /// No description provided for @dating_leave30.
  ///
  /// In en, this message translates to:
  /// **'Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.'**
  String get dating_leave30;

  /// No description provided for @dating_leaveSafety.
  ///
  /// In en, this message translates to:
  /// **'Kept for safety, for up to 2 years, only if your account is restricted or you\'ve blocked someone: a code made from your phone number, never the number itself.'**
  String get dating_leaveSafety;

  /// No description provided for @dating_leaveRecord.
  ///
  /// In en, this message translates to:
  /// **'Kept as a record: when you agreed to Dating\'s terms and when you left.'**
  String get dating_leaveRecord;

  /// No description provided for @dating_leaveKeepList.
  ///
  /// In en, this message translates to:
  /// **'Keep my \'Never introduce me\' list in case I come back. It holds codes, not numbers.'**
  String get dating_leaveKeepList;

  /// No description provided for @dating_leaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave and delete'**
  String get dating_leaveConfirm;

  /// No description provided for @dating_leavePause.
  ///
  /// In en, this message translates to:
  /// **'Pause instead'**
  String get dating_leavePause;

  /// No description provided for @dating_leftDone.
  ///
  /// In en, this message translates to:
  /// **'You\'ve left Dating. You can set it up again any time.'**
  String get dating_leftDone;

  /// §3.8 Done when exit answers suspended (carry 13; plan: no 'set it up again').
  ///
  /// In en, this message translates to:
  /// **'You\'ve left Dating.'**
  String get dating_leftSuspended;

  /// Spec 2 W3 final fix (M-16): D9's confirm before a photo is deleted (the delete is at once, so no undo).
  ///
  /// In en, this message translates to:
  /// **'Remove photo {n}?'**
  String dating_photoRemoveQ(int n);

  /// Spec 2 W3 final fix (M-16): D9's remove confirm.
  ///
  /// In en, this message translates to:
  /// **'It\'s deleted at once. A photo you add later is checked again before anyone sees it.'**
  String get dating_photoRemoveBody;

  /// Spec 2 W3 final fix (M-16): D9's remove confirm, the safe choice.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get dating_photoKeep;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'es', 'fr', 'it', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
    case 'it': return AppLocalizationsIt();
    case 'pt': return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
