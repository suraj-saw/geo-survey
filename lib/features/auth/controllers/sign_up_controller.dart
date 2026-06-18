import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/repositories/auth_repository.dart';

class SignUpController extends GetxController {
  final _authRepo = AuthRepository();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final isLoading = false.obs;
  final isPasswordVisible = false.obs;

  Future<void> signUp() async {
    isLoading.value = true;
    try {
      await _authRepo.signUp(
        name: nameController.text,
        email: emailController.text,
        phone: phoneController.text,
        password: passwordController.text,
      );

      AppSnackbar.show(
        'Account Created',
        'You can now sign in with your credentials.',
      );
      Get.offAllNamed(AppRoutes.signIn);
    } on FirebaseAuthException catch (e) {
      AppSnackbar.show('Sign Up Failed', _messageFor(e.code, e.message));
    } catch (e) {
      AppSnackbar.show('Error', 'Something went wrong. Please try again.');
    } finally {
      isLoading.value = false;
    }
  }

  String _messageFor(String code, String? fallback) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      default:
        return fallback ?? 'Sign up failed. Please try again.';
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}