import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/repositories/auth_repository.dart';

class SignUpController extends GetxController {
  final _authRepo = AuthRepository();

  final isLoading = false.obs;
  final isPasswordVisible = false.obs;

  Future<void> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    isLoading.value = true;
    try {
      await _authRepo.signUp(
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        password: password.trim(),
      );

      // Firebase automatically signs the user in after createUserWithEmailAndPassword.
      // Sign out immediately so the RootPage auth-state listener returns to the
      // unauthenticated state before we navigate — otherwise Get.offAllNamed
      // would land on a RootPage that shows HomeEnumeratorPage instead of SignIn.
      await _authRepo.signOut();

      AppSnackbar.show(
        'Account Created',
        'You can now sign in with your credentials.',
      );
      Get.offAllNamed(AppRoutes.signIn);
    } on FirebaseAuthException catch (e) {
      AppSnackbar.show('Sign Up Failed', _messageFor(e.code, e.message));
    } on FirebaseException catch (e) {
      // Auth succeeded but the Firestore write failed even after the retry.
      // Sign the user out so they're not stuck in a half-created state, then
      // ask them to try again (the Auth account already exists, so the next
      // attempt will hit 'email-already-in-use' — guide them to sign in instead).
      await _authRepo.signOut();
      AppSnackbar.show(
        'Setup Incomplete',
        'Your account was created but we couldn\'t save your profile '
            '(${e.message ?? 'network error'}). '
            'Please try signing up again or contact support.',
      );
    } catch (e) {
      AppSnackbar.show('Error', 'Something went wrong. Please try again. ($e)');
    } finally {
      isLoading.value = false;
    }
  }

  String _messageFor(String code, String? fallback) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return fallback ?? 'Sign up failed. Please try again.';
    }
  }
}