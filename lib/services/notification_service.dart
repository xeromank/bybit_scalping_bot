import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 로컬 푸시 알림 서비스
///
/// Responsibility: 앱 내 이벤트 발생 시 로컬 알림 표시
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// 알림 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    // iOS 설정
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Android 설정 (향후 지원 시)
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
      android: initializationSettingsAndroid,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
    print('✅ 알림 서비스 초기화 완료');
  }

  /// 알림 권한 요청 (iOS)
  Future<bool> requestPermissions() async {
    final result = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    if (result == true) {
      print('✅ 알림 권한 허용됨');
    } else {
      print('❌ 알림 권한 거부됨');
    }

    return result ?? false;
  }

  /// 알림 탭 시 콜백
  void _onNotificationTapped(NotificationResponse response) {
    print('🔔 알림 탭됨: ${response.payload}');
    // TODO: 알림 탭 시 특정 화면으로 이동
  }

  /// 테스트 알림 표시
  Future<void> showTestNotification() async {
    const notificationDetails = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      ),
      android: AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: '테스트 알림 채널',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      0, // 알림 ID
      '🔔 테스트 알림',
      '알림이 정상적으로 작동합니다!',
      notificationDetails,
      payload: 'test',
    );

    print('✅ 테스트 알림 전송됨');
  }

  /// 거래 체결 알림
  Future<void> showTradeNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const notificationDetails = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      ),
      android: AndroidNotificationDetails(
        'trade_channel',
        'Trade Notifications',
        channelDescription: '거래 알림 채널',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // 고유 ID
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// 가격 알림
  Future<void> showPriceAlert({
    required String symbol,
    required double price,
    required String message,
  }) async {
    await showTradeNotification(
      title: '💰 $symbol 가격 알림',
      body: '\$$price - $message',
      payload: 'price_alert_$symbol',
    );
  }

  /// 포지션 알림
  Future<void> showPositionNotification({
    required String type, // 'open' or 'close'
    required String symbol,
    required String side, // 'Buy' or 'Sell'
    required double price,
    double? pnl,
  }) async {
    final emoji = type == 'open' ? '📈' : '📉';
    final action = type == 'open' ? '진입' : '청산';
    final sideKr = side == 'Buy' ? '롱' : '숏';

    String body = '$sideKr 포지션 $action - \$$price';
    if (pnl != null && type == 'close') {
      final pnlEmoji = pnl >= 0 ? '💚' : '❤️';
      body += '\n$pnlEmoji 손익: ${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}';
    }

    await showTradeNotification(
      title: '$emoji $symbol 포지션 $action',
      body: body,
      payload: 'position_${type}_$symbol',
    );
  }

  /// 모든 알림 취소
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    print('🔕 모든 알림 취소됨');
  }
}
