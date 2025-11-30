import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Request notification permissions
    await _requestPermissions();

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Configure Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'price_alerts',
      'Price Alerts',
      description: 'Notifications for price drops and threshold alerts',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

    // Get FCM token and register with backend
    final token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');

    // Register token with backend (deferred to avoid circular dependency)
    if (token != null) {
      _registerTokenWithBackend(token);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('FCM Token refreshed: $newToken');
      _registerTokenWithBackend(newToken);
    });

    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  // Register FCM token with backend (deferred to avoid circular dependency)
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      // Use dynamic import to avoid circular dependency
      final apiService = ApiService();
      await apiService.registerFCMToken(token);
    } catch (e) {
      print('⚠️ Failed to register FCM token with backend: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Foreground message: ${message.notification?.title}');

    // Show local notification when app is in foreground
    await showLocalNotification(
      title: message.notification?.title ?? 'Price Alert',
      body: message.notification?.body ?? '',
      payload: message.data.toString(),
    );
  }

  void _handleBackgroundMessageTap(RemoteMessage message) {
    print('Background message tapped: ${message.notification?.title}');
    // Navigate to product detail or home screen
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'price_alerts',
      'Price Alerts',
      channelDescription: 'Notifications for price drops and threshold alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> showThresholdReachedNotification({
    required String productTitle,
    required String currentPrice,
    required double thresholdPrice,
  }) async {
    await showLocalNotification(
      title: '🎯 Price Alert!',
      body:
          '$productTitle dropped to $currentPrice (Threshold: ₹${thresholdPrice.toStringAsFixed(0)})',
      payload: 'threshold_reached',
    );
  }

  Future<void> showPriceDropNotification({
    required String productTitle,
    required String currentPrice,
    required String previousPrice,
  }) async {
    await showLocalNotification(
      title: '📉 Price Drop!',
      body: '$productTitle price dropped from $previousPrice to $currentPrice',
      payload: 'price_drop',
    );
  }
}
