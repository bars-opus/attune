import 'package:attune/core/utils/exports/export_screens.dart';

class ReadAll extends StatelessWidget {
  final String body;
  const ReadAll({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      children: [
        AppTextButton(),
        Gap(20.h),
        Text(
          body,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
