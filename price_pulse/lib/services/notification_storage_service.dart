import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';

class NotificationStorageService {
  static final NotificationStorageService _instance =
      NotificationStorageService._internal();
  factory NotificationStorageService() => _instance;
  NotificationStorageService._internal();

  static const String _notificationsKey = 'app_notifications';
  static const int _maxNotifications = 100; // Keep last 100 notifications

  Future<List<AppNotification>> getNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = prefs.getStringList(_notificationsKey) ?? [];

      return notificationsJson
          .map((json) => AppNotification.fromMap(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
    } catch (e) {
      print('Error loading notifications: $e');
      return [];
    }
  }

  Future<void> addNotification(AppNotification notification) async {
    try {
      final notifications = await getNotifications();

      // Add new notification at the beginning
      notifications.insert(0, notification);

      // Keep only last N notifications
      if (notifications.length > _maxNotifications) {
        notifications.removeRange(_maxNotifications, notifications.length);
      }

      await _saveNotifications(notifications);
    } catch (e) {
      print('Error adding notification: $e');
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      final notifications = await getNotifications();
      final index = notifications.indexWhere((n) => n.id == notificationId);

      if (index != -1) {
        notifications[index] = notifications[index].copyWith(isRead: true);
        await _saveNotifications(notifications);
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final notifications = await getNotifications();
      final updatedNotifications = notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      await _saveNotifications(updatedNotifications);
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      final notifications = await getNotifications();
      notifications.removeWhere((n) => n.id == notificationId);
      await _saveNotifications(notifications);
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  Future<void> deleteNotificationsByProductId(String productId) async {
    try {
      final notifications = await getNotifications();
      final filteredNotifications = notifications
          .where((n) => n.productId != productId)
          .toList();
      await _saveNotifications(filteredNotifications);
      print('Deleted ${notifications.length - filteredNotifications.length} notification(s) for product: $productId');
    } catch (e) {
      print('Error deleting notifications by productId: $e');
    }
  }

  Future<void> clearAllNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notificationsKey);
    } catch (e) {
      print('Error clearing notifications: $e');
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final notifications = await getNotifications();
      return notifications.where((n) => !n.isRead).length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _saveNotifications(List<AppNotification> notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = notifications
          .map((n) => jsonEncode(n.toMap()))
          .toList();
      await prefs.setStringList(_notificationsKey, notificationsJson);
    } catch (e) {
      print('Error saving notifications: $e');
    }
  }
}
