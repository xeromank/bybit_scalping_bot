import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/models/price_prediction_signal.dart';

/// 예측 데이터 상세 카드
///
/// 다음 캔들 예측 정보를 시각적으로 표현:
/// - 예측 HIGH/LOW/CLOSE
/// - 상승/하락 여력 (%)
/// - 시장 상태
/// - 신뢰도
/// - avgMove5m 기반 예측
class PredictionDetailCard extends StatelessWidget {
  final PricePredictionSignal prediction;
  final double currentPrice;

  const PredictionDetailCard({
    Key? key,
    required this.prediction,
    required this.currentPrice,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final upPotential = prediction.upwardPotentialPercent;
    final downPotential = prediction.downwardPotentialPercent;
    final closeChange = prediction.closeChangePercent;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '다음 5분 캔들 예측',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildConfidenceBadge(prediction.confidence),
              ],
            ),
          ),

          // 시장 상태
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildMarketState(),
          ),

          // 가격 예측
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildPriceRow(
                  label: '예측 최고가',
                  price: prediction.predictedHigh,
                  percent: upPotential,
                  icon: Icons.arrow_upward,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                _buildPriceRow(
                  label: '예측 종가',
                  price: prediction.predictedClose,
                  percent: closeChange,
                  icon: closeChange >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: closeChange >= 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 12),
                _buildPriceRow(
                  label: '예측 최저가',
                  price: prediction.predictedLow,
                  percent: -downPotential,
                  icon: Icons.arrow_downward,
                  color: Colors.red,
                ),
              ],
            ),
          ),

          // 예측 범위 시각화
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildRangeVisualization(),
          ),

          // 기술 정보
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              children: [
                _buildTechRow('예측 범위', '\$${prediction.predictedRange.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                _buildTechRow('범위 (%)', '${prediction.rangePercent.toStringAsFixed(3)}%'),
                const SizedBox(height: 8),
                _buildTechRow('avgMove5m', '\$${prediction.avgMove5m.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                _buildTechRow('생성 시각', _formatTime(prediction.timestamp)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 신뢰도 배지
  Widget _buildConfidenceBadge(double confidence) {
    final percent = (confidence * 100).toInt();
    Color color;

    if (percent >= 90) {
      color = Colors.green;
    } else if (percent >= 80) {
      color = Colors.blue;
    } else if (percent >= 70) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            '신뢰도 $percent%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 시장 상태
  Widget _buildMarketState() {
    final state = prediction.marketState;
    final stateText = state.displayName;

    Color stateColor;
    IconData stateIcon;

    switch (state) {
      case MarketState.SQUEEZE_5M:
      case MarketState.SQUEEZE_30M:
        stateColor = Colors.purple;
        stateIcon = Icons.compress;
        break;
      case MarketState.STRONG_UP:
      case MarketState.WEAK_UP:
        stateColor = Colors.green;
        stateIcon = Icons.trending_up;
        break;
      case MarketState.STRONG_DOWN:
      case MarketState.WEAK_DOWN:
        stateColor = Colors.red;
        stateIcon = Icons.trending_down;
        break;
      default:
        stateColor = Colors.grey;
        stateIcon = Icons.horizontal_rule;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stateColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stateColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(stateIcon, color: stateColor, size: 20),
          const SizedBox(width: 8),
          Text(
            '시장 상태: $stateText',
            style: TextStyle(
              color: stateColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 가격 행
  Widget _buildPriceRow({
    required String label,
    required double price,
    required double percent,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${price.toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(3)}%',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 범위 시각화
  Widget _buildRangeVisualization() {
    final range = prediction.predictedHigh - prediction.predictedLow;
    final currentRelative = (currentPrice - prediction.predictedLow) / range;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '가격 범위 시각화',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            return Stack(
              children: [
                // 배경
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.withOpacity(0.3),
                        Colors.yellow.withOpacity(0.3),
                        Colors.green.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),

                // 현재가 마커
                Positioned(
                  left: currentRelative.clamp(0.0, 1.0) * width,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    color: Colors.white,
                  ),
                ),

                // 현재가 레이블
                Positioned(
                  left: (currentRelative.clamp(0.0, 1.0) * width - 30).clamp(0.0, width - 60),
                  top: -20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '현재',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '\$${prediction.predictedLow.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
            Text(
              '\$${currentPrice.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              '\$${prediction.predictedHigh.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.green, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  /// 기술 정보 행
  Widget _buildTechRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
