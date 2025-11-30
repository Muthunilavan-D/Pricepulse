import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a product URL'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
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
      // First, scrape to get current price for threshold validation (if threshold is provided)
      if (threshold != null) {
        try {
          final scrapeResponse = await http
              .get(
                Uri.parse(
                  '${_apiService.baseUrl}/scrape?url=${Uri.encodeComponent(_urlController.text.trim())}',
                ),
              )
              .timeout(const Duration(seconds: 30));

          if (scrapeResponse.statusCode == 200) {
            final scrapeData = json.decode(scrapeResponse.body);
            final priceStr = scrapeData['price']?.toString() ?? '';
            final currentPrice = double.tryParse(
              priceStr.replaceAll('₹', '').replaceAll(',', '').trim(),
            );

            if (currentPrice != null) {
              final thresholdValue = threshold;
              // Check if threshold is too low (less than 50% of current price)
              final thresholdPercentage = (thresholdValue / currentPrice) * 100;
              if (thresholdPercentage < 50) {
                // Show confirmation dialog
                final shouldProceed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppTheme.secondaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text(
                      'Threshold Price Too Low',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    content: Text(
                      'The threshold price (₹${thresholdValue.toStringAsFixed(0)}) is ${thresholdPercentage.toStringAsFixed(1)}% of the current price (₹${currentPrice.toStringAsFixed(0)}).\n\n'
                      'A price drop of ${(100 - thresholdPercentage).toStringAsFixed(1)}% is very unlikely. Are you sure you want to set this threshold?',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accentOrange,
                        ),
                        child: const Text('Yes, Set Threshold'),
                      ),
                    ],
                  ),
                );

                if (shouldProceed != true) {
                  setState(() {
                    _isLoading = false;
                  });
                  return;
                }
              }
            }
          }
        } catch (e) {
          // If scrape fails, continue anyway - backend will validate
          print('Warning: Could not pre-validate threshold: $e');
        }
      }

      // Now add the product with threshold
      await _apiService.trackProduct(
        _urlController.text.trim(),
        thresholdPrice: threshold,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  threshold != null
                      ? 'Product added with threshold ₹${threshold.toStringAsFixed(0)}!'
                      : 'Product added successfully!',
                ),
              ],
            ),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(11);
        }

        // Handle duplicate product error
        if (errorMessage.contains('already being tracked') ||
            errorMessage.contains('duplicate')) {
          errorMessage = 'This product is already being tracked.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
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
