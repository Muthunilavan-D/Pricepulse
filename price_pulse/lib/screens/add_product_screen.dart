import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_snackbar.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({Key? key}) : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _thresholdController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _enableThreshold = false;

  void _trackProduct() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      GlassSnackBar.show(
        context,
        message: 'Please enter a product URL',
        type: SnackBarType.warning,
      );
      return;
    }

    // Basic URL validation (accept amazon, amzn.in, and flipkart)
    final urlLower = url.toLowerCase();
    if (!urlLower.contains('amazon') &&
        !urlLower.contains('amzn.in') &&
        !urlLower.contains('flipkart')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Only Amazon and Flipkart URLs are supported'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Parse threshold if provided - validation will happen on backend after scraping
    double? threshold;
    if (_enableThreshold && _thresholdController.text.trim().isNotEmpty) {
      final thresholdValue = double.tryParse(_thresholdController.text.trim());
      if (thresholdValue == null || thresholdValue <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter a valid threshold price'),
            backgroundColor: AppTheme.accentOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      threshold = thresholdValue;
    }

    try {
      // Add the product directly - backend will scrape and validate threshold
      // No need to pre-scrape, this was causing double delay
      final productData = await _apiService.trackProduct(
        _urlController.text.trim(),
        thresholdPrice: threshold,
      );
      if (mounted) {
        GlassSnackBar.show(
          context,
          message: threshold != null
              ? 'Product added with threshold ₹${threshold.toStringAsFixed(0)}!'
              : 'Product added successfully!',
          type: SnackBarType.success,
          duration: const Duration(seconds: 2),
        );
        // Return product data instead of just true
        Navigator.pop(context, productData);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        SnackBarType snackBarType = SnackBarType.error;
        
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(11);
        }

        // Handle threshold validation error (40% rule) - CHECK THIS FIRST before other errors
        // This must come before "Could not fetch" check to avoid incorrect error messages
        if (errorMessage.contains('must be at least 40%') ||
            (errorMessage.contains('Threshold price') && errorMessage.contains('40%'))) {
          errorMessage = 'Threshold must be at least 40% of the product price.';
          snackBarType = SnackBarType.warning;
        }
        // Handle generic threshold errors
        else if (errorMessage.contains('Threshold price must be less') ||
                 errorMessage.contains('Threshold must be less')) {
          errorMessage = 'Threshold must be less than current price.';
          snackBarType = SnackBarType.warning;
        }
        // Handle duplicate product error
        else if (errorMessage.contains('already being tracked') ||
                 errorMessage.contains('duplicate')) {
          errorMessage = 'This product is already being tracked.';
        }
        // Handle scraping/network errors with concise message (only if not a threshold error)
        else if (errorMessage.contains('Could not fetch') ||
                 errorMessage.contains('scraping') ||
                 errorMessage.contains('network') ||
                 errorMessage.contains('CAPTCHA')) {
          errorMessage = 'Could not fetch product details. Please try again.';
        }

        GlassSnackBar.show(
          context,
          message: errorMessage,
          type: snackBarType,
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Add Product'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.link_rounded,
                            color: AppTheme.accentBlue,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Product URL',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'Paste Amazon or Flipkart link here',
                          helperText:
                              'Example: https://amazon.in/...  or  \nhttps://flipkart.com/...',
                          prefixIcon: const Icon(Icons.shopping_bag_outlined),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          alignLabelWithHint: true,
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _trackProduct(),
                        style: const TextStyle(color: AppTheme.textPrimary),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Threshold Price Section
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_active_rounded,
                            color: AppTheme.accentBlue,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Price Alert (Optional)',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Set price alert threshold'),
                        subtitle: const Text('Get notified when price drops'),
                        value: _enableThreshold,
                        onChanged: (value) {
                          setState(() {
                            _enableThreshold = value;
                            if (!value) {
                              _thresholdController.clear();
                            }
                          });
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      if (_enableThreshold) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _thresholdController,
                          decoration: InputDecoration(
                            labelText: 'Threshold Price (₹)',
                            hintText: 'Enter price below current price',
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text(
                                '₹',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            helperText:
                                'You\'ll be notified when price drops to or below this amount',
                          ),
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GlassButton(
                  text: 'Track Price',
                  icon: Icons.track_changes_rounded,
                  onPressed: _trackProduct,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 32),
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppTheme.accentBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Supported Sites',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSiteInfo('Amazon', Icons.shopping_cart_rounded),
                      const SizedBox(height: 8),
                      _buildSiteInfo('Flipkart', Icons.store_rounded),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSiteInfo(String site, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(site, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
