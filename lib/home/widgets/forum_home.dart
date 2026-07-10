import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';

class ForumHome extends StatelessWidget {
  const ForumHome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final textTheme = theme.textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          'Opinions',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onBackground,
          ),
        ),
      ),
      body: OpinionsTab(),
    );
  }
}
