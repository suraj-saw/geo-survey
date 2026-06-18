import 'package:cloud_firestore/cloud_firestore.dart';

import '../../survey/models/survey_models.dart';

/// Data class holding a single response document.
class SurveyResponse {
  final String id;
  final Map<String, dynamic> answers;
  final String? submittedBy;
  final DateTime? submittedAt;

  const SurveyResponse({
    required this.id,
    required this.answers,
    this.submittedBy,
    this.submittedAt,
  });

  factory SurveyResponse.fromMap(String id, Map<String, dynamic> map) {
    final ts = map['submittedAt'] as Timestamp?;
    return SurveyResponse(
      id: id,
      answers: Map<String, dynamic>.from(map['answers'] as Map? ?? {}),
      submittedBy: map['submittedBy'] as String?,
      submittedAt: ts?.toDate(),
    );
  }
}

/// Aggregate stats for one survey, fetched by the admin dashboard.
class SurveyStats {
  final Survey survey;
  final int questionCount;
  final int responseCount;

  const SurveyStats({
    required this.survey,
    required this.questionCount,
    required this.responseCount,
  });
}

/// Repository that provides admin-only Firestore queries.
class AdminRepository {
  final _db = FirebaseFirestore.instance;

  /// Returns ALL surveys (both active and inactive).
  Future<List<Survey>> getAllSurveys() async {
    final snap = await _db.collection('surveys').get();
    return snap.docs.map((d) => Survey.fromMap(d.id, d.data())).toList();
  }

  /// Returns the number of questions for a given survey.
  Future<int> getQuestionCount(String surveyId) async {
    final snap = await _db
        .collection('surveys')
        .doc(surveyId)
        .collection('questions')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Returns the number of responses for a given survey.
  Future<int> getResponseCount(String surveyId) async {
    final snap = await _db
        .collection('surveys')
        .doc(surveyId)
        .collection('responses')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Returns lightweight stats (question + response counts) for every survey.
  Future<List<SurveyStats>> getAllSurveyStats() async {
    final surveys = await getAllSurveys();
    final statsFutures = surveys.map((s) async {
      final qCount = await getQuestionCount(s.id);
      final rCount = await getResponseCount(s.id);
      return SurveyStats(
        survey: s,
        questionCount: qCount,
        responseCount: rCount,
      );
    });
    return Future.wait(statsFutures);
  }

  /// Returns all questions for a survey, sorted by order.
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

  /// Returns all responses for a survey, ordered by submission time (newest first).
  Future<List<SurveyResponse>> getResponses(String surveyId) async {
    final snap = await _db
        .collection('surveys')
        .doc(surveyId)
        .collection('responses')
        .orderBy('submittedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => SurveyResponse.fromMap(d.id, d.data()))
        .toList();
  }

  /// Fetches the name of a user by UID.  Returns null if not found.
  Future<String?> getUserName(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['name'] as String?;
    } catch (_) {
      return null;
    }
  }
}