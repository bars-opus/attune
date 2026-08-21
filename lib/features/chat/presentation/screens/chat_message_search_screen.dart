import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Live-as-you-type search over this conversation's message history,
/// reached from Chat settings' "Search" row. Debounced the same way
/// LocationSearchScreen debounces its own query field. Tapping a result
/// pops with that message's id as a typed result — the caller
/// (chat_settings_screen.dart) is NOT an already-open ChatScreen, so it
/// pops itself too and pushes a fresh ChatScreen with jumpTo, same shape
/// as ChatMediaScreen's own "Go to message" handling.
class ChatMessageSearchScreen extends ConsumerStatefulWidget {
  const ChatMessageSearchScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatMessageSearchScreen> createState() =>
      _ChatMessageSearchScreenState();
}

class _ChatMessageSearchScreenState
    extends ConsumerState<ChatMessageSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _debouncer = Debouncer(
    const Duration(milliseconds: 350),
    initialValue: '',
    checkEquality: true,
  );

  List<Message>? _results;
  bool _isSearching = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _debouncer.values.listen(_runSearch);
    _controller.addListener(() => _debouncer.setValue(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _results = null;
          _isSearching = false;
          _error = null;
        });
      }
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await ref
          .read(chatRepositoryProvider)
          .searchMessages(widget.conversation.relationshipId, query: query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = error;
      });
    }
  }

  void _openResult(Message message) {
    context.pop(message.id);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Search messages'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: SearchFormField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              hintText: 'Search messages',
              isLoading: _isSearching,
              onChanged: (_) {
                // Rebuild immediately so the empty/prompt state clears the
                // instant typing starts, rather than waiting on the
                // debounced search itself to resolve.
                setState(() {});
              },
            ),
          ),
          Expanded(child: _buildBody(textTheme)),
        ],
      ),
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: EmptyStateWidget(
          title: '',
          icon: Icons.search,
          subtitle: 'Search for messages in this chat',
          compact: false,
        ),
      );
    }
    if (_isSearching && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorStateWidget.from(
        _error,
        onRetry: () => _runSearch(_controller.text),
      );
    }
    final results = _results ?? const <Message>[];
    if (results.isEmpty) {
      return const EmptyStateWidget(
        type: EmptyStateType.noResults,
        compact: false,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final message = results[index];
        return InfoRowWidget(
          title: message.content,
          subtitle: DateFormat.yMMMd().add_jm().format(message.createdAt),
          icon: Icons.chat_bubble_outline,
          showAvatar: false,
          showDivider: true,
          onTap: () => _openResult(message),
        );
      },
    );
  }
}
