// lib/features/documentation/data/models/faq_model.dart

class FAQModel {
  final String id;
  final String question;
  final String answer;
  final String category;
  final int order;
  final bool isExpanded;

  const FAQModel({
    required this.id,
    required this.question,
    required this.answer,
    this.category = 'General',
    this.order = 0,
    this.isExpanded = false,
  });

  FAQModel copyWith({
    String? id,
    String? question,
    String? answer,
    String? category,
    int? order,
    bool? isExpanded,
  }) {
    return FAQModel(
      id: id ?? this.id,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      category: category ?? this.category,
      order: order ?? this.order,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}
