// lib/features/forums/presentation/screens/debate_room_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/forum_insight_screen.dart';
import 'package:attune/features/forums/presentation/widgets/forum_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

class DebateRoomScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String topicTitle;
  final String userSide; // 'for', 'against', or 'browse'

  const DebateRoomScreen({
    super.key,
    required this.topicId,
    required this.topicTitle,
    required this.userSide,
  });

  @override
  ConsumerState<DebateRoomScreen> createState() => _DebateRoomScreenState();
}

class _DebateRoomScreenState extends ConsumerState<DebateRoomScreen> {
  final ScrollController _forScrollController = ScrollController();
  final ScrollController _againstScrollController = ScrollController();
  final TextEditingController _postController = TextEditingController();
  final FocusNode _postFocusNode = FocusNode();
  String? _replyToPostId;
  String? _replyToQuotedText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _forScrollController.dispose();
    _againstScrollController.dispose();
    _postController.dispose();
    _postFocusNode.dispose();
    super.dispose();
  }

  void _loadPosts() {
    Future.microtask(() {
      ref.read(forumPostsProvider(widget.topicId));
    });
  }

  void _setReplyTarget(String postId, String contentPreview) {
    setState(() {
      _replyToPostId = postId;
      _replyToQuotedText =
          contentPreview.length > 60
              ? '${contentPreview.substring(0, 60)}...'
              : contentPreview;
    });
    _postFocusNode.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToPostId = null;
      _replyToQuotedText = null;
    });
  }

  Future<void> _submitPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty || _isSubmitting) return;
    if (widget.userSide == 'browse') return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        submitForumPostProvider((
          topicId: widget.topicId,
          content: content,
          side: widget.userSide,
          replyToPostId: _replyToPostId,
          quotedText: _replyToQuotedText,
        )).future,
      );

      _postController.clear();
      _clearReplyTarget();
      ref.invalidate(forumPostsProvider(widget.topicId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final postsAsync = ref.watch(forumPostsProvider(widget.topicId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.topicTitle.length > 40
              ? '${widget.topicTitle.substring(0, 40)}...'
              : widget.topicTitle,
          style: textTheme.titleSmall,
        ),
        actions: [
          // Insight button
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForumInsightScreen(topicId: widget.topicId),
                ),
              );
            },
          ),
          // Menu button
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report forum'),
                  ),
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.md.w,
              vertical: Spacing.sm.h,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.thumb_up, size: 16, color: colorScheme.primary),
                Gap(Spacing.xs.w),
                Text(
                  'FOR',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
                Gap(Spacing.sm.w),
                postsAsync.when(
                  data: (posts) {
                    final forCount = posts.where((p) => p.side == 'for').length;
                    final againstCount =
                        posts.where((p) => p.side == 'against').length;
                    return Text(
                      '$forCount  ·  $againstCount',
                      style: textTheme.labelSmall,
                    );
                  },
                  loading: () => const Text('...'),
                  error: (_, __) => const Text('0 · 0'),
                ),
                Gap(Spacing.sm.w),
                Text(
                  'AGAINST',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
                Icon(Icons.thumb_down, size: 16, color: colorScheme.error),
              ],
            ),
          ),
          // Two-column debate layout
          Expanded(
            child: postsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: (allPosts) {
                final forPosts =
                    allPosts.where((p) => p.side == 'for').toList();
                final againstPosts =
                    allPosts.where((p) => p.side == 'against').toList();

                return Row(
                  children: [
                    // FOR column (left)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Column header
                            Container(
                              padding: EdgeInsets.all(Spacing.sm.w),
                              color: colorScheme.primary.withOpacity(0.05),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.thumb_up,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  Gap(Spacing.xs.w),
                                  Text(
                                    'FOR',
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${forPosts.length} posts',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            // FOR posts list
                            Expanded(
                              child: ListView.builder(
                                controller: _forScrollController,
                                padding: EdgeInsets.all(Spacing.sm.w),
                                itemCount: forPosts.length,
                                itemBuilder: (context, index) {
                                  final post = forPosts[index];
                                  return ForumPostCard(
                                    post: post,
                                    userSide: widget.userSide,
                                    onReply:
                                        () => _setReplyTarget(
                                          post.id,
                                          post.content,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // AGAINST column (right)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Column header
                          Container(
                            padding: EdgeInsets.all(Spacing.sm.w),
                            color: colorScheme.error.withOpacity(0.05),
                            child: Row(
                              children: [
                                const Spacer(),
                                Text(
                                  '${againstPosts.length} posts',
                                  style: textTheme.bodySmall,
                                ),
                                Gap(Spacing.xs.w),
                                Text(
                                  'AGAINST',
                                  style: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.error,
                                  ),
                                ),
                                Gap(Spacing.xs.w),
                                Icon(
                                  Icons.thumb_down,
                                  size: 16,
                                  color: colorScheme.error,
                                ),
                              ],
                            ),
                          ),
                          // AGAINST posts list
                          Expanded(
                            child: ListView.builder(
                              controller: _againstScrollController,
                              padding: EdgeInsets.all(Spacing.sm.w),
                              itemCount: againstPosts.length,
                              itemBuilder: (context, index) {
                                final post = againstPosts[index];
                                return ForumPostCard(
                                  post: post,
                                  userSide: widget.userSide,
                                  onReply:
                                      () => _setReplyTarget(
                                        post.id,
                                        post.content,
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Reply indicator
          if (_replyToPostId != null)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.md.w,
                vertical: Spacing.sm.h,
              ),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to: "$_replyToQuotedText"',
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearReplyTarget,
                  ),
                ],
              ),
            ),
          // Composer (only if user is not in browse mode)
          if (widget.userSide != 'browse')
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  // Side indicator
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.sm.w,
                      vertical: Spacing.xs.h,
                    ),
                    decoration: BoxDecoration(
                      color:
                          widget.userSide == 'for'
                              ? colorScheme.primary.withOpacity(0.1)
                              : colorScheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.sm.r,
                      ),
                    ),
                    child: Text(
                      widget.userSide == 'for' ? 'FOR' : 'AGAINST',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            widget.userSide == 'for'
                                ? colorScheme.primary
                                : colorScheme.error,
                      ),
                    ),
                  ),
                  Gap(Spacing.sm.w),
                  // Post input
                  Expanded(
                    child: AppTextFormField(
                      controller: _postController,
                      focusNode: _postFocusNode,
                      hintText:
                          widget.userSide == 'for'
                              ? 'Add to the FOR argument...'
                              : 'Add to the AGAINST argument...',
                      maxLines: 3,
                      maxLength: 280,
                      enabled: !_isSubmitting,
                      label: '',
                    ),
                  ),
                  Gap(Spacing.sm.w),
                  // Post button
                  AppButton(
                    label: 'Post',
                    onPressed:
                        _postController.text.trim().isNotEmpty && !_isSubmitting
                            ? _submitPost
                            : null,
                    size: ButtonSize.small,
                    isLoading: _isSubmitting,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Report this forum'),
            content: const Text('Report inappropriate topic or content'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(reportForumProvider(widget.topicId).future);
                  if (context.mounted) {
                    context.showInfoSnackbar('Thank you. We will review this.');
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
    );
  }
}
