import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/repositories/auth_repository.dart';

class SignInController {
  final _authRepo = AuthRepository();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final isLoading = false.obs;
  final isPasswordVisible = false.obs;

  Future<void> signIn() async {
    isLoading.value = true;
    try {
      await _authRepo.signIn(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final data = await _authRepo.getCurrentUserData();
      final isAdmin = data?['isAdmin'] == true;

      if (isAdmin) {
        Get.offAllNamed(AppRoutes.homeAdmin);
      } else {
        Get.offAllNamed(AppRoutes.homeEnumerator);
      }
    } on FirebaseAuthException catch (e) {
      AppSnackbar.show('Sign In Failed', _messageFor(e.code, e.message));
    } catch (e) {
      AppSnackbar.show('Error', 'Something went wrong. Please try again.');
    } finally {
      isLoading.value = false;
    }
  }

  String _messageFor(String code, String? fallback) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return fallback ?? 'Sign in failed. Please try again.';
    }
  }

  void dispose() {
    emailController.dispose();
    passwordController.dispose();
  }
}