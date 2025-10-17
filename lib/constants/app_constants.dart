/// Application-wide constants
///
/// Responsibility: Centralize all application-level constants
///
/// This class contains general application settings, default values, and limits.
class AppConstants {
  AppConstants._(); // Private constructor to prevent instantiation

  // App Info
  static const String appName = 'Bybit Scalping Bot';
  static const String appVersion = '1.0.0';

  // Default Trading Settings
  static const String defaultSymbol = 'BTCUSDT';
  static const double defaultOrderAmount = 10.0;
  static const double defaultProfitTargetPercent = 0.5;
  static const double defaultStopLossPercent = 0.3;
  static const String defaultLeverage = '5';

  // Trading Limits
  static const double minOrderAmount = 0.001;
  static const double maxOrderAmount = 10000.0;
  static const double minProfitTargetPercent = 0.1;
  static const double maxProfitTargetPercent = 10.0;
  static const double minStopLossPercent = 0.1;
  static const double maxStopLossPercent = 5.0;
  static const int minLeverage = 1;
  static const int maxLeverage = 100;

  // Bot Settings
  static const Duration botMonitoringInterval = Duration(seconds: 3);
  static const int maxLogEntries = 100;
  static const Duration splashScreenDuration = Duration(seconds: 1);

  // UI Settings
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 8.0;
  static const double buttonHeight = 48.0;

  // Validation Messages
  static const String errorApiKeyRequired = 'API Key를 입력해주세요';
  static const String errorApiSecretRequired = 'API Secret을 입력해주세요';
  static const String errorInvalidAmount = '올바른 수량을 입력해주세요';
  static const String errorInvalidPercent = '올바른 퍼센트를 입력해주세요';
  static const String errorSymbolRequired = '심볼을 입력해주세요';

  // Success Messages
  static const String successLogin = '로그인 성공';
  static const String successLogout = '로그아웃 성공';
  static const String successBotStarted = '스캘핑 봇 시작';
  static const String successBotStopped = '스캘핑 봇 중지';

  // Error Messages
  static const String errorLoginFailed = '로그인 실패';
  static const String errorBotStartFailed = '봇 시작 실패';
  static const String errorBotStopFailed = '봇 중지 실패';
  static const String errorNetworkFailed = '네트워크 오류';
  static const String errorUnknown = '알 수 없는 오류';

  // Dialog Messages
  static const String dialogLogoutTitle = '로그아웃';
  static const String dialogLogoutMessage = '정말 로그아웃하시겠습니까?';
  static const String dialogConfirm = '확인';
  static const String dialogCancel = '취소';

  // Storage Keys (for shared preferences if needed)
  static const String keyLastSymbol = 'last_symbol';
  static const String keyLastAmount = 'last_amount';
  static const String keyLastProfitTarget = 'last_profit_target';
  static const String keyLastStopLoss = 'last_stop_loss';

  // Date/Time Formats
  static const String timeFormat = 'HH:mm:ss';
  static const String dateFormat = 'yyyy-MM-dd';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
}
