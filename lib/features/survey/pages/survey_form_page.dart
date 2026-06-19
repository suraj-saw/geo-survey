// lib/features/survey/pages/survey_form_page.dart

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
  /// Snapshot of ALL questions split into pages, captured once at init.
  ///
  /// WHY ALL (not pre-filtered):
  /// The page structure (how many pages exist, which questions live on which
  /// page) must stay fixed for the lifetime of this screen.  If we filtered
  /// by visibility here, sections that became hidden would collapse pages and
  /// confuse the pagination indicator.  Instead the ListView builder inside
  /// [build] applies [SurveyController.isQuestionVisible] at render time —
  /// Obx ensures it re-runs on every answer change, so conditional questions
  /// appear and disappear instantly without restructuring the pages.
  ///
  /// WHY SNAPSHOT (not live observable):
  /// closeSurvey() defers questions.clear() to the next frame.  Without a
  /// snapshot the list widget could briefly see an empty list and flash
  /// "No questions found" during the pop animation.
  late final List<List<SurveyQuestion>> _pageSnapshot;

  final ScrollController _scrollController = ScrollController();
  Worker? _pageWorker;

  @override
  void initState() {
    super.initState();
    _pageSnapshot = widget.ctrl.pages
        .map((p) => List<SurveyQuestion>.unmodifiable(p))
        .toList();

    widget.ctrl.onSubmitSuccess = _onSubmitSuccess;

    // Scroll to top whenever the user navigates to a new page.
    _pageWorker = ever<int>(widget.ctrl.currentPageIndex, (_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    widget.ctrl.onSubmitSuccess = null;
    _pageWorker?.dispose();
    _scrollController.dispose();

    // closeSurvey() disposes TextEditingControllers.  Calling it here
    // (in dispose) ensures the widgets are already deactivated and will
    // never touch the controllers again — avoiding the framework assertion
    // "TextEditingController used after being disposed".
    widget.ctrl.closeSurvey();

    super.dispose();
  }

  SurveyController get ctrl => widget.ctrl;

  Future<void> _handleBack(BuildContext context) async {
    // On a multi-page form, "back" steps to the previous page first.
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
    Navigator.of(context).pop();
  }

  /// Called by the controller after a successful submission — scroll to top
  /// so the enumerator starts the next entry from the beginning.
  void _onSubmitSuccess() {
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
            if (totalPages > 1)
              _PageProgress(ctrl: ctrl, totalPages: totalPages),
            Expanded(
              child: Obx(() {
                // Obx re-runs this block whenever answers change, which
                // means isQuestionVisible() is re-evaluated for every
                // question on every answer update — giving instant
                // show/hide behaviour for conditional questions.
                final idx = ctrl.currentPageIndex.value
                    .clamp(0, totalPages - 1);
                final pageQuestions = _pageSnapshot[idx];

                // ── Visibility filter ───────────────────────────────
                // Filter to only the questions that should be visible
                // given the current answers state.  This is the sole
                // place where conditional questions are hidden/shown.
                final visibleQuestions = pageQuestions
                    .where(ctrl.isQuestionVisible)
                    .toList();
                // ────────────────────────────────────────────────────

                if (visibleQuestions.isEmpty) {
                  return const SizedBox.shrink();
                }

                return ListView.separated(
                  key: ValueKey(idx),
                  controller: _scrollController,
                  padding:
                  const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  itemCount: visibleQuestions.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final q = visibleQuestions[index];
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

// ── Bottom navigation bar (Back / Next / Submit) ──────────────────────────────

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
        final showBack    = totalPages > 1 && !ctrl.isFirstPage;
        final isLast      = ctrl.isLastPage;
        final isSubmitting = ctrl.isSubmitting.value;

        return Row(
          children: [
            if (showBack) ...[
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed:
                    isSubmitting ? null : ctrl.goToPreviousPage,
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
                  onPressed:
                  isSubmitting ? null : ctrl.submitResponse,
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
                    isSubmitting
                        ? 'Submitting...'
                        : 'Submit Response',
                    style: const TextStyle(fontSize: 16),
                  ),
                )
                    : ElevatedButton.icon(
                  onPressed: ctrl.goToNextPage,
                  icon:
                  const Icon(Icons.arrow_forward_rounded),
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