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
  /// checkbox             → list of selected values
  /// radio with allowText → also stores "other_text_{fieldName}" → String
  final answers = <String, dynamic>{}.obs;

  /// TextEditingControllers keyed by fieldName (text, number, other-text inputs)
  final Map<String, TextEditingController> textControllers = {};

  /// Cached enumerator name so we don't hit Firestore on every form open.
  String? _cachedEnumeratorName;

  /// Optional callback invoked after a successful submission so the UI layer
  /// can react (e.g. scroll to top).  Set by the form page and cleared on close.
  VoidCallback? onSubmitSuccess;
  int _geocodeRequestToken = 0;

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
      // Best-effort; fall back to email display name if available.
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
  }

  void _initControllers() {
    for (final q in questions) {
      if (q.type == 'text' || q.type == 'number') {
        textControllers[q.fieldName] = TextEditingController();
      }
      // For radio "other" text fields
      if (q.type == 'radio') {
        for (final opt in q.options) {
          if (opt.allowText) {
            textControllers['other_text_${q.fieldName}'] =
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
        final name =
            _cachedEnumeratorName ??
            _auth.currentUser?.displayName ??
            _auth.currentUser?.email ??
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
  }

  bool get hasUnsavedAnswers {
    _syncTextAnswers();

    for (final q in questions) {
      final value = answers[q.fieldName];
      if (q.type == 'geocode') continue;

      if (_isEnumeratorNameField(q) &&
          value == textControllers[q.fieldName]?.text) {
        continue;
      }

      if (value is List && value.isNotEmpty) return true;
      if (value is String && value.trim().isNotEmpty) return true;
      if (value != null && value is! List && value is! String) return true;
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

  // ── Validation & submit ────────────────────────────────────────────────────

  /// Syncs text controller values into [answers] before validating.
  void _syncTextAnswers() {
    for (final q in questions) {
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
    }
  }

  String? validate() {
    _syncTextAnswers();

    for (final q in questions) {
      if (!q.required) continue;

      final val = answers[q.fieldName];

      if (q.type == 'checkbox') {
        final list = val as List? ?? [];
        if (list.isEmpty) return '"${q.label}" is required.';
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

  Future<void> submitResponse() async {
    final error = validate();
    if (error != null) {
      AppSnackbar.show('Incomplete', error);
      return;
    }

    isSubmitting.value = true;
    try {
      _syncTextAnswers();

      // Build final answers map.  For radio questions with an "other" option
      // selected, we merge the free-text into the answer so the stored value
      // clearly shows what was entered (e.g. "Other: the user typed text").
      final finalAnswers = <String, dynamic>{};
      for (final q in questions) {
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
                : val;
          } else {
            finalAnswers[q.fieldName] = val;
          }
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
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to submit. Please try again.');
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
