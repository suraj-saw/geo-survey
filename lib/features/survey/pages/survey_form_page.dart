import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/survey_controller.dart';
import '../widgets/question_widgets.dart';

class SurveyFormPage extends StatefulWidget {
  final SurveyController ctrl;

  const SurveyFormPage({super.key, required this.ctrl});

  @override
  State<SurveyFormPage> createState() => _SurveyFormPageState();
}

class _SurveyFormPageState extends State<SurveyFormPage> {
  /// Snapshot of the questions taken when the page first builds.
  ///
  /// WHY: closeSurvey() defers questions.clear() to the next frame, but
  /// because GetX Obx rebuilds synchronously on observable changes, there
  /// is still a brief window where the list widget could see an empty
  /// questions list and show "No questions found" before the pop animation
  /// completes.  Using a local snapshot means the page always renders the
  /// same questions it was opened with, regardless of what the controller
  /// does during navigation.
  late final List _questionSnapshot;

  /// Controls the scroll position of the questions list so we can
  /// programmatically scroll back to the top after a successful submission.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Take the snapshot once; it never changes for the lifetime of this page.
    _questionSnapshot = List.unmodifiable(widget.ctrl.questions);

    // Register a callback so the controller can notify us after a successful
    // submission (to scroll to top).
    widget.ctrl.onSubmitSuccess = _onSubmitSuccess;
  }

  @override
  void dispose() {
    // Clean up the callback so the controller doesn't hold a stale reference.
    widget.ctrl.onSubmitSuccess = null;
    _scrollController.dispose();

    // Clean up the survey state AFTER the page is fully unmounted.
    // This is critical: disposing TextEditingControllers while the page's
    // widgets are still in the tree (e.g. during the pop animation) causes
    // a "TextEditingController was used after being disposed" assertion.
    // By calling closeSurvey() here in dispose(), the widgets are already
    // deactivated and will never try to access the controllers again.
    widget.ctrl.closeSurvey();

    super.dispose();
  }

  SurveyController get ctrl => widget.ctrl;

  void _handleBack(BuildContext context) {
    // Only pop — closeSurvey() is called in dispose() after the page is
    // fully unmounted, ensuring controllers are not disposed while widgets
    // still reference them during the pop animation.
    Navigator.of(context).pop();
  }

  /// Called by the controller after a successful form submission.
  void _onSubmitSuccess() {
    // Scroll to the top of the form with a smooth animation.
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
        body: _questionSnapshot.isEmpty
            ? const Center(child: Text('No questions found for this survey.'))
            : Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                itemCount: _questionSnapshot.length,
                separatorBuilder: (_, __) => const Divider(height: 32),
                itemBuilder: (context, index) {
                  final q = _questionSnapshot[index];
                  return QuestionWidget(question: q, ctrl: ctrl);
                },
              ),
            ),
            _SubmitBar(ctrl: ctrl),
          ],
        ),
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