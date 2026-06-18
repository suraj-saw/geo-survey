import 'package:get/get.dart';

import '../controllers/forgot_password_controller.dart';
import '../controllers/sign_up_controller.dart';

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SignUpController>(() => SignUpController(), fenix: true);
    Get.lazyPut<ForgotPasswordController>(
          () => ForgotPasswordController(),
      fenix: true,
    );
  }
}