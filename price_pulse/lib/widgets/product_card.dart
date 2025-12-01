import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../screens/product_detail_screen.dart';
import '../utils/price_formatter.dart';

class ProductCard extends StatefulWidget {
  final String id;
  final String title;
  final String price;
  final String image;
  final String url;
  final String lastChecked;
  final List<dynamic> priceHistory;
  final double? thresholdPrice;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final Function(Map<String, dynamic>)? onDeleteWithUndo;
  final Function(String)? onSelectToggle;

  const ProductCard({
    Key? key,
    required this.id,
    required this.title,
    required this.price,
    required this.image,
    required this.url,
    required this.lastChecked,
    required this.priceHistory,
    this.thresholdPrice,
    required this.onDelete,
    this.onLongPress,
    this.isSelectionMode = false,
    this.onDeleteWithUndo,
    this.onSelectToggle,
  }) : super(key: key);

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _showDetails = false;

  // Get short title (first 4 words)
  String _getShortTitle(String title) {
    final words = title.trim().split(' ');
    if (words.length <= 5) {
      return title;
    }
    return words.take(5).join(' ');
  }

  // Parse price to number for comparison
  double? _parsePrice(String priceStr) {
    try {
      // Remove currency symbols and commas
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

  // Get price change indicator
  Widget _getPriceChangeIndicator() {
    if (widget.priceHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentPrice = _parsePrice(widget.price);
    if (currentPrice == null) return const SizedBox.shrink();

    // Get the oldest price from history
    final historyPrices = widget.priceHistory
        .map((entry) => _parsePrice(entry['price'] ?? ''))
        .where((p) => p != null)
        .toList();

    if (historyPrices.isEmpty) return const SizedBox.shrink();

    final oldestPrice = historyPrices.first;
    if (oldestPrice == null) return const SizedBox.shrink();

    final difference = currentPrice - oldestPrice;
    final percentChange = (difference / oldestPrice * 100);

    if (difference == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_rounded, size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            'No change',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final isIncrease = difference > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isIncrease ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 16,
          color: isIncrease ? AppTheme.accentRed : AppTheme.accentGreen,
        ),
        const SizedBox(width: 4),
        Text(
          '${isIncrease ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
          style: TextStyle(
            color: isIncrease ? AppTheme.accentRed : AppTheme.accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Product?'),
        content: const Text(
          'Are you sure you want to stop tracking this product?',
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

    if (confirmed == true) {
      try {
        final productId = widget.id.trim();

        if (productId.isEmpty) {
          throw Exception('Product ID is invalid or empty');
        }

        // Store product data for undo before deletion
        final productData = {
          'id': widget.id,
          'title': widget.title,
          'price': widget.price,
          'image': widget.image,
          'url': widget.url,
          'lastChecked': widget.lastChecked,
          'priceHistory': widget.priceHistory,
          'thresholdPrice': widget.thresholdPrice,
        };

        print('🗑️ Deleting product: "$productId"');
        final apiService = ApiService();
        await apiService.deleteProduct(productId);

        if (mounted) {
          // Call onDeleteWithUndo if provided, otherwise use regular onDelete
          if (widget.onDeleteWithUndo != null) {
            widget.onDeleteWithUndo!(productData);
          } else {
            // Small delay to ensure backend has processed the delete
            await Future.delayed(const Duration(milliseconds: 500));
            widget.onDelete(); // Refresh the list
          }
        }
      } catch (e) {
        print('❌ Delete error: $e');
        if (mounted) {
          String errorMsg = e.toString().replaceAll('Exception: ', '');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMsg,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.accentRed,
              behavior: SnackBarBehavior.floating,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM d, y').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image and Info - tappable for navigation or selection
                Expanded(
                  child: GestureDetector(
                    onLongPress: widget.isSelectionMode
                        ? null
                        : widget.onLongPress,
                    onTap:
                        widget.isSelectionMode && widget.onSelectToggle != null
                        ? () {
                            widget.onSelectToggle!(widget.id);
                          }
                        : null,
                    child: InkWell(
                      onTap: widget.isSelectionMode
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailScreen(
                                    id: widget.id,
                                    title: widget.title,
                                    price: widget.price,
                                    image: widget.image,
                                    url: widget.url,
                                    lastChecked: widget.lastChecked,
                                    priceHistory: widget.priceHistory,
                                    thresholdPrice: widget.thresholdPrice,
                                  ),
                                ),
                              ).then((shouldRefresh) {
                                if (shouldRefresh == true) {
                                  widget
                                      .onDelete(); // Refresh on return if threshold was updated
                                }
                              });
                            },
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: widget.image.isNotEmpty
                                ? Image.network(
                                    widget.image,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (
                                          context,
                                          error,
                                          stackTrace,
                                        ) => Container(
                                          width: 80,
                                          height: 80,
                                          color: AppTheme.secondaryDark,
                                          child: Icon(
                                            Icons.image_not_supported_rounded,
                                            color: AppTheme.textTertiary,
                                          ),
                                        ),
                                  )
                                : Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryDark,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.shopping_bag_rounded,
                                      color: AppTheme.textTertiary,
                                      size: 40,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          // Product Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getShortTitle(widget.title),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      PriceFormatter.formatPrice(widget.price),
                                      style: TextStyle(
                                        color: AppTheme.accentGreen,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _getPriceChangeIndicator(),
                                  ],
                                ),
                                // Show threshold indicator if set
                                if (widget.thresholdPrice != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.notifications_active_rounded,
                                        size: 14,
                                        color: AppTheme.accentBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Alert: ${PriceFormatter.formatNumber(widget.thresholdPrice!)}',
                                        style: TextStyle(
                                          color: AppTheme.accentBlue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 12,
                                      color: AppTheme.textTertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate(widget.lastChecked),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Action buttons column - moved below to make space for product name
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Delete button - moved a little below
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppTheme.accentRed.withOpacity(0.8),
                        ),
                        onPressed: widget.isSelectionMode
                            ? null
                            : () {
                                _deleteProduct();
                              },
                        tooltip: 'Delete',
                      ),
                    ),
                    // Visit Product button - below delete
                    IconButton(
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        color: AppTheme.accentBlue.withOpacity(0.8),
                      ),
                      onPressed: widget.isSelectionMode
                          ? null
                          : () async {
                              try {
                                String urlToLaunch = widget.url.trim();

                                // Ensure URL has protocol
                                if (!urlToLaunch.startsWith('http://') &&
                                    !urlToLaunch.startsWith('https://')) {
                                  urlToLaunch = 'https://$urlToLaunch';
                                }

                                // Ensure Flipkart URLs are properly formatted
                                if (urlToLaunch.contains('flipkart.com')) {
                                  // Replace any flipkart.com with www.flipkart.com (unless it's dl.flipkart.com)
                                  if (!urlToLaunch.contains(
                                        'www.flipkart.com',
                                      ) &&
                                      !urlToLaunch.contains(
                                        'dl.flipkart.com',
                                      ) &&
                                      !urlToLaunch.contains('m.flipkart.com')) {
                                    urlToLaunch = urlToLaunch.replaceAll(
                                      'flipkart.com',
                                      'www.flipkart.com',
                                    );
                                  }
                                }

                                print('Launching URL: $urlToLaunch');
                                final uri = Uri.parse(urlToLaunch);

                                // Try to launch directly - canLaunchUrl sometimes fails for valid URLs
                                try {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } catch (launchError) {
                                  // If direct launch fails, try with canLaunchUrl check
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    throw Exception('URL cannot be launched');
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Could not open URL. Please check your internet connection.',
                                      ),
                                      backgroundColor: AppTheme.accentRed,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                                print('Error launching URL: $e');
                                print('Original URL: ${widget.url}');
                              }
                            },
                      tooltip: 'Visit Product',
                    ),
                    // Share Product button - below visit product
                    IconButton(
                      icon: Icon(
                        Icons.share_rounded,
                        color: AppTheme.accentPurple.withOpacity(0.8),
                      ),
                      onPressed: widget.isSelectionMode
                          ? null
                          : () async {
                              try {
                                String urlToShare = widget.url.trim();

                                // Ensure URL has protocol
                                if (!urlToShare.startsWith('http://') &&
                                    !urlToShare.startsWith('https://')) {
                                  urlToShare = 'https://$urlToShare';
                                }

                                // Ensure Flipkart URLs are properly formatted
                                if (urlToShare.contains('flipkart.com')) {
                                  if (!urlToShare.contains(
                                        'www.flipkart.com',
                                      ) &&
                                      !urlToShare.contains('dl.flipkart.com') &&
                                      !urlToShare.contains('m.flipkart.com')) {
                                    urlToShare = urlToShare.replaceAll(
                                      'flipkart.com',
                                      'www.flipkart.com',
                                    );
                                  }
                                }

                                final shareText =
                                    'Check out this product: ${widget.title}\n$urlToShare';

                                print('📤 Attempting to share: $shareText');

                                // Try Share.shareUri first (better for URLs), then fallback to text
                                try {
                                  final uri = Uri.parse(urlToShare);
                                  await Share.shareUri(uri);
                                  print('✅ Share successful (URI)');
                                } catch (uriError) {
                                  // Fallback to text sharing if URI sharing fails
                                  print(
                                    '⚠️ URI share failed, trying text share: $uriError',
                                  );
                                  try {
                                    await Share.share(
                                      shareText,
                                      subject: widget.title,
                                    );
                                    print('✅ Share successful (text)');
                                  } catch (textError) {
                                    print(
                                      '❌ Text share also failed: $textError',
                                    );
                                    throw textError;
                                  }
                                }

                                // Success - no error shown (user may have cancelled, which is fine)
                              } catch (e) {
                                print('❌ Error sharing product: $e');
                                print('Error type: ${e.runtimeType}');

                                // Show error only for actual failures
                                if (mounted) {
                                  final errorStr = e.toString().toLowerCase();
                                  // Don't show error for user cancellation
                                  if (!errorStr.contains('cancelled') &&
                                      !errorStr.contains('dismissed') &&
                                      !errorStr.contains('user') &&
                                      !errorStr.contains('platform')) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not share product. Please try again.',
                                        ),
                                        backgroundColor: AppTheme.accentRed,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                      tooltip: 'Share Product',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Expandable details section
          if (widget.priceHistory.isNotEmpty && !widget.isSelectionMode)
            InkWell(
              onTap: () {
                setState(() {
                  _showDetails = !_showDetails;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.glassBorder, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Price History (${widget.priceHistory.length})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Icon(
                      _showDetails
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          // Price history list
          if (_showDetails && widget.priceHistory.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.priceHistory.length,
                itemBuilder: (context, index) {
                  final entry = widget.priceHistory[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: AppTheme.glassBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          PriceFormatter.formatPrice(entry['price'] ?? 'N/A'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          _formatDate(entry['date'] ?? ''),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
