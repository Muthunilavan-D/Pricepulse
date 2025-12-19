import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glassmorphism_widget.dart';
import '../../services/auth_service.dart';
import '../../widgets/glass_snackbar.dart';
import '../home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Check if user is already signed in when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && mounted) {
        final isGoogleUser = currentUser.providerData.any(
          (p) => p.providerId == 'google.com',
        );
        if (currentUser.emailVerified || isGoogleUser) {
          print('✅ User already signed in, navigating to HomeScreen');
          Navigator.of(context, rootNavigator: true).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await _authService.signInWithGoogle();

      if (userCredential != null && mounted) {
        // Sign-in successful
        print('✅ Sign-in successful, user: ${userCredential.user?.email}');
        print('   User ID: ${userCredential.user?.uid}');
        print('   Email verified: ${userCredential.user?.emailVerified}');
        print('   Providers: ${userCredential.user?.providerData.map((p) => p.providerId).toList()}');
        
        // Stop loading state immediately
        setState(() {
          _isLoading = false;
        });
        
        // Reload user to ensure all data is fresh and trigger stream update
        try {
          await userCredential.user?.reload();
          print('✅ User reloaded successfully');
        } catch (e) {
          print('⚠️ User reload error (non-critical): $e');
        }
        
        // Verify user is still signed in
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          print('✅ Current user confirmed: ${currentUser.email}');
          
          // Force navigation immediately after sign-in
          // Don't wait for AuthWrapper - navigate directly
          if (mounted) {
            // Small delay to ensure Firebase state is fully updated
            await Future.delayed(const Duration(milliseconds: 100));
            
            // Verify user is still signed in
            final verifiedUser = FirebaseAuth.instance.currentUser;
            if (verifiedUser != null) {
              print('✅ Verified user exists, navigating to HomeScreen');
              
              // Navigate directly to HomeScreen
              // Using pushAndRemoveUntil to clear the entire stack
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false, // Remove all previous routes
                );
                print('✅ Navigation to HomeScreen completed');
              }
            } else {
              print('❌ WARNING: User is null after sign-in, cannot navigate');
            }
          }
        } else {
          print('❌ WARNING: Current user is null after sign-in!');
        }
      } else if (mounted) {
        // User canceled sign-in
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        String errorMessage = 'Failed to sign in with Google';
        if (e.toString().contains('network_error') ||
            e.toString().contains('network')) {
          errorMessage =
              'Network error. Please check your internet connection.';
        } else if (e.toString().contains('sign_in_canceled')) {
          errorMessage = 'Sign-in was canceled';
        } else {
          errorMessage = 'Sign-in failed: ${e.toString()}';
        }

        GlassSnackBar.show(
          context,
          message: errorMessage,
          type: SnackBarType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo/Icon
                  Column(
                    children: [
                      Image.asset(
                        'assets/price_pulse_logo.png',
                        width: 96,
                        height: 96,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.trending_down_rounded,
                          color: AppTheme.accentBlue,
                          size: 96,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.accentBlue,
                            const Color(0xFF00D4FF), // Neon cyan
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'PricePulse',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            fontSize: 48,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Track prices, save money',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  // Sign In Card
                  GlassContainer(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome',
                          style: Theme.of(context).textTheme.displaySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to track your favorite products',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        // Google Sign-In Button
                        GlassContainer(
                          padding: EdgeInsets.zero,
                          borderRadius: 16,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _signInWithGoogle,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isLoading)
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppTheme.textPrimary,
                                              ),
                                        ),
                                      )
                                    else ...[
                                      Image.asset(
                                        'assets/image.png',
                                        width: 22,
                                        height: 22,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Icon(
                                                  Icons.login_rounded,
                                                  color: AppTheme.textPrimary,
                                                  size: 20,
                                                ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Text(
                                      'Continue with Google',
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Info text
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryDark.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.glassBorder,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: AppTheme.accentBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You can only sign in using your Google account',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
