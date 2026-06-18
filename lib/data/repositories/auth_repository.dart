import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralizes every Firebase Auth + Firestore call related to user
/// accounts, so controllers and pages never talk to Firebase directly.
class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool isUserLoggedIn() => _auth.currentUser != null;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Creates the Firebase Auth account and writes the matching
  /// `users/{uid}` document with the schema:
  /// { name, email, phone, isAdmin, createdAt }
  Future<UserCredential> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    final uid = cred.user!.uid;

    await _firestore.collection('users').doc(uid).set({
      'name': name.trim(),
      'email': email.trim(),
      // Stored as a number to match the existing Firestore schema
      // (falls back to the raw string if it can't be parsed).
      'phone': int.tryParse(phone.trim()) ?? phone.trim(),
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return cred;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Fetches the signed-in user's Firestore document (name, email,
  /// phone, isAdmin, createdAt), or null if not signed in / not found.
  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<bool> isCurrentUserAdmin() async {
    final data = await getCurrentUserData();
    return data?['isAdmin'] == true;
  }

  Future<void> signOut() => _auth.signOut();
}