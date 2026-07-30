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
  /// **'You are browsing {appName} as a guest. Log in or create an account to start managing your shop — it takes less than 5 seconds. We have a variety of tools to help grow your business, all free of charge.'**
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
  /// **'Anonymous forum accounts you've muted'**
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

  /// Title shown when no data of a specific type is available
  ///
  /// In en, this message translates to:
  /// **'No {dataType} yet'**
  String emptyStateNoDataTitle(String dataType);

  /// Subtitle explaining when data will appear
  ///
  /// In en, this message translates to:
  /// **'When {dataType} becomes available, they will appear here.'**
  String emptyStateNoDataSubtitle(String dataType);

  /// No description provided for @emptyStateNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get emptyStateNoResultsTitle;

  /// Hint for finding specific data type
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search or filters to find {dataType}.'**
  String emptyStateNoResultsSubtitle(String dataType);

  /// No description provided for @emptyStateNoInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get emptyStateNoInternetTitle;

  /// No description provided for @emptyStateNoInternetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get emptyStateNoInternetSubtitle;

  /// No description provided for @emptyStateNoFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get emptyStateNoFavoritesTitle;

  /// No description provided for @emptyStateNoFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start adding items to your favorites list.'**
  String get emptyStateNoFavoritesSubtitle;

  /// No description provided for @emptyStateNoMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get emptyStateNoMessagesTitle;

  /// No description provided for @emptyStateNoMessagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation to see messages here.'**
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

  /// No description provided for @emptyStateExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get emptyStateExplore;

  /// No description provided for @emptyStateStartChat.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
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

  /// No description provided for @dataTypeUsers.
  ///
  /// In en, this message translates to:
  /// **'users'**
  String get dataTypeUsers;

  /// No description provided for @dataTypeUser.
  ///
  /// In en, this message translates to:
  /// **'user'**
  String get dataTypeUser;

  /// No description provided for @dataTypeProducts.
  ///
  /// In en, this message translates to:
  /// **'products'**
  String get dataTypeProducts;

  /// No description provided for @dataTypeProduct.
  ///
  /// In en, this message translates to:
  /// **'product'**
  String get dataTypeProduct;

  /// No description provided for @dataTypeOrders.
  ///
  /// In en, this message translates to:
  /// **'orders'**
  String get dataTypeOrders;

  /// No description provided for @dataTypeOrder.
  ///
  /// In en, this message translates to:
  /// **'order'**
  String get dataTypeOrder;

  /// No description provided for @dataTypeMessages.
  ///
  /// In en, this message translates to:
  /// **'messages'**
  String get dataTypeMessages;

  /// No description provided for @dataTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'message'**
  String get dataTypeMessage;

  /// No description provided for @dataTypeFavorites.
  ///
  /// In en, this message translates to:
  /// **'favorites'**
  String get dataTypeFavorites;

  /// No description provided for @dataTypeFavorite.
  ///
  /// In en, this message translates to:
  /// **'favorite'**
  String get dataTypeFavorite;

  /// No description provided for @dataTypeData.
  ///
  /// In en, this message translates to:
  /// **'data'**
  String get dataTypeData;

  /// No description provided for @dataTypeContent.
  ///
  /// In en, this message translates to:
  /// **'content'**
  String get dataTypeContent;

  /// No description provided for @dataTypeItems.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get dataTypeItems;

  /// No description provided for @dataTypeItem.
  ///
  /// In en, this message translates to:
  /// **'item'**
  String get dataTypeItem;

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
