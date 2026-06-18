import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/repositories/auth_repository.dart';

class SignInController extends GetxController {
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

      bool isAdmin = false;
      try {
        final data = await _authRepo.getCurrentUserData();
        isAdmin = data?['isAdmin'] == true;
      } catch (_) {
        isAdmin = false;
      }

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
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return fallback ?? 'Sign in failed. Please try again.';
    }
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
