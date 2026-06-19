// lib/features/survey/models/survey_models.dart

/// Condition that controls whether a question is shown.
///
/// A question is visible only when the answer stored under [fieldName]
/// equals [value].  If a question's [SurveyQuestion.visibleIf] is null
/// the question is always visible — this keeps every existing survey that
/// was created before this feature was added working without any changes.
class VisibleCondition {
  final String fieldName;
  final dynamic value;

  const VisibleCondition({required this.fieldName, required this.value});

  factory VisibleCondition.fromMap(Map<String, dynamic> map) {
    return VisibleCondition(
      fieldName: map['fieldName'] as String? ?? '',
      value: map['value'],
    );
  }
}

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

  /// Used by matrix (the rating scale, e.g. [1, 2, 3, 4, 5]).
  final List<int> columns;

  /// Optional visibility condition.
  ///
  /// • null  → always visible  (all old surveys without this field)
  /// • set   → visible only when [VisibleCondition] is satisfied
  final VisibleCondition? visibleIf;

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
    this.visibleIf,
  });

  /// Section / subsection are pure UI headings: no input, never validated,
  /// never stored in the response.
  bool get isDisplayOnly => type == 'section' || type == 'subsection';

  factory SurveyQuestion.fromMap(String id, Map<String, dynamic> map) {
    final rawOptions = map['options'] as List<dynamic>? ?? [];
    final rawRows    = map['rows']    as List<dynamic>? ?? [];
    final rawColumns = map['columns'] as List<dynamic>? ?? [];

    // Parse visibleIf — null-safe so surveys without the field keep working.
    VisibleCondition? visibleIf;
    final rawVisibleIf = map['visibleIf'];
    if (rawVisibleIf is Map<String, dynamic>) {
      visibleIf = VisibleCondition.fromMap(rawVisibleIf);
    }

    return SurveyQuestion(
      id:       id,
      fieldName: map['fieldName'] as String? ?? '',
      label:    map['label']     as String? ?? '',
      order:    (map['order']    as num?)?.toInt() ?? 0,
      required: map['required'] == true,
      type:     map['type']      as String? ?? 'text',
      options:  rawOptions
          .map((o) => SurveyOption.fromMap(o as Map<String, dynamic>))
          .toList(),
      rows: rawRows
          .map((o) => SurveyOption.fromMap(o as Map<String, dynamic>))
          .toList(),
      columns:  rawColumns.map((c) => (c as num).toInt()).toList(),
      visibleIf: visibleIf,
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
      id:          id,
      title:       map['title']       as String? ?? '',
      description: map['description'] as String? ?? '',
      active:      map['active'] == true,
    );
  }
}