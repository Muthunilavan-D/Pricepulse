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

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
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
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppTheme.primaryDark,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
              ),
            ),
          );
        }

        // If user is signed in, show HomeScreen
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          print('🔍 StreamBuilder: User detected: ${user.email}, Verified: ${user.emailVerified}');
          
          // Check if email is verified (Google accounts are automatically verified)
          if (user.emailVerified || user.providerData.any((p) => p.providerId == 'google.com')) {
            print('✅ Email verified for ${user.email}. Allowing access.');
            return const HomeScreen();
          } else {
            print('⚠️ Email not verified for ${user.email}. Showing login.');
            return const LoginScreen();
          }
        }

        // If user is not signed in, show LoginScreen
        print('! StreamBuilder: No authenticated user, showing login screen');
        return const LoginScreen();
      },
    );
  }
}
