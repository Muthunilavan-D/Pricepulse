import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user profile data
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        print('❌ No user ID available');
        return null;
      }

      final doc = await _firestore.collection('userProfiles').doc(userId).get();
      
      if (doc.exists) {
        return doc.data();
      }
      
      // If profile doesn't exist, create default profile
      return await _createDefaultProfile(userId);
    } catch (e) {
      print('❌ Error getting user profile: $e');
      return null;
    }
  }

  // Create default profile for new user
  Future<Map<String, dynamic>> _createDefaultProfile(String userId) async {
    final user = _auth.currentUser;
    final defaultProfile = {
      'username': user?.displayName ?? user?.email?.split('@')[0] ?? 'User',
      'avatarIndex': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore.collection('userProfiles').doc(userId).set(defaultProfile);
      print('✅ Created default profile for user: $userId');
      return defaultProfile;
    } catch (e) {
      print('❌ Error creating default profile: $e');
      return defaultProfile;
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    String? username,
    int? avatarIndex,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (username != null && username.trim().isNotEmpty) {
        updateData['username'] = username.trim();
      }

      if (avatarIndex != null) {
        updateData['avatarIndex'] = avatarIndex;
      }

      await _firestore.collection('userProfiles').doc(userId).update(updateData);
      print('✅ Profile updated successfully');
    } catch (e) {
      print('❌ Error updating profile: $e');
      rethrow;
    }
  }
}

