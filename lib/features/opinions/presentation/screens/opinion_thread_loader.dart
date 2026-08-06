import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';

class OpinionThreadLoader extends ConsumerWidget {
  const OpinionThreadLoader({super.key, required this.opinionId});

  final String opinionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(opinionRepositoryProvider).getQuotedOpinion(opinionId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final opinion = snapshot.data;
        if (opinion == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This opinion is unavailable.')),
          );
        }

        return CommentThreadScreen(opinionId: opinion.id, opinion: opinion);
      },
    );
  }
}
