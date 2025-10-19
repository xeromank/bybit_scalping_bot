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
  static const double defaultOrderAmount = 1000.0;
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
  static const double defaultBollingerRsiOverbought = 75.0;
  static const double defaultBollingerRsiOversold = 25.0;

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

  // ===== MULTI-TIMEFRAME MODE SETTINGS =====

  // Multi-Timeframe RSI Thresholds for LONG
  static const double defaultMtfRsi6LongThreshold = 30.0;  // 5분봉 RSI6 과매도 기준
  static const double defaultMtfRsi14LongMin = 30.0;       // 1분봉 RSI14 최소값
  static const double defaultMtfRsi14LongMax = 50.0;       // 1분봉 RSI14 최대값
  static const double defaultMtfVolumeLongMultiplier = 2.0; // LONG 거래량 배수 (개선: 1.2배 → 2.0배)

  // Multi-Timeframe RSI Thresholds for SHORT (Stricter conditions)
  static const double defaultMtfRsi6ShortThreshold = 80.0; // 5분봉 RSI6 과열 기준 (70 → 80 강화)
  static const double defaultMtfRsi14ShortMin = 50.0;      // 1분봉 RSI14 최소값
  static const double defaultMtfRsi14ShortMax = 70.0;      // 1분봉 RSI14 최대값
  static const double defaultMtfVolumeShortMultiplier = 3.0; // SHORT 거래량 배수 (2.0배 → 3.0배 강화)

  // Multi-Timeframe Trend Filter (NEW - for SHORT safety)
  static const bool defaultMtfUseTrendFilter = true;       // 추세 필터 사용 여부
  static const int defaultMtfTrendPeriod = 20;             // 추세 판별 기간 (20 캔들)
  static const double defaultMtfTrendThreshold = -0.5;     // 하락 추세 기준 (-0.5% 이상 하락)

  // Multi-Timeframe Profit/Loss Targets (Price%) - Improved from backtest
  static const double defaultMtfProfitPercent = 1.0;       // 진입가 대비 +1.0% (개선: 0.5% → 1.0%)
  static const double defaultMtfStopLossPercent = 0.5;     // 진입가 대비 -0.5% (개선: 0.25% → 0.5%)

  // Multi-Timeframe Risk Management - Improved from backtest
  static const double defaultMtfPositionSize = 30.0;       // 총 자금의 30%
  static const double defaultMtfMaxDailyLoss = 3.0;        // 일일 최대 손실 3%
  static const int defaultMtfMaxConsecutiveLosses = 3;     // 연속 손실 3회
  static const int defaultMtfTimeoutMinutes = 30;          // 시간 손절 30분 (개선: 15분 → 30분)
  static const double defaultMtfRsi6ExitThreshold = 80.0;  // RSI6 과열 청산 기준
  static const int defaultMtfSignalCooldownMinutes = 10;   // 연속 신호 방지 (신규 추가)

  // ===== MARKET TREND ANALYSIS =====

  // Trend Analysis Settings
  static const int trendAnalysisCandleCount = 200;        // 200 candles = ~16.7 hours (5min)
  static const double trendUptrendThreshold = 1.0;        // +1.0% = uptrend
  static const double trendDowntrendThreshold = -1.0;     // -1.0% = downtrend
  static const bool trendAutoReanalyze = false;           // Auto re-analyze periodically

  // ===== ADAPTIVE STRATEGY ADJUSTMENTS =====

  // Bollinger Band Mode Adjustments
  static const double bollingerUptrendRsiAdjust = -5.0;   // Uptrend: RSI oversold 30 → 25
  static const double bollingerDowntrendRsiAdjust = 5.0;  // Downtrend: RSI overbought 70 → 75
  static const double bollingerSidewaysRsiAdjust = -5.0;  // Sideways: stricter RSI 30 → 25

  static const double bollingerUptrendVolumeAdjust = -0.5; // Uptrend: easier volume 1.5 → 1.0
  static const double bollingerDowntrendVolumeAdjust = 0.5; // Downtrend: harder volume 1.5 → 2.0
  static const double bollingerSidewaysVolumeAdjust = 0.0; // Sideways: no change

  // EMA Mode Adjustments
  static const double emaUptrendRsi6Adjust = 5.0;         // Uptrend: RSI6 long 25 → 30
  static const double emaDowntrendRsi6Adjust = -5.0;      // Downtrend: RSI6 long 25 → 20
  static const double emaSidewaysRsi6Adjust = -5.0;       // Sideways: stricter RSI6 25 → 20

  static const double emaUptrendVolumeAdjust = -0.5;      // Uptrend: easier volume
  static const double emaDowntrendVolumeAdjust = 0.5;     // Downtrend: harder volume
  static const double emaSidewaysVolumeAdjust = 0.0;      // Sideways: no change

  // Multi-Timeframe Mode Adjustments
  static const double mtfUptrendLongRsiAdjust = 5.0;      // Uptrend: easier LONG (30 → 35)
  static const double mtfUptrendShortRsiAdjust = 5.0;     // Uptrend: harder SHORT (80 → 85)
  static const double mtfDowntrendLongRsiAdjust = -5.0;   // Downtrend: harder LONG (30 → 25)
  static const double mtfDowntrendShortRsiAdjust = -5.0;  // Downtrend: easier SHORT (80 → 75)
  static const double mtfSidewaysLongRsiAdjust = -5.0;    // Sideways: stricter LONG (30 → 25)
  static const double mtfSidewaysShortRsiAdjust = -5.0;   // Sideways: stricter SHORT (80 → 75)

  static const double mtfUptrendLongVolumeAdjust = -0.5;  // Uptrend: easier LONG (2.0 → 1.5)
  static const double mtfUptrendShortVolumeAdjust = 0.5;  // Uptrend: harder SHORT (3.0 → 3.5)
  static const double mtfDowntrendLongVolumeAdjust = 1.0; // Downtrend: harder LONG (2.0 → 3.0)
  static const double mtfDowntrendShortVolumeAdjust = -1.0; // Downtrend: easier SHORT (3.0 → 2.0)
  static const double mtfSidewaysLongVolumeAdjust = 0.5;  // Sideways: moderate LONG (2.0 → 2.5)
  static const double mtfSidewaysShortVolumeAdjust = -0.5; // Sideways: moderate SHORT (3.0 → 2.5)

  // Sideways-specific: Bollinger Band requirement
  static const bool mtfSidewaysRequireBollingerTouch = true;  // Require BB touch in sideways
  static const double mtfSidewaysBollingerTolerance = 0.002;  // 0.2% tolerance

  // ===== COMMON SETTINGS (All Modes) =====

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
