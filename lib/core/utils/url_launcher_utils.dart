// lib/core/utils/url_launcher_utils.dart
import 'package:attune/core/utils/exports/export_screens.dart';

class UrlLauncherUtils {
  /// Launch a URL with error handling and optional feedback
  static Future<void> launchUrlWithFeedback({
    required BuildContext context,
    required String url,
    LaunchMode mode = LaunchMode.externalApplication,
    bool showSnackbar = true,
    String? errorMessage,
  }) async {
    try {
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: mode);
      } else {
        _showError(context, errorMessage ?? 'Cannot open link', showSnackbar);
      }
    } catch (e) {
      _showError(context, 'Error: ${e.toString()}', showSnackbar);
    }
  }

  /// Launch common URL types with presets
  static Future<void> launchEmail({
    required BuildContext context,
    required String email,
    String? subject,
    String? body,
    bool showSnackbar = true,
  }) async {
    final url =
        Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {
            if (subject != null) 'subject': subject,
            if (body != null) 'body': body,
          },
        ).toString();

    await launchUrlWithFeedback(
      context: context,
      url: url,

      errorMessage: 'Cannot open email app',
      showSnackbar: showSnackbar,
    );
  }

  static Future<void> launchPhone({
    required BuildContext context,
    required String phoneNumber,
    bool showSnackbar = true,
  }) async {
    final url = 'tel:$phoneNumber';

    await launchUrlWithFeedback(
      context: context,
      url: url,

      errorMessage: 'Cannot make phone call',
      showSnackbar: showSnackbar,
    );
  }

  static Future<void> launchSms({
    required BuildContext context,
    required String phoneNumber,
    String? body,
    bool showSnackbar = true,
  }) async {
    final url =
        Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {if (body != null) 'body': body},
        ).toString();

    await launchUrlWithFeedback(
      context: context,
      url: url,

      errorMessage: 'Cannot open messages app',
      showSnackbar: showSnackbar,
    );
  }

  static Future<void> launchMaps({
    required BuildContext context,
    required double latitude,
    required double longitude,
    String? label,
    bool showSnackbar = true,
  }) async {
    final url =
        Uri(
          scheme: 'https',
          host: 'maps.google.com',
          queryParameters: {
            'q': '$latitude,$longitude',
            if (label != null) 'q': '$latitude,$longitude($label)',
          },
        ).toString();

    await launchUrlWithFeedback(
      context: context,
      url: url,

      errorMessage: 'Cannot open maps app',
      showSnackbar: showSnackbar,
    );
  }

  static Future<void> launchAppStore({
    required BuildContext context,
    String? appId,
    bool showSnackbar = true,
  }) async {
    // iOS App Store
    final iosUrl = AppConstants.appStoreLink;

    // Android Play Store
    final androidUrl = AppConstants.playStoreLink;

    // Detect platform
    final url =
        Theme.of(context).platform == TargetPlatform.iOS ? iosUrl : androidUrl;

    await launchUrlWithFeedback(
      context: context,
      url: url,

      errorMessage: 'Cannot open app store',
      showSnackbar: showSnackbar,
    );
  }

  // Private helper method
  static void _showError(
    BuildContext context,
    String message,
    bool showSnackbar,
  ) {
    if (showSnackbar) {
      context.showErrorSnackbar(message);
    }
  }
}
