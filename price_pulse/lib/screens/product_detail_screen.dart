import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../widgets/glassmorphism_widget.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/price_formatter.dart';

class ProductDetailScreen extends StatefulWidget {
  final String id;
  final String title;
  final String price;
  final String image;
  final String url;
  final String lastChecked;
  final List<dynamic> priceHistory;
  final double? thresholdPrice;

  const ProductDetailScreen({
    Key? key,
    required this.id,
    required this.title,
    required this.price,
    required this.image,
    required this.url,
    required this.lastChecked,
    required this.priceHistory,
    this.thresholdPrice,
  }) : super(key: key);

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  double? _thresholdPrice;
  final TextEditingController _thresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _thresholdPrice = widget.thresholdPrice;
    if (_thresholdPrice != null) {
      _thresholdController.text = _thresholdPrice!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  // Parse price to number
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

  Future<void> _setThreshold() async {
    final thresholdText = _thresholdController.text.trim();
    if (thresholdText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a threshold price'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final threshold = double.tryParse(thresholdText);
    if (threshold == null || threshold <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid price'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final currentPrice = _parsePrice(widget.price);
    if (currentPrice != null && threshold >= currentPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Threshold must be less than current price'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('Setting threshold: productId=${widget.id}, threshold=$threshold');
      await _apiService.setThresholdPrice(widget.id, threshold);
      setState(() {
        _thresholdPrice = threshold;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Threshold price set successfully!'),
              ],
            ),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        // Pop and refresh to show updated threshold
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('Exception: ')) {
          errorMsg = errorMsg.substring(11);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMsg'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
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

  Future<void> _removeThreshold() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.removeThresholdPrice(widget.id);
      setState(() {
        _thresholdPrice = null;
        _thresholdController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Threshold removed'),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, y • h:mm a').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildPriceChart() {
    if (widget.priceHistory.length < 2) {
      return GlassContainer(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Not enough data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Track this product for a while to see price trends',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Prepare chart data
    final chartData = widget.priceHistory.map((entry) {
      final price = _parsePrice(entry['price'] ?? '');
      final date = DateTime.tryParse(entry['date'] ?? '');
      return {'price': price, 'date': date};
    }).where((entry) => entry['price'] != null && entry['date'] != null).toList();

    if (chartData.length < 2) {
      return GlassContainer(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Not enough data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    final prices = chartData.map((e) => e['price'] as double).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    final chartMin = minPrice - (priceRange * 0.1);
    final chartMax = maxPrice + (priceRange * 0.1);

    final spots = chartData.asMap().entries.map((entry) {
      final index = entry.key.toDouble();
      final price = entry.value['price'] as double;
      return FlSpot(index, price);
    }).toList();

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price Trend',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_thresholdPrice != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentBlue, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_active, size: 16, color: AppTheme.accentBlue),
                      const SizedBox(width: 4),
                      Text(
                        PriceFormatter.formatNumber(_thresholdPrice!),
                        style: TextStyle(
                          color: AppTheme.accentBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (chartMax - chartMin) / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppTheme.glassBorder,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: (chartData.length / 4).ceil().toDouble(),
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= chartData.length) return const Text('');
                        final date = chartData[value.toInt()]['date'] as DateTime;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat('MMM d').format(date),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: (chartMax - chartMin) / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          PriceFormatter.formatNumber(value),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: AppTheme.glassBorder, width: 1),
                ),
                minX: 0,
                maxX: (chartData.length - 1).toDouble(),
                minY: chartMin,
                maxY: chartMax,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppTheme.accentBlue,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.accentBlue.withOpacity(0.1),
                    ),
                  ),
                  if (_thresholdPrice != null)
                    LineChartBarData(
                      spots: List.generate(
                        chartData.length,
                        (index) => FlSpot(index.toDouble(), _thresholdPrice!),
                      ),
                      isCurved: false,
                      color: AppTheme.accentGreen,
                      barWidth: 2,
                      dashArray: [5, 5],
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = _parsePrice(widget.price);
    final isThresholdReached = _thresholdPrice != null &&
        currentPrice != null &&
        currentPrice <= _thresholdPrice!;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Product Details'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product Info Card
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: widget.image.isNotEmpty
                            ? Image.network(
                                widget.image,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 100,
                                  height: 100,
                                  color: AppTheme.secondaryDark,
                                  child: Icon(
                                    Icons.image_not_supported_rounded,
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                              )
                            : Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryDark,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.shopping_bag_rounded,
                                  color: AppTheme.textTertiary,
                                  size: 50,
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              PriceFormatter.formatPrice(widget.price),
                              style: TextStyle(
                                color: AppTheme.accentGreen,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: AppTheme.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDate(widget.lastChecked),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Price Chart
                _buildPriceChart(),
                const SizedBox(height: 16),
                // Threshold Price Card
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
                            'Price Alert',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isThresholdReached)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.accentGreen, width: 2),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.accentGreen,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Price dropped below threshold!',
                                  style: TextStyle(
                                    color: AppTheme.accentGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_thresholdPrice != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryDark,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Threshold',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    PriceFormatter.formatNumber(_thresholdPrice!),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: AppTheme.accentBlue,
                                        ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: _isLoading ? null : _removeThreshold,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Remove'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.accentRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _thresholdController,
                          decoration: InputDecoration(
                            labelText: 'Set threshold price (₹)',
                            hintText: 'Enter price below current price',
                            prefixIcon: const Icon(Icons.attach_money_rounded),
                            helperText: currentPrice != null
                                ? 'Current price: ₹${currentPrice.toStringAsFixed(0)}'
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        GlassButton(
                          text: 'Set Alert',
                          icon: Icons.notifications_active_rounded,
                          onPressed: _isLoading ? null : _setThreshold,
                          isLoading: _isLoading,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'You\'ll be notified when the price drops to or below your threshold.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Price History List
                if (widget.priceHistory.isNotEmpty)
                  GlassContainer(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Price History',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        ...widget.priceHistory.reversed.take(10).map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
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
                        }).toList(),
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
}

