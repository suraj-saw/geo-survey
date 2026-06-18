// Replace lib/features/home/pages/home_enumerator_page.dart with this file.

import 'package:flutter/material.dart';

import '../../survey/pages/survey_list_page.dart';

/// The enumerator home is simply the survey list.
/// Keeping this wrapper allows future tab navigation if needed.
class HomeEnumeratorPage extends StatelessWidget {
  const HomeEnumeratorPage({super.key});

  @override
  Widget build(BuildContext context) => const SurveyListPage();
}