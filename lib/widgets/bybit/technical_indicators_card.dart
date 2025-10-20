import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Technical Indicators Card
///
/// 실시간 기술적 지표 표시:
/// - RSI(14)
/// - Bollinger Bands (상단/중간/하단)
/// - EMA(9, 21, 50)
/// - 현재 가격 위치
class TechnicalIndicatorsCard extends StatelessWidget {
  const TechnicalIndicatorsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final currentPrice = provider.currentPrice;
        final rsi = provider.currentRSI;
        final bb = provider.currentBB;
        final ema9 = provider.currentEMA9;
        final ema21 = provider.currentEMA21;
        final ema50 = provider.currentEMA50;

        if (currentPrice == null) {
          return Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '데이터 로딩 중...',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            ),
          );
        }

        return Card(
          color: const Color(0xFF2D2D2D),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.analytics_outlined,
                      color: Colors.purple,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '실시간 기술적 지표',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // RSI
                _buildIndicatorRow(
                  'RSI(14)',
                  rsi != null ? rsi.toStringAsFixed(2) : 'N/A',
                  _getRSIColor(rsi),
                  _getRSIStatus(rsi),
                ),
                const SizedBox(height: 12),

                // Bollinger Bands
                if (bb != null) ...[
                  _buildIndicatorRow(
                    'BB 상단',
                    '\$${bb.upper.toStringAsFixed(2)}',
                    Colors.red.shade300,
                    _getPricePositionToBB(currentPrice, bb.upper),
                  ),
                  const SizedBox(height: 8),
                  _buildIndicatorRow(
                    'BB 중간',
                    '\$${bb.middle.toStringAsFixed(2)}',
                    Colors.amber,
                    _getPricePositionToBB(currentPrice, bb.middle),
                  ),
                  const SizedBox(height: 8),
                  _buildIndicatorRow(
                    'BB 하단',
                    '\$${bb.lower.toStringAsFixed(2)}',
                    Colors.green.shade300,
                    _getPricePositionToBB(currentPrice, bb.lower),
                  ),
                  const SizedBox(height: 12),
                ],

                // EMAs
                if (ema9 != null)
                  _buildIndicatorRow(
                    'EMA(9)',
                    '\$${ema9.toStringAsFixed(2)}',
                    Colors.blue.shade300,
                    _getPricePositionToEMA(currentPrice, ema9),
                  ),
                const SizedBox(height: 8),
                if (ema21 != null)
                  _buildIndicatorRow(
                    'EMA(21)',
                    '\$${ema21.toStringAsFixed(2)}',
                    Colors.blue.shade400,
                    _getPricePositionToEMA(currentPrice, ema21),
                  ),
                const SizedBox(height: 8),
                if (ema50 != null)
                  _buildIndicatorRow(
                    'EMA(50)',
                    '\$${ema50.toStringAsFixed(2)}',
                    Colors.blue.shade500,
                    _getPricePositionToEMA(currentPrice, ema50),
                  ),

                // Current Price Summary
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '현재가',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$${currentPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Entry Condition Check
                if (provider.currentSignal != null && provider.currentSignal!.hasSignal) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${provider.currentSignal!.type.name.toUpperCase()} 진입 조건 충족',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIndicatorRow(String label, String value, Color color, String status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 13,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getRSIColor(double? rsi) {
    if (rsi == null) return Colors.grey;
    if (rsi > 70) return Colors.red;
    if (rsi > 55) return Colors.orange;
    if (rsi < 30) return Colors.green;
    if (rsi < 45) return Colors.lightGreen;
    return Colors.amber;
  }

  String _getRSIStatus(double? rsi) {
    if (rsi == null) return '-';
    if (rsi > 70) return '과매수';
    if (rsi > 55) return '강세';
    if (rsi < 30) return '과매도';
    if (rsi < 45) return '약세';
    return '중립';
  }

  String _getPricePositionToBB(double price, double bbValue) {
    final diff = ((price - bbValue) / bbValue * 100).abs();
    if (diff < 0.5) return '근접';
    if (price > bbValue) return '상단';
    return '하단';
  }

  String _getPricePositionToEMA(double price, double emaValue) {
    if ((price - emaValue).abs() / emaValue < 0.002) return '접촉';
    if (price > emaValue) return '상승';
    return '하락';
  }
}
