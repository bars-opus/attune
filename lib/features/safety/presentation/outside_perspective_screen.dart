import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every way into this card (Pulse, Settings, the Understand footer, the
/// supporter card) is closed until its content is signed off: it shares the
/// private safety check's flag (Spec 8, plan review P1, M10).
final outsidePerspectiveEnabledProvider = Provider<bool>(
  (ref) => ref.watch(safetySelfCheckEnabledProvider).valueOrNull ?? false,
);

/// Research 06 B10: "a trained outside perspective". A resource, never an
/// insight: it is never framed as "recommended for your relationship", and
/// CTAs say "a trained outside perspective", not "therapist" (CLINICAL
/// §9.3). Country lists and "When your partner is struggling" await
/// clinician authorship, so they ship as [DRAFT].
class OutsidePerspectiveScreen extends StatelessWidget {
  const OutsidePerspectiveScreen({super.key});

  static const routeName = '/support/outside-perspective';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('A trained outside perspective')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            'What couples counselling is',
            'Time with someone trained to help two people hear each other, '
                'usually weekly for a while. It is for ordinary couples as '
                'much as couples in crisis.',
          ),
          section(
            'What to look for',
            'An approach with good evidence behind it, such as integrative '
                'behavioural couple therapy (IBCT), emotionally focused '
                'therapy (EFT) or behavioural couple therapy (BCT); and '
                'someone who meets each of you on your own first, so either '
                'of you can say what is hard to say together.',
          ),
          section(
            'How to find someone',
            '[DRAFT] Ghana: ask a clinic or your GP for a counselling '
                'psychologist. UK: Relate, or the BACP directory. US: the '
                'AAMFT therapist locator. Elsewhere: your national '
                'psychology or counselling association.',
          ),
          section(
            'Support for you on your own',
            'You can see someone by yourself, whatever your partner decides. '
                'Talking it through alone is often where things start.',
          ),
          section(
            'When your partner is struggling',
            '[DRAFT] If they might be in danger, call your local emergency '
                'number. Otherwise: stay close, listen more than you advise, '
                'and look after yourself too. You can be supportive without '
                'carrying it alone.',
          ),
        ],
      ),
    );
  }
}
