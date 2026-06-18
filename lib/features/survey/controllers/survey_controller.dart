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

  Future<void> openSurvey(Survey survey) async {
    activeSurvey.value = survey;
    isQuestionsLoading.value = true;
    _clearForm();

    try {
      questions.value = await _repo.getQuestions(survey.id);
      _initControllers();
      await _autoFetchGeocode();
    } catch (e) {
      AppSnackbar.show('Error', 'Failed to load questions. Please try again.');
    } finally {
      isQuestionsLoading.value = false;
    }
  }

  void closeSurvey() {
    activeSurvey.value = null;
    questions.clear();
    _clearForm();
  }

  // ── Form helpers ───────────────────────────────────────────────────────────

  void _clearForm() {
    for (final c in textControllers.values) {
      c.dispose();
    }
    textControllers.clear();
    answers.clear();
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

  Future<void> _autoFetchGeocode() async {
    final geocodeQuestions =
    questions.where((q) => q.type == 'geocode').toList();
    if (geocodeQuestions.isEmpty) return;

    for (final q in geocodeQuestions) {
      await fetchGeocodeFor(q.fieldName);
    }
  }

  Future<void> fetchGeocodeFor(String fieldName) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppSnackbar.show(
            'Location Disabled', 'Please enable location services.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          AppSnackbar.show(
              'Permission Denied', 'Location permission is required.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        AppSnackbar.show('Permission Denied',
            'Location permission is permanently denied. Enable it in settings.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      answers[fieldName] =
      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    } catch (e) {
      AppSnackbar.show('Location Error', 'Could not fetch location: $e');
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
          return '"${q.label}" — location not yet fetched. Tap refresh.';
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