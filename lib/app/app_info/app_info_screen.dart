import 'package:attune/core/utils/exports/export_screens.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: ElevationTokens.none,
      ),
      body: SingleChildScrollView(
        padding: Spacing.allLg,
        child: AppInfoWidget(
          showLogo: true,
          showVersion: true,
          showDeveloper: true,
          showSocialLinks: true,
          showTechnicalDetails: true,
          showLegalLinks: true,
          onCheckForUpdates: () {},
          onViewChangelog: () {
            // Navigate to changelog screen
            // Navigator.push(context, MaterialPageRoute(
            //   builder: (context) => const ChangelogScreen(),
            // ));
          },
          onContactSupport: () {
            _launchEmail(AppConstants.supportEmail);
          },
        ),
      ),
    );
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    // if (await canLaunchUrl(uri)) {
    //   await launchUrl(uri);
    // }
  }
}
