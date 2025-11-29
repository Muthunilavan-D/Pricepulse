import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // 🔧 CONFIGURATION FOR PHYSICAL DEVICE:
  // Replace 'YOUR_COMPUTER_IP' with your actual IP address from ipconfig
  // Example: 'http://192.168.1.5:5000'
  static const String PHYSICAL_DEVICE_URL = 'http://192.168.31.248:5000';

  // Set this to true if using a physical device, false for emulator
  static const bool USE_PHYSICAL_DEVICE = true;

  String get baseUrl {
    if (USE_PHYSICAL_DEVICE) {
      return PHYSICAL_DEVICE_URL; // Physical device - UPDATE THIS!
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:5000'; // Android emulator
    } else {
      return 'http://localhost:5000'; // iOS simulator, web, etc.
    }
  }

  Future<List<dynamic>> getProducts() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/get-products'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
          'Cannot connect to backend server.\n'
          'Make sure the server is running at $baseUrl\n'
          'Run: cd backend && node index.js',
        );
      }
      rethrow;
    }
  }

  Future<void> trackProduct(String url) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/track-product'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'url': url.trim()}),
          )
          .timeout(const Duration(seconds: 30)); // Scraping can take time

      if (response.statusCode != 200) {
        String errorMessage = 'Unknown error occurred';
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
          'Cannot connect to backend server.\n'
          'Make sure the server is running at $baseUrl\n'
          'Run: cd backend && node index.js',
        );
      }
      if (e.toString().contains('TimeoutException')) {
        throw Exception(
          'Request timed out. The website may be slow or unresponsive.\n'
          'Please try again.',
        );
      }
      rethrow;
    }
  }

  Future<void> refreshProductPrice(String productId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/refresh-product'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'id': productId}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        String errorMessage = 'Unknown error occurred';
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
          'Cannot connect to backend server.\n'
          'Make sure the server is running at $baseUrl\n'
          'Run: cd backend && node index.js',
        );
      }
      if (e.toString().contains('TimeoutException')) {
        throw Exception(
          'Request timed out. The website may be slow or unresponsive.\n'
          'Please try again.',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/delete-product?id=$productId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        String errorMessage = 'Unknown error occurred';
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
          'Cannot connect to backend server.\n'
          'Make sure the server is running at $baseUrl\n'
          'Run: cd backend && node index.js',
        );
      }
      rethrow;
    }
  }
}
