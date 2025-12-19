import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock screen orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
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

    // Listen to user changes stream and update state
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (mounted && user != _currentUser) {
        setState(() {
          _currentUser = user;
        });
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
    // Use _currentUser which is updated by the stream listener
    // This prevents infinite rebuild loops
    final user = _currentUser;

    // If user is signed in, show HomeScreen
    if (user != null) {
      final isGoogleUser = user.providerData.any(
        (p) => p.providerId == 'google.com',
      );

      if (user.emailVerified || isGoogleUser) {
        return const HomeScreen();
      } else {
        return const LoginScreen();
      }
    }

    // If user is not signed in, show LoginScreen
    return const LoginScreen();
  }
}
