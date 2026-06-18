import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Small wrapper around Get.snackbar so the rest of the app doesn't need
/// to know about snackbar styling details.
class AppSnackbar {
  static void show(String title, String message, {Color? backgroundColor}) {
    Get.closeAllSnackbars();
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: backgroundColor ?? Colors.black87,
      colorText: Colors.white,
      margin: const EdgeInsets.all(14),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }
}