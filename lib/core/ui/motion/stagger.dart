import 'package:flutter/widgets.dart';

import 'settle_in.dart';

/// Cascades a list of children into view by giving each a slightly longer
/// settle so they arrive in sequence. Generic — the chat reconnect cascade is
/// the consumer. Children must carry their own keys. Renders at rest under
/// reduce-motion because it defers to [SettleIn]'s reduce-motion handling.
class Stagger extends StatelessWidget {
  const Stagger({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 60),
    this.animate = true,
    this.baseDuration = const Duration(milliseconds: 260),
  });

  final List<Widget> children;
  final Duration interval;
  final bool animate;
  final Duration baseDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          SettleIn(
            key: ValueKey('stagger_$i'),
            animate: animate,
            duration: baseDuration + interval * i,
            child: children[i],
          ),
      ],
    );
  }
}
