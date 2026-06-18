import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../data/repositories/auth_repository.dart';

class HomeAdminPage extends StatelessWidget {
  const HomeAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
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
            'Welcome, Admin!\n\nBuild your survey management UI here '
                '(manage enumerators, view collected surveys, etc.).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}