import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/survey_controller.dart';
import '../models/survey_models.dart';
import '../widgets/question_widgets.dart';

class SurveyFormPage extends StatefulWidget {
  final SurveyController ctrl;

  const SurveyFormPage({super.key, required this.ctrl});

  @override
  State<SurveyFormPage> createState() => _SurveyFormPageState();
}

class _SurveyFormPageState extends State<SurveyFormPage> {
  /// Snapshot of the questions, already split into pages, taken when the
  /// page first builds.
  ///
  /// WHY: closeSurvey() defers questions.clear() to the next frame, but
  /// because GetX Obx rebuilds synchronously on observable changes, there
  /// is still a brief window where the list widget could see an empty
  /// questions list and show "No questions found" before the pop animation
  /// completes.  Using a local snapshot means the page always renders the
  /// same questions it was opened with, regardless of what the controller
  /// does during navigation.
  late final List<List<SurveyQuestion>> _pageSnapshot;

  /// Controls the scroll position of the questions list so we can
  /// programmatically scroll back to the top after a successful submission
  /// or whenever the visible page changes.
  final ScrollController _scrollController = ScrollController();

  Worker? _pageWorker;

  @override
  void initState() {
    super.initState();
    // Take the snapshot once; it never changes for the lifetime of this page.
    _pageSnapshot = widget.ctrl.pages
        .map((p) => List<SurveyQuestion>.unmodifiable(p))
        .toList();

    // Register a callback so the controller can notify us after a successful
    // submission (to scroll to top).
    widget.ctrl.onSubmitSuccess = _onSubmitSuccess;

    // Jump back to the top of the list whenever the page changes (Next/Back).
    _pageWorker = ever<int>(widget.ctrl.currentPageIndex, (_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    // Clean up the callback so the controller doesn't hold a stale reference.
    widget.ctrl.onSubmitSuccess = null;
    _pageWorker?.dispose();
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

  Future<void> _handleBack(BuildContext context) async {
    // On a multi-page form, "back" steps to the previous page first —
    // it only offers to discard once the enumerator is on page 1.
    if (!ctrl.isFirstPage) {
      ctrl.goToPreviousPage();
      return;
    }

    if (ctrl.hasUnsavedAnswers) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard response?'),
          content: const Text(
            'Your current answers have not been submitted and will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (shouldDiscard != true) return;
    }

    if (!context.mounted) return;
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
    final totalPages = _pageSnapshot.length;

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
        body: _pageSnapshot.isEmpty
            ? const Center(child: Text('No questions found for this survey.'))
            : Column(
          children: [
            if (totalPages > 1) _PageProgress(ctrl: ctrl, totalPages: totalPages),
            Expanded(
              child: Obx(() {
                final idx = ctrl.currentPageIndex.value.clamp(
                  0,
                  totalPages - 1,
                );
                final pageQuestions = _pageSnapshot[idx];

                return ListView.separated(
                  key: ValueKey(idx),
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  itemCount: pageQuestions.length,
                  separatorBuilder: (context, index) =>
                  const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final q = pageQuestions[index];
                    return QuestionWidget(question: q, ctrl: ctrl);
                  },
                );
              }),
            ),
            _NavigationBar(ctrl: ctrl, totalPages: totalPages),
          ],
        ),
      ),
    );
  }
}

// ── Page progress indicator ───────────────────────────────────────────────────

class _PageProgress extends StatelessWidget {
  final SurveyController ctrl;
  final int totalPages;
  const _PageProgress({required this.ctrl, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final idx = ctrl.currentPageIndex.value;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Part ${idx + 1} of $totalPages',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (idx + 1) / totalPages,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    });
  }
}

// ── Bottom navigation (Back / Next / Submit) ──────────────────────────────────

class _NavigationBar extends StatelessWidget {
  final SurveyController ctrl;
  final int totalPages;
  const _NavigationBar({required this.ctrl, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Obx(() {
        final showBack = totalPages > 1 && !ctrl.isFirstPage;
        final isLast = ctrl.isLastPage;
        final isSubmitting = ctrl.isSubmitting.value;

        return Row(
          children: [
            if (showBack) ...[
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: isSubmitting ? null : ctrl.goToPreviousPage,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: isLast
                    ? ElevatedButton.icon(
                  onPressed: isSubmitting ? null : ctrl.submitResponse,
                  icon: isSubmitting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    isSubmitting ? 'Submitting...' : 'Submit Response',
                    style: const TextStyle(fontSize: 16),
                  ),
                )
                    : ElevatedButton.icon(
                  onPressed: ctrl.goToNextPage,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text(
                    'Next',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}