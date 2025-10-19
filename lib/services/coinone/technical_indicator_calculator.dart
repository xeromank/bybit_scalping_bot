import 'dart:math';
import 'package:bybit_scalping_bot/models/coinone/coinone_chart.dart';
import 'package:bybit_scalping_bot/models/coinone/technical_indicators.dart';

/// Technical Indicator Calculator Service
///
/// Calculates RSI, EMA, Bollinger Bands from chart candle data
class TechnicalIndicatorCalculator {
  /// Calculate all technical indicators
  ///
  /// Requires at least 200 candles for accurate EMA200
  TechnicalIndicators? calculate(List<CoinoneCandle> candles) {
    if (candles.isEmpty) return null;

    // Need at least 200 candles for EMA200
    if (candles.length < 200) {
      // Fallback: calculate what we can with available data
      return _calculateWithLimitedData(candles);
    }

    // Get closing prices and volumes
    final closes = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume).toList();
    final currentPrice = closes.last;
    final currentVolume = volumes.last;

    // Calculate indicators
    final rsi = _calculateRSI(closes, 14);
    final ema9 = _calculateEMA(closes, 9);
    final ema21 = _calculateEMA(closes, 21);
    final ema50 = _calculateEMA(closes, 50);
    final ema200 = _calculateEMA(closes, 200);
    final bb = _calculateBollingerBands(closes, 20, 2.0);
    final volumeMA5 = _calculateVolumeMA(volumes, 5);

    if (rsi == null || ema9 == null || ema21 == null || ema50 == null || ema200 == null || bb == null || volumeMA5 == null) {
      return null;
    }

    return TechnicalIndicators(
      rsi: rsi,
      ema9: ema9,
      ema21: ema21,
      ema50: ema50,
      ema200: ema200,
      bollingerUpper: bb['upper']!,
      bollingerMiddle: bb['middle']!,
      bollingerLower: bb['lower']!,
      currentPrice: currentPrice,
      currentVolume: currentVolume,
      volumeMA5: volumeMA5,
      timestamp: candles.last.timestamp,
    );
  }

  /// Calculate with limited data (less than 200 candles)
  TechnicalIndicators? _calculateWithLimitedData(List<CoinoneCandle> candles) {
    if (candles.length < 20) return null; // At minimum need 20 for Bollinger Bands

    final closes = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume).toList();
    final currentPrice = closes.last;
    final currentVolume = volumes.last;

    final rsi = _calculateRSI(closes, min(14, candles.length - 1));
    final ema9 = candles.length >= 9 ? _calculateEMA(closes, 9) : null;
    final ema21 = candles.length >= 21 ? _calculateEMA(closes, 21) : null;
    final ema50 = candles.length >= 50 ? _calculateEMA(closes, 50) : null;
    final ema200 = candles.length >= 200 ? _calculateEMA(closes, 200) : null;
    final bb = _calculateBollingerBands(closes, min(20, candles.length), 2.0);
    final volumeMA5 = candles.length >= 5 ? _calculateVolumeMA(volumes, 5) : null;

    if (rsi == null || bb == null) return null;

    return TechnicalIndicators(
      rsi: rsi,
      ema9: ema9 ?? currentPrice,
      ema21: ema21 ?? currentPrice,
      ema50: ema50 ?? currentPrice,
      ema200: ema200 ?? currentPrice,
      bollingerUpper: bb['upper']!,
      bollingerMiddle: bb['middle']!,
      bollingerLower: bb['lower']!,
      currentPrice: currentPrice,
      currentVolume: currentVolume,
      volumeMA5: volumeMA5 ?? currentVolume,
      timestamp: candles.last.timestamp,
    );
  }

  /// Calculate RSI (Relative Strength Index)
  double? _calculateRSI(List<double> prices, int period) {
    if (prices.length < period + 1) return null;

    double avgGain = 0;
    double avgLoss = 0;

    // Calculate initial average gain/loss
    for (int i = 1; i <= period; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        avgGain += change;
      } else {
        avgLoss -= change;
      }
    }

    avgGain /= period;
    avgLoss /= period;

    // Calculate RSI for remaining prices
    for (int i = period + 1; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        avgGain = (avgGain * (period - 1) + change) / period;
        avgLoss = (avgLoss * (period - 1)) / period;
      } else {
        avgGain = (avgGain * (period - 1)) / period;
        avgLoss = (avgLoss * (period - 1) - change) / period;
      }
    }

    if (avgLoss == 0) return 100;

    final rs = avgGain / avgLoss;
    final rsi = 100 - (100 / (1 + rs));

    return rsi;
  }

  /// Calculate EMA (Exponential Moving Average)
  double? _calculateEMA(List<double> prices, int period) {
    if (prices.length < period) return null;

    // Calculate initial SMA
    double sma = 0;
    for (int i = 0; i < period; i++) {
      sma += prices[i];
    }
    sma /= period;

    // Calculate EMA
    double ema = sma;
    final multiplier = 2.0 / (period + 1);

    for (int i = period; i < prices.length; i++) {
      ema = (prices[i] - ema) * multiplier + ema;
    }

    return ema;
  }

  /// Calculate Bollinger Bands
  Map<String, double>? _calculateBollingerBands(
    List<double> prices,
    int period,
    double stdDevMultiplier,
  ) {
    if (prices.length < period) return null;

    // Calculate SMA (middle band)
    double sum = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      sum += prices[i];
    }
    final middle = sum / period;

    // Calculate standard deviation
    double variance = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      variance += pow(prices[i] - middle, 2);
    }
    final stdDev = sqrt(variance / period);

    // Calculate upper and lower bands
    final upper = middle + (stdDev * stdDevMultiplier);
    final lower = middle - (stdDev * stdDevMultiplier);

    return {
      'upper': upper,
      'middle': middle,
      'lower': lower,
    };
  }

  /// Calculate Volume Moving Average
  double? _calculateVolumeMA(List<double> volumes, int period) {
    if (volumes.length < period) return null;

    // Calculate simple moving average of volume
    double sum = 0;
    for (int i = volumes.length - period; i < volumes.length; i++) {
      sum += volumes[i];
    }

    return sum / period;
  }
}
