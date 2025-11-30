import 'package:intl/intl.dart';

// Utility to format prices with rupee symbol
class PriceFormatter {
  // Ensure price string starts with ₹
  static String formatPrice(String price) {
    if (price.isEmpty) return '₹0';
    
    // Remove existing rupee symbols and clean
    String cleaned = price
        .replaceAll('₹', '')
        .replaceAll('Rs.', '')
        .replaceAll('Rs', '')
        .trim();
    
    // If it doesn't start with ₹, add it
    if (!cleaned.startsWith('₹')) {
      return '₹$cleaned';
    }
    
    return price;
  }
  
  // Format number to price string
  static String formatNumber(double price) {
    // Format with commas for thousands
    final formatter = NumberFormat('#,##,###');
    return '₹${formatter.format(price)}';
  }
}

