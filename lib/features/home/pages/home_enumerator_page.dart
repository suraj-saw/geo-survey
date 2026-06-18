import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../data/repositories/auth_repository.dart';

class HomeEnumeratorPage extends StatelessWidget {
  const HomeEnumeratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Surveys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthRepository().signOut();
              Get.offAllNamed(AppRoutes.signIn);
            },
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Welcome, Enumerator!\n\nThis is where the survey form with '
                'automatic geocoding will live.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}