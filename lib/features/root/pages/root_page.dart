import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/pages/sign_in_page.dart';
import '../../home/pages/home_admin_page.dart';
import '../../home/pages/home_enumerator_page.dart';

/// Entry point widget: listens to Firebase auth state. Signed-out users
/// see the sign-in screen; signed-in users get routed to the Admin or
/// Enumerator home screen based on the `isAdmin` flag on their Firestore
/// user document.
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = authSnapshot.data;
        if (user == null) return const SignInPage();

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future:
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final isAdmin = userSnapshot.data?.data()?['isAdmin'] == true;
            return isAdmin ? const HomeAdminPage() : const HomeEnumeratorPage();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}