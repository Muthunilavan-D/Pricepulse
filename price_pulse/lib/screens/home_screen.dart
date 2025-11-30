import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/product_card.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'add_product_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _products = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final products = await _apiService.getProducts();

      // Check for notifications and show them
      await _checkAndShowNotifications(products);

      setState(() {
        _products = products;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _checkAndShowNotifications(List<dynamic> products) async {
    try {
      final notificationService = NotificationService();

      for (var product in products) {
        // Check if product has a new notification
        if (product['hasNotification'] == true &&
            product['notificationType'] != null) {
          final notificationType = product['notificationType'] as String;
          final productTitle = product['title']?.toString() ?? 'Product';
          final currentPrice = product['price']?.toString() ?? 'N/A';
          final productId = product['id']?.toString() ?? '';

          bool notificationShown = false;

          if (notificationType == 'threshold_reached') {
            final thresholdPrice = product['thresholdPrice'];
            if (thresholdPrice != null) {
              await notificationService.showThresholdReachedNotification(
                productTitle: productTitle,
                currentPrice: currentPrice,
                thresholdPrice: (thresholdPrice as num).toDouble(),
              );
              notificationShown = true;
            }
          } else if (notificationType == 'price_drop') {
            // Get previous price from price history
            final priceHistory = product['priceHistory'] as List?;
            String? previousPrice;
            if (priceHistory != null && priceHistory.length >= 2) {
              previousPrice = priceHistory[priceHistory.length - 2]['price']
                  ?.toString();
            }

            if (previousPrice != null) {
              await notificationService.showPriceDropNotification(
                productTitle: productTitle,
                currentPrice: currentPrice,
                previousPrice: previousPrice,
              );
              notificationShown = true;
            }
          }

          // Clear notification flag after showing to prevent duplicates
          if (notificationShown && productId.isNotEmpty) {
            try {
              // Clear the notification flag in the database
              // We'll do this by updating the product (backend will clear it on next price update)
              // For now, we'll just mark it as shown locally
              print('✅ Notification shown for: $productTitle');
            } catch (e) {
              print('Error clearing notification flag: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error showing notifications: $e');
    }
  }

  Future<void> _refreshProducts() async {
    setState(() {
      _isRefreshing = true;
    });
    await _fetchProducts();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.trending_down, color: AppTheme.accentBlue, size: 28),
              const SizedBox(width: 8),
              const Text(
                'PricePulse',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.textPrimary,
                        ),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: _isRefreshing ? null : _refreshProducts,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? Center(
                  child: GlassContainer(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.accentBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading products...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : _products.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: GlassContainer(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No products tracked yet',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the + button to start tracking prices',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshProducts,
                  color: AppTheme.accentBlue,
                  backgroundColor: AppTheme.secondaryDark,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final product = _products[index];

                      // Get product ID - ensure it's a string
                      final productId = (product['id']?.toString() ?? '')
                          .trim();

                      if (productId.isEmpty) {
                        print(
                          '⚠️ CRITICAL: Product at index $index has NO ID!',
                        );
                        print('   Product keys: ${product.keys.toList()}');
                        print('   Product data: $product');
                        // Skip this product
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ProductCard(
                          id: productId,
                          title: product['title']?.toString() ?? 'Unknown',
                          price: product['price']?.toString() ?? 'N/A',
                          image: product['image']?.toString() ?? '',
                          url: product['url']?.toString() ?? '',
                          lastChecked: product['lastChecked']?.toString() ?? '',
                          priceHistory: product['priceHistory'] ?? [],
                          thresholdPrice: product['thresholdPrice'] != null
                              ? (product['thresholdPrice'] as num).toDouble()
                              : null,
                          onDelete: () => _fetchProducts(),
                        ),
                      );
                    },
                  ),
                ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AddProductScreen(),
                fullscreenDialog: true,
              ),
            );
            if (result == true) {
              _fetchProducts();
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Track Product'),
        ),
      ),
    );
  }
}
