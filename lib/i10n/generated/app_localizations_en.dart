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
    return 'You are browsing $appName as a guest. Log in or create an account to start managing your shop — it takes less than 5 seconds. We have a variety of tools to help grow your business, all free of charge.';
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
  String emptyStateNoDataTitle(String dataType) {
    return 'No $dataType yet';
  }

  @override
  String emptyStateNoDataSubtitle(String dataType) {
    return 'When $dataType becomes available, they will appear here.';
  }

  @override
  String get emptyStateNoResultsTitle => 'No results found';

  @override
  String emptyStateNoResultsSubtitle(String dataType) {
    return 'Try adjusting your search or filters to find $dataType.';
  }

  @override
  String get emptyStateNoInternetTitle => 'No internet connection';

  @override
  String get emptyStateNoInternetSubtitle => 'Check your connection and try again.';

  @override
  String get emptyStateNoFavoritesTitle => 'No favorites yet';

  @override
  String get emptyStateNoFavoritesSubtitle => 'Start adding items to your favorites list.';

  @override
  String get emptyStateNoMessagesTitle => 'No messages';

  @override
  String get emptyStateNoMessagesSubtitle => 'Start a conversation to see messages here.';

  @override
  String get emptyStateRefresh => 'Refresh';

  @override
  String get emptyStateClearFilters => 'Clear filters';

  @override
  String get emptyStateRetry => 'Try again';

  @override
  String get emptyStateExplore => 'Explore';

  @override
  String get emptyStateStartChat => 'Start chat';

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
  String get dataTypeUsers => 'users';

  @override
  String get dataTypeUser => 'user';

  @override
  String get dataTypeProducts => 'products';

  @override
  String get dataTypeProduct => 'product';

  @override
  String get dataTypeOrders => 'orders';

  @override
  String get dataTypeOrder => 'order';

  @override
  String get dataTypeMessages => 'messages';

  @override
  String get dataTypeMessage => 'message';

  @override
  String get dataTypeFavorites => 'favorites';

  @override
  String get dataTypeFavorite => 'favorite';

  @override
  String get dataTypeData => 'data';

  @override
  String get dataTypeContent => 'content';

  @override
  String get dataTypeItems => 'items';

  @override
  String get dataTypeItem => 'item';

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
}
