import 'package:flutter/material.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/glass_app_bar.dart';
import 'auth/login_screen.dart';
import '../widgets/skeleton_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _apiService = ApiService();
  List<dynamic> _products = [];
  bool _isLoading = true;
  int _selectedAvatarIndex = 0;
  String _username = '';
  
  // Statistics - computed values stored in state
  int _totalTracked = 0;
  int _currentlyTracking = 0;
  int _boughtProducts = 0;

  // Avatar image paths
  final List<String> _avatarPaths = [
    'assets/avatars/avatar.png',
    'assets/avatars/boy.png',
    'assets/avatars/gamer.png',
    'assets/avatars/girl.png',
    'assets/avatars/man (1).png',
    'assets/avatars/man.png',
    'assets/avatars/panda.png',
  ];
  
  // Helper method to compute statistics from products list
  void _computeStatistics() {
    int total = _products.length;
    int tracking = 0;
    int bought = 0;
    
    for (var product in _products) {
      final isBought = product['isBought'];
      
      // Check if product is bought
      if (isBought == true || 
          isBought == 'true' || 
          isBought == 1 || 
          isBought == '1') {
        bought++;
      } else {
        // Everything else (null, false, etc.) is considered "tracking"
        tracking++;
      }
    }
    
    print('📊 Computing Statistics:');
    print('   Total products: $total');
    print('   Currently tracking: $tracking');
    print('   Bought: $bought');
    print('   Verification: ${tracking + bought} == $total: ${tracking + bought == total}');
    
    setState(() {
      _totalTracked = total;
      _currentlyTracking = tracking;
      _boughtProducts = bought;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    _loadProducts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh when app comes to foreground
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshProducts();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh products when screen becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Small delay to ensure we're actually visible
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _refreshProducts();
          }
        });
      }
    });
  }

  Future<void> _refreshProducts() async {
    try {
      print('🔄 Refreshing products from API...');
      final products = await _apiService.getProducts();
      
      if (mounted) {
        print('✅ Refreshed ${products.length} products from API');
        
        // Update products list
        setState(() {
          _products = products;
        });
        
        // Compute statistics after updating products
        _computeStatistics();
      }
    } catch (e) {
      print('❌ Error refreshing products: $e');
      // Don't clear products on error, just log it
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _authService.getUserProfile();
      final user = _authService.currentUser;

      setState(() {
        _username =
            profile?['username'] ??
            user?.displayName ??
            user?.email?.split('@')[0] ??
            'User';
        _selectedAvatarIndex = profile?['avatarIndex'] ?? 0;
      });
    } catch (e) {
      print('Error loading profile: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      print('📦 Loading products from API...');
      final products = await _apiService.getProducts();
      
      if (mounted) {
        print('✅ Received ${products.length} products from API');
        
        // Log sample products for debugging
        if (products.isNotEmpty) {
          print('Sample products:');
          for (int i = 0; i < products.length && i < 3; i++) {
            final p = products[i];
            print('   ${i + 1}. "${p['title']?.toString().substring(0, 30) ?? 'N/A'}" - isBought: ${p['isBought']} (type: ${p['isBought']?.runtimeType})');
          }
        }
        
        // Update products list
        setState(() {
          _products = products;
          _isLoading = false;
        });
        
        // Compute statistics after updating products
        _computeStatistics();
      }
    } catch (e) {
      print('❌ Error loading products: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _products = [];
        });
        _computeStatistics(); // Update stats to show zeros
      }
    }
  }

  Future<void> _showEditDialog() async {
    final textColor = AppTheme.textPrimary;
    final secondaryColor = AppTheme.textSecondary;

    // Use local state variables for the dialog
    String tempUsername = _username;
    int tempAvatarIndex = _selectedAvatarIndex;
    final usernameController = TextEditingController(text: tempUsername);

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (context, setDialogState) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: GlassContainer(
              padding: const EdgeInsets.all(24),
              borderRadius: 20,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Profile',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Username field
                    Text(
                      'Username',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: usernameController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Enter username',
                        hintStyle: TextStyle(color: secondaryColor),
                        filled: true,
                        fillColor: AppTheme.primaryDark.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.glassBorder,
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.glassBorder,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.accentBlue,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        tempUsername = value;
                      },
                    ),
                    const SizedBox(height: 24),
                    // Avatar selection
                    Text(
                      'Choose Avatar',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.0,
                            ),
                        itemCount: _avatarPaths.length,
                        itemBuilder: (context, index) {
                          final isSelected = tempAvatarIndex == index;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                tempAvatarIndex = index;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.accentBlue
                                      : Colors.transparent,
                                  width: isSelected ? 4 : 0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.accentBlue
                                              .withOpacity(0.4),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  _avatarPaths[index],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: AppTheme.secondaryDark,
                                      child: Icon(
                                        Icons.person_rounded,
                                        size: 40,
                                        color: AppTheme.textSecondary,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: secondaryColor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GlassButton(
                          text: 'Save',
                          onPressed: () async {
                            Navigator.of(context).pop();
                            // Update the actual state only when Save is pressed
                            setState(() {
                              _username = tempUsername.trim();
                              _selectedAvatarIndex = tempAvatarIndex;
                            });
                            await _saveProfileChanges();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfileChanges() async {
    try {
      // Update username
      if (_username.trim().isNotEmpty) {
        await _authService.updateUserProfile(username: _username.trim());
      }

      // Update avatar
      await _authService.updateUserProfile(avatarIndex: _selectedAvatarIndex);

      // Ensure username is trimmed
      setState(() {
        _username = _username.trim();
      });

      if (mounted) {
        GlassSnackBar.show(
          context,
          message: 'Profile updated!',
          type: SnackBarType.success,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.show(
          context,
          message: 'Failed to update profile: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign Out?',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to sign out?',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentRed,
                    ),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          GlassSnackBar.show(
            context,
            message: 'Sign out failed: ${e.toString()}',
            type: SnackBarType.error,
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          automaticallyImplyLeading: true,
          title: const Text(
            'Profile',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontSize: 22,
              color: Colors.white,
            ),
          ),
        ),
        body: _isLoading
            ? const ProfileScreenSkeleton()
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Profile Header
                      GlassContainer(
                        padding: const EdgeInsets.all(24),
                        borderRadius: 20,
                        child: Column(
                          children: [
                            // Current Avatar Display
                            GestureDetector(
                              onTap: () => _showEditDialog(),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.accentBlue,
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.accentBlue
                                              .withOpacity(0.3),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        _avatarPaths[_selectedAvatarIndex],
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Container(
                                                color: AppTheme.secondaryDark,
                                                child: Icon(
                                                  Icons.person_rounded,
                                                  size: 60,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppTheme.accentBlue,
                                        border: Border.all(
                                          color: AppTheme.primaryDark,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.edit_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Username
                            Center(
                              child: Text(
                                _username.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _authService.currentUser?.email ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Statistics
                      GlassContainer(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statistics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStatItem(
                              'Total Tracked',
                              '$_totalTracked',
                              Icons.inventory_2_rounded,
                              AppTheme.accentBlue,
                              AppTheme.textPrimary,
                            ),
                            const SizedBox(height: 12),
                            _buildStatItem(
                              'Currently Tracking',
                              '$_currentlyTracking',
                              Icons.track_changes_rounded,
                              AppTheme.accentGreen,
                              AppTheme.textPrimary,
                            ),
                            const SizedBox(height: 12),
                            _buildStatItem(
                              'Bought Products',
                              '$_boughtProducts',
                              Icons.check_circle_rounded,
                              AppTheme.accentPurple,
                              AppTheme.textPrimary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Logout Button
                      GlassContainer(
                        padding: EdgeInsets.zero,
                        borderRadius: 16,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _handleLogout,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppTheme.accentRed.withOpacity(0.8),
                                    AppTheme.accentRed.withOpacity(0.6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    color: AppTheme.textPrimary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Sign Out',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color iconColor,
    Color textColor,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor.withOpacity(0.7),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
