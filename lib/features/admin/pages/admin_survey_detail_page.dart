import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_controller.dart';

class AdminSurveyDetailPage extends StatelessWidget {
  const AdminSurveyDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminController>();

    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(ctrl.activeSurvey.value?.title ?? 'Survey Details'),
        ),
      ),
      body: Obx(() {
        if (ctrl.isDetailLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return _DetailBody(ctrl: ctrl);
      }),
    );
  }
}

// ── Detail Body ──────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final AdminController ctrl;
  const _DetailBody({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Stats Grid ────────────────────────────────────────────────────
        _StatsGrid(ctrl: ctrl),
        const SizedBox(height: 24),

        // ── Export Button ─────────────────────────────────────────────────
        _ExportSection(ctrl: ctrl),
        const SizedBox(height: 24),

        // ── Questions List ────────────────────────────────────────────────
        _SectionHeader(title: 'Questions', icon: Icons.help_outline_rounded),
        const SizedBox(height: 8),
        _QuestionsList(ctrl: ctrl),
        const SizedBox(height: 24),

        // ── Responses Table ───────────────────────────────────────────────
        _SectionHeader(
          title: 'Responses (${ctrl.responses.length})',
          icon: Icons.table_chart_outlined,
        ),
        const SizedBox(height: 8),
        ctrl.responses.isEmpty
            ? _EmptyState(
                icon: Icons.inbox_outlined,
                message: 'No responses yet',
              )
            : _ResponsesTable(ctrl: ctrl),
      ],
    );
  }
}

// ── Stats Grid ───────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final AdminController ctrl;
  const _StatsGrid({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final latestTime = ctrl.latestResponseTime;
    final latestLabel = latestTime != null ? _formatDateTime(latestTime) : '—';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _StatCard(
          icon: Icons.description_outlined,
          label: 'Responses',
          value: '${ctrl.responses.length}',
          gradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
        ),
        _StatCard(
          icon: Icons.help_outline_rounded,
          label: 'Questions',
          value: '${ctrl.questions.length}',
          gradient: const [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
        ),
        _StatCard(
          icon: Icons.people_outline_rounded,
          label: 'Enumerators',
          value: '${ctrl.uniqueEnumeratorCount}',
          gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
        ),
        _StatCard(
          icon: Icons.access_time_rounded,
          label: 'Latest Response',
          value: latestLabel,
          valueFontSize: latestTime != null ? 13 : null,
          gradient: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthName(local.month);
    final year = local.year;
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year\n$hour:$minute $amPm';
  }

  String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[m];
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final double? valueFontSize;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    this.valueFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: valueFontSize ?? 28,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Export Section ────────────────────────────────────────────────────────────

class _ExportSection extends StatelessWidget {
  final AdminController ctrl;
  const _ExportSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(
      () => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          onPressed: ctrl.isExporting.value || ctrl.responses.isEmpty
              ? null
              : ctrl.exportCsv,
          icon: ctrl.isExporting.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
          label: Text(
            ctrl.isExporting.value
                ? 'Exporting...'
                : 'Download Responses as CSV',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Questions List ───────────────────────────────────────────────────────────

class _QuestionsList extends StatelessWidget {
  final AdminController ctrl;
  const _QuestionsList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.questions.isEmpty) {
      return _EmptyState(
        icon: Icons.help_outline,
        message: 'No questions found',
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: ctrl.questions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final q = ctrl.questions[index];
          final cs = Theme.of(context).colorScheme;

          return ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
            title: Text(
              q.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${_typeLabel(q.type)}${q.required ? '  •  Required' : ''}',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            trailing: _TypeIcon(type: q.type),
          );
        },
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'text':
        return 'Text';
      case 'number':
        return 'Number';
      case 'geocode':
        return 'Geocode';
      case 'dropdown':
        return 'Dropdown';
      case 'radio':
        return 'Radio';
      case 'checkbox':
        return 'Checkbox';
      default:
        return type;
    }
  }
}

class _TypeIcon extends StatelessWidget {
  final String type;
  const _TypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (type) {
      case 'text':
        icon = Icons.short_text_rounded;
        break;
      case 'number':
        icon = Icons.pin_outlined;
        break;
      case 'geocode':
        icon = Icons.location_on_outlined;
        break;
      case 'dropdown':
        icon = Icons.arrow_drop_down_circle_outlined;
        break;
      case 'radio':
        icon = Icons.radio_button_checked_outlined;
        break;
      case 'checkbox':
        icon = Icons.check_box_outlined;
        break;
      default:
        icon = Icons.text_fields;
    }
    return Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline);
  }
}

// ── Responses Table ──────────────────────────────────────────────────────────



// class _ResponsesTable extends StatelessWidget {
//   final AdminController ctrl;
//   const _ResponsesTable({required this.ctrl});
//
//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//
//     // Build column headers: S.No, Submitted By, Submitted At, then each question label.
//     final fieldNames = ctrl.questions.map((q) => q.fieldName).toList();
//     final columns = <DataColumn>[
//       const DataColumn(label: Text('S.No', style: TextStyle(fontWeight: FontWeight.w700))),
//       const DataColumn(label: Text('Submitted By', style: TextStyle(fontWeight: FontWeight.w700))),
//       const DataColumn(label: Text('Submitted At', style: TextStyle(fontWeight: FontWeight.w700))),
//       ...ctrl.questions.map((q) => DataColumn(
//         label: Flexible(
//           child: Text(
//             q.label,
//             style: const TextStyle(fontWeight: FontWeight.w700),
//             overflow: TextOverflow.ellipsis,
//           ),
//         ),
//       )),
//     ];
//
//     // Build rows.
//     final rows = <DataRow>[];
//     for (var i = 0; i < ctrl.responses.length; i++) {
//       final r = ctrl.responses[i];
//       final cells = <DataCell>[
//         DataCell(Text('${i + 1}')),
//         DataCell(Text(ctrl.enumeratorName(r.submittedBy))),
//         DataCell(Text(
//           r.submittedAt != null
//               ? _formatShortDate(r.submittedAt!)
//               : '—',
//         )),
//         ...fieldNames.map((fn) {
//           final val = r.answers[fn];
//           final display = val is List ? val.join(', ') : (val?.toString() ?? '');
//           return DataCell(
//             ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 200),
//               child: Text(display, overflow: TextOverflow.ellipsis, maxLines: 2),
//             ),
//           );
//         }),
//       ];
//       rows.add(DataRow(cells: cells));
//     }
//
//     return Card(
//       elevation: 1,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       clipBehavior: Clip.antiAlias,
//       child: SingleChildScrollView(
//         scrollDirection: Axis.horizontal,
//         child: DataTable(
//           headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHighest),
//           columnSpacing: 20,
//           horizontalMargin: 16,
//           columns: columns,
//           rows: rows,
//         ),
//       ),
//     );
//   }
//
//   String _formatShortDate(DateTime dt) {
//     final local = dt.toLocal();
//     final day = local.day.toString().padLeft(2, '0');
//     final month = local.month.toString().padLeft(2, '0');
//     final year = local.year;
//     final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
//     final minute = local.minute.toString().padLeft(2, '0');
//     final amPm = local.hour >= 12 ? 'PM' : 'AM';
//     return '$day/$month/$year $hour:$minute $amPm';
//   }
// }

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _ResponsesTable extends StatelessWidget {
  final AdminController ctrl;
  const _ResponsesTable({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fieldNames = ctrl.questions.map((q) => q.fieldName).toList();
    final columns = <DataColumn>[
      const DataColumn(
        label: Text('S.No', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      const DataColumn(
        label: Text(
          'Submitted By',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const DataColumn(
        label: Text(
          'Submitted At',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      ...ctrl.questions.map(
        (q) => DataColumn(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              q.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ];

    final rows = <DataRow>[];
    for (var i = 0; i < ctrl.responses.length; i++) {
      final r = ctrl.responses[i];
      rows.add(
        DataRow(
          cells: [
            DataCell(Text('${i + 1}')),
            DataCell(Text(ctrl.enumeratorName(r.submittedBy))),
            DataCell(
              Text(
                r.submittedAt != null ? _formatShortDate(r.submittedAt!) : '-',
              ),
            ),
            ...fieldNames.map((fn) {
              final val = r.answers[fn];
              final display = val is List
                  ? val.join(', ')
                  : (val?.toString() ?? '');
              return DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    display,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHighest),
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: columns,
          rows: rows,
        ),
      ),
    );
  }

  String _formatShortDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month/$year $hour:$minute $amPm';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
