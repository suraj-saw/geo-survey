import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/survey_controller.dart';
import '../models/survey_models.dart';

/// Renders the correct input widget based on [question.type].
class QuestionWidget extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;

  const QuestionWidget({
    super.key,
    required this.question,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuestionLabel(question: question),
        const SizedBox(height: 8),
        _buildInput(context),
      ],
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (question.type) {
      case 'text':
        return _TextInput(question: question, ctrl: ctrl);
      case 'number':
        return _NumberInput(question: question, ctrl: ctrl);
      case 'geocode':
        return _GeocodeInput(question: question, ctrl: ctrl);
      case 'dropdown':
        return _DropdownInput(question: question, ctrl: ctrl);
      case 'radio':
        return _RadioInput(question: question, ctrl: ctrl);
      case 'checkbox':
        return _CheckboxInput(question: question, ctrl: ctrl);
      default:
        return _TextInput(question: question, ctrl: ctrl);
    }
  }
}

// ── Label ─────────────────────────────────────────────────────────────────────

class _QuestionLabel extends StatelessWidget {
  final SurveyQuestion question;
  const _QuestionLabel({required this.question});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: question.label),
          if (question.required)
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Text ──────────────────────────────────────────────────────────────────────

class _TextInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _TextInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl.textControllers[question.fieldName],
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Enter ${question.label.toLowerCase()}',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ── Number ────────────────────────────────────────────────────────────────────

class _NumberInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _NumberInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl.textControllers[question.fieldName],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: const InputDecoration(
        hintText: 'Enter number',
        border: OutlineInputBorder(),
      ),
    );
  }
}

// ── Geocode ───────────────────────────────────────────────────────────────────

class _GeocodeInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _GeocodeInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final value = ctrl.answers[question.fieldName]?.toString() ?? '';
      final hasValue = value.isNotEmpty;
      final isLoading = ctrl.geocodeLoading[question.fieldName] == true;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasValue ? cs.primary : cs.outline,
          ),
          borderRadius: BorderRadius.circular(4),
          color: hasValue ? cs.primaryContainer.withOpacity(0.2) : null,
        ),
        child: Row(
          children: [
            isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: cs.primary,
              ),
            )
                : Icon(
              hasValue ? Icons.location_on : Icons.location_searching,
              color: hasValue ? cs.primary : cs.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isLoading
                    ? 'Fetching location…'
                    : hasValue
                    ? value
                    : 'Location not yet available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: (isLoading || hasValue) ? cs.onSurface : cs.outline,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh location',
              onPressed: isLoading
                  ? null
                  : () => ctrl.fetchGeocodeFor(question.fieldName),
            ),
          ],
        ),
      );
    });
  }
}

// ── Dropdown ──────────────────────────────────────────────────────────────────

class _DropdownInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _DropdownInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = ctrl.answers[question.fieldName] as String?;

      return DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        hint: const Text('Select an option'),
        items: question.options
            .map(
              (opt) => DropdownMenuItem(
            value: opt.value,
            child: Text(opt.label),
          ),
        )
            .toList(),
        onChanged: (val) {
          if (val != null) ctrl.setAnswer(question.fieldName, val);
        },
      );
    });
  }
}

// ── Radio ─────────────────────────────────────────────────────────────────────

class _RadioInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _RadioInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final selected = ctrl.answers[question.fieldName] as String?;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: question.options.map((opt) {
          final isSelected = selected == opt.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<String>(
                value: opt.value,
                groupValue: selected,
                title: Text(opt.label),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onChanged: (val) {
                  if (val != null) ctrl.setAnswer(question.fieldName, val);
                },
              ),
              // Show the "Other" free-text area when:
              //  • this option has allowText == true  AND
              //  • this option is currently selected
              if (opt.allowText && isSelected)
                Padding(
                  padding:
                  const EdgeInsets.only(left: 16, right: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Please specify:',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: ctrl.textControllers[
                        'other_text_${question.fieldName}'],
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Enter details here…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor:
                          cs.surfaceContainerHighest.withOpacity(0.5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }).toList(),
      );
    });
  }
}

// ── Checkbox ──────────────────────────────────────────────────────────────────

class _CheckboxInput extends StatelessWidget {
  final SurveyQuestion question;
  final SurveyController ctrl;
  const _CheckboxInput({required this.question, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        children: question.options.map((opt) {
          final isChecked =
          ctrl.isCheckboxSelected(question.fieldName, opt.value);
          return CheckboxListTile(
            value: isChecked,
            title: Text(opt.label),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              ctrl.toggleCheckbox(
                  question.fieldName, opt.value, val ?? false);
            },
          );
        }).toList(),
      );
    });
  }
}