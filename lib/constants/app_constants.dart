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
  static const String defaultSymbol = 'ETHUSDT';
  static const double defaultOrderAmount = 50.0;
  static const String defaultLeverage = '10'; // Changed to 10x for both strategies

  // ===== BOLLINGER BAND MODE SETTINGS =====

  // Bollinger Band Settings
  static const int defaultBollingerPeriod = 20;
  static const double defaultBollingerStdDev = 2.0;
  static const int minBollingerPeriod = 10;
  static const int maxBollingerPeriod = 50;
  static const double minBollingerStdDev = 1.0;
  static const double maxBollingerStdDev = 3.0;

  // Bollinger Mode: RSI 14 Settings
  static const int defaultBollingerRsiPeriod = 14;
  static const double defaultBollingerRsiOverbought = 70.0;
  static const double defaultBollingerRsiOversold = 30.0;

  // Bollinger Mode: Profit/Loss Targets (ROE%)
  static const double defaultBollingerProfitPercent = 5.0;  // Conservative scalping
  static const double defaultBollingerStopLossPercent = 3.0;

  // ===== EMA TREND MODE SETTINGS =====

  // EMA Settings
  static const int defaultEma9Period = 9;
  static const int defaultEma21Period = 21;

  // EMA Mode: RSI 6 + RSI 14 Settings
  static const double defaultRsi6LongThreshold = 25.0;
  static const double defaultRsi6ShortThreshold = 75.0;
  static const int defaultRsi14Period = 14; // Changed from RSI 12 to RSI 14
  static const double defaultRsi14LongThreshold = 30.0;
  static const double defaultRsi14ShortThreshold = 70.0;

  // EMA Mode: Profit/Loss Targets (ROE%)
  static const double defaultEmaProfitPercent = 5.0;  // Conservative scalping
  static const double defaultEmaStopLossPercent = 3.0;

  // ===== COMMON SETTINGS (Both Modes) =====

  // Volume Filter Settings
  static const bool defaultUseVolumeFilter = true;
  static const double defaultVolumeMultiplier = 1.5;
  static const double minVolumeMultiplier = 1.0;
  static const double maxVolumeMultiplier = 3.0;

  // Chart Timeframes
  static const String defaultMainInterval = '5'; // 5-minute main chart
  static const String defaultTrendInterval = '15'; // 15-minute trend confirmation

  // Trading Limits
  static const double minOrderAmount = 40.0; // Minimum to ensure 0.01 qty for most symbols
  static const double maxOrderAmount = 10000.0;
  static const double minProfitTargetPercent = 0.1;
  static const double maxProfitTargetPercent = 10.0;
  static const double minStopLossPercent = 0.1;
  static const double maxStopLossPercent = 5.0;
  static const int minLeverage = 1;
  static const int maxLeverage = 100;

  // RSI Limits
  static const double minRsiThreshold = 10.0;
  static const double maxRsiThreshold = 90.0;
  static const int minRsiPeriod = 5;
  static const int maxRsiPeriod = 20;

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
