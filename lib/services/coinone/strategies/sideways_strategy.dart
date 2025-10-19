import '../../../models/coinone/technical_indicators.dart';
import '../../../models/coinone/trading_signal.dart';

/// Sideways Strategy - Improved Mean Reversion
///
/// Entry conditions (Relaxed for more opportunities):
/// - BB Position < 40% (was 30%, relaxed to lower 40%)
/// - RSI ≤ 32 (was 28, slightly relaxed)
/// - RSI ≥ 15 (not extreme crash)
/// - Volume ≥ 1.1x (was 1.2x, relaxed)
///
/// Exit conditions:
/// - Stop loss: -2.5% (was 3%, tighter for faster exit)
/// - Take profit: +1.2% (was 1%, slightly higher)
/// - Price reaches Bollinger middle (mean reversion complete)
class SidewaysStrategy implements TradingStrategy {
  @override
  String get name => 'Sideways Improved';

  // Improved parameters (tighter SL, better TP)
  final double stopLossPercent = 2.5; // 2.5% stop loss (faster exit)
  final double takeProfitPercent = 1.2; // 1.2% take profit (better reward)

  @override
  TradingSignal generateSignal(TechnicalIndicators indicators) {
    final price = indicators.currentPrice;
    final rsi = indicators.rsi;
    final bbLower = indicators.bollingerLower;
    final bbUpper = indicators.bollingerUpper;
    final volumeRatio = indicators.volumeRatio;
    final timestamp = indicators.timestamp;

    // Calculate Bollinger Band position (0 = lower, 0.5 = middle, 1 = upper)
    final bbRange = bbUpper - bbLower;
    final bbPosition = bbRange > 0 ? (price - bbLower) / bbRange : 0.5;

    // Check entry conditions (RELAXED for more opportunities)
    final bool nearLowerBand = bbPosition < 0.4; // Relaxed: lower 40% (was 30%)
    final bool deeplyOversold = rsi <= 32; // Relaxed: ≤32 (was 28)
    final bool notExtreme = rsi >= 15; // But not crash level
    final bool volumeSpike = volumeRatio >= 1.1; // Relaxed: ≥1.1x (was 1.2x)

    // Calculate signal strength
    double strength = 0.0;
    final List<String> reasons = [];

    if (nearLowerBand) {
      strength += 0.35;
      reasons.add('볼린저 하단 근처 (${(bbPosition * 100).toStringAsFixed(0)}%)');
    }

    if (deeplyOversold) {
      strength += 0.25;
      reasons.add('RSI 심각한 과매도 (${rsi.toStringAsFixed(1)})');
    }

    if (notExtreme) {
      strength += 0.2;
      reasons.add('극단적 하락 아님');
    }

    if (volumeSpike) {
      strength += 0.2;
      reasons.add('거래량 급증 (${volumeRatio.toStringAsFixed(2)}x)');
    }

    // Generate BUY signal if strength >= 0.8 (most conditions met)
    if (strength >= 0.8) {
      final entryPrice = price;
      final stopLoss = entryPrice * (1 - stopLossPercent / 100);
      final takeProfit = entryPrice * (1 + takeProfitPercent / 100);

      return TradingSignal.buy(
        strength: strength,
        reason: '횡보 - ${reasons.join(', ')}',
        entryPrice: entryPrice,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        timestamp: timestamp,
      );
    }

    // No signal
    return TradingSignal.hold(
      reason: '진입 조건 미충족 (${reasons.join(', ')})',
      timestamp: timestamp,
    );
  }

  @override
  bool shouldClosePosition(
    TechnicalIndicators indicators,
    double entryPrice,
    double currentPrice,
  ) {
    // Check stop loss
    final lossPercent = ((currentPrice - entryPrice) / entryPrice) * 100;
    if (lossPercent <= -stopLossPercent) {
      return true; // Stop loss hit
    }

    // Check take profit
    final profitPercent = ((currentPrice - entryPrice) / entryPrice) * 100;
    if (profitPercent >= takeProfitPercent) {
      return true; // Take profit hit
    }

    // Check mean reversion: price reached Bollinger middle
    final price = indicators.currentPrice;
    final bbUpper = indicators.bollingerUpper;
    final bbRange = bbUpper - indicators.bollingerLower;
    final bbPosition = bbRange > 0 ? (price - indicators.bollingerLower) / bbRange : 0.5;

    // Exit if price reached middle band (50% of BB range)
    if (bbPosition >= 0.5) {
      return true; // Mean reversion complete
    }

    return false; // Hold position
  }
}
