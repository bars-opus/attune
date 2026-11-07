// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'Your innovative app';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonLogin => 'Login';

  @override
  String get commonLogout => 'Logout';

  @override
  String get commonDone => 'Done';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonAccept => 'Accept';

  @override
  String get commonReject => 'Reject';

  @override
  String get introGetStarted => 'Get Started';

  @override
  String get actionsBlock => 'Block user';

  @override
  String get actionsReport => 'Report user';

  @override
  String get actionsSend => 'Send to chat';

  @override
  String get actionsShare => 'Share';

  @override
  String get actionsCopy => 'Copy link';

  @override
  String get appInfoVersion => 'Version';

  @override
  String get appInfoReleased => 'Released';

  @override
  String get appInfoPackageName => 'Package Name';

  @override
  String get appInfoDeveloper => 'Developer Name';

  @override
  String get appInfoSupportEmail => 'Support Email';

  @override
  String get appInfoTechnicalDetails => 'Technical Details';

  @override
  String get appInfoBundleID => 'Bundle ID';

  @override
  String get appInfoBuildVersion => 'Build Version';

  @override
  String get appInfoBuildNumber => 'Build Number';

  @override
  String get appInfoReleaseDate => 'Release Date';

  @override
  String get appInfoAppSize => 'App Size';

  @override
  String appInfoOverview(String appName) {
    return '$appName is a modern mobile application built with robust security and functionality, designed to provide an exceptional user experience with clean architecture and performance optimization.';
  }

  @override
  String introTitle(String appName) {
    return 'Welcome to $appName';
  }

  @override
  String get introFeature1Title => 'See Your Progress';

  @override
  String get introFeature1Description => 'Track your development milestones with detailed analytics and insights';

  @override
  String get introFeature2Title => 'Explore Templates';

  @override
  String get introFeature2Description => 'Discover pre-built components and screens for rapid development';

  @override
  String get introFeature3Title => 'Get Started Quickly';

  @override
  String get introFeature3Description => 'Jumpstart your project with zero-config setup and best practices';

  @override
  String get appleSignIn => 'Sign in with Apple';

  @override
  String get googleSignIn => 'Sign in with Google';

  @override
  String get appleRegister => 'Continue with Apple';

  @override
  String get googleRegister => 'Continue with Google';

  @override
  String get emailAndPassword => 'Enter email and password';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get legalConsentPart1 => 'Kindly read the ';

  @override
  String get legalConsentPart2 => 'terms and conditions';

  @override
  String legalConsentPart3(String appName) {
    return ' and other legal documents that govern your use of $appName.';
  }

  @override
  String get emailTitle => 'Email';

  @override
  String get passwordTitle => 'Password';

  @override
  String get loginEmailLabel => 'Email address';

  @override
  String get loginEmailHint => 'Enter your email';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHint => 'Enter your password';

  @override
  String get loginForgotPasswordPart1 => 'Have you forgotten your password? ';

  @override
  String get loginForgotPasswordPart2 => 'Tap here';

  @override
  String get loginForgotPasswordPart3 => ' to reset your password?';

  @override
  String get commonConfirmPasswordLabel => 'Confirm Password';

  @override
  String get commonConfirmPasswordHint => 'Please confirm your password';

  @override
  String get commonPasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get commonPasswordConfirmRequired => 'Please confirm your password';

  @override
  String commonFieldIsValid(String field) {
    return '$field is valid';
  }

  @override
  String get commonPleaseWait => 'Please wait for the current operation to complete';

  @override
  String get commonUnexpectedError => 'An unexpected error occurred. Please try again.';

  @override
  String get commonSomethingWentWrong => 'Something went wrong. Please try again.';

  @override
  String get commonEnterEmailAndRetry => 'Please enter your email address and try again';

  @override
  String get commonLearnMore => 'Learn more';

  @override
  String get authSignUpVerificationSent => 'Verification email sent! Please check your inbox.';

  @override
  String authSignUpFailed(String error) {
    return 'Sign-up failed: $error';
  }

  @override
  String get authForgotPasswordTitle => 'Forgot your password?';

  @override
  String get authForgotPasswordSubtitle => 'Enter your email and we\'ll send you a link to reset your password.';

  @override
  String get authSendResetLink => 'Send reset link';

  @override
  String get authBackToSignIn => 'Back to sign in';

  @override
  String get authUsernameScreenTitle => 'Choose your username';

  @override
  String get authUsernameScreenSubtitle => 'This is how others will see you. You can change it later.';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authUsernameHint => 'Enter a username';

  @override
  String authUsernameMinLength(int min) {
    return 'Username must be at least $min characters';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'Username must be at most $max characters';
  }

  @override
  String get authUsernameFormatError => 'Only letters, numbers, and underscores are allowed';

  @override
  String get authUsernameTaken => 'This username is already taken';

  @override
  String get authUsernameCheckError => 'Unable to check username availability. Please try again.';

  @override
  String get authUsernameSaveError => 'Could not save your username. Please try again.';

  @override
  String get authUsernameSavedSuccess => 'Username saved successfully!';

  @override
  String get authUpdatePasswordTitle => 'Create new password';

  @override
  String get authUpdatePasswordButton => 'Update password';

  @override
  String get authUpdatePasswordSuccess => 'Password updated successfully. Please sign in again.';

  @override
  String get authPasswordResetSentTitle => 'Check your email';

  @override
  String get authPasswordResetSentBody => 'We sent a password reset link to';

  @override
  String get authPasswordResetSentNote => 'Tap the link in the email to set a new password. The link expires in 1 hour.';

  @override
  String get authGuestHello => 'Hello!';

  @override
  String authGuestOverview(String appName) {
    return 'You\'re browsing $appName as a guest. Sign in with your phone number to start your shared space with your partner — it takes a few seconds.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Welcome to\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Welcome to the platform we built for you. Enjoy and have fun — the best is waiting.';

  @override
  String get authReadLegalities => 'Read legalities';

  @override
  String get authPasswordRequired => 'Please enter your password';

  @override
  String get authCreatingAccount => 'Creating account...';

  @override
  String get authAccountCreatedSuccess => 'Account created successfully!';

  @override
  String get authCheckEmailToConfirm => 'Please check your email to confirm your account';

  @override
  String get authSigningInWithGoogle => 'Signing in with Google...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Google sign-in failed: $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Authenticating with Apple...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Apple sign-in failed: $error';
  }

  @override
  String get authSendingResetEmail => 'Sending reset email...';

  @override
  String get authResetEmailSent => 'Reset email sent. Check your inbox.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Password reset failed: $error';
  }

  @override
  String get authVerifyEmailTitle => 'Check your email';

  @override
  String get authVerifyEmailSubtitle => 'We sent a confirmation link to';

  @override
  String get authVerifyEmailNote => 'Tap the link in the email to verify your account and continue.';

  @override
  String get authConfirmationResent => 'Confirmation email resent. Check your inbox.';

  @override
  String get authResendFailed => 'Failed to resend email. Please try again.';

  @override
  String get authResendEmailButton => 'Resend confirmation email';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'Resend email (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Select currency';

  @override
  String get currencySelectorNoSelected => 'No currency selected';

  @override
  String get currencySelectorTitle => 'Select Currency';

  @override
  String get currencySelectorSearchHint => 'Search by currency, code, or flag...';

  @override
  String get currencySelectorNoResults => 'No currencies found';

  @override
  String get discoverScreenTitle => 'Discover';

  @override
  String get discoverSearchHint => 'Search...';

  @override
  String get discoverAllShopsRegion => 'All shops in your region';

  @override
  String get discoverAllFreelancers => 'All freelancers near you';

  @override
  String get discoverMarketplaceTitle => 'Marketplace';

  @override
  String get discoverMarketplaceSubtitle => 'Shop beauty products with cash on delivery';

  @override
  String get discoverBrowseProducts => 'Browse products';

  @override
  String get discoverMyOrders => 'My orders';

  @override
  String get discoverCartTooltip => 'Cart';

  @override
  String get homeScheduleTabLabel => 'Schedule';

  @override
  String get homeDashboardTabLabel => 'Dashboard';

  @override
  String get homeMapTabLabel => 'Map';

  @override
  String get validationRequired => 'This field is required';

  @override
  String get validationEmailInvalid => 'Please enter a valid email address';

  @override
  String validationPasswordLength(int minLength) {
    return 'Password must be at least $minLength characters';
  }

  @override
  String get validationPasswordUppercase => 'Password must include at least one uppercase letter';

  @override
  String get loggingInIndicatorText => 'Logging in...';

  @override
  String get loginSuccessful => 'Login successful!\nWelcome back';

  @override
  String get errorLoginFailed => 'Login failed. Please check your credentials';

  @override
  String get errorNetwork => 'Network error. Please check your connection';

  @override
  String get homeTitle => 'Home';

  @override
  String get profileTitle => 'Profile';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Name';

  @override
  String get editProfileNameFieldLabel => 'Full name';

  @override
  String get editProfileUserFieldNameTitle => 'Username';

  @override
  String get editProfileUsernameFieldLabel => '@username';

  @override
  String get editProfileBioFieldTitle => 'Bio';

  @override
  String get editProfileBioFieldLabel => 'Tell us about yourself';

  @override
  String get editProfileScreenTitle => 'Edit profile';

  @override
  String get editProfileSettingTitle => 'Account Settings';

  @override
  String get editProfileSettingSubtitle => 'Manage your account';

  @override
  String get editProfileScreenEditShopTitle => 'Edit Shop';

  @override
  String get editProfileScreenEditShopSubtitle => 'Change your shop information';

  @override
  String get languageScreenSubtitle => 'Choose your preferred language for the app interface.\nThis will not affect your device settings.';

  @override
  String get languageScreeUseDeviceLang => 'Use Device Language.';

  @override
  String get languageScreeUseDeviceLangNote => 'This will reset to match your device system language.';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get accountSectionTitle => 'Account';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Profile';

  @override
  String get profileItemSubtitle => 'Manage your personal data';

  @override
  String get locationItemTitle => 'Change Location';

  @override
  String get locationItemSubtitle => 'Change your current city';

  @override
  String get saveItemTitle => 'Saved Contents';

  @override
  String get saveItemSubtitle => 'Contents you have saved';

  @override
  String get notificationsItemTitle => 'Notifications';

  @override
  String get notificationsItemSubtitle => 'Manage push and email notifications';

  @override
  String get blockedItemTitle => 'Blocked Accounts';

  @override
  String get blockedItemSubtitle => 'Accounts you have blocked';

  @override
  String get mutedItemTitle => 'Muted Accounts';

  @override
  String get mutedItemSubtitle => 'Anonymous Opinions accounts you\'ve muted';

  @override
  String get qrCodeItemTitle => 'Share QR Code';

  @override
  String get qrCodeItemSubtitle => 'Share your account QR code';

  @override
  String get shareProfileItemTitle => 'Share Profile';

  @override
  String get shareProfileItemSubtitle => 'Share your profile with friends';

  @override
  String get appSettingsSectionTitle => 'App Settings';

  @override
  String get appSettingsSectionSubtitle => 'Customize your experience';

  @override
  String get themeItemTitle => 'Theme';

  @override
  String get themeItemSubtitle => 'Light, Dark, or System';

  @override
  String get languageItemTitle => 'Language';

  @override
  String get languageItemSubtitle => 'Change app language';

  @override
  String get biometricItemTitle => 'Biometric Login';

  @override
  String get biometricItemSubtitle => 'Use Face ID or Touch ID';

  @override
  String get supportSectionTitle => 'Support';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'User Guide';

  @override
  String get guideItemSubtitle => 'Documentation and tutorials';

  @override
  String get helpItemTitle => 'Contact Support';

  @override
  String get helpItemSubtitle => 'Get help with the app';

  @override
  String get feedbackItemTitle => 'Send Feedback';

  @override
  String get feedbackItemSubtitle => 'Share your thoughts';

  @override
  String get rateItemTitle => 'Rate the App';

  @override
  String get rateItemSubtitle => 'Leave a review';

  @override
  String appInfoItemTitle(String appName) {
    return 'About $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Technical information';

  @override
  String get legalSectionTitle => 'Legal';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Terms, Privacy & Policies';

  @override
  String get termsItemSubtitle => 'Read our terms';

  @override
  String get licensesItemTitle => 'Open Source Licenses';

  @override
  String get licensesItemSubtitle => 'Third-party libraries and licenses';

  @override
  String get accountActionsSectionTitle => 'Account Actions';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Deactivate';

  @override
  String get deactivateItemSubtitle => 'Deactivate out of your account';

  @override
  String get deleteItemTitle => 'Delete Account';

  @override
  String get deleteItemSubtitle => 'Permanently remove your account';

  @override
  String get logoutItemTitle => 'Log Out';

  @override
  String get logoutItemSubtitle => 'Sign out of your account';

  @override
  String get loadingDefaultMessage => 'Loading...';

  @override
  String get emptyStateNoDataTitle => 'Nothing here yet';

  @override
  String get emptyStateNoDataSubtitle => 'When there\'s something to show, it\'ll appear here.';

  @override
  String get emptyStateNoResultsTitle => 'No matches';

  @override
  String get emptyStateNoResultsSubtitle => 'Try a different word or filter.';

  @override
  String get emptyStateNoInternetTitle => 'You\'re offline';

  @override
  String get emptyStateNoInternetSubtitle => 'Check your connection and try again.';

  @override
  String get emptyStateNoMessagesTitle => 'No messages yet';

  @override
  String get emptyStateNoMessagesSubtitle => 'Say hello to start your conversation.';

  @override
  String get emptyStateRefresh => 'Refresh';

  @override
  String get emptyStateClearFilters => 'Clear filters';

  @override
  String get emptyStateRetry => 'Try again';

  @override
  String get emptyStateStartChat => 'Say hello';

  @override
  String get errorNetworkTitle => 'Connection Error';

  @override
  String get errorNetworkSubtitle => 'Unable to connect to the server. Check your internet connection.';

  @override
  String get errorServerTitle => 'Server Error';

  @override
  String get errorServerSubtitle => 'Something went wrong on our end. Please try again later.';

  @override
  String get errorClientTitle => 'Request Error';

  @override
  String get errorClientSubtitle => 'There was a problem with your request. Please check and try again.';

  @override
  String get errorParsingTitle => 'Data Error';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'Unable to process the $dataType. This might be a temporary issue.';
  }

  @override
  String get errorPermissionTitle => 'Access Denied';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'You don\'t have permission to access this $dataType.';
  }

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'An unexpected error occurred while loading $dataType. Please try again.';
  }

  @override
  String get errorRetry => 'Try again';

  @override
  String get errorCheckSettings => 'Check settings';

  @override
  String get errorReport => 'Report issue';

  @override
  String get errorGoBack => 'Go back';

  @override
  String get errorRefresh => 'Refresh';

  @override
  String get errorRequestAccess => 'Request access';

  @override
  String get errorContactSupport => 'Contact support';

  @override
  String get eulaTitle => 'End User License Agreement';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'This End User License Agreement (\"EULA\") is a legal agreement between you and Bars Opus, Ltd. for $appName.\n\nBy installing, accessing, or using $appName, you agree to be bound by the terms of this EULA. $appName is licensed, not sold, to you for use only under the terms of this license. Bars Opus, Ltd. reserves all rights not expressly granted to you in this EULA.\n\nYou may not modify, reverse engineer, decompile, or disassemble $appName. This license is valid until terminated by you or Bars Opus, Ltd. Your rights under this license will terminate automatically without notice if you fail to comply with any term(s).\n\nAll intellectual property rights in and to $appName are owned by Bars Opus, Ltd. This EULA is governed by the laws of England and Wales.\n\nFor questions about this EULA, please contact: $supportEmail.';
  }

  @override
  String get eulaFooter => 'By agreeing, you acknowledge that you have read and understood this End User License Agreement.';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String privacyPolicyContent(String appName) {
    return 'This Privacy Policy explains how Bars Opus, Ltd. (\"we\", \"us\", \"our\") collects, uses, and protects your information when you use $appName.\n\nWe collect information you provide directly, such as when you create an account, complete your profile, or contact support. We automatically collect certain information about your device and how you use $appName. We use cookies and similar tracking technologies to track activity and hold certain information.\n\nWe use the information we collect to provide, maintain, and improve $appName. We may share your information with third-party service providers who perform services on our behalf. We may disclose your information if required by law or to protect our rights and safety.\n\nYou have the right to access, correct, or delete your personal information. We implement appropriate technical and organizational measures to protect your information. We may update this Privacy Policy from time to time. We will notify you of any changes.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return '$appName Privacy Policy - Last updated: $currentDateString';
  }

  @override
  String get termsTitle => 'Terms of Service';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'These Terms of Service (\"Terms\") govern your access to and use of $appName. By accessing or using $appName, you agree to be bound by these Terms.\n\nYou must be at least 13 years old to use $appName. You are responsible for safeguarding your account credentials and for all activities under your account. You may not use $appName for any illegal or unauthorized purpose.\n\nWe reserve the right to modify, suspend, or discontinue $appName at any time. All content included in $appName is the property of Bars Opus, Ltd. or its licensors.\n\nWe may terminate or suspend your access to $appName immediately if you violate these Terms. These Terms shall be governed by and construed in accordance with the laws of England and Wales.\n\nFor any questions about these Terms, please contact us at $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Data Sharing Agreement';

  @override
  String dataSharingContent(String appName) {
    return 'This Data Sharing Agreement outlines how your information may be shared when you use $appName social features.\n\nWhen you connect with friends on $appName, certain activity data may be visible to them. Shared activity data may include workout duration, calories burned, exercise minutes, and achievement badges. Your profile information (display name and profile picture) is visible to friends you connect with.\n\nYour email address and contact information remain private and are never shared with other users. You control what data is shared through your $appName privacy settings. You can revoke sharing permissions at any time in the app settings.\n\nData shared with friends is encrypted during transmission and storage. We retain shared data only as long as necessary to provide the sharing functionality. Third-party integrations may have their own data sharing practices, which we recommend reviewing.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'Data sharing in $appName helps create a supportive community while respecting your privacy choices.';
  }

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardSubtitle => 'Manage your shop activities efficiently';

  @override
  String get dashboardSectionTitle => 'Dashboard';

  @override
  String get dashboardSectionSubtitle => 'Overview of your shop\'s performance and key metrics';

  @override
  String get dashboardPayoutTitle => 'Request Payout';

  @override
  String get dashboardPayoutContent => 'Shop owners can request weekly payouts. Navigate to the Earnings section, review your balance, and submit a payout request. Funds typically process within 3-5 business days.';

  @override
  String get dashboardAnalyticsTitle => 'Analytics Dashboard';

  @override
  String get dashboardAnalyticsContent => 'Track your shop\'s performance with real-time analytics. Monitor sales trends, customer engagement, and inventory levels through interactive charts and reports.';

  @override
  String get dashboardScreenshotTitle => 'Dashboard Overview';

  @override
  String get dashboardScreenshotContent => 'The main dashboard provides a comprehensive view of your shop\'s key metrics, recent activities, and quick access to essential features.';

  @override
  String get categoryFeatures => 'Features';

  @override
  String get categoryDashboard => 'Dashboard';

  @override
  String get faqDashboard1Question => 'When can I request a payout?';

  @override
  String get faqDashboard1Answer => 'You can request your payout once a week, every Saturday. The weekly cutoff is Friday at 11:59 PM. Payouts are processed within 3-5 business days.';

  @override
  String get faqDashboard2Question => 'Where do I request my payout?';

  @override
  String get faqDashboard2Answer => 'Navigate to your dashboard and click on the \'Earnings\' section. From there, you\'ll see your current balance and a \'Request Payout\' button. Follow the prompts to complete your request.';

  @override
  String get profileScreenCantChatWithYourself => 'You can\'t chat with yourself';

  @override
  String get profileScreenStartingConversation => 'Starting conversation...';

  @override
  String get profileScreenNoActiveSession => 'No active session — please log in again.';

  @override
  String get profileScreenSignInToChatMessage => 'You have to sign in to send a message';

  @override
  String get profileScreenFollowFeatureComingSoon => 'Follow feature coming soon';

  @override
  String get profileScreenEnterBioPlaceholder => 'Enter a bio so people can know you';

  @override
  String get profileScreenNoBioYet => 'No bio yet';

  @override
  String get profileScreenErrorLoadingProfileBody => 'Unable to load profile. Check your internet and try again.';

  @override
  String get profileScreenLoadingNotifications => 'Loading...';

  @override
  String get profileHeaderBookingsStatLabel => 'Bookings';

  @override
  String get profileHeaderOrdersStatLabel => 'Orders';

  @override
  String get profileHeaderEditProfileButton => 'Edit profile';

  @override
  String get profileHeaderMessageButton => 'Message';

  @override
  String get editableProfileAvatarTakePhoto => 'Take a photo';

  @override
  String get editableProfileAvatarChooseGallery => 'Choose from gallery';

  @override
  String get editProfileScreenAccountTypeLabel => 'Account Type';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Select how you want to use this app. This determines what features are available to you.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Updating account type...';

  @override
  String get editProfileScreenPleaseLogIn => 'Please log in';

  @override
  String get editProfileScreenNameLabel => 'Name';

  @override
  String get editProfileScreenNameHint => 'Enter your name';

  @override
  String get editProfileScreenUsernameLabel => 'Username';

  @override
  String get editProfileScreenUsernameHint => 'Enter username';

  @override
  String get editProfileScreenBioLabel => 'Bio';

  @override
  String get editProfileScreenBioHint => 'Tell something about yourself';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Edit work profile';

  @override
  String get profileTabsAppointments => 'Appointments';

  @override
  String get profileTabsBuys => 'Buys';

  @override
  String get profileTabsSaves => 'Saves';

  @override
  String get searchScreenSearchHint => 'Search shops, professionals, products...';

  @override
  String get searchScreenNoResultsFound => 'No results found';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'No $category found';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Searched for: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Something went wrong';

  @override
  String get searchAppBarSearchHint => 'Search...';

  @override
  String get searchSuggestionsHint => 'Search for shops, professionals for home service, or hair products to buy';

  @override
  String get searchSuggestionsRecentSearches => 'Recent Searches';

  @override
  String get searchSuggestionsClearAll => 'Clear All';

  @override
  String get searchEmptyStateNoResults => 'No results found';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'We couldn\'t find anything for \"$query\"';
  }

  @override
  String get searchEmptyStateTryThese => 'Try these instead:';

  @override
  String get searchResultsShopsHeader => 'Shops';

  @override
  String get searchResultsSeeAll => 'See all';

  @override
  String searchResultsTitle(String category) {
    return '$category Results';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Searching for \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Try different keywords or remove filters';

  @override
  String get searchResultsSomethingWentWrong => 'Something went wrong';

  @override
  String nearYouShopsTitle(int km) {
    return 'Near You\nwithin ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Shops located within $km km of your current location, shown from closest to farthest. Simply set your location once, and we\'ll show you what\'s nearby—whether you\'re at home, work, or exploring a new neighborhood. Handy for last‑minute bookings or when you prefer to walk.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'No shops found nearby';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'No $luxury shops found nearby';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'Shops in $location would be shown here once they become available';
  }

  @override
  String get premiumShopsScreenTitle => 'Premium Shops';

  @override
  String get premiumShopsEmpty => 'No premium shops found';

  @override
  String get premiumShopsHorizontalTitle => 'Premium shops\nfor premium looks';

  @override
  String get premiumShopsHorizontalBody => 'Handpicked high‑end salons and spas offering luxury experiences. These shops are classified as Luxury or Ultra‑Luxury based on their services, pricing, and customer reviews. Perfect when you\'re looking for that extra touch of elegance.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'No premium shops available';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'No $luxury premium shops available';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'Shops would be shown here once they become available';

  @override
  String get topRatedShopsHorizontalTitle => 'Top Rated';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Top Rated \nin $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Shops with the highest customer ratings (4.5+ stars) and a solid number of reviews. These are the favorites among our community—consistently praised for quality, service, and professionalism. A great place to start if you want reliable, crowd‑approved options.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'No top rated shops available';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'No $luxury premium shops available';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'Shops would be shown here once they become available';

  @override
  String get topRatedShopsScreenTitle => 'Top Rated Shops';

  @override
  String get topRatedShopsEmpty => 'No top rated shops found';

  @override
  String get nearYouFreelancersScreenTitle => 'Freelancers near you';

  @override
  String get nearYouFreelancersEmpty => 'No freelancers found nearby';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Try expanding your search area or change location';

  @override
  String get topRatedFreelancersScreenTitle => 'Top rated freelancers';

  @override
  String get topRatedFreelancersEmpty => 'No top rated freelancers found';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Try adjusting your search area';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Top Rated \nin $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Handpicked high‑end professionals offering luxury experiences. These freelancers are classified as top rated based on their work quality, pricing, and customer reviews. Perfect when you\'re looking for that extra touch of excellence.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freelancers Near You in $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Skilled professionals located near you. These freelancers are available for quick bookings and offer convenient, local service. Perfect when you\'re looking for reliability and proximity.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'No top rated freelancers available';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'Freelancers would be shown here once they become available';

  @override
  String get shopNoLocationSetTitle => 'Set your location to discover';

  @override
  String get shopNoLocationSetContent => 'Set your location to discover premium and top rated shops near you.';

  @override
  String get providerTypeShops => 'Shops';

  @override
  String get providerTypeFreelancers => 'Freelancers';

  @override
  String get providerTypeBuy => 'Buy';

  @override
  String get luxuryLevelChipsAll => 'All';

  @override
  String get searchRadiusSliderTitle => 'Explore radius';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Showing results within ${km}km of your location';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'Password must be at most $max characters';
  }

  @override
  String get validationPasswordRepeatingChars => 'Password contains too many repeating characters';

  @override
  String get validationPasswordSequential => 'Password contains sequential characters';

  @override
  String validationPhoneDigits(int digits) {
    return 'Phone number must be $digits digits';
  }

  @override
  String get validationPhoneUK => 'Invalid UK phone number';

  @override
  String validationUrlScheme(String schemes) {
    return 'URL must start with $schemes';
  }

  @override
  String get validationUrlDomain => 'Invalid domain name';

  @override
  String get validationUrlPublicAddress => 'URL must point to a public address';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field must be at most $max characters';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field cannot contain consecutive hyphens or spaces';
  }

  @override
  String get validationCreditCardFormat => 'Please enter a valid credit card number';

  @override
  String get validationCreditCardInvalid => 'Invalid credit card number';

  @override
  String get validationDatePastNotAllowed => 'Date cannot be in the past';

  @override
  String get validationPostalCodeZip => 'Please enter a valid ZIP code (e.g., 12345 or 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Please enter a valid Canadian postal code (e.g., A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Please enter a valid postal code';

  @override
  String get validationSSNFormat => 'Please enter a valid SSN (e.g., 123-45-6789)';

  @override
  String get validationSSNInvalid => 'Invalid SSN';

  @override
  String get validationEmailTooLong => 'Email is too long (max 254 characters)';

  @override
  String get validationEmailLocalPartTooLong => 'Local part of email is too long';

  @override
  String get categoriesAll => 'All';

  @override
  String get categoriesSalon => 'Salons';

  @override
  String get categoriesBarbershop => 'Barbershops';

  @override
  String get categoriesSpa => 'Spas';

  @override
  String get categoriesNailSalon => 'Nail Salons';

  @override
  String get categoriesLashStudio => 'Lash Studios';

  @override
  String get categoriesWaxing => 'Waxing';

  @override
  String get categoriesMassage => 'Massage';

  @override
  String get categoriesMakeup => 'Makeup';

  @override
  String get categoriesSkincare => 'Skincare';

  @override
  String get luxuryLevelModerate => 'Moderate';

  @override
  String get luxuryLevelLuxury => 'Luxury';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Luxury';

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
  String get dating_dashboardFallbackReason => 'You always opt in separately, and nothing starts until you do.';

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
}
