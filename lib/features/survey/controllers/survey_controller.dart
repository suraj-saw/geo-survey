import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../models/survey_models.dart';
import '../repositories/survey_repository.dart';

class SurveyController extends GetxController {
  final _repo = SurveyRepository();

  // ── Survey list state ──────────────────────────────────────────────────────
  final surveys = <Survey>[].obs;
  final isSurveysLoading = true.obs;

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
  /// checkbox             → List<String> (selected values)
  /// radio with allowText → also stores "other_text_{fieldName}" → String
  final answers = <String, dynamic>{}.obs;

  /// TextEditingControllers keyed by fieldName (text, number, other-text inputs)
  final Map<String, TextEditingController> textControllers = {};

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
  }

  // ── Survey list ────────────────────────────────────────────────────────────

  Future<void> loadSurveys() async {
    isSurveysLoading.value = true;
    try {
      surveys.value = await _repo.getActiveSurveys();
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to load surveys. Please try again.');
    } finally {
      isSurveysLoading.value = false;
    }
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

  /// Resets survey state safely without flickering the survey list.
  /// We defer clearing [activeSurvey] to the next frame so that any
  /// Obx widgets watching it don't see a null/empty value mid-navigation.
  void closeSurvey() {
    // Clear the heavy data straight away.
    _clearForm();
    questions.clear();

    // Defer the activeSurvey reset so the list page has already been
    // re-inserted into the widget tree before its Obx re-evaluates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  // ── Geocode ────────────────────────────────────────────────────────────────

  /// Silently fetches geocode for all geocode questions in the background.
  /// Errors are swallowed; users can tap the refresh button to retry.
  void _autoFetchGeocodeBackground() {
    final geocodeQuestions =
    questions.where((q) => q.type == 'geocode').toList();
    if (geocodeQuestions.isEmpty) return;

    for (final q in geocodeQuestions) {
      // Fire-and-forget; individual fields show their own loading state.
      fetchGeocodeFor(q.fieldName, silent: true);
    }
  }

  /// Fetches and stores the current GPS coordinates for [fieldName].
  ///
  /// [silent] — when true, permission/service errors are not shown as
  /// snackbars (used during automatic background fetch). The user can
  /// always tap the refresh icon to retry with feedback.
  Future<void> fetchGeocodeFor(String fieldName, {bool silent = false}) async {
    geocodeLoading[fieldName] = true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent) {
          AppSnackbar.show(
              'Location Disabled', 'Please enable location services.');
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
        desiredAccuracy: LocationAccuracy.high,
      );

      answers[fieldName] =
      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    } catch (e) {
      if (!silent) {
        AppSnackbar.show('Location Error', 'Could not fetch location: $e');
      }
    } finally {
      geocodeLoading[fieldName] = false;
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

      // Build final answers map with only fieldName keys (drop internal keys)
      final finalAnswers = <String, dynamic>{};
      for (final q in questions) {
        finalAnswers[q.fieldName] = answers[q.fieldName];
      }

      await _repo.submitResponse(
        surveyId: activeSurvey.value!.id,
        answers: finalAnswers,
      );

      AppSnackbar.show('Submitted', 'Survey response saved successfully.');
      closeSurvey();
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