import 'package:csv/csv.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../survey/models/survey_models.dart';
import '../repositories/admin_repository.dart';

class AdminController extends GetxController {
  final _repo = AdminRepository();

  // ── Survey list state ─────────────────────────────────────────────────────
  final surveyStats = <SurveyStats>[].obs;
  final isLoading = true.obs;
  final RxnString surveysError = RxnString();

  // ── Detail-page state ─────────────────────────────────────────────────────
  final Rx<Survey?> activeSurvey = Rx(null);
  final questions = <SurveyQuestion>[].obs;
  final responses = <SurveyResponse>[].obs;
  final isDetailLoading = false.obs;
  final isExporting = false.obs;

  /// uid → display name cache so we only fetch once per enumerator.
  final _nameCache = <String, String>{};

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
  }

  // ── Survey list ───────────────────────────────────────────────────────────

  Future<void> loadSurveys() async {
    isLoading.value = true;
    surveysError.value = null;
    try {
      surveyStats.value = await _repo.getAllSurveyStats();
    } catch (e) {
      surveysError.value = 'Failed to load surveys. Please try again.';
      AppSnackbar.show('Error', surveysError.value!);
    } finally {
      isLoading.value = false;
    }
  }

  // ── Detail page ───────────────────────────────────────────────────────────

  Future<void> openSurveyDetail(Survey survey) async {
    activeSurvey.value = survey;
    isDetailLoading.value = true;
    questions.clear();
    responses.clear();

    try {
      final results = await Future.wait([
        _repo.getQuestions(survey.id),
        _repo.getResponses(survey.id),
      ]);
      questions.value = results[0] as List<SurveyQuestion>;
      responses.value = results[1] as List<SurveyResponse>;

      // Pre-cache enumerator names for all unique UIDs in responses.
      final uids = responses
          .map((r) => r.submittedBy)
          .whereType<String>()
          .toSet();
      for (final uid in uids) {
        if (!_nameCache.containsKey(uid)) {
          _nameCache[uid] = await _repo.getUserName(uid) ?? uid;
        }
      }
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to load survey details.');
    } finally {
      isDetailLoading.value = false;
    }
  }

  /// Returns the cached display name for a UID, or the raw UID if unknown.
  String enumeratorName(String? uid) {
    if (uid == null) return 'Unknown';
    return _nameCache[uid] ?? uid;
  }

  /// Number of unique enumerators who have submitted responses.
  int get uniqueEnumeratorCount {
    return responses
        .map((r) => r.submittedBy)
        .whereType<String>()
        .toSet()
        .length;
  }

  /// The most recent submission time, or null if no responses exist.
  DateTime? get latestResponseTime {
    DateTime? latest;
    for (final r in responses) {
      if (r.submittedAt != null) {
        if (latest == null || r.submittedAt!.isAfter(latest)) {
          latest = r.submittedAt;
        }
      }
    }
    return latest;
  }

  /// Questions that actually carry a value in the response — section and
  /// subsection are display-only headings and were never stored.
  List<SurveyQuestion> get _storableQuestions =>
      questions.where((q) => !q.isDisplayOnly).toList();

  // ── Answer formatting for CSV ─────────────────────────────────────────────

  /// Formats a stored answer value for CSV display.
  ///
  /// Most answer types (text, number, geocode, radio, dropdown, checkbox) are
  /// already stored as human-readable labels by [SurveyController.submitResponse].
  ///
  /// Matrix answers are stored as {rowValue: columnInt}.  This method
  /// resolves rowValue → rowLabel using the question's [rows] definition,
  /// producing a readable string like "Cost: 3, Comfort: 4, Safety: 5".
  String _formatAnswer(SurveyQuestion question, dynamic val) {
    if (val == null) return '';

    if (question.type == 'matrix' && val is Map) {
      // Build a rowValue → rowLabel lookup from the question definition.
      final rowLabelFor = {
        for (final row in question.rows) row.value: row.label,
      };
      // Produce "RowLabel: columnValue" pairs joined by ", ".
      final parts = val.entries.map((e) {
        final label = rowLabelFor[e.key.toString()] ?? e.key.toString();
        return '$label: ${e.value}';
      }).toList();
      return parts.join(', ');
    }

    if (val is List) {
      // Checkbox answers — already stored as labels by the submit logic.
      return val.map((e) => e.toString()).join(', ');
    }

    return val.toString();
  }

  // ── CSV Export ─────────────────────────────────────────────────────────────

  Future<void> exportCsv() async {
    if (responses.isEmpty) {
      AppSnackbar.show('No Data', 'There are no responses to export.');
      return;
    }

    isExporting.value = true;
    try {
      final storable = _storableQuestions;

      // Build header row: meta columns + one column per question (by label).
      final header = [
        'S.No',
        'Submitted By',
        'Submitted At',
        ...storable.map((q) => q.label),
      ];

      // Build data rows.
      final rows = <List<dynamic>>[];
      for (var i = 0; i < responses.length; i++) {
        final r = responses[i];
        final row = <dynamic>[
          i + 1,
          enumeratorName(r.submittedBy),
          r.submittedAt?.toLocal().toString() ?? '',
        ];

        for (final q in storable) {
          final val = r.answers[q.fieldName];
          row.add(_formatAnswer(q, val));
        }

        rows.add(row);
      }

      final csvData = const ListToCsvConverter().convert([header, ...rows]);

      // Keep exports outside cache so the OS is less likely to remove them.
      final dir = await getApplicationDocumentsDirectory();
      final safeTitle = activeSurvey.value!.title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${safeTitle}_responses_$timestamp.csv');
      await file.writeAsString(csvData);

      AppSnackbar.show('Exported', 'CSV saved to:\n${file.path}');

      try {
        final result = await OpenFile.open(file.path, type: 'text/csv');
        if (result.type != ResultType.done) {
          debugPrint(
            'OpenFile could not open the CSV: '
                '${result.type} — ${result.message}',
          );
        }
      } catch (_) {
        // Silently ignore if no handler is available.
      }
    } catch (e) {
      AppSnackbar.show('Export Error', 'Failed to export CSV: $e');
    } finally {
      isExporting.value = false;
    }
  }
}