import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/routes/app_routes.dart';
import 'features/auth/bindings/auth_binding.dart';
import 'features/auth/pages/forgot_password_page.dart';
import 'features/auth/pages/sign_in_page.dart';
import 'features/auth/pages/sign_up_page.dart';
import 'features/home/pages/home_admin_page.dart';
import 'features/home/pages/home_enumerator_page.dart';
import 'features/root/pages/root_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Geo Survey',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RootPage(),
      getPages: [
        GetPage(name: AppRoutes.signIn, page: () => const SignInPage()),
        GetPage(
          name: AppRoutes.signUp,
          page: () => SignUpPage(),
          binding: AuthBinding(),
        ),
        GetPage(
          name: AppRoutes.forgotPassword,
          page: () => const ForgotPasswordPage(),
          binding: AuthBinding(),
        ),
        GetPage(name: AppRoutes.homeAdmin, page: () => const HomeAdminPage()),
        GetPage(
          name: AppRoutes.homeEnumerator,
          page: () => const HomeEnumeratorPage(),
        ),
      ],
    );
  }
}