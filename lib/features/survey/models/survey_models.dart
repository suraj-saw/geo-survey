/// Represents a single option in dropdown / radio / checkbox questions.
class QuestionOption {
  final String label;
  final String value;
  final bool allowText; // only relevant for radio "Other" options

  const QuestionOption({
    required this.label,
    required this.value,
    this.allowText = false,
  });

  factory QuestionOption.fromMap(Map<String, dynamic> map) {
    return QuestionOption(
      label: map['label'] as String? ?? '',
      value: map['value'] as String? ?? '',
      allowText: map['allowText'] == true,
    );
  }
}

/// Represents one question document from Firestore.
class SurveyQuestion {
  final String id;
  final String fieldName;
  final String label;
  final int order;
  final bool required;
  final String type; // text | number | geocode | dropdown | radio | checkbox
  final List<QuestionOption> options;

  const SurveyQuestion({
    required this.id,
    required this.fieldName,
    required this.label,
    required this.order,
    required this.required,
    required this.type,
    required this.options,
  });

  factory SurveyQuestion.fromMap(String id, Map<String, dynamic> map) {
    final rawOptions = map['options'] as List<dynamic>? ?? [];
    return SurveyQuestion(
      id: id,
      fieldName: map['fieldName'] as String? ?? '',
      label: map['label'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      required: map['required'] == true,
      type: map['type'] as String? ?? 'text',
      options: rawOptions
          .map((o) => QuestionOption.fromMap(o as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents a survey document from Firestore.
class Survey {
  final String id;
  final String title;
  final String description;
  final bool active;

  const Survey({
    required this.id,
    required this.title,
    required this.description,
    required this.active,
  });

  factory Survey.fromMap(String id, Map<String, dynamic> map) {
    return Survey(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      active: map['active'] == true,
    );
  }
}