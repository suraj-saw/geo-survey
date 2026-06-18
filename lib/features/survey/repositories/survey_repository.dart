import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/survey_models.dart';

class SurveyRepository {
  final _db = FirebaseFirestore.instance;

  /// Returns all active surveys.
  Future<List<Survey>> getActiveSurveys() async {
    final snap = await _db
        .collection('surveys')
        .where('active', isEqualTo: true)
        .get();

    return snap.docs
        .map((d) => Survey.fromMap(d.id, d.data()))
        .toList();
  }

  /// Returns all questions for a survey, sorted by [order].
  Future<List<SurveyQuestion>> getQuestions(String surveyId) async {
    final snap = await _db
        .collection('surveys')
        .doc(surveyId)
        .collection('questions')
        .orderBy('order')
        .get();

    return snap.docs
        .map((d) => SurveyQuestion.fromMap(d.id, d.data()))
        .toList();
  }

  /// Saves a completed survey response under:
  /// surveys/{surveyId}/responses/{autoId}
  ///
  /// [answers] is a map of fieldName → dynamic value.
  Future<void> submitResponse({
    required String surveyId,
    required Map<String, dynamic> answers,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    await _db
        .collection('surveys')
        .doc(surveyId)
        .collection('responses')
        .add({
      'answers': answers,
      'submittedBy': uid,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }
}