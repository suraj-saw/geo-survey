import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/survey_controller.dart';
import '../widgets/question_widgets.dart';

class SurveyFormPage extends StatelessWidget {
  final SurveyController ctrl;

  const SurveyFormPage({super.key, required this.ctrl});

  void _handleBack(BuildContext context) {
    ctrl.closeSurvey();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Allow the pop but call closeSurvey first.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(ctrl.activeSurvey.value?.title ?? 'Survey')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(context),
          ),
        ),
        body: Obx(() {
          if (ctrl.isQuestionsLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          if (ctrl.questions.isEmpty) {
            return const Center(
                child: Text('No questions found for this survey.'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  itemCount: ctrl.questions.length,
                  separatorBuilder: (_, __) => const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final q = ctrl.questions[index];
                    return QuestionWidget(question: q, ctrl: ctrl);
                  },
                ),
              ),
              _SubmitBar(ctrl: ctrl),
            ],
          );
        }),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  final SurveyController ctrl;
  const _SubmitBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Obx(() => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed:
          ctrl.isSubmitting.value ? null : ctrl.submitResponse,
          icon: ctrl.isSubmitting.value
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Colors.white),
          )
              : const Icon(Icons.check_circle_outline),
          label: Text(
            ctrl.isSubmitting.value
                ? 'Submitting...'
                : 'Submit Response',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      )),
    );
  }
}