# Price Pulse - Complete Technical Documentation

## Table of Contents
1. [Overview](#overview)
2. [Project Structure](#project-structure)
3. [Architecture Overview](#architecture-overview)
4. [Features & Implementation](#features--implementation)
5. [UI Implementation](#ui-implementation)
6. [Backend Architecture](#backend-architecture)
7. [Dependencies](#dependencies)
8. [Data Flow](#data-flow)
9. [Adding New Features](#adding-new-features)
10. [Summary & Future Improvements](#summary--future-improvements)

---

## 1. Overview

### What is Price Pulse?

**Price Pulse** is a Flutter-based mobile application that helps users track product prices from e-commerce websites (primarily Amazon.in and Flipkart). The app monitors price changes, maintains price history, and sends notifications when prices drop or reach user-defined thresholds.

### Core Goals
- **Price Tracking**: Monitor product prices from Amazon and Flipkart
- **Price History**: Maintain historical price data for trend analysis
- **Smart Alerts**: Notify users when prices drop or reach their desired threshold
- **User Profiles**: Personalized experience with custom avatars and usernames
- **Real-time Updates**: Background price checking via backend cron jobs

---

## 2. Project Structure

```
price_pulse_pack/
├── price_pulse/                    # Flutter frontend application
│   ├── lib/
│   │   ├── main.dart              # App entry point & initialization
│   │   ├── firebase_options.dart   # Firebase configuration
│   │   ├── models/                 # Data models
│   │   │   └── notification_model.dart
│   │   ├── screens/                # UI screens
│   │   │   ├── home_screen.dart
│   │   │   ├── add_product_screen.dart
│   │   │   ├── product_detail_screen.dart
│   │   │   ├── profile_screen.dart
│   │   │   ├── notifications_screen.dart
│   │   │   └── auth/
│   │   │       └── login_screen.dart
│   │   ├── services/               # Business logic & API services
│   │   │   ├── api_service.dart
│   │   │   ├── auth_service.dart
│   │   │   ├── notification_service.dart
│   │   │   ├── notification_storage_service.dart
│   │   │   └── profile_service.dart
│   │   ├── widgets/                # Reusable UI components
│   │   │   ├── glassmorphism_widget.dart
│   │   │   ├── glass_app_bar.dart
│   │   │   ├── glass_snackbar.dart
│   │   │   ├── product_card.dart
│   │   │   └── skeleton_loader.dart
│   │   ├── theme/                  # App theming
│   │   │   └── app_theme.dart
│   │   └── utils/                  # Utility functions
│   │       └── price_formatter.dart
│   ├── assets/                     # Images, logos, avatars
│   ├── android/                    # Android-specific configuration
│   ├── ios/                        # iOS-specific configuration
│   └── pubspec.yaml                # Dependencies & assets
│
├── backend/                        # Node.js backend server
│   ├── index.js                   # Main server file
│   ├── package.json               # Backend dependencies
│   ├── serviceAccountKey.json     # Firebase Admin SDK credentials
│   └── DEPLOYMENT_GUIDE.md        # Deployment instructions
│
├── firestore.rules                 # Firestore security rules
└── README.md                      # Project documentation
```

### Folder Responsibilities

#### `lib/models/`
Contains data models representing app entities:
- **notification_model.dart**: Defines the `AppNotification` class with fields like `id`, `type`, `title`, `message`, `productId`, `timestamp`, `isRead`

#### `lib/screens/`
Contains all UI screens:
- **home_screen.dart**: Main screen displaying product list, search, filters
- **add_product_screen.dart**: Form to add new products via URL
- **product_detail_screen.dart**: Detailed view with price chart and history
- **profile_screen.dart**: User profile management
- **notifications_screen.dart**: Notification history
- **auth/login_screen.dart**: Google Sign-In authentication

#### `lib/services/`
Business logic and external API communication:
- **api_service.dart**: HTTP requests to backend server
- **auth_service.dart**: Firebase Authentication & Google Sign-In
- **notification_service.dart**: FCM & local notifications
- **notification_storage_service.dart**: Local notification storage (SharedPreferences)
- **profile_service.dart**: User profile CRUD operations

#### `lib/widgets/`
Reusable UI components:
- **glassmorphism_widget.dart**: GlassContainer, GlassButton (glassmorphism effect)
- **glass_app_bar.dart**: Custom app bar with glassmorphism
- **product_card.dart**: Product display card
- **skeleton_loader.dart**: Loading placeholders

#### `lib/theme/`
App-wide styling:
- **app_theme.dart**: Color palette, text styles, Material theme configuration

#### `lib/utils/`
Helper functions:
- **price_formatter.dart**: Price formatting utilities (₹ symbol, number formatting)

---

## 3. Architecture Overview

### Technology Stack

**Frontend (Flutter)**:
- **Language**: Dart 3.8.1+
- **State Management**: Built-in `setState` (no external state management library)
- **UI Framework**: Material Design 3 with custom glassmorphism theme
- **Backend Communication**: HTTP REST API via `http` package

**Backend (Node.js)**:
- **Runtime**: Node.js
- **Framework**: Express.js
- **Database**: Firebase Firestore
- **Web Scraping**: Axios + Cheerio
- **Scheduling**: Cron jobs for background price checks

**Cloud Services**:
- **Firebase Authentication**: Google Sign-In
- **Firebase Firestore**: Product & user data storage
- **Firebase Cloud Messaging (FCM)**: Push notifications
- **Firebase Admin SDK**: Backend Firestore access

### Architecture Pattern

The app follows a **Service-Oriented Architecture** with clear separation of concerns:

```
UI Layer (Screens/Widgets)
    ↓
Service Layer (API, Auth, Notification, Profile)
    ↓
Backend API (Node.js/Express)
    ↓
Firebase Services (Firestore, Auth, FCM)
```

### Data Storage Strategy

1. **Firebase Firestore**: Primary database for products, user profiles, price history
2. **SharedPreferences**: Local storage for notifications (last 100)
3. **No Hive**: The app does NOT use Hive - it uses Firestore for all persistent data

---

## 4. Features & Implementation

### 4.1 Product Tracking & Price History

#### Feature Description
Users can add products by pasting Amazon/Flipkart URLs. The app tracks price changes over time and maintains a history.

#### Technical Implementation

**Frontend Flow**:
1. User enters product URL in `AddProductScreen`
2. `ApiService.trackProduct()` sends POST request to backend
3. Backend scrapes product details (price, title, image)
4. Product saved to Firestore with `userId` for multi-user support
5. Frontend receives product data and navigates to `ProductDetailScreen`

**Code Snippet - Adding Product**:
```dart
// lib/services/api_service.dart
Future<Map<String, dynamic>> trackProduct(String url, {double? thresholdPrice}) async {
  final userId = _userId;
  if (userId == null) throw Exception('User not authenticated');

  final response = await http.post(
    Uri.parse('$baseUrl/track-product'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      'url': url,
      'userId': userId,
      'thresholdPrice': thresholdPrice,
    }),
  ).timeout(const Duration(seconds: 60));

  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to add product');
  }
}
```

**Backend Flow**:
1. Receives URL and `userId` from frontend
2. Resolves shortened URLs (amzn.in, dl.flipkart.com)
3. Scrapes product page using Cheerio
4. Extracts price, title, image using CSS selectors
5. Saves to Firestore `products` collection with structure:
   ```javascript
   {
     url: "https://amazon.in/dp/...",
     title: "Product Name",
     price: "₹1,23,456",
     image: "https://...",
     userId: "user123",
     priceHistory: [
       {price: "₹1,23,456", date: "2024-01-01T10:00:00Z"}
     ],
     thresholdPrice: 100000,
     lastChecked: "2024-01-01T10:00:00Z",
     isBought: false
   }
   ```

**Price History Storage**:
- Stored as array in Firestore document: `priceHistory: [{price, date}, ...]`
- Updated on each price check
- Displayed as line chart using `fl_chart` package

---

### 4.2 Price Drop Alerts

#### Feature Description
Users receive notifications when:
- Product price drops
- Price reaches user-defined threshold

#### Technical Implementation

**Notification Types**:
1. **Price Drop**: Automatic notification when price decreases
2. **Threshold Reached**: Notification when price ≤ threshold

**Backend Logic** (`backend/index.js`):
```javascript
async function checkThresholdAndNotify(productId, currentPrice, thresholdPrice, userId) {
  if (thresholdPrice && currentPrice <= thresholdPrice) {
    // Send FCM notification
    await sendNotificationToUser(userId, {
      title: '🎯 Price Threshold Reached!',
      body: `Your tracked product is now ₹${currentPrice}`,
      data: { productId, type: 'threshold_reached' }
    });
  }
}
```

**Frontend Notification Handling**:
1. **FCM Token Registration**: On app start, FCM token is registered with backend
2. **Foreground Messages**: Handled by `FirebaseMessaging.onMessage` listener
3. **Background Messages**: Handled by `_firebaseMessagingBackgroundHandler` (top-level function)
4. **Local Notifications**: Displayed using `flutter_local_notifications`

**Code Snippet - Notification Service**:
```dart
// lib/services/notification_service.dart
Future<void> initialize() async {
  // Request permissions
  await _requestPermissions();
  
  // Initialize local notifications
  await _localNotifications.initialize(initSettings, onDidReceiveNotificationResponse: _onNotificationTapped);
  
  // Handle foreground messages
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  
  // Register FCM token with backend
  final token = await _firebaseMessaging.getToken();
  if (token != null) {
    _registerTokenWithBackend(token);
  }
}
```

**Notification Storage**:
- Stored locally using `SharedPreferences`
- Maximum 100 notifications kept
- Sorted by timestamp (newest first)

---

### 4.3 Local Notification Storage

#### Feature Description
Notifications are stored locally for offline access and history viewing.

#### Technical Implementation

**Storage Service** (`lib/services/notification_storage_service.dart`):
- Uses `SharedPreferences` (key-value storage)
- Stores notifications as JSON strings
- Maximum 100 notifications (oldest removed when limit exceeded)

**Code Snippet**:
```dart
class NotificationStorageService {
  static const String _notificationsKey = 'app_notifications';
  static const int _maxNotifications = 100;

  Future<List<AppNotification>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsJson = prefs.getStringList(_notificationsKey) ?? [];
    
    return notificationsJson
        .map((json) => AppNotification.fromMap(jsonDecode(json)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> addNotification(AppNotification notification) async {
    final notifications = await getNotifications();
    notifications.insert(0, notification);
    
    if (notifications.length > _maxNotifications) {
      notifications.removeRange(_maxNotifications, notifications.length);
    }
    
    await _saveNotifications(notifications);
  }
}
```

**Note**: The app does NOT use Hive. All persistent data (except notifications) is stored in Firestore.

---

### 4.4 Adding New Products

#### Feature Description
Users can add products by pasting product URLs from Amazon or Flipkart.

#### Technical Implementation

**Screen**: `lib/screens/add_product_screen.dart`

**UI Components**:
- `TextField` for URL input
- `TextField` for optional threshold price
- `GlassButton` for submit action
- Validation for URL format

**Flow**:
1. User enters URL
2. Validates URL format (must contain "amazon" or "flipkart")
3. Calls `ApiService.trackProduct()`
4. Shows loading indicator
5. On success: Navigates to `ProductDetailScreen`
6. On error: Shows error snackbar

**Code Snippet**:
```dart
Future<void> _addProduct() async {
  if (_urlController.text.trim().isEmpty) {
    _showError('Please enter a product URL');
    return;
  }

  setState(() => _isLoading = true);

  try {
    final product = await _apiService.trackProduct(
      _urlController.text.trim(),
      thresholdPrice: _thresholdPrice,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(
            id: product['id'],
            title: product['title'],
            price: product['price'],
            image: product['image'],
            url: product['url'],
            lastChecked: product['lastChecked'],
            priceHistory: product['priceHistory'] ?? [],
            thresholdPrice: product['thresholdPrice'],
          ),
        ),
      );
    }
  } catch (e) {
    _showError(e.toString());
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

---

### 4.5 Product List Display

#### Feature Description
Home screen displays all tracked products in a grid/list view with search and filter capabilities.

#### Technical Implementation

**Screen**: `lib/screens/home_screen.dart`

**State Management**:
- Uses `StatefulWidget` with `setState`
- Maintains product list in `_products` list
- Loading state: `_isLoading`
- Search query: `_searchQuery`
- Filter state: `_selectedFilter`

**Data Fetching**:
```dart
Future<void> _fetchProducts() async {
  setState(() => _isLoading = true);
  
  try {
    final products = await _apiService.getProducts();
    setState(() {
      _products = products;
      _isLoading = false;
    });
  } catch (e) {
    setState(() => _isLoading = false);
    _showError(e.toString());
  }
}
```

**UI Components**:
- `GridView.builder`: Product grid display
- `ProductCard`: Custom card widget for each product
- `TextField`: Search input
- `GlassAppBar`: Custom app bar with logo and actions

**Filtering**:
- Filters by search query (title matching)
- Can filter by price range, date added, etc.

---

### 4.6 Product Detail Screen

#### Feature Description
Shows detailed product information including price chart, history, and threshold management.

#### Technical Implementation

**Screen**: `lib/screens/product_detail_screen.dart`

**Features**:
1. **Price Chart**: Line chart using `fl_chart` package
2. **Price History**: List of historical prices
3. **Threshold Management**: Set/edit price threshold
4. **Mark as Bought**: Remove product from tracking
5. **Open in Browser**: Launch product URL

**Price Chart Implementation**:
```dart
Widget _buildPriceChart() {
  // Prepare chart data from priceHistory
  final chartData = widget.priceHistory
      .map((entry) => {
            'price': _parsePrice(entry['price']),
            'date': DateTime.tryParse(entry['date']),
          })
      .where((entry) => entry['price'] != null && entry['date'] != null)
      .toList();

  // Calculate min/max for chart bounds
  final prices = chartData.map((e) => e['price'] as double).toList();
  final minPrice = prices.reduce((a, b) => a < b ? a : b);
  final maxPrice = prices.reduce((a, b) => a > b ? a : b);
  
  // Create FlSpot data points
  final spots = chartData.asMap().entries.map((entry) {
    return FlSpot(entry.key.toDouble(), entry.value['price'] as double);
  }).toList();

  return LineChart(
    LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppTheme.accentBlue,
          barWidth: 3,
        ),
      ],
      minY: chartMin,
      maxY: chartMax,
      // ... grid, titles, borders configuration
    ),
  );
}
```

**Threshold Management**:
- User can set/edit threshold price
- Backend checks threshold on each price update
- Notification sent when threshold reached

---

### 4.7 Profile Screen

#### Feature Description
User profile management with username and avatar selection.

#### Technical Implementation

**Screen**: `lib/screens/profile_screen.dart`

**Features**:
- Display user email, username, avatar
- Edit username
- Select avatar from 7 predefined avatars
- View statistics (products tracked, notifications)
- Logout functionality

**Profile Service** (`lib/services/profile_service.dart`):
```dart
class ProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<Map<String, dynamic>?> getUserProfile() async {
    final userId = _auth.currentUser?.uid;
    final doc = await _firestore.collection('userProfiles').doc(userId).get();
    
    if (doc.exists) {
      return doc.data();
    }
    
    // Create default profile if doesn't exist
    return await _createDefaultProfile(userId);
  }
  
  Future<void> updateUserProfile({String? username, int? avatarIndex}) async {
    await _firestore.collection('userProfiles').doc(userId).update({
      'username': username,
      'avatarIndex': avatarIndex,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
```

**Firestore Structure**:
```javascript
userProfiles/{userId} {
  username: "John Doe",
  avatarIndex: 2,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

---

### 4.8 Authentication

#### Feature Description
Google Sign-In authentication using Firebase Auth.

#### Technical Implementation

**Service**: `lib/services/auth_service.dart`

**Flow**:
1. User taps "Continue with Google" button
2. `AuthService.signInWithGoogle()` called
3. Google Sign-In flow initiated
4. Firebase credential created from Google token
5. User signed in to Firebase
6. Profile created/updated in Firestore
7. Navigate to `HomeScreen`

**Code Snippet**:
```dart
Future<UserCredential?> signInWithGoogle() async {
  final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
  if (googleUser == null) return null;

  final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    accessToken: googleAuth.accessToken,
    idToken: googleAuth.idToken,
  );

  return await _auth.signInWithCredential(credential);
}
```

**Auth Wrapper** (`lib/main.dart`):
- `AuthWrapper` widget listens to `FirebaseAuth.instance.userChanges()`
- Shows `LoginScreen` if user is null
- Shows `HomeScreen` if user is authenticated

---

## 5. UI Implementation

### 5.1 Design System

**Theme**: Dark glassmorphism design with neon accents

**Color Palette** (`lib/theme/app_theme.dart`):
```dart
static const Color primaryDark = Color.fromARGB(255, 25, 52, 82);
static const Color secondaryDark = Color.fromARGB(255, 17, 34, 60);
static const Color accentBlue = Color(0xFF4A90E2);
static const Color accentPurple = Color(0xFF9B59B6);
static const Color accentGreen = Color(0xFF2ECC71);
static const Color accentRed = Color(0xFFE74C3C);
```

### 5.2 Glassmorphism Widgets

**GlassContainer** (`lib/widgets/glassmorphism_widget.dart`):
- Uses `BackdropFilter` with `ImageFilter.blur`
- Semi-transparent background
- Border with glass effect
- Customizable blur, padding, border radius

**Implementation**:
```dart
class GlassContainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppTheme.glassBorder, width: borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassBackground,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

### 5.3 Navigation

**Navigation Method**: `Navigator.push()` / `Navigator.pushReplacement()`

**No Navigation Package**: Uses Flutter's built-in navigation

**Example**:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ProductDetailScreen(...),
  ),
);
```

### 5.4 User Input & Validation

**URL Validation**:
- Checks if URL contains "amazon" or "flipkart"
- Validates URL format
- Shows error messages via `GlassSnackBar`

**Threshold Price Validation**:
- Must be numeric
- Must be > 0
- Backend validates: must be at least 40% of current price

---

## 6. Backend Architecture

### 6.1 Server Setup

**Technology**: Node.js + Express.js

**Main File**: `backend/index.js`

**Dependencies**:
- `express`: Web server framework
- `axios`: HTTP client for web scraping
- `cheerio`: HTML parsing (jQuery-like)
- `firebase-admin`: Firestore access from backend
- `cors`: Cross-origin resource sharing
- `node-cron`: Scheduled tasks (optional, uses cron-job.org)

### 6.2 API Endpoints

#### `POST /track-product`
- **Purpose**: Add new product to tracking
- **Request Body**: `{url, userId, thresholdPrice?}`
- **Response**: Product data with ID
- **Process**:
  1. Resolve shortened URLs
  2. Scrape product page
  3. Extract price, title, image
  4. Save to Firestore
  5. Return product data

#### `GET /get-products?userId=xxx`
- **Purpose**: Fetch all products for a user
- **Response**: Array of product objects
- **Filters**: Excludes products marked as `isBought: true`

#### `GET /get-product/:id?userId=xxx`
- **Purpose**: Get single product details
- **Response**: Product object with price history

#### `POST /mark-bought`
- **Purpose**: Mark product as bought
- **Request Body**: `{productId, userId}`
- **Action**: Sets `isBought: true` in Firestore

#### `POST /set-threshold`
- **Purpose**: Set/update price threshold
- **Request Body**: `{productId, userId, thresholdPrice}`
- **Validation**: Threshold must be ≥ 40% of current price

#### `GET /background-check`
- **Purpose**: Cron job endpoint for price updates
- **Process**:
  1. Fetch all active products
  2. Scrape current prices
  3. Update Firestore
  4. Check thresholds
  5. Send notifications if needed

#### `POST /register-fcm-token`
- **Purpose**: Register FCM token for push notifications
- **Request Body**: `{userId, fcmToken}`

### 6.3 Web Scraping Implementation

**Strategy**:
1. **URL Resolution**: Resolves shortened URLs (amzn.in, dl.flipkart.com)
2. **Session Establishment**: Pre-request to establish cookies (first-time success)
3. **Challenge Bypass**: Handles Amazon CAPTCHA/challenge pages
4. **Mobile-First**: Uses mobile URLs (m.amazon.in) for better success rate
5. **Price Extraction**: Prioritizes `apexPriceToPay` selector (final price, not MRP)
6. **Title Validation**: Filters out invalid titles (e.g., "Product gallery")

**Price Selectors (Priority Order)**:
```javascript
const priceSelectors = [
  '.apexPriceToPay .a-offscreen',  // Final price to pay (most accurate)
  '#corePriceDisplay_desktop_feature_div .a-price .a-offscreen',
  '#priceblock_ourprice',
  // ... more selectors
];
```

**Title Selectors**:
```javascript
const titleSelectors = [
  '#productTitle',  // Most reliable
  'span#productTitle',
  'h1.a-size-large span.a-size-large',
  // ... more selectors
];
```

### 6.4 Background Price Checking

**Cron Job Setup**:
- Uses external service (cron-job.org) to call `/background-check` endpoint
- Runs every 6 hours (configurable)
- Processes all products asynchronously
- Updates prices and sends notifications

**Implementation**:
```javascript
app.get('/background-check', async (req, res) => {
  // Respond immediately (don't wait for processing)
  res.json({ status: 'processing', startedAt: new Date().toISOString() });
  
  // Process in background
  (async () => {
    const products = await db.collection('products')
      .where('isBought', '==', false)
      .get();
    
    for (const doc of products.docs) {
      const newData = await scrapeProduct(doc.data().url);
      if (newData && newData.price) {
        await updateProductPrice(doc.id, newData.price, ...);
        await checkThresholdAndNotify(...);
      }
    }
  })();
});
```

---

## 7. Dependencies

### 7.1 Frontend Dependencies (`pubspec.yaml`)

#### Core Flutter
- `flutter`: SDK
- `cupertino_icons`: iOS-style icons

#### Firebase
- `firebase_core: ^3.15.2`: Firebase initialization
- `firebase_messaging: ^15.2.10`: Push notifications (FCM)
- `cloud_firestore: ^5.6.12`: NoSQL database
- `firebase_auth: ^5.7.0`: Authentication

#### Authentication
- `google_sign_in: ^6.2.1`: Google Sign-In

#### Notifications
- `flutter_local_notifications: ^19.3.1`: Local notifications
- `permission_handler: ^12.0.1`: Request notification permissions

#### Networking
- `http: ^1.4.0`: HTTP requests to backend

#### UI & Charts
- `fl_chart: ^0.69.0`: Price history charts
- `intl: ^0.19.0`: Date/number formatting

#### Utilities
- `device_info_plus: ^11.5.0`: Device information
- `url_launcher: ^6.3.1`: Open URLs in browser
- `shared_preferences: ^2.3.3`: Local key-value storage
- `share_plus: ^10.1.2`: Share functionality

### 7.2 Backend Dependencies (`package.json`)

- `express: ^5.1.0`: Web server
- `axios: ^1.11.0`: HTTP client
- `cheerio: ^1.1.2`: HTML parsing
- `firebase-admin: ^13.6.0`: Firestore access
- `cors: ^2.8.5`: CORS middleware
- `node-cron: ^4.2.1`: Cron scheduling (optional)

### 7.3 State Management

**Current**: No external state management library
- Uses `setState` in `StatefulWidget`
- Service classes are singletons (factory pattern)

**Future Consideration**: Could migrate to Riverpod or Provider for better state management

---

## 8. Data Flow

### 8.1 Adding a Product

```
User Input (URL)
    ↓
AddProductScreen._addProduct()
    ↓
ApiService.trackProduct()
    ↓
HTTP POST /track-product
    ↓
Backend: scrapeProduct()
    ↓
Backend: Save to Firestore
    ↓
Response: Product Data
    ↓
Navigate to ProductDetailScreen
```

### 8.2 Price Update Flow

```
Cron Job (every 6 hours)
    ↓
GET /background-check
    ↓
Backend: Fetch all products
    ↓
For each product: scrapeProduct()
    ↓
Update Firestore priceHistory
    ↓
Check threshold
    ↓
If threshold reached: Send FCM notification
    ↓
Frontend: Receive FCM message
    ↓
Show local notification
    ↓
Save to SharedPreferences
```

### 8.3 Authentication Flow

```
User taps "Continue with Google"
    ↓
AuthService.signInWithGoogle()
    ↓
Google Sign-In flow
    ↓
Firebase Auth: signInWithCredential()
    ↓
ProfileService: Create/update profile
    ↓
AuthWrapper: Listen to userChanges()
    ↓
Navigate to HomeScreen
```

---

## 9. Adding New Features

### 9.1 Architecture Support for Scalability

The current architecture supports adding new features through:

1. **Service Layer Pattern**: New features can add new services (e.g., `analytics_service.dart`)
2. **Modular Screens**: New screens can be added to `lib/screens/`
3. **Reusable Widgets**: Common UI patterns in `lib/widgets/`
4. **Firestore Collections**: Easy to add new collections (e.g., `userSettings`, `categories`)

### 9.2 Example: Adding Product Categories

**Step 1**: Add category field to product model
```dart
// In Firestore document
{
  category: "Electronics",
  // ... other fields
}
```

**Step 2**: Add category filter to HomeScreen
```dart
String? _selectedCategory;

Widget _buildCategoryFilter() {
  return DropdownButton<String>(
    value: _selectedCategory,
    onChanged: (value) {
      setState(() => _selectedCategory = value);
      _filterProducts();
    },
    items: ['All', 'Electronics', 'Fashion', 'Books'].map((cat) {
      return DropdownMenuItem(value: cat, child: Text(cat));
    }).toList(),
  );
}
```

**Step 3**: Update backend scraping to detect category
```javascript
// In scrapeProduct function
const category = detectCategoryFromPage($);
productData.category = category;
```

### 9.3 Example: Adding Price Prediction

**Step 1**: Create prediction service
```dart
// lib/services/prediction_service.dart
class PredictionService {
  Future<double?> predictFuturePrice(String productId) async {
    // Fetch price history
    // Calculate trend
    // Return predicted price
  }
}
```

**Step 2**: Add prediction widget to ProductDetailScreen
```dart
Widget _buildPredictionCard() {
  return FutureBuilder<double?>(
    future: _predictionService.predictFuturePrice(widget.id),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return GlassContainer(
          child: Text('Predicted price: ₹${snapshot.data}'),
        );
      }
      return CircularProgressIndicator();
    },
  );
}
```

### 9.4 Best Practices for New Features

1. **Follow Service Pattern**: Create service classes for business logic
2. **Use Firestore**: Store data in Firestore (not local storage)
3. **User-Specific Data**: Always include `userId` in queries
4. **Error Handling**: Use try-catch and show user-friendly errors
5. **Loading States**: Show loading indicators for async operations
6. **Validation**: Validate user input before API calls

---

## 10. Summary & Future Improvements

### 10.1 Architecture Strengths

✅ **Clear Separation of Concerns**
- UI, Services, and Backend are well-separated
- Easy to understand and maintain

✅ **Scalable Backend**
- Express.js handles multiple users
- Firestore scales automatically
- Background jobs for price updates

✅ **Modern UI Design**
- Glassmorphism theme is visually appealing
- Consistent design system
- Responsive layouts

✅ **Real-time Notifications**
- FCM for push notifications
- Local notifications for offline support
- Notification history stored locally

✅ **Multi-User Support**
- All data is user-specific (`userId` in queries)
- Secure with Firestore rules
- User profiles with customization

### 10.2 Possible Improvements

#### 1. State Management Migration
**Current**: `setState` in StatefulWidget
**Improvement**: Migrate to **Riverpod** or **Provider**
- Better state sharing across widgets
- Easier testing
- Less boilerplate code

**Example**:
```dart
// Using Riverpod
final productsProvider = FutureProvider<List<Product>>((ref) async {
  return await ApiService().getProducts();
});

// In widget
final products = ref.watch(productsProvider);
```

#### 2. Offline Support
**Current**: Requires internet for all operations
**Improvement**: Add local caching with **Hive** or **SQLite**
- Cache products locally
- Sync when online
- Better offline experience

#### 3. Analytics Integration
**Improvement**: Add **Firebase Analytics**
- Track user behavior
- Monitor app performance
- A/B testing capabilities

#### 4. Enhanced Price Charts
**Current**: Basic line chart
**Improvement**: 
- Add price prediction using ML
- Show price trends (increasing/decreasing)
- Compare prices across sellers

#### 5. Product Comparison
**Improvement**: Allow users to compare multiple products
- Side-by-side price comparison
- Feature comparison
- Best deal recommendations

#### 6. Wishlist Feature
**Improvement**: Add wishlist functionality
- Save products without tracking
- Organize by categories
- Share wishlists

#### 7. Price History Export
**Improvement**: Export price history as CSV/PDF
- Share with others
- Analyze in Excel
- Keep records

#### 8. Multi-Platform Support
**Current**: Android/iOS
**Improvement**: Add web and desktop support
- Flutter web for browser access
- Desktop apps for Windows/Mac/Linux

#### 9. Advanced Filtering
**Improvement**: Enhanced search and filters
- Filter by price range
- Filter by date added
- Sort by price, name, date
- Saved filter presets

#### 10. Social Features
**Improvement**: Add social elements
- Share price drops with friends
- Follow other users' tracked products
- Price drop alerts for friends

#### 11. Backend Improvements
**Improvement**: 
- Add Redis caching for faster responses
- Implement rate limiting
- Add API versioning
- GraphQL API for flexible queries

#### 12. Testing
**Improvement**: Add comprehensive testing
- Unit tests for services
- Widget tests for UI
- Integration tests for flows
- Backend API tests

### 10.3 Migration Path Example: Adding Riverpod

**Step 1**: Add dependency
```yaml
dependencies:
  flutter_riverpod: ^2.4.0
```

**Step 2**: Wrap app with ProviderScope
```dart
void main() {
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
```

**Step 3**: Create providers
```dart
// lib/providers/product_provider.dart
final productsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await ApiService().getProducts();
});
```

**Step 4**: Use in widgets
```dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    
    return productsAsync.when(
      data: (products) => ProductGrid(products: products),
      loading: () => CircularProgressIndicator(),
      error: (err, stack) => ErrorWidget(err),
    );
  }
}
```

---

## Conclusion

Price Pulse is a well-architected Flutter application with a clear separation of concerns, modern UI design, and scalable backend. The app successfully tracks product prices, maintains history, and sends notifications. The architecture supports future enhancements while maintaining code quality and user experience.

**Key Takeaways**:
- Service-oriented architecture enables easy feature additions
- Firestore provides scalable, real-time data storage
- Glassmorphism UI creates a modern, appealing interface
- Background jobs ensure timely price updates
- Multi-user support with secure data isolation

The app is production-ready and can be extended with the improvements suggested above to enhance functionality and user experience.

---

**Document Version**: 1.0  
**Last Updated**: December 2024  
**Author**: Technical Documentation Team

