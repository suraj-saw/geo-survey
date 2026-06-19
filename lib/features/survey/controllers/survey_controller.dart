import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../models/survey_models.dart';
import '../repositories/survey_repository.dart';

class SurveyController extends GetxController {
  final _repo = SurveyRepository();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Survey list state ──────────────────────────────────────────────────────
  final surveys = <Survey>[].obs;
  final isSurveysLoading = true.obs;
  final RxnString surveysError = RxnString();

  // ── Active survey / form state ─────────────────────────────────────────────
  final Rx<Survey?> activeSurvey = Rx(null);
  final questions = <SurveyQuestion>[].obs;
  final isQuestionsLoading = false.obs;
  final isSubmitting = false.obs;

  /// Per-geocode-field loading state so the UI can show a spinner per field.
  final geocodeLoading = <String, bool>{}.obs;

  /// fieldName → current answer value
  /// text/number/geocode  → String
  /// dropdown/radio       → String (selected value)
  /// checkbox             → List<String> of selected values
  /// matrix               → Map<String, int> (row value → selected column)
  /// radio with allowText → also stores "other_text_{fieldName}" → String
  /// checkbox with allowText → also stores "{fieldName}_{optionValue}" → String
  /// section/subsection   → never present here
  final answers = <String, dynamic>{}.obs;

  /// TextEditingControllers keyed by fieldName (text, number, other-text inputs)
  final Map<String, TextEditingController> textControllers = {};

  /// Cached enumerator name so we don't hit Firestore on every form open.
  String? _cachedEnumeratorName;

  /// Optional callback invoked after a successful submission so the UI layer
  /// can react (e.g. scroll to top).  Set by the form page and cleared on close.
  VoidCallback? onSubmitSuccess;
  int _geocodeRequestToken = 0;

  // ── Pagination ───────────────────────────────────────────────────────────
  //
  // Large forms are split into pages using `section` questions as page
  // breaks — each `section` starts a new page, `subsection` stays as just
  // a header within the current page. Surveys with zero or one `section`
  // (e.g. existing single-page surveys) naturally collapse to one page,
  // so nothing changes for them.

  final currentPageIndex = 0.obs;

  List<List<SurveyQuestion>> get pages {
    if (questions.isEmpty) return [];
    final result = <List<SurveyQuestion>>[];
    var current = <SurveyQuestion>[];
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

  int get pageCount => pages.length;
  bool get isFirstPage => currentPageIndex.value == 0;
  bool get isLastPage => currentPageIndex.value >= pageCount - 1;

  List<SurveyQuestion> get currentPageQuestions {
    final p = pages;
    if (p.isEmpty) return [];
    final idx = currentPageIndex.value.clamp(0, p.length - 1);
    return p[idx];
  }

  /// Validates only the required questions on the current page, advances
  /// to the next page if they pass, and shows an error if they don't.
  void goToNextPage() {
    final error = _validateQuestions(currentPageQuestions);
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

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
    _prefetchEnumeratorName();
  }

  // ── Survey list ────────────────────────────────────────────────────────────

  Future<void> loadSurveys() async {
    isSurveysLoading.value = true;
    surveysError.value = null;
    try {
      surveys.value = await _repo.getActiveSurveys();
    } catch (e) {
      surveysError.value = 'Failed to load surveys. Please try again.';
      AppSnackbar.show('Error', surveysError.value!);
    } finally {
      isSurveysLoading.value = false;
    }
  }

  // ── Enumerator name ────────────────────────────────────────────────────────

  /// Fetches the signed-in user's name from Firestore and caches it.
  Future<void> _prefetchEnumeratorName() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final doc = await _firestore.collection('users').doc(uid).get();
      _cachedEnumeratorName = doc.data()?['name'] as String?;
    } catch (_) {
      // Best-effort; fall back to Firebase Auth display name if available.
      _cachedEnumeratorName = _auth.currentUser?.displayName;
    }
  }

  /// Returns true if a question should be auto-filled with the enumerator name.
  bool _isEnumeratorNameField(SurveyQuestion q) {
    if (q.type != 'text') return false;
    final fn = q.fieldName.toLowerCase();
    final lbl = q.label.toLowerCase();
    // Match common field names/labels used for enumerator identity.
    return fn.contains('enumerator') ||
        fn.contains('surveyor') ||
        fn == 'name_of_enumerator' ||
        fn == 'enumerator_name' ||
        lbl.contains('enumerator') ||
        lbl.contains('surveyor');
  }

  // ── Open a survey ──────────────────────────────────────────────────────────

  /// Opens a survey and navigates immediately. Location is fetched in the
  /// background so the form appears without any delay.
  Future<void> openSurvey(Survey survey) async {
    activeSurvey.value = survey;
    isQuestionsLoading.value = true;
    _clearForm();

    try {
      questions.value = await _repo.getQuestions(survey.id);
      _initControllers();

      // If the background prefetch (started in onInit) hasn't completed yet,
      // wait for it now so _autoFillKnownFields gets the real name — not null,
      // which would otherwise fall through to the email fallback.
      if (_cachedEnumeratorName == null) {
        await _prefetchEnumeratorName();
      }

      _autoFillKnownFields();
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to load questions. Please try again.');
    } finally {
      isQuestionsLoading.value = false;
    }

    // Kick off location fetching in the background — don't await, so the
    // form page is pushed immediately and the geocode fields update once
    // coordinates are available.
    _autoFetchGeocodeBackground();
  }

  /// Resets survey state safely.
  ///
  /// IMPORTANT: This method MUST only be called after the SurveyFormPage is
  /// fully unmounted (i.e. from the page's dispose()). Calling it while the
  /// form is still in the widget tree will dispose TextEditingControllers that
  /// are still attached to TextField widgets, causing a framework assertion.
  void closeSurvey() {
    _clearForm();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      questions.clear();
      activeSurvey.value = null;
    });
  }

  // ── Form helpers ───────────────────────────────────────────────────────────

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
      // For radio "other" text fields.
      if (q.type == 'radio') {
        for (final opt in q.options) {
          if (opt.allowText) {
            textControllers['other_text_${q.fieldName}'] =
                TextEditingController();
          }
        }
      }
      // For checkbox "other"-style text fields — one per allowText option,
      // keyed as "{fieldName}_{optionValue}" (e.g. "transport_mode_other").
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

  /// Auto-fills any fields whose names/labels indicate known values
  /// (currently: enumerator name).
  void _autoFillKnownFields() {
    for (final q in questions) {
      if (_isEnumeratorNameField(q)) {
        // Use the Firestore 'name' field first, then Firebase Auth display name.
        // Never fall back to email — that is the wrong value for this field.
        final name = _cachedEnumeratorName ??
            _auth.currentUser?.displayName ??
            '';
        if (name.isNotEmpty) {
          answers[q.fieldName] = name;
          // Also populate the TextEditingController so the UI reflects the value.
          textControllers[q.fieldName]?.text = name;
        }
      }
    }
  }

  // ── Reset form for a new entry (after successful submit) ───────────────────

  /// Resets the form to a clean state so the enumerator can fill another
  /// response for the same survey — without disposing controllers or closing
  /// the survey.
  void resetFormForNewEntry() {
    // Clear all answers.
    answers.clear();
    geocodeLoading.clear();

    // Reset all text controllers to empty (don't dispose — they're still
    // attached to mounted TextField widgets).
    for (final entry in textControllers.entries) {
      entry.value.text = '';
    }

    // Re-auto-fill known fields (e.g. enumerator name).
    _autoFillKnownFields();

    // Re-fetch geocode in the background for the new entry.
    _autoFetchGeocodeBackground();

    // Start the next entry from page 1.
    currentPageIndex.value = 0;
  }

  bool get hasUnsavedAnswers {
    _syncTextAnswers();

    for (final q in questions) {
      if (q.isDisplayOnly) continue;

      final value = answers[q.fieldName];
      if (q.type == 'geocode') continue;

      if (_isEnumeratorNameField(q) &&
          value == textControllers[q.fieldName]?.text) {
        continue;
      }

      if (value is List && value.isNotEmpty) return true;
      if (value is Map && value.isNotEmpty) return true;
      if (value is String && value.trim().isNotEmpty) return true;
      if (value != null &&
          value is! List &&
          value is! Map &&
          value is! String) {
        return true;
      }
    }

    for (final entry in answers.entries) {
      if (!entry.key.startsWith('other_text_')) continue;
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) return true;
    }

    return false;
  }

  // ── Geocode ────────────────────────────────────────────────────────────────

  /// Silently fetches geocode for all geocode questions in the background.
  void _autoFetchGeocodeBackground() {
    final geocodeQuestions = questions
        .where((q) => q.type == 'geocode')
        .toList();
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

  /// Fetches and stores the current GPS coordinates for [fieldName].
  Future<void> fetchGeocodeFor(
      String fieldName, {
        bool silent = false,
        int? requestToken,
      }) async {
    requestToken ??= ++_geocodeRequestToken;
    geocodeLoading[fieldName] = true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent) {
          AppSnackbar.show(
            'Location Disabled',
            'Please enable location services.',
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent) {
            AppSnackbar.show(
              'Permission Denied',
              'Location permission is required.',
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (!silent) {
          AppSnackbar.show(
            'Permission Denied',
            'Location permission is permanently denied. Enable it in settings.',
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (requestToken != _geocodeRequestToken) return;
      answers[fieldName] =
      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
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

  // ── Answer setters ─────────────────────────────────────────────────────────

  void setAnswer(String fieldName, dynamic value) {
    answers[fieldName] = value;
  }

  void toggleCheckbox(String fieldName, String value, bool selected) {
    final current = List<String>.from(answers[fieldName] as List? ?? []);
    if (selected) {
      if (!current.contains(value)) current.add(value);
    } else {
      current.remove(value);
    }
    answers[fieldName] = current;
  }

  bool isCheckboxSelected(String fieldName, String value) {
    final current = answers[fieldName] as List? ?? [];
    return current.contains(value);
  }

  /// Returns the current matrix selections for [fieldName] as
  /// Map<rowValue, selectedColumn>.
  Map<String, int> matrixAnswerFor(String fieldName) {
    final raw = answers[fieldName] as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  void setMatrixAnswer(String fieldName, String rowValue, int column) {
    final current = matrixAnswerFor(fieldName);
    current[rowValue] = column;
    answers[fieldName] = current;
  }

  // ── Validation & submit ────────────────────────────────────────────────────

  /// Syncs text controller values into [answers] before validating.
  void _syncTextAnswers() {
    for (final q in questions) {
      if (q.isDisplayOnly) continue;

      if (q.type == 'text' || q.type == 'number') {
        final text = textControllers[q.fieldName]?.text.trim() ?? '';
        answers[q.fieldName] = text;
      }
      if (q.type == 'radio') {
        for (final opt in q.options) {
          if (opt.allowText) {
            final key = 'other_text_${q.fieldName}';
            final text = textControllers[key]?.text.trim() ?? '';
            if (text.isNotEmpty) answers[key] = text;
          }
        }
      }
      if (q.type == 'checkbox') {
        for (final opt in q.options) {
          if (!opt.allowText) continue;
          final key = '${q.fieldName}_${opt.value}';
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

  /// Validates the required questions in [pageQuestions], returning the
  /// first error message found, or null if everything required is filled.
  String? _validateQuestions(List<SurveyQuestion> pageQuestions) {
    _syncTextAnswers();

    for (final q in pageQuestions) {
      if (q.isDisplayOnly) continue;
      if (!q.required) continue;

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
          return '"${q.label}" — location not yet fetched. Tap the refresh icon next to the field.';
        }
      } else if (q.type == 'radio') {
        if (val == null || val.toString().trim().isEmpty) {
          return '"${q.label}" is required.';
        }
        // If "Other" is selected and the field requires free text, validate it.
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
    return null; // no error
  }

  /// Validates every question across every page — used as the final
  /// safety check right before submitting.
  String? validate() => _validateQuestions(questions);

  /// Resolves the human-readable label for a dropdown/radio/checkbox
  /// option, given the internally-stored value. Falls back to the raw
  /// value itself if no matching option is found (e.g. nothing selected,
  /// or the survey's options changed after this response was answered).
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

      // Build final answers map. Section/subsection are display-only and
      // are never included in the stored response.
      final finalAnswers = <String, dynamic>{};
      for (final q in questions) {
        if (q.isDisplayOnly) continue;

        // Defensive guard: Firestore rejects empty-string field names
        // outright, which would fail the *entire* submission. A question
        // doc missing `fieldName` is a config error — skip just that one
        // field instead of crashing the whole response.
        if (q.fieldName.trim().isEmpty) {
          debugPrint(
            'Survey config warning: question "${q.label}" has an empty '
                'fieldName and was skipped from the saved response.',
          );
          continue;
        }

        final val = answers[q.fieldName];

        if (q.type == 'radio') {
          // For radio questions with an "other" option selected, merge the
          // free-text into the answer so the stored value clearly shows
          // what was entered (e.g. "Other: the user typed text").
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
          // Store the human-readable labels (e.g. "Rail", "Bus") instead of
          // the internal option values, so exported data doesn't need a
          // lookup table to clean up later.
          finalAnswers[q.fieldName] = selectedValues
              .map((v) => _labelFor(q, v))
              .toList();
          // Store each selected "other"-style option's free text as its own
          // field, e.g. transport_mode_other: "Metro".
          for (final opt in q.options) {
            if (!opt.allowText) continue;
            final key = '${q.fieldName}_${opt.value}';
            final selected = selectedValues.contains(opt.value);
            if (selected && answers.containsKey(key)) {
              finalAnswers[key] = answers[key];
            }
          }
        } else if (q.type == 'matrix') {
          // Strip any row that resolved to an empty key (shouldn't happen
          // now that SurveyOption falls back to a label slug, but this is
          // a last-resort safety net so a bad row can never fail the
          // entire submission again).
          final map = matrixAnswerFor(q.fieldName)
            ..removeWhere((k, _) => k.trim().isEmpty);
          finalAnswers[q.fieldName] = map;
        } else {
          finalAnswers[q.fieldName] = val;
        }
      }

      await _repo.submitResponse(
        surveyId: activeSurvey.value!.id,
        answers: finalAnswers,
      );

      AppSnackbar.show('Submitted', 'Survey response saved successfully.');

      // Reset the form for a new entry instead of closing the survey.
      // The enumerator stays on the same form to fill another response.
      resetFormForNewEntry();

      // Notify the UI (e.g. to scroll to top).
      onSubmitSuccess?.call();
    } on FirebaseException catch (e) {
      // Surface the real Firestore error (e.g. "permission-denied" usually
      // means the survey's `active` field isn't literally boolean true, or
      // the security rules rejected the write for another reason) instead
      // of a generic message that hides the cause.
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

  @override
  void onClose() {
    _clearForm();
    super.onClose();
  }
}