import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const MyApp());
}

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Handling a background message: ${message.messageId}');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
  print('   Data: ${message.data}');

  // Initialize notification service to show notification
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Show local notification when app is in background
  if (message.notification != null) {
    await notificationService.showLocalNotification(
      title: message.notification!.title ?? 'Price Alert',
      body: message.notification!.body ?? '',
      payload: message.data.toString(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PricePulse',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
    );
  }
}

// Wrapper widget to check authentication state
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _currentUser;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Check current user immediately
    _currentUser = FirebaseAuth.instance.currentUser;
    print(
      '🔍 AuthWrapper init: currentUser = ${_currentUser?.email ?? "null"}',
    );

    // Listen to user changes stream and force rebuild
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (mounted) {
        print('🔄 User changed in stream: ${user?.email ?? "null"}');
        if (user != _currentUser) {
          setState(() {
            _currentUser = user;
          });
        }
      }
    });

    // Also set up a periodic check to catch any missed updates
    // This ensures we catch the user even if stream is delayed
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final latestUser = FirebaseAuth.instance.currentUser;
        if (latestUser != _currentUser) {
          print(
            '🔄 Periodic check: User detected = ${latestUser?.email ?? "null"}',
          );
          setState(() {
            _currentUser = latestUser;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always check current user directly first (most up-to-date)
    // This is synchronous and immediate - no waiting for streams
    final currentUser = FirebaseAuth.instance.currentUser;

    // Update local state if changed (for stream listener)
    if (currentUser != _currentUser) {
      // Update state immediately in next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && currentUser != _currentUser) {
          setState(() {
            _currentUser = currentUser;
          });
        }
      });
    }

    // ALWAYS use currentUser directly (most up-to-date, synchronous check)
    // Don't rely on _currentUser or stream data - check Firebase directly
    final user = currentUser;

    print(
      '🔍 AuthWrapper build: user = ${user?.email ?? "null"}, currentUser = ${currentUser?.email ?? "null"}, _currentUser = ${_currentUser?.email ?? "null"}',
    );

    // If user is signed in, show HomeScreen immediately
    if (user != null) {
      final isGoogleUser = user.providerData.any(
        (p) => p.providerId == 'google.com',
      );

      if (user.emailVerified || isGoogleUser) {
        print('✅ User authenticated: ${user.email}, showing HomeScreen');
        return const HomeScreen();
      } else {
        print('⚠️ User not verified: ${user.email}, showing LoginScreen');
        return const LoginScreen();
      }
    }

    // If user is not signed in, show LoginScreen
    print('ℹ️ No authenticated user, showing LoginScreen');
    return const LoginScreen();
  }
}
