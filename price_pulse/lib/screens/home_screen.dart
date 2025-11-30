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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchProducts();
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

      // Refresh products sequentially with a small delay to avoid overwhelming the server
      for (var product in _products) {
        final productId = (product['id']?.toString() ?? '').trim();
        if (productId.isEmpty) {
          failCount++;
          continue;
        }

        try {
          print('🔄 Refreshing product: $productId');
          await _apiService.refreshProductPrice(productId);
          successCount++;
          print('✅ Successfully refreshed product: $productId');

          // Small delay between requests to avoid overwhelming the server
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          failCount++;
          final errorMsg = e.toString();
          errorMessages.add(
            'Product $productId: ${errorMsg.length > 50 ? errorMsg.substring(0, 50) + "..." : errorMsg}',
          );
          print('❌ Failed to refresh product $productId: $e');
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
    // Store deleted product data for undo
    setState(() {
      _lastDeletedProduct = productData;
      _lastDeletedProductId = productData['id']?.toString();
    });

    // Refresh product list
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchProducts();

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
      // Restore product using track-product endpoint
      final productData = _lastDeletedProduct!;
      final url = productData['url']?.toString() ?? '';
      final thresholdPrice = productData['thresholdPrice'];

      if (url.isEmpty) {
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

      // Restore product
      await _apiService.trackProduct(
        url,
        thresholdPrice: thresholdPrice != null
            ? (thresholdPrice as num).toDouble()
            : null,
      );

      // Refresh product list
      await _fetchProducts();

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

    setState(() {
      _isRefreshing = true;
    });

    try {
      int successCount = 0;
      int failCount = 0;

      for (var productId in _selectedProductIds) {
        try {
          await _apiService.deleteProduct(productId);
          successCount++;
        } catch (e) {
          failCount++;
          print('Failed to delete product $productId: $e');
        }
      }

      // Refresh the product list
      await _fetchProducts();

      // Clear selection
      setState(() {
        _selectedProductIds.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted $successCount products${failCount > 0 ? ' ($failCount failed)' : ''}',
            ),
            backgroundColor: failCount > 0
                ? AppTheme.accentOrange
                : AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting products: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
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
              if (_isSelectionMode)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedProductIds.clear();
                    });
                  },
                  tooltip: 'Cancel Selection',
                )
              else
                IconButton(
                  icon: const Icon(Icons.filter_list_rounded),
                  onPressed: _showFilterDialog,
                  tooltip: 'Filter & Sort',
                ),
              if (!_isSelectionMode)
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
                  onPressed: _isRefreshing ? null : _refreshAllProducts,
                  tooltip: 'Refresh All',
                ),
              if (_isSelectionMode && _selectedProductIds.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _bulkDelete,
                  tooltip: 'Delete Selected',
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
      ),
    );
  }
}
