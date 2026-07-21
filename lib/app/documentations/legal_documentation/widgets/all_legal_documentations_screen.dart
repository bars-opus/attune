import 'package:attune/core/utils/exports/export_screens.dart';

// Updated with your design tokens
class AllLegalDocumentationsScreen extends StatelessWidget {
  const AllLegalDocumentationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [AppTextButton()],
      ),
      body: ListView(
        children: [
          Gap(Spacing.md.h),
          InfoRowWidget(
            title:
                LegalDocumentationData.privacyPolicy(
                  context,
                ).title, // ← Need context!
            subtitle:
                LegalDocumentationData.privacyPolicy(context).subtitle ?? '',
            icon: LegalDocumentationData.privacyPolicy(context).icon,
            iconColor: LegalDocumentationData.privacyPolicy(context).iconColor,
            backgroundColor: LegalDocumentationData.privacyPolicy(
              context,
            ).iconColor?.withOpacity(0.1),
            avatarRadius: 25.h,
            onTap: () async {
              // await UrlLauncherUtils.launchUrlWithFeedback(
              //   context: context,
              //   url: AppConstants.dataSharingPolicyUrl,

              //   errorMessage: 'Cannot open this link',
              // );
             
            },
            showTrailingArrow: false,
          ),
          InfoRowWidget(
            title: LegalDocumentationData.termsOfService(context).title,
            subtitle:
                LegalDocumentationData.termsOfService(context).subtitle ?? '',
            icon: LegalDocumentationData.termsOfService(context).icon,
            iconColor: LegalDocumentationData.termsOfService(context).iconColor,
            backgroundColor: LegalDocumentationData.termsOfService(
              context,
            ).iconColor?.withOpacity(0.1),
            avatarRadius: 25.h,
            onTap: () {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,
                widget: EmptyStateWidget(
                  type: EmptyStateType.noMessages,

                  onAction: () {},
                ),
              );
            },
            showTrailingArrow: false,
          ),
          InfoRowWidget(
            title: LegalDocumentationData.eula(context).title,
            subtitle: LegalDocumentationData.eula(context).subtitle ?? '',
            icon: LegalDocumentationData.eula(context).icon,
            iconColor: LegalDocumentationData.eula(context).iconColor,
            backgroundColor: LegalDocumentationData.eula(
              context,
            ).iconColor?.withOpacity(0.1),
            avatarRadius: 25.h,
            onTap: () {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,
                widget: ErrorStateWidget(
                  showDetails: true,
                  title: '',
                  compact: true,
                  subtitle:
                      'Unable to process the data. This might be a temporary issue',
                  errorDetails: '',

                  type: ErrorStateType.genericError,
                ),
              );
            },
            showTrailingArrow: false,
          ),
          InfoRowWidget(
            title: LegalDocumentationData.dataSharingAgreement(context).title,
            subtitle:
                LegalDocumentationData.dataSharingAgreement(context).subtitle ??
                '',
            icon: LegalDocumentationData.dataSharingAgreement(context).icon,
            iconColor:
                LegalDocumentationData.dataSharingAgreement(context).iconColor,
            backgroundColor: LegalDocumentationData.dataSharingAgreement(
              context,
            ).iconColor?.withOpacity(0.1),
            avatarRadius: 25.h,
            onTap: () async {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,maxHeight: 400.h,
                widget: ConfirmationDialog(
                  type: ConfirmationType.warning,
                  title: 'Are you sure you want to continue',
                  confirmText: 'Continue',
                  message:
                      'We Continue to the bext page and see what is there all day al nught',
                  onConfirm: () {},
                ),
              );
            },
            showTrailingArrow: false,
          ),
        ],
      ),
    );
  }
}
