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

        return _RoleRouter(uid: user.uid);
      },
    );
  }
}

/// Separated into its own StatefulWidget so the FutureBuilder is only
/// rebuilt when the UID actually changes, not on every auth stream tick.
class _RoleRouter extends StatefulWidget {
  final String uid;
  const _RoleRouter({required this.uid});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late Future<bool> _isAdminFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _fetchIsAdmin(widget.uid);
  }

  @override
  void didUpdateWidget(_RoleRouter old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) {
      _isAdminFuture = _fetchIsAdmin(widget.uid);
    }
  }

  Future<bool> _fetchIsAdmin(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return doc.data()?['isAdmin'] == true;
    } catch (_) {
      // If the read fails for any reason, default to enumerator role.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }
        final isAdmin = snapshot.data ?? false;
        return isAdmin ? const HomeAdminPage() : const HomeEnumeratorPage();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}