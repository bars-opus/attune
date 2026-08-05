// lib/features/documentation/presentation/widgets/faq_widget.dart
import 'package:attune/core/utils/exports/export_screens.dart';

class FAQWidget extends StatefulWidget {
  final List<FAQModel> faqs;
  final bool groupByCategory;

  const FAQWidget({super.key, required this.faqs, this.groupByCategory = true});

  @override
  State<FAQWidget> createState() => _FAQWidgetState();
}

class _FAQWidgetState extends State<FAQWidget> {
  final Map<String, bool> _expandedStates = {};

  @override
  void initState() {
    super.initState();
    // Initialize all FAQs as collapsed
    for (final faq in widget.faqs) {
      _expandedStates[faq.id] = faq.isExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final faqs = widget.faqs;

    if (widget.groupByCategory) {
      final categorized = _groupFAQsByCategory(faqs);
      return _buildCategorizedFAQs(context, categorized);
    }

    return _buildSimpleFAQs(context, faqs);
  }

  Map<String, List<FAQModel>> _groupFAQsByCategory(List<FAQModel> faqs) {
    final Map<String, List<FAQModel>> categorized = {};

    for (final faq in faqs) {
      categorized.putIfAbsent(faq.category, () => []).add(faq);
    }

    // Sort categories and FAQs within
    categorized.forEach((category, categoryFaqs) {
      categoryFaqs.sort((a, b) => a.order.compareTo(b.order));
    });

    return categorized;
  }

  Widget _buildCategorizedFAQs(
    BuildContext context,
    Map<String, List<FAQModel>> categorized,
  ) {
    final categories = categorized.keys.toList()..sort();
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, categoryIndex) {
        final category = categories[categoryIndex];
        final categoryFaqs = categorized[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Header
            Padding(
              padding: EdgeInsets.only(bottom: 16.h, top: 8.h),
              child: Text(
                category,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // FAQs in this category
            ...categoryFaqs.map((faq) => _buildFAQItem(context, faq)),
            // Divider between categories (except last)
            if (categoryIndex < categories.length - 1) ...[
              Gap(Spacing.md),
              const AppDivider(),
              Gap(Spacing.md),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSimpleFAQs(BuildContext context, List<FAQModel> faqs) {
    return ListView.builder(
      itemCount: faqs.length,
      itemBuilder: (context, index) {
        return _buildFAQItem(context, faqs[index]);
      },
    );
  }

  Widget _buildFAQItem(BuildContext context, FAQModel faq) {
    final isExpanded = _expandedStates[faq.id] ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        children: [
          ExpansionTile(
            key: ValueKey(faq.id),
            title: Text(
              faq.question,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _expandedStates[faq.id] = expanded;
              });
            },
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 16.h),
                child: Text(
                  faq.answer,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onBackground,
                  ),
                ),
              ),
            ],
          ),
          AppDivider(),
        ],
      ),
    );
  }
}
