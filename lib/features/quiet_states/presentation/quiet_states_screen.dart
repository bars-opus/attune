import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/quiet_states/data/quiet_state_service.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// The fixed line a person may choose to send once (research 06 B9 (a)).
const quietLine = "I'm in a heavy patch. I may be quieter; it isn't about you.";

/// Settings -> Quiet for a while (Spec 7, B9 (a)).
class QuietStatesScreen extends ConsumerStatefulWidget {
  const QuietStatesScreen({super.key, this.sendLine, this.canSendLine});

  static const routeName = '/settings/quiet';

  /// Sends [quietLine] as an ordinary message; true when it went.
  final Future<bool> Function(String text)? sendLine;

  /// Whether there is an active relationship to send it to (review M11).
  final Future<bool> Function()? canSendLine;

  @override
  ConsumerState<QuietStatesScreen> createState() => _QuietStatesScreenState();
}

class _QuietStatesScreenState extends ConsumerState<QuietStatesScreen> {
  bool _busy = false;

  QuietStateService get _service => ref.read(quietStateServiceProvider);

  Future<bool> _canSend() async {
    final custom = widget.canSendLine;
    if (custom != null) return custom();
    return await ref.read(currentRelationshipIdProvider.future) != null;
  }

  Future<bool> _send(String text) async {
    final custom = widget.sendLine;
    if (custom != null) return custom(text);
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (relationshipId == null || me == null) return false;
    await ref
        .read(chatRepositoryProvider)
        .sendTextMessage(
          relationshipId: relationshipId,
          senderId: me,
          clientMessageId: const Uuid().v4(),
          content: text,
        );
    return true;
  }

  Future<void> _toggle(QuietKind kind, bool on, QuietState? current) async {
    setState(() => _busy = true);
    try {
      if (on) {
        await _service.start(kind);
      } else if (current?.kind == kind) {
        await _service.end();
      }
      ref.invalidate(quietStateProvider);
      final now = await ref.read(quietStateProvider.future);
      if (on && now != null && !now.lineOffered && mounted) {
        await _offerLine();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't change it. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerLine() async {
    final canSend = await _canSend();
    if (!mounted) return;
    final send = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _LineSheet(canSend: canSend),
    );
    await _service.markLineOffered();
    ref.invalidate(quietStateProvider);
    if (send == true) {
      final sent = await _send(quietLine).catchError((_) => false);
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send it. Try again.")),
        );
      }
    }
  }

  Future<void> _end() async {
    setState(() => _busy = true);
    try {
      await _service.end();
      ref.invalidate(quietStateProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(quietStateProvider).valueOrNull;
    final enabled = ref.watch(quietStatesEnabledProvider).valueOrNull;
    if (enabled == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiet for a while')),
        body: Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Text('Coming soon', style: text.titleMedium),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Quiet for a while')),
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg.w),
        children: [
          Text(
            'For a while, Attune stops celebrating: no sparkles, no goal '
            'notices, a plainer daily summary and no On this day. It ends on '
            'its own after 14 days. Only you can see this.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Gap(Spacing.lg.h),
          for (final kind in QuietKind.values)
            InfoRowWidget(
              title: kind.label,
              subtitle: '',
              icon:
                  kind == QuietKind.loss
                      ? Icons.spa_outlined
                      : Icons.cloud_outlined,
              isToggleItem: true,
              toggleValue: state?.kind == kind,
              onToggleChanged: (on) {
                if (!_busy) _toggle(kind, on, state);
              },
              showDivider: kind != QuietKind.values.last,
            ),
          if (state != null) ...[
            Gap(Spacing.lg.h),
            Text(
              'Until ${MyDateFormat.toDate(state.until.toLocal())}',
              style: text.bodyLarge,
            ),
            Gap(Spacing.md.h),
            OutlinedButton(
              onPressed: _busy ? null : _end,
              child: const Text('End now'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LineSheet extends StatelessWidget {
  const _LineSheet({required this.canSend});

  final bool canSend;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              canSend
                  ? 'Want to let them know? You can send this, once:'
                  : 'If you want to, you could tell them:',
              style: text.titleMedium,
            ),
            Gap(Spacing.md.h),
            Text(quietLine, style: text.bodyLarge),
            Gap(Spacing.lg.h),
            if (canSend) ...[
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send'),
              ),
              Gap(Spacing.sm.h),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
