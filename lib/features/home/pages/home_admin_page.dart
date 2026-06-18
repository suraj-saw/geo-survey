import 'package:flutter/material.dart';

import '../../admin/pages/admin_survey_list_page.dart';

/// The admin home is the admin survey list with statistics.
/// Keeping this wrapper allows future tab navigation if needed.
class HomeAdminPage extends StatelessWidget {
  const HomeAdminPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminSurveyListPage();
}