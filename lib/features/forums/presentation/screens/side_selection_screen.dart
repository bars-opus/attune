// lib/features/forums/presentation/screens/side_selection_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/debate_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class SideSelectionScreen extends ConsumerStatefulWidget {
  final TopicModel topic;

  const SideSelectionScreen({super.key, required this.topic});

  @override
  ConsumerState<SideSelectionScreen> createState() =>
      _SideSelectionScreenState();
}

class _SideSelectionScreenState extends ConsumerState<SideSelectionScreen> {
  String? _selectedSide;
  bool _isLoading = false;

  Future<void> _joinForum() async {
    if (_selectedSide == null) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(
        joinForumProvider((
          topicId: widget.topic.id,
          side: _selectedSide!,
        )).future,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (_) => DebateRoomScreen(
                  topicId: widget.topic.id,
                  topicTitle: widget.topic.content,
                  userSide: _selectedSide!,
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to join forum: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final forPercentage =
        widget.topic.totalPosts > 0
            ? (widget.topic.forPosts / widget.topic.totalPosts * 100)
                .toStringAsFixed(0)
            : '0';
    final againstPercentage =
        widget.topic.totalPosts > 0
            ? (widget.topic.againstPosts / widget.topic.totalPosts * 100)
                .toStringAsFixed(0)
            : '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join the debate', style: TextStyle(fontSize: 18)),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic title
            Text(
              '"${widget.topic.content}"',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            // Stats
            Row(
              children: [
                _buildStatBox(
                  'FOR',
                  widget.topic.forPosts,
                  forPercentage,
                  colorScheme.primary,
                ),
                Gap(Spacing.md.w),
                _buildStatBox(
                  'AGAINST',
                  widget.topic.againstPosts,
                  againstPercentage,
                  colorScheme.error,
                ),
              ],
            ),
            Gap(Spacing.xl.h),
            // Side selection prompt
            Text(
              'Pick your side to contribute',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            // Side buttons
            Row(
              children: [
                Expanded(
                  child: _buildSideCard(
                    side: 'for',
                    label: 'I\'m FOR',
                    description: 'I agree with this statement',
                    color: colorScheme.primary,
                    isSelected: _selectedSide == 'for',
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: _buildSideCard(
                    side: 'against',
                    label: 'I\'m AGAINST',
                    description: 'I disagree with this statement',
                    color: colorScheme.error,
                    isSelected: _selectedSide == 'against',
                  ),
                ),
              ],
            ),
            Gap(Spacing.md.h),
            // Browse only option
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => DebateRoomScreen(
                            topicId: widget.topic.id,
                            topicTitle: widget.topic.content,
                            userSide: 'browse',
                          ),
                    ),
                  );
                },
                child: const Text('Just browse — I won\'t post'),
              ),
            ),
            const Spacer(),
            // Join button
            AppButton(
              label: 'Join debate',
              onPressed:
                  _selectedSide != null && !_isLoading ? _joinForum : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(
    String label,
    int count,
    String percentage,
    Color color,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: BorderWidthTokens.hairline,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Gap(Spacing.sm.h),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              '$percentage% of posts',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideCard({
    required String side,
    required String label,
    required String description,
    required Color color,
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => setState(() => _selectedSide = side),
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? color.withOpacity(0.15)
                  : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: BorderWidthTokens.md,
          ),
        ),
        child: Column(
          children: [
            Icon(
              side == 'for' ? Icons.thumb_up : Icons.thumb_down,
              color:
                  isSelected ? color : colorScheme.onSurface.withOpacity(0.5),
              size: 32,
            ),
            Gap(Spacing.sm.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : null,
              ),
            ),
            Gap(Spacing.xs.h),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
