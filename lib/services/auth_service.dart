import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get user => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> waitForRestoredUser() async {
    final immediate = _auth.currentUser;
    if (immediate != null) return immediate;

    try {
      return await _auth
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => _auth.currentUser,
          );
    } catch (_) {
      return _auth.currentUser;
    }
  }
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = name.trim();
    final normalizedRole = _normalizeMobileRole(role);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    try {
      await credential.user?.updateDisplayName(normalizedName);
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(credential.user!.uid)
          .set({
        'uid': credential.user!.uid,
        'name': normalizedName,
        'email': normalizedEmail,
        'role': normalizedRole,
        'active': true,
        'isOwner': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await credential.user?.delete();
      rethrow;
    }

    // Account creation is complete even if the email provider temporarily
    // rejects the first send. The verification screen provides a resend action.
    try {
      await credential.user?.sendEmailVerification();
    } catch (_) {}

    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    await credential.user?.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null || !refreshedUser.emailVerified) {
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verify your email address before signing in.',
      );
    }

    await ensureMobileAccess();
    return credential;
  }

  Future<void> ensureMobileAccess() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No signed-in user was found.',
      );
    }

    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null || !refreshedUser.emailVerified) {
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verify your email address before using SoilSense.',
      );
    }

    // Force a fresh ID token so Firestore Security Rules immediately receive
    // the updated email_verified claim after the user taps the email link.
    await refreshedUser.getIdToken(true);

    var profile = await getUserProfile();
    if (profile == null) {
      final email = (refreshedUser.email ?? '').trim().toLowerCase();
      final displayName = (refreshedUser.displayName ?? '').trim();
      final emailName = email.contains('@') ? email.split('@').first.trim() : '';
      final restoredName = displayName.length >= 2
          ? displayName
          : emailName.length >= 2
              ? emailName
              : 'SoilSense User';

      profile = {
        'uid': refreshedUser.uid,
        'name': restoredName,
        'email': email,
        'role': 'farmer',
        'active': true,
        'isOwner': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(refreshedUser.uid)
          .set(profile);
    }

    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final active = profile['active'] != false;

    if (!active) {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'account-disabled',
        message: 'This account is currently disabled.',
      );
    }
    if (role != 'farmer' && role != 'technician') {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'role-not-authorized',
        message: 'This account does not have a valid mobile-app role.',
      );
    }

    await _firestore
        .collection(AppConfig.usersCollection)
        .doc(refreshedUser.uid)
        .update({'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign in again before requesting a verification email.',
      );
    }

    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser?.emailVerified == true) return;
    await refreshedUser?.sendEmailVerification();
  }

  Future<bool> refreshEmailVerificationStatus() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshedUser = _auth.currentUser;
    final verified = refreshedUser?.emailVerified ?? false;
    if (verified) {
      await refreshedUser?.getIdToken(true);
    }
    return verified;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> resetPassword(String email) async {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter your email address first.',
      );
    }
    await _auth.sendPasswordResetEmail(email: value);
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore
        .collection(AppConfig.usersCollection)
        .doc(user.uid)
        .get();
    return doc.data();
  }

  Future<void> updateProfile({required String name}) async {
    final user = currentUser;
    if (user == null) throw StateError('No signed-in user.');

    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Name cannot be empty.');

    await user.updateDisplayName(cleanName);

    final profileRef =
        _firestore.collection(AppConfig.usersCollection).doc(user.uid);
    final profileSnapshot = await profileRef.get();

    if (profileSnapshot.exists) {
      await profileRef.update({
        'name': cleanName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await profileRef.set({
        'uid': user.uid,
        'name': cleanName,
        'email': (user.email ?? '').trim().toLowerCase(),
        'role': 'farmer',
        'active': true,
        'isOwner': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  String _normalizeMobileRole(String role) {
    final value = role.trim().toLowerCase();
    if (value == 'agricultural technician' || value == 'technician') {
      return 'technician';
    }
    return 'farmer';
  }

  static String friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'weak-password':
          return 'Use a stronger password.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait before trying again.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        case 'email-not-verified':
          return 'Verify your email address before using SoilSense.';
        case 'account-disabled':
        case 'profile-not-found':
        case 'role-not-authorized':
          return error.message ?? 'Sign-in is not allowed.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
