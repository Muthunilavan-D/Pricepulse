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
      print('Fetching products from: $baseUrl/get-products');
      final response = await http
          .get(Uri.parse('$baseUrl/get-products'))
          .timeout(const Duration(seconds: 10));

      print('Get products response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final products = json.decode(response.body) as List;
        print('✅ Fetched ${products.length} products');
        // Debug: Log first product's ID structure
        if (products.isNotEmpty) {
          print('Sample product ID: "${products[0]['id']}" (type: ${products[0]['id'].runtimeType})');
        }
        return products;
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

  Future<Map<String, dynamic>> trackProduct(String url, {double? thresholdPrice}) async {
    try {
      final body = <String, dynamic>{'url': url.trim()};
      if (thresholdPrice != null) {
        body['thresholdPrice'] = thresholdPrice;
      }
      
      print('Tracking product: url=$url, threshold=$thresholdPrice');
      final response = await http
          .post(
            Uri.parse('$baseUrl/track-product'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30)); // Scraping can take time

      print('Track product response status: ${response.statusCode}');
      print('Track product response body: ${response.body}');

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
      
      // Return the product data including threshold
      try {
        final responseData = json.decode(response.body);
        return responseData['product'] ?? {};
      } catch (e) {
        return {};
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
      if (productId.isEmpty) {
        throw Exception('Product ID cannot be empty');
      }

      print('Refreshing product: $productId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/refresh-product'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'id': productId}),
          )
          .timeout(const Duration(seconds: 30));

      print('Refresh response status: ${response.statusCode}');
      print('Refresh response body: ${response.body}');

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
      if (productId.isEmpty || productId.trim().isEmpty) {
        throw Exception('Product ID cannot be empty');
      }

      final trimmedId = productId.trim();
      print('=== DELETE PRODUCT REQUEST ===');
      print('Product ID: "$trimmedId"');
      print('Product ID length: ${trimmedId.length}');
      print('Product ID bytes: ${trimmedId.codeUnits}');
      print('URL: $baseUrl/delete-product');
      print('Request body: ${json.encode({'id': trimmedId})}');

      final uri = Uri.parse('$baseUrl/delete-product');
      print('Full URI: $uri');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'id': trimmedId}),
          )
          .timeout(const Duration(seconds: 15));

      print('=== DELETE RESPONSE ===');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');
      print('Response Headers: ${response.headers}');

      if (response.statusCode == 200) {
        print('✅ Product deleted successfully');
        return;
      }

      // Handle different error status codes
      String errorMessage = 'Unknown error occurred';
      try {
        final errorData = json.decode(response.body);
        errorMessage = errorData['error'] ?? errorData['message'] ?? errorMessage;
      } catch (e) {
        if (response.statusCode == 404) {
          errorMessage = 'Product not found. It may have already been deleted.';
        } else if (response.statusCode == 400) {
          errorMessage = 'Invalid request. Please try again.';
        } else {
          errorMessage = 'Server error: ${response.statusCode}';
        }
      }
      throw Exception(errorMessage);
    } on http.ClientException catch (e) {
      throw Exception(
        'Network error: ${e.message}\n'
        'Make sure the backend server is running at $baseUrl',
      );
    } on SocketException catch (e) {
      throw Exception(
        'Cannot connect to backend server.\n'
        'Make sure the server is running at $baseUrl\n'
        'Run: cd backend && node index.js\n'
        'Error: ${e.message}',
      );
    } catch (e) {
      if (e.toString().contains('TimeoutException') || 
          e.toString().contains('Timeout')) {
        throw Exception(
          'Request timed out. The server may be slow or unresponsive.\n'
          'Please try again.',
        );
      }
      rethrow;
    }
  }

  Future<void> setThresholdPrice(String productId, double threshold) async {
    try {
      final trimmedId = productId.trim();
      
      if (trimmedId.isEmpty) {
        throw Exception('Product ID cannot be empty');
      }

      print('🔔 Setting threshold for product: "$trimmedId", threshold: $threshold');
      
      final response = await http
          .post(
            Uri.parse('$baseUrl/set-threshold'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'id': trimmedId,
              'threshold': threshold
            }),
          )
          .timeout(const Duration(seconds: 15));

      print('Set threshold response status: ${response.statusCode}');
      print('Set threshold response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Threshold set successfully');
        return;
      }

      // Handle errors
      String errorMessage = 'Unknown error occurred';
      try {
        final errorData = json.decode(response.body);
        errorMessage = errorData['error'] ?? errorMessage;
      } catch (e) {
        if (response.statusCode == 404) {
          errorMessage = 'Product not found';
        } else if (response.statusCode == 400) {
          errorMessage = 'Invalid request. Please check the threshold value.';
        } else {
          errorMessage = 'Server error: ${response.statusCode}';
        }
      }
      throw Exception(errorMessage);
    } on SocketException catch (e) {
      throw Exception(
        'Cannot connect to backend server.\n'
        'Make sure the server is running at $baseUrl\n'
        'Run: cd backend && node index.js\n'
        'Error: ${e.message}',
      );
    } catch (e) {
      if (e.toString().contains('TimeoutException') || 
          e.toString().contains('Timeout')) {
        throw Exception(
          'Request timed out. The server may be slow or unresponsive.\n'
          'Please try again.',
        );
      }
      rethrow;
    }
  }

  Future<void> removeThresholdPrice(String productId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/remove-threshold'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'id': productId}),
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
