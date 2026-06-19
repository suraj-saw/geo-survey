// lib/features/survey/controllers/survey_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../models/survey_models.dart';
import '../repositories/survey_repository.dart';

class SurveyController extends GetxController {
  final _repo      = SurveyRepository();
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  // ── Survey list state ──────────────────────────────────────────────────────
  final surveys          = <Survey>[].obs;
  final isSurveysLoading = true.obs;
  final RxnString surveysError = RxnString();

  // ── Active survey / form state ─────────────────────────────────────────────
  final Rx<Survey?> activeSurvey   = Rx(null);
  final questions                  = <SurveyQuestion>[].obs;
  final isQuestionsLoading         = false.obs;
  final isSubmitting               = false.obs;

  /// Per-geocode-field loading state so the UI can show a spinner per field.
  final geocodeLoading = <String, bool>{}.obs;

  /// Master answers map — single source of truth for the entire form.
  ///
  /// Key   → question fieldName (String)
  /// Value →
  ///   text / number / geocode        : String
  ///   dropdown / radio               : String  (selected option value)
  ///   checkbox                       : List<String>  (selected option values)
  ///   matrix                         : Map<String, int>  (rowValue → column)
  ///   radio  "other" free-text       : stored as  "other_text_{fieldName}"
  ///   checkbox "other" free-text     : stored as  "{fieldName}_{optionValue}"
  ///   section / subsection           : never stored
  final answers = <String, dynamic>{}.obs;

  /// TextEditingControllers keyed by fieldName / ancillary key.
  final Map<String, TextEditingController> textControllers = {};

  /// Cached enumerator name (fetched once from Firestore on init).
  String? _cachedEnumeratorName;

  /// Optional callback invoked after a successful submission so the UI layer
  /// can react (e.g. scroll to top).
  VoidCallback? onSubmitSuccess;

  /// Token incremented whenever geocode fetches are reset, so stale
  /// async callbacks know to discard their results.
  int _geocodeRequestToken = 0;

  // ══════════════════════════════════════════════════════════════════════════
  // PAGINATION
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Large forms are split into pages using `section` questions as page
  // breaks.  Pages are built from ALL questions (regardless of visibility)
  // so the page structure stays stable while the user changes answers.
  // Visibility filtering happens in the UI layer (survey_form_page.dart)
  // and in the per-page validation helper below.

  final currentPageIndex = 0.obs;

  /// All questions split into pages (section = new page).
  List<List<SurveyQuestion>> get pages {
    if (questions.isEmpty) return [];
    final result  = <List<SurveyQuestion>>[];
    var   current = <SurveyQuestion>[];
    for (final q in questions) {
      if (q.type == 'section' && current.isNotEmpty) {
        result.add(current);
        current = [q];
      } else {
        current.add(q);
      }
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }

  int  get pageCount   => pages.length;
  bool get isFirstPage => currentPageIndex.value == 0;
  bool get isLastPage  => currentPageIndex.value >= pageCount - 1;

  List<SurveyQuestion> get currentPageQuestions {
    final p = pages;
    if (p.isEmpty) return [];
    return p[currentPageIndex.value.clamp(0, p.length - 1)];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VISIBILITY
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns true when [question] should be shown to the user.
  ///
  /// • Questions without [visibleIf] are always visible (backwards-compatible
  ///   with every survey that existed before this feature was added).
  /// • A conditional question is visible only when the current answer to the
  ///   dependency field exactly matches the expected value.
  /// • If the dependency is a checkbox (List), we check containment instead
  ///   of equality so e.g. visibleIf: { fieldName:"modes", value:"air" }
  ///   works even when multiple checkboxes are selected.
  bool isQuestionVisible(SurveyQuestion question) {
    final condition = question.visibleIf;
    if (condition == null) return true; // no condition → always visible

    final currentAnswer = answers[condition.fieldName];

    if (currentAnswer is List) {
      // Dependency is a multi-select checkbox → check containment.
      return currentAnswer
          .map((e) => e.toString())
          .contains(condition.value?.toString());
    }

    return currentAnswer?.toString() == condition.value?.toString();
  }

  /// All currently-visible questions (across every page).
  /// Used for final validation and for building the submitted response.
  List<SurveyQuestion> get visibleQuestions =>
      questions.where(isQuestionVisible).toList();

  /// Visible questions on the current page only.
  /// Used by [goToNextPage] so hidden required fields don't block navigation.
  List<SurveyQuestion> get visibleCurrentPageQuestions =>
      currentPageQuestions.where(isQuestionVisible).toList();

  // ══════════════════════════════════════════════════════════════════════════
  // ANSWER MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Central entry-point for every answer change that originates from the UI.
  ///
  /// 1. Stores the new value.
  /// 2. Removes stored answers for any questions that just became hidden as a
  ///    result of the change (so hidden data is never submitted).
  void onAnswerChanged(String fieldName, dynamic value) {
    answers[fieldName] = value;
    _removeHiddenAnswers();
  }

  /// Walks every question and clears the answer + associated text-controller
  /// content for anything that is currently not visible.
  ///
  /// This ensures that if a user selects "Air", fills in air_class, then
  /// switches to "Bus", the air_class answer is wiped before submission.
  void _removeHiddenAnswers() {
    for (final q in questions) {
      if (q.isDisplayOnly)       continue;
      if (isQuestionVisible(q))  continue; // still visible — leave it alone

      // Clear the primary answer.
      answers.remove(q.fieldName);
      textControllers[q.fieldName]?.clear();

      // Clear ancillary free-text keys for radio "Other".
      if (q.type == 'radio') {
        final key = 'other_text_${q.fieldName}';
        answers.remove(key);
        textControllers[key]?.clear();
      }

      // Clear ancillary free-text keys for checkbox "Other".
      if (q.type == 'checkbox') {
        for (final opt in q.options) {
          if (!opt.allowText) continue;
          final key = '${q.fieldName}_${opt.value}';
          answers.remove(key);
          textControllers[key]?.clear();
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGINATION NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Validates only the required, *visible* questions on the current page,
  /// then advances to the next page if they pass.
  void goToNextPage() {
    final error = _validateQuestions(visibleCurrentPageQuestions);
    if (error != null) {
      AppSnackbar.show('Incomplete', error);
      return;
    }
    if (!isLastPage) currentPageIndex.value++;
  }

  /// Going back never re-validates — the enumerator should always be able
  /// to revisit earlier answers.
  void goToPreviousPage() {
    if (!isFirstPage) currentPageIndex.value--;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
    _prefetchEnumeratorName();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SURVEY LIST
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadSurveys() async {
    isSurveysLoading.value = true;
    surveysError.value     = null;
    try {
      surveys.value = await _repo.getActiveSurveys();
    } catch (e) {
      surveysError.value = 'Failed to load surveys. Please try again.';
      AppSnackbar.show('Error', surveysError.value!);
    } finally {
      isSurveysLoading.value = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENUMERATOR NAME
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _prefetchEnumeratorName() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final doc = await _firestore.collection('users').doc(uid).get();
      _cachedEnumeratorName = doc.data()?['name'] as String?;
    } catch (_) {
      _cachedEnumeratorName = _auth.currentUser?.displayName;
    }
  }

  bool _isEnumeratorNameField(SurveyQuestion q) {
    if (q.type != 'text') return false;
    final fn  = q.fieldName.toLowerCase();
    final lbl = q.label.toLowerCase();
    return fn.contains('enumerator')   ||
        fn.contains('surveyor')     ||
        fn == 'name_of_enumerator'  ||
        fn == 'enumerator_name'     ||
        lbl.contains('enumerator')  ||
        lbl.contains('surveyor');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OPEN / CLOSE A SURVEY
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> openSurvey(Survey survey) async {
    activeSurvey.value     = survey;
    isQuestionsLoading.value = true;
    _clearForm();

    try {
      questions.value = await _repo.getQuestions(survey.id);
      _initControllers();

      if (_cachedEnumeratorName == null) {
        await _prefetchEnumeratorName();
      }
      _autoFillKnownFields();
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to load questions. Please try again.');
    } finally {
      isQuestionsLoading.value = false;
    }

    // Geocode runs in the background so the form opens immediately.
    _autoFetchGeocodeBackground();
  }

  /// Must be called only after the form page is fully unmounted (from
  /// dispose()) so TextEditingControllers are not disposed while still
  /// attached to TextField widgets.
  void closeSurvey() {
    _clearForm();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      questions.clear();
      activeSurvey.value = null;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORM HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _clearForm() {
    for (final c in textControllers.values) {
      c.dispose();
    }
    textControllers.clear();
    answers.clear();
    geocodeLoading.clear();
    _geocodeRequestToken++;
    currentPageIndex.value = 0;
  }

  void _initControllers() {
    for (final q in questions) {
      if (q.isDisplayOnly) continue;

      if (q.type == 'text' || q.type == 'number') {
        textControllers[q.fieldName] = TextEditingController();
      }

      // Radio "other" free-text field.
      if (q.type == 'radio') {
        for (final opt in q.options) {
          if (opt.allowText) {
            textControllers['other_text_${q.fieldName}'] =
                TextEditingController();
          }
        }
      }

      // Checkbox "other"-style free-text fields keyed as
      // "{fieldName}_{optionValue}".
      if (q.type == 'checkbox') {
        for (final opt in q.options) {
          if (opt.allowText) {
            textControllers['${q.fieldName}_${opt.value}'] =
                TextEditingController();
          }
        }
      }
    }
  }

  void _autoFillKnownFields() {
    for (final q in questions) {
      if (!_isEnumeratorNameField(q)) continue;
      final name = _cachedEnumeratorName ??
          _auth.currentUser?.displayName ??
          '';
      if (name.isNotEmpty) {
        answers[q.fieldName]              = name;
        textControllers[q.fieldName]?.text = name;
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESET FOR NEW ENTRY (after successful submit)
  // ══════════════════════════════════════════════════════════════════════════

  void resetFormForNewEntry() {
    answers.clear();
    geocodeLoading.clear();

    // Reset controllers without disposing — they are still in the tree.
    for (final c in textControllers.values) {
      c.text = '';
    }

    _autoFillKnownFields();
    _autoFetchGeocodeBackground();
    currentPageIndex.value = 0;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UNSAVED-ANSWERS CHECK
  // ══════════════════════════════════════════════════════════════════════════

  bool get hasUnsavedAnswers {
    _syncTextAnswers();

    for (final q in questions) {
      if (q.isDisplayOnly)      continue;
      if (!isQuestionVisible(q)) continue; // hidden questions don't count

      final value = answers[q.fieldName];
      if (q.type == 'geocode') continue; // auto-filled, not "user" input

      // Auto-filled enumerator name is not "unsaved" user input.
      if (_isEnumeratorNameField(q) &&
          value == textControllers[q.fieldName]?.text) {
        continue;
      }

      if (value is List   && value.isNotEmpty) return true;
      if (value is Map    && value.isNotEmpty) return true;
      if (value is String && value.trim().isNotEmpty) return true;
      if (value != null   &&
          value is! List  &&
          value is! Map   &&
          value is! String) return true;
    }

    // Check "other" free-text ancillary fields.
    for (final entry in answers.entries) {
      if (!entry.key.startsWith('other_text_')) continue;
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) return true;
    }

    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GEOCODE
  // ══════════════════════════════════════════════════════════════════════════

  void _autoFetchGeocodeBackground() {
    final geocodeQuestions =
    questions.where((q) => q.type == 'geocode').toList();
    if (geocodeQuestions.isEmpty) return;

    _geocodeRequestToken++;
    for (final q in geocodeQuestions) {
      fetchGeocodeFor(
        q.fieldName,
        silent: true,
        requestToken: _geocodeRequestToken,
      );
    }
  }

  Future<void> fetchGeocodeFor(
      String fieldName, {
        bool silent = false,
        int?  requestToken,
      }) async {
    requestToken ??= ++_geocodeRequestToken;
    geocodeLoading[fieldName] = true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent) {
          AppSnackbar.show('Location Disabled',
              'Please enable location services.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent) {
            AppSnackbar.show(
                'Permission Denied', 'Location permission is required.');
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (!silent) {
          AppSnackbar.show('Permission Denied',
              'Location permission is permanently denied. Enable it in settings.');
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
        const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (requestToken != _geocodeRequestToken) return;
      // Use onAnswerChanged so that if a geocode field somehow has a
      // visibleIf condition, the cleanup still runs.
      onAnswerChanged(
        fieldName,
        '${pos.latitude.toStringAsFixed(6)}, '
            '${pos.longitude.toStringAsFixed(6)}',
      );
    } catch (e) {
      if (!silent) {
        AppSnackbar.show('Location Error', 'Could not fetch location: $e');
      }
    } finally {
      if (requestToken == _geocodeRequestToken) {
        geocodeLoading[fieldName] = false;
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANSWER SETTERS  (all route through onAnswerChanged)
  // ══════════════════════════════════════════════════════════════════════════

  void setAnswer(String fieldName, dynamic value) {
    onAnswerChanged(fieldName, value);
  }

  void toggleCheckbox(String fieldName, String value, bool selected) {
    final current = List<String>.from(answers[fieldName] as List? ?? []);
    if (selected) {
      if (!current.contains(value)) current.add(value);
    } else {
      current.remove(value);
    }
    onAnswerChanged(fieldName, current);
  }

  bool isCheckboxSelected(String fieldName, String value) {
    final current = answers[fieldName] as List? ?? [];
    return current.contains(value);
  }

  Map<String, int> matrixAnswerFor(String fieldName) {
    final raw = answers[fieldName] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  void setMatrixAnswer(String fieldName, String rowValue, int column) {
    final current = matrixAnswerFor(fieldName);
    current[rowValue] = column;
    onAnswerChanged(fieldName, current);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VALIDATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Copies text-controller values back into [answers].
  /// Only syncs *visible* questions — hidden inputs are irrelevant.
  void _syncTextAnswers() {
    for (final q in questions) {
      if (q.isDisplayOnly)       continue;
      if (!isQuestionVisible(q)) continue; // ← skip hidden questions

      if (q.type == 'text' || q.type == 'number') {
        final text = textControllers[q.fieldName]?.text.trim() ?? '';
        answers[q.fieldName] = text;
      }

      if (q.type == 'radio') {
        for (final opt in q.options) {
          if (!opt.allowText) continue;
          final key  = 'other_text_${q.fieldName}';
          final text = textControllers[key]?.text.trim() ?? '';
          if (text.isNotEmpty) answers[key] = text;
        }
      }

      if (q.type == 'checkbox') {
        for (final opt in q.options) {
          if (!opt.allowText) continue;
          final key  = '${q.fieldName}_${opt.value}';
          final text = textControllers[key]?.text.trim() ?? '';
          if (text.isNotEmpty) {
            answers[key] = text;
          } else {
            answers.remove(key);
          }
        }
      }
    }
  }

  /// Validates [pageQuestions], skipping hidden and non-required questions.
  /// Returns the first error message, or null if everything is valid.
  String? _validateQuestions(List<SurveyQuestion> pageQuestions) {
    _syncTextAnswers();

    for (final q in pageQuestions) {
      if (q.isDisplayOnly)       continue;
      if (!q.required)           continue;
      if (!isQuestionVisible(q)) continue; // ← never validate hidden questions

      final val = answers[q.fieldName];

      if (q.type == 'checkbox') {
        final list = val as List? ?? [];
        if (list.isEmpty) return '"${q.label}" is required.';
      } else if (q.type == 'matrix') {
        final map = matrixAnswerFor(q.fieldName);
        for (final row in q.rows) {
          if (!map.containsKey(row.value)) {
            return '"${q.label}" — please rate "${row.label}".';
          }
        }
      } else if (q.type == 'geocode') {
        if (val == null || val.toString().isEmpty) {
          return '"${q.label}" — location not yet fetched. '
              'Tap the refresh icon next to the field.';
        }
      } else if (q.type == 'radio') {
        if (val == null || val.toString().trim().isEmpty) {
          return '"${q.label}" is required.';
        }
        // If an "Other" option is selected, the free-text must be filled.
        final selectedOpt = q.options
            .where((o) => o.value == val && o.allowText)
            .firstOrNull;
        if (selectedOpt != null) {
          final otherText =
              answers['other_text_${q.fieldName}']?.toString().trim() ?? '';
          if (otherText.isEmpty) {
            return '"${q.label}" — please specify the "Other" option.';
          }
        }
      } else {
        if (val == null || val.toString().trim().isEmpty) {
          return '"${q.label}" is required.';
        }
      }
    }
    return null; // all good
  }

  /// Final full-form validation (all pages, visible questions only).
  String? validate() => _validateQuestions(visibleQuestions);

  // ══════════════════════════════════════════════════════════════════════════
  // SUBMIT
  // ══════════════════════════════════════════════════════════════════════════

  /// Resolves the human-readable label for a dropdown / radio / checkbox
  /// option.  Falls back to the raw value if no match is found.
  String? _labelFor(SurveyQuestion q, String? value) {
    if (value == null || value.isEmpty) return value;
    final opt = q.options.where((o) => o.value == value).firstOrNull;
    return opt?.label ?? value;
  }

  Future<void> submitResponse() async {
    final error = validate();
    if (error != null) {
      AppSnackbar.show('Incomplete', error);
      return;
    }

    isSubmitting.value = true;
    try {
      _syncTextAnswers();

      // Build the final answers map.
      // Rules:
      //   • Skip display-only questions (section / subsection).
      //   • Skip currently-hidden questions (visibleIf not satisfied).
      //   • Skip questions with an empty fieldName (config error — log it).
      final finalAnswers = <String, dynamic>{};

      for (final q in questions) {
        if (q.isDisplayOnly)       continue;
        if (!isQuestionVisible(q)) continue; // ← only save visible answers

        if (q.fieldName.trim().isEmpty) {
          debugPrint(
            'Survey config warning: question "${q.label}" has an empty '
                'fieldName and was skipped from the saved response.',
          );
          continue;
        }

        final val = answers[q.fieldName];

        if (q.type == 'radio') {
          final selectedOpt = q.options
              .where((o) => o.value == val && o.allowText)
              .firstOrNull;
          if (selectedOpt != null) {
            final otherText =
                answers['other_text_${q.fieldName}']?.toString().trim() ?? '';
            finalAnswers[q.fieldName] = otherText.isNotEmpty
                ? 'Other: $otherText'
                : selectedOpt.label;
          } else {
            finalAnswers[q.fieldName] = _labelFor(q, val as String?);
          }
        } else if (q.type == 'dropdown') {
          finalAnswers[q.fieldName] = _labelFor(q, val as String?);
        } else if (q.type == 'checkbox') {
          final selectedValues = List<String>.from(val as List? ?? []);
          // Store human-readable labels so exports need no lookup table.
          finalAnswers[q.fieldName] =
              selectedValues.map((v) => _labelFor(q, v)).toList();
          // Also store each "other"-style free-text as its own field.
          for (final opt in q.options) {
            if (!opt.allowText) continue;
            final key = '${q.fieldName}_${opt.value}';
            if (selectedValues.contains(opt.value) &&
                answers.containsKey(key)) {
              finalAnswers[key] = answers[key];
            }
          }
        } else if (q.type == 'matrix') {
          final map = matrixAnswerFor(q.fieldName)
            ..removeWhere((k, _) => k.trim().isEmpty);
          finalAnswers[q.fieldName] = map;
        } else {
          finalAnswers[q.fieldName] = val;
        }
      }

      await _repo.submitResponse(
        surveyId: activeSurvey.value!.id,
        answers:  finalAnswers,
      );

      AppSnackbar.show('Submitted', 'Survey response saved successfully.');

      // Stay on the form for the next entry.
      resetFormForNewEntry();
      onSubmitSuccess?.call();
    } on FirebaseException catch (e) {
      AppSnackbar.show(
        'Submit Failed',
        '${e.message ?? 'Unknown error'} (${e.code})',
      );
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to submit. Please try again. ($e)');
    } finally {
      isSubmitting.value = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void onClose() {
    _clearForm();
    super.onClose();
  }
}