import '../../../models/coinone/technical_indicators.dart';
import '../../../models/coinone/trading_signal.dart';

/// Uptrend Strategy - Gradual RSI Entry (Buy the Dip)
///
/// Gradual entry based on RSI levels:
/// - RSI ≤ 30: Full position (100%), SL: -5%, TP: +3%
/// - RSI ≤ 35: Half position (50%), SL: -4%, TP: +2%
/// - RSI ≤ 40: Quarter position (25%), SL: -3%, TP: +1.5%
///
/// Other conditions:
/// - Price > EMA21 * 0.98 (near or above EMA21, 2% buffer)
/// - EMA9 > EMA21 * 0.99 (short-term uptrend, slight relaxation)
/// - Price ≤ BB Middle * 1.01 (not overbought)
/// - Volume ≥ 1.0x average (confirmation)
///
/// Exit: SL/TP based on RSI tier, or price < EMA21
class UptrendStrategy implements TradingStrategy {
  @override
  String get name => 'Uptrend Gradual Entry';

  @override
  TradingSignal generateSignal(TechnicalIndicators indicators) {
    final price = indicators.currentPrice;
    final rsi = indicators.rsi;
    final ema9 = indicators.ema9;
    final ema21 = indicators.ema21;
    final bbMiddle = indicators.bollingerMiddle;
    final volumeRatio = indicators.volumeRatio;
    final timestamp = indicators.timestamp;

    // Determine RSI tier (gradual entry)
    double positionSize = 0.0;
    double stopLossPercent = 0.0;
    double takeProfitPercent = 0.0;
    String rsiTier = '';

    if (rsi <= 30) {
      // Tier 1: Deeply oversold - Full position
      positionSize = 1.0;
      stopLossPercent = 5.0;
      takeProfitPercent = 3.0;
      rsiTier = '강과매도';
    } else if (rsi <= 35) {
      // Tier 2: Oversold - Half position
      positionSize = 0.5;
      stopLossPercent = 4.0;
      takeProfitPercent = 2.0;
      rsiTier = '중과매도';
    } else if (rsi <= 40) {
      // Tier 3: Slightly oversold - Quarter position
      positionSize = 0.25;
      stopLossPercent = 3.0;
      takeProfitPercent = 1.5;
      rsiTier = '약과매도';
    } else {
      // RSI > 40: No entry
      return TradingSignal.hold(
        reason: 'RSI > 40 (${rsi.toStringAsFixed(1)}) - 진입 구간 아님',
        timestamp: timestamp,
      );
    }

    // Check other conditions (relaxed from original)
    final bool priceNearEma21 = price > ema21 * 0.98; // 2% buffer
    final bool shortTermUptrend = ema9 > ema21 * 0.99; // Slight relaxation
    final bool notOverbought = price <= bbMiddle * 1.01; // Not overbought
    final bool volumeConfirmation = volumeRatio >= 1.0; // Volume confirmation

    // Calculate signal strength
    double strength = 0.0;
    final List<String> reasons = [rsiTier, 'RSI ${rsi.toStringAsFixed(1)}'];

    if (priceNearEma21) {
      strength += 0.25;
      reasons.add('가격 ≥ EMA21');
    }

    if (shortTermUptrend) {
      strength += 0.25;
      reasons.add('단기상승');
    }

    if (notOverbought) {
      strength += 0.25;
      reasons.add('과매수X');
    }

    if (volumeConfirmation) {
      strength += 0.25;
      reasons.add('거래량 ${volumeRatio.toStringAsFixed(2)}x');
    }

    // Need at least 75% strength (3 out of 4 conditions)
    if (strength >= 0.75) {
      final entryPrice = price;
      final stopLoss = entryPrice * (1 - stopLossPercent / 100);
      final takeProfit = entryPrice * (1 + takeProfitPercent / 100);

      return TradingSignal.buy(
        strength: strength,
        reason: '상승 ${reasons.join(', ')} (포지션 ${(positionSize * 100).toStringAsFixed(0)}%)',
        entryPrice: entryPrice,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        positionSizeMultiplier: positionSize,
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
    // Note: SL/TP are calculated at entry time based on RSI tier
    // This method is called by the provider which uses the signal's stopLoss/takeProfit values
    // So we only check for momentum loss here

    // Check momentum loss: price crosses below EMA21
    final price = indicators.currentPrice;
    final ema21 = indicators.ema21;
    if (price < ema21) {
      return true; // Exit on momentum loss
    }

    return false; // Hold position (SL/TP checked by provider)
  }
}
