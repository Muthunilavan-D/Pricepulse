import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/product_card.dart';
import '../widgets/glassmorphism_widget.dart';
import '../widgets/glass_app_bar.dart';
import '../theme/app_theme.dart';
import 'dart:ui';
import '../services/notification_service.dart';
import '../services/notification_storage_service.dart';
import '../models/notification_model.dart';
import 'add_product_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Search and Filter state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _sortBy = 'dateAdded'; // 'dateAdded', 'price', 'priceChange', 'name'
  bool _sortAscending = false;

  // Filter state
  double? _minPrice;
  double? _maxPrice;
  bool _showOnlyWithThreshold = false;

  // Bulk selection state
  bool _isSelectionMode = false;
  Set<String> _selectedProductIds = {};

  // Undo state for deleted products
  Map<String, dynamic>? _lastDeletedProduct;
  String? _lastDeletedProductId;

  // Notification state
  final NotificationStorageService _notificationStorage =
      NotificationStorageService();
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchProducts();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationStorage.getUnreadCount();
    if (mounted) {
      setState(() {
        _unreadNotificationCount = count;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<dynamic> filtered = List.from(_products);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        final title = (product['title']?.toString() ?? '').toLowerCase();
        return title.contains(_searchQuery);
      }).toList();
    }

    // Apply price range filter
    if (_minPrice != null || _maxPrice != null) {
      filtered = filtered.where((product) {
        final priceStr = product['price']?.toString() ?? '';
        final price = _parsePrice(priceStr);
        if (price == null) return false;
        if (_minPrice != null && price < _minPrice!) return false;
        if (_maxPrice != null && price > _maxPrice!) return false;
        return true;
      }).toList();
    }

    // Apply threshold filter
    if (_showOnlyWithThreshold) {
      filtered = filtered.where((product) {
        return product['thresholdPrice'] != null;
      }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      int comparison = 0;

      switch (_sortBy) {
        case 'price':
          final priceA = _parsePrice(a['price']?.toString() ?? '') ?? 0;
          final priceB = _parsePrice(b['price']?.toString() ?? '') ?? 0;
          comparison = priceA.compareTo(priceB);
          break;
        case 'name':
          final nameA = (a['title']?.toString() ?? '').toLowerCase();
          final nameB = (b['title']?.toString() ?? '').toLowerCase();
          comparison = nameA.compareTo(nameB);
          break;
        case 'dateAdded':
        default:
          final dateA =
              DateTime.tryParse(a['lastChecked']?.toString() ?? '') ??
              DateTime(1970);
          final dateB =
              DateTime.tryParse(b['lastChecked']?.toString() ?? '') ??
              DateTime(1970);
          comparison = dateA.compareTo(dateB);
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });

    setState(() {
      _filteredProducts = filtered;
    });
  }

  double? _parsePrice(String priceStr) {
    try {
      String cleaned = priceStr
          .replaceAll('₹', '')
          .replaceAll(',', '')
          .replaceAll('Rs.', '')
          .replaceAll(' ', '')
          .trim();
      return double.tryParse(cleaned);
    } catch (e) {
      return null;
    }
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
      _applyFilters();
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
          AppNotification? appNotification;

          if (notificationType == 'threshold_reached') {
            final thresholdPrice = product['thresholdPrice'];
            if (thresholdPrice != null) {
              await notificationService.showThresholdReachedNotification(
                productTitle: productTitle,
                currentPrice: currentPrice,
                thresholdPrice: thresholdPrice is num
                    ? thresholdPrice.toDouble()
                    : double.tryParse(thresholdPrice.toString()) ?? 0.0,
              );

              // Store in-app notification
              appNotification = AppNotification(
                id: '${productId}_${DateTime.now().millisecondsSinceEpoch}',
                type: 'threshold_reached',
                title: '🎯 Price Alert!',
                message:
                    '$productTitle dropped to $currentPrice (Threshold: ₹${thresholdPrice is num ? thresholdPrice.toInt() : thresholdPrice.toString()})',
                productId: productId,
                productTitle: productTitle,
                timestamp: DateTime.now(),
                isRead: false,
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

              // Store in-app notification
              appNotification = AppNotification(
                id: '${productId}_${DateTime.now().millisecondsSinceEpoch}',
                type: 'price_drop',
                title: '📉 Price Drop!',
                message:
                    '$productTitle price dropped from $previousPrice to $currentPrice',
                productId: productId,
                productTitle: productTitle,
                timestamp: DateTime.now(),
                isRead: false,
              );
              notificationShown = true;
            }
          }

          // Store notification in local storage
          if (appNotification != null) {
            await _notificationStorage.addNotification(appNotification);
            await _loadUnreadCount();
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

  Future<void> _refreshAllProducts() async {
    if (_products.isEmpty) {
      await _refreshProducts();
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      int successCount = 0;
      int failCount = 0;
      List<String> errorMessages = [];

      // Get all product IDs
      final productIds = _products
          .map((p) => (p['id']?.toString() ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toList();

      if (productIds.isEmpty) {
        setState(() {
          _isRefreshing = false;
        });
        return;
      }

      // Refresh products in parallel batches (3 at a time to avoid overwhelming server)
      const batchSize = 3;
      for (int i = 0; i < productIds.length; i += batchSize) {
        final batch = productIds.skip(i).take(batchSize).toList();

        // Process batch in parallel
        final results = await Future.wait(
          batch.map((productId) async {
            try {
              print('🔄 Refreshing product: $productId');
              await _apiService.refreshProductPrice(productId);
              print('✅ Successfully refreshed product: $productId');
              return {'success': true, 'id': productId};
            } catch (e) {
              final errorMsg = e.toString();
              errorMessages.add(
                'Product $productId: ${errorMsg.length > 50 ? errorMsg.substring(0, 50) + "..." : errorMsg}',
              );
              print('❌ Failed to refresh product $productId: $e');
              return {'success': false, 'id': productId};
            }
          }),
          eagerError: false, // Don't stop on first error
        );

        // Count successes and failures
        for (var result in results) {
          if (result['success'] == true) {
            successCount++;
          } else {
            failCount++;
          }
        }

        // Small delay between batches (not between individual requests)
        if (i + batchSize < productIds.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // Refresh the product list to get updated prices
      await _fetchProducts();

      if (mounted) {
        String message = 'Refreshed $successCount products';
        if (failCount > 0) {
          message += ' ($failCount failed)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (failCount > 0 && errorMessages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessages.take(2).join('\n'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            backgroundColor: failCount > 0
                ? AppTheme.accentOrange
                : AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: Duration(seconds: failCount > 0 ? 4 : 2),
          ),
        );
      }
    } catch (e) {
      // Even if refresh fails, try to fetch updated products
      try {
        await _fetchProducts();
      } catch (fetchError) {
        print('Error fetching products: $fetchError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing products: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _handleDeleteWithUndo(Map<String, dynamic> productData) async {
    final productId = productData['id']?.toString() ?? '';

    // Delete all notifications related to this product
    await _notificationStorage.deleteNotificationsByProductId(productId);
    await _loadUnreadCount();

    // Store deleted product data for undo
    setState(() {
      _lastDeletedProduct = productData;
      _lastDeletedProductId = productId;

      // Optimistic UI update - remove from list immediately
      _products.removeWhere((p) => p['id']?.toString() == productId);
      _applyFilters();
    });

    // Show undo snackbar
    if (mounted) {
      // Dismiss any existing snackbars first
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Product deleted: ${productData['title']?.toString().substring(0, (productData['title']?.toString().length ?? 0) > 30 ? 30 : (productData['title']?.toString().length ?? 0)) ?? 'Product'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () async {
              await _undoDelete();
            },
          ),
        ),
      );
    }
  }

  Future<void> _undoDelete() async {
    if (_lastDeletedProduct == null || _lastDeletedProductId == null) {
      return;
    }

    try {
      // Restore product using fast restore endpoint
      final productData = _lastDeletedProduct!;

      if (productData['url']?.toString().isEmpty ?? true) {
        throw Exception('Cannot restore: Product URL is missing');
      }

      // Dismiss undo snackbar
      ScaffoldMessenger.of(context).clearSnackBars();

      // Show restoring message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Restoring product...'),
            ],
          ),
          backgroundColor: AppTheme.accentBlue,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      // Restore product using fast restore endpoint (no scraping)
      final restoredProduct = await _apiService.restoreProduct(productData);

      // Optimistic UI update - add product back immediately
      setState(() {
        _products.insert(0, restoredProduct);
        _applyFilters();
      });

      // Refresh in background to ensure sync
      _fetchProducts().catchError((e) {
        print('Background refresh error: $e');
      });

      // Clear undo data
      setState(() {
        _lastDeletedProduct = null;
        _lastDeletedProductId = null;
      });

      if (mounted) {
        // Dismiss restoring snackbar
        ScaffoldMessenger.of(context).clearSnackBars();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Product restored successfully'),
              ],
            ),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Clear undo data on error
      setState(() {
        _lastDeletedProduct = null;
        _lastDeletedProductId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedProductIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Selected Products?'),
        content: Text(
          'Are you sure you want to delete ${_selectedProductIds.length} product(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Optimistic UI update - remove products immediately
    final deletedIds = Set<String>.from(_selectedProductIds);
    final deletedCount = deletedIds.length;

    // Delete all notifications related to these products
    for (var productId in deletedIds) {
      await _notificationStorage.deleteNotificationsByProductId(productId);
    }
    await _loadUnreadCount();

    setState(() {
      _products.removeWhere((p) => deletedIds.contains(p['id']?.toString()));
      _applyFilters();
      _selectedProductIds.clear();
      _isSelectionMode = false;
    });

    // Show immediate feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $deletedCount products'),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Delete in background (non-blocking)
    for (var productId in deletedIds) {
      _apiService.deleteProduct(productId).catchError((e) {
        print('Failed to delete product $productId: $e');
        // If delete fails, refresh to restore the product
        if (mounted) {
          _fetchProducts();
        }
      });
    }

    // Refresh product list in background to sync
    _fetchProducts().catchError((e) {
      print('Background refresh error: $e');
    });
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
        _minPrice != null ||
        _maxPrice != null ||
        _showOnlyWithThreshold ||
        _sortBy != 'dateAdded' ||
        _sortAscending;
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close, size: 18),
        backgroundColor: AppTheme.secondaryDark,
        labelStyle: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: AppTheme.secondaryDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.glassBorder, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filter & Sort',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sort Section
                      Text(
                        'Sort By',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      RadioListTile<String>(
                        title: const Text('Date Added'),
                        value: 'dateAdded',
                        groupValue: _sortBy,
                        onChanged: (value) {
                          setState(() {
                            _sortBy = value!;
                          });
                          setDialogState(() {});
                          _applyFilters();
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      RadioListTile<String>(
                        title: const Text('Price'),
                        value: 'price',
                        groupValue: _sortBy,
                        onChanged: (value) {
                          setState(() {
                            _sortBy = value!;
                          });
                          setDialogState(() {});
                          _applyFilters();
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      RadioListTile<String>(
                        title: const Text('Name'),
                        value: 'name',
                        groupValue: _sortBy,
                        onChanged: (value) {
                          setState(() {
                            _sortBy = value!;
                          });
                          setDialogState(() {});
                          _applyFilters();
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      CheckboxListTile(
                        title: const Text('Ascending'),
                        value: _sortAscending,
                        onChanged: (value) {
                          setState(() {
                            _sortAscending = value ?? false;
                          });
                          setDialogState(() {});
                          _applyFilters();
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      const SizedBox(height: 24),
                      // Price Range Filter
                      Text(
                        'Price Range',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(
                                text: _minPrice?.toStringAsFixed(0) ?? '',
                              ),
                              decoration: InputDecoration(
                                labelText: 'Min Price (₹)',
                                hintText: '0',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                setState(() {
                                  _minPrice = value.isEmpty
                                      ? null
                                      : double.tryParse(value);
                                });
                                setDialogState(() {});
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(
                                text: _maxPrice?.toStringAsFixed(0) ?? '',
                              ),
                              decoration: InputDecoration(
                                labelText: 'Max Price (₹)',
                                hintText: '100000',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                setState(() {
                                  _maxPrice = value.isEmpty
                                      ? null
                                      : double.tryParse(value);
                                });
                                setDialogState(() {});
                                _applyFilters();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Threshold Filter
                      CheckboxListTile(
                        title: const Text('Show only products with threshold'),
                        value: _showOnlyWithThreshold,
                        onChanged: (value) {
                          setState(() {
                            _showOnlyWithThreshold = value ?? false;
                          });
                          setDialogState(() {});
                          _applyFilters();
                        },
                        activeColor: AppTheme.accentBlue,
                      ),
                      const SizedBox(height: 24),
                      // Clear Filters Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _minPrice = null;
                              _maxPrice = null;
                              _showOnlyWithThreshold = false;
                              _sortBy = 'dateAdded';
                              _sortAscending = false;
                            });
                            setDialogState(() {});
                            _applyFilters();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentRed,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Clear All Filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: WillPopScope(
        onWillPop: () async {
          // Unfocus search bar when back button is pressed
          if (_searchFocusNode.hasFocus) {
            _searchFocusNode.unfocus();
            return false; // Prevent default back action
          }
          return true; // Allow default back action
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: false,
          appBar: GlassAppBar(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accentBlue.withOpacity(0.3),
                        AppTheme.accentPurple.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.accentBlue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.trending_down_rounded,
                    color: AppTheme.accentBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.accentBlue, AppTheme.accentPurple],
                  ).createShader(bounds),
                  child: const Text(
                    'PricePulse',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_isSelectionMode)
                _GlassAppBarIconButton(
                  icon: Icons.close_rounded,
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedProductIds.clear();
                    });
                  },
                  tooltip: 'Cancel Selection',
                )
              else ...[
                // Notification icon with badge
                _GlassAppBarIconButton(
                  icon: Icons.notifications_rounded,
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsScreen(),
                      ),
                    );
                    // Reload unread count when returning
                    if (result == true || mounted) {
                      await _loadUnreadCount();
                    }
                  },
                  tooltip: 'Notifications',
                  badge: _unreadNotificationCount > 0
                      ? _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount'
                      : null,
                ),
                _GlassAppBarIconButton(
                  icon: Icons.filter_list_rounded,
                  onPressed: _showFilterDialog,
                  tooltip: 'Filter & Sort',
                ),
                _GlassAppBarIconButton(
                  icon: Icons.refresh_rounded,
                  onPressed: _isRefreshing ? null : _refreshAllProducts,
                  tooltip: 'Refresh All',
                  child: _isRefreshing
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
                      : null,
                ),
              ],
              if (_isSelectionMode && _selectedProductIds.isNotEmpty)
                _GlassAppBarIconButton(
                  icon: Icons.delete_outline_rounded,
                  onPressed: _bulkDelete,
                  tooltip: 'Delete Selected',
                ),
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
                : Column(
                    children: [
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: GlassContainer(
                          padding: EdgeInsets.zero,
                          borderRadius: 16,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            enabled: !_isSelectionMode,
                            decoration: InputDecoration(
                              hintText: _isSelectionMode
                                  ? 'Selection mode active'
                                  : 'Search products...',
                              hintStyle: TextStyle(
                                color: _isSelectionMode
                                    ? AppTheme.textTertiary
                                    : AppTheme.textSecondary,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _isSelectionMode
                                    ? AppTheme.textTertiary
                                    : AppTheme.textSecondary,
                              ),
                              suffixIcon:
                                  _searchQuery.isNotEmpty && !_isSelectionMode
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: AppTheme.textSecondary,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              filled: true,
                              fillColor: Colors.transparent,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            style: TextStyle(
                              color: _isSelectionMode
                                  ? AppTheme.textTertiary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      // Filter chips
                      if (_hasActiveFilters())
                        Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              if (_searchQuery.isNotEmpty)
                                _buildFilterChip('Search: $_searchQuery', () {
                                  _searchController.clear();
                                }),
                              if (_minPrice != null || _maxPrice != null)
                                _buildFilterChip('Price Filter', () {
                                  setState(() {
                                    _minPrice = null;
                                    _maxPrice = null;
                                  });
                                  _applyFilters();
                                }),
                              if (_showOnlyWithThreshold)
                                _buildFilterChip('With Threshold', () {
                                  setState(() {
                                    _showOnlyWithThreshold = false;
                                  });
                                  _applyFilters();
                                }),
                              if (_sortBy != 'dateAdded' || _sortAscending)
                                _buildFilterChip('Sorted', () {
                                  setState(() {
                                    _sortBy = 'dateAdded';
                                    _sortAscending = false;
                                  });
                                  _applyFilters();
                                }),
                            ],
                          ),
                        ),
                      // Products List
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshProducts,
                          color: AppTheme.accentBlue,
                          backgroundColor: AppTheme.secondaryDark,
                          child:
                              _filteredProducts.isEmpty && _hasActiveFilters()
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: GlassContainer(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 64,
                                            color: AppTheme.textTertiary,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No products match your filters',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Try adjusting your search or filters',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = _filteredProducts[index];

                                    // Get product ID - ensure it's a string
                                    final productId =
                                        (product['id']?.toString() ?? '')
                                            .trim();

                                    if (productId.isEmpty) {
                                      print(
                                        '⚠️ CRITICAL: Product at index $index has NO ID!',
                                      );
                                      print(
                                        '   Product keys: ${product.keys.toList()}',
                                      );
                                      print('   Product data: $product');
                                      // Skip this product
                                      return const SizedBox.shrink();
                                    }

                                    final isSelected = _selectedProductIds
                                        .contains(productId);

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: Stack(
                                        children: [
                                          ProductCard(
                                            id: productId,
                                            title:
                                                product['title']?.toString() ??
                                                'Unknown',
                                            price:
                                                product['price']?.toString() ??
                                                'N/A',
                                            image:
                                                product['image']?.toString() ??
                                                '',
                                            url:
                                                product['url']?.toString() ??
                                                '',
                                            lastChecked:
                                                product['lastChecked']
                                                    ?.toString() ??
                                                '',
                                            priceHistory:
                                                product['priceHistory'] ?? [],
                                            thresholdPrice:
                                                product['thresholdPrice'] !=
                                                    null
                                                ? (product['thresholdPrice']
                                                          as num)
                                                      .toDouble()
                                                : null,
                                            onDelete: () => _fetchProducts(),
                                            onLongPress: () {
                                              if (!_isSelectionMode) {
                                                setState(() {
                                                  _isSelectionMode = true;
                                                  _selectedProductIds.add(
                                                    productId,
                                                  );
                                                });
                                              }
                                            },
                                            isSelectionMode: _isSelectionMode,
                                            onDeleteWithUndo: (productData) {
                                              _handleDeleteWithUndo(
                                                productData,
                                              );
                                            },
                                            onSelectToggle: _isSelectionMode
                                                ? (productId) {
                                                    setState(() {
                                                      if (_selectedProductIds
                                                          .contains(
                                                            productId,
                                                          )) {
                                                        _selectedProductIds
                                                            .remove(productId);
                                                      } else {
                                                        _selectedProductIds.add(
                                                          productId,
                                                        );
                                                      }
                                                    });
                                                  }
                                                : null,
                                          ),
                                          if (_isSelectionMode)
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    if (isSelected) {
                                                      _selectedProductIds
                                                          .remove(productId);
                                                    } else {
                                                      _selectedProductIds.add(
                                                        productId,
                                                      );
                                                    }
                                                  });
                                                },
                                                child: Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? AppTheme.accentBlue
                                                        : Colors.transparent,
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? AppTheme.accentBlue
                                                          : AppTheme
                                                                .textSecondary,
                                                      width: 2,
                                                    ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: isSelected
                                                      ? Icon(
                                                          Icons.check_rounded,
                                                          color: Colors.white,
                                                          size: 16,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
          floatingActionButton: GlassFloatingActionButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddProductScreen(),
                  fullscreenDialog: true,
                ),
              );
              if (result != null) {
                // If result is product data, create notification immediately
                if (result is Map<String, dynamic> && result['id'] != null) {
                  final notification = AppNotification(
                    id: '${result['id']}_${DateTime.now().millisecondsSinceEpoch}',
                    type: 'product_added',
                    title: '✅ Product Added',
                    message:
                        '${result['title'] ?? 'Product'} is now being tracked',
                    productId: result['id']?.toString() ?? '',
                    productTitle: result['title']?.toString(),
                    timestamp: DateTime.now(),
                    isRead: false,
                  );
                  await _notificationStorage.addNotification(notification);
                  await _loadUnreadCount();

                  // Add product to local list immediately (optimistic update)
                  setState(() {
                    _products.insert(0, result);
                    _applyFilters();
                  });
                }

                // Refresh products list in background (non-blocking, don't await)
                // This ensures we have the latest data but doesn't block the UI
                _fetchProducts().catchError((e) {
                  print('Background refresh error: $e');
                });
              }
            },
            icon: Icons.add_rounded,
            label: 'Track Product',
            isExtended: true,
          ),
        ),
      ),
    );
  }
}

// Glassmorphism Icon Button for AppBar
class _GlassAppBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? badge;
  final Widget? child;

  const _GlassAppBarIconButton({
    Key? key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.badge,
    this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      child ??
                          Icon(
                            icon,
                            color: onPressed == null
                                ? AppTheme.textTertiary
                                : AppTheme.textPrimary,
                            size: 22,
                          ),
                      if (badge != null)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.accentRed,
                                  AppTheme.accentRed.withOpacity(0.8),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentRed.withOpacity(0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
