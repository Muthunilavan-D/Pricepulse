class AppNotification {
  final String id;
  final String type; // 'product_added', 'price_drop', 'threshold_reached'
  final String title;
  final String message;
  final String productId;
  final String? productTitle;
  final DateTime timestamp;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.productId,
    this.productTitle,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'productId': productId,
      'productTitle': productTitle,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] ?? '',
      type: map['type'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      productId: map['productId'] ?? '',
      productTitle: map['productTitle'],
      timestamp: DateTime.parse(
        map['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
      isRead: map['isRead'] ?? false,
    );
  }

  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    String? productId,
    String? productTitle,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      productId: productId ?? this.productId,
      productTitle: productTitle ?? this.productTitle,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}
