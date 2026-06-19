/// Represents a single selectable option in dropdown / radio / checkbox
/// questions, and a single row in matrix questions.
class SurveyOption {
  final String label;
  final String value;
  final bool allowText; // "Other" style options that need free text

  const SurveyOption({
    required this.label,
    required this.value,
    this.allowText = false,
  });

  factory SurveyOption.fromMap(Map<String, dynamic> map) {
    return SurveyOption(
      label: map['label'] as String? ?? '',
      value: map['value']?.toString() ?? '',
      allowText: map['allowText'] == true,
    );
  }
}

/// Backwards-compatible alias. Older code referenced `QuestionOption` —
/// keep this so nothing else in the app needs to change.
typedef QuestionOption = SurveyOption;

/// Represents one question document from Firestore.
class SurveyQuestion {
  final String id;
  final String fieldName;
  final String label;
  final int order;
  final bool required;

  /// text | number | geocode | dropdown | radio | checkbox | matrix |
  /// section | subsection
  final String type;

  /// Used by dropdown / radio / checkbox.
  final List<SurveyOption> options;

  /// Used by matrix (the rated items, e.g. Cost / Comfort / Safety).
  final List<SurveyOption> rows;

  /// Used by matrix (the rating scale, e.g. [1,2,3,4,5]).
  final List<int> columns;

  const SurveyQuestion({
    required this.id,
    required this.fieldName,
    required this.label,
    required this.order,
    required this.required,
    required this.type,
    required this.options,
    this.rows = const [],
    this.columns = const [],
  });

  /// Section / subsection are pure UI headings: no input, never validated,
  /// never stored in the response.
  bool get isDisplayOnly => type == 'section' || type == 'subsection';

  factory SurveyQuestion.fromMap(String id, Map<String, dynamic> map) {
    final rawOptions = map['options'] as List<dynamic>? ?? [];
    final rawRows = map['rows'] as List<dynamic>? ?? [];
    final rawColumns = map['columns'] as List<dynamic>? ?? [];

    return SurveyQuestion(
      id: id,
      fieldName: map['fieldName'] as String? ?? '',
      label: map['label'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      required: map['required'] == true,
      type: map['type'] as String? ?? 'text',
      options: rawOptions
          .map((o) => SurveyOption.fromMap(o as Map<String, dynamic>))
          .toList(),
      rows: rawRows
          .map((o) => SurveyOption.fromMap(o as Map<String, dynamic>))
          .toList(),
      columns: rawColumns.map((c) => (c as num).toInt()).toList(),
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