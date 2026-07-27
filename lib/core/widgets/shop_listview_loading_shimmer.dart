import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/forum_shimmer.dart';

class ListviewLoadingShimmer extends StatelessWidget {
  final bool isComment;
  const ListviewLoadingShimmer({super.key, this.isComment = false});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: 10,
      separatorBuilder: (_, __) => AppDivider(),
      itemBuilder: (_, __) => ForumSchimmer(isComment:isComment),
    );
  }
}
