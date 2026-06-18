import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/repositories/auth_repository.dart';

class ForgotPasswordController extends GetxController {
  final _authRepo = AuthRepository();

  final emailController = TextEditingController();
  final isLoading = false.obs;
  final emailSent = false.obs;

  Future<void> sendPasswordResetEmail() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      AppSnackbar.show('Required', 'Please enter your email address.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      AppSnackbar.show('Invalid Email', 'Please enter a valid email address.');
      return;
    }

    isLoading.value = true;
    try {
      await _authRepo.sendPasswordResetEmail(email);
      emailSent.value = true;
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'No account found with this email address.',
        'invalid-email' => 'The email address is not valid.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? 'Failed to send reset email. Please try again.',
      };
      AppSnackbar.show('Error', message);
    } catch (e) {
      AppSnackbar.show('Error', 'Something went wrong. Please try again.');
    } finally {
      isLoading.value = false;
    }
  }

  void goBackToSignIn() => Get.offAllNamed(AppRoutes.signIn);

  @override
  void onClose() {
    emailController.dispose();
    super.onClose();
  }
}
