/// 가격 범위 예측 신호
class PricePredictionSignal {
  /// 현재 시장 상태
  final MarketState marketState;

  /// 현재 가격
  final double currentPrice;

  /// 예측된 다음 캔들 최고가 (얇은 꼬리 제외)
  final double predictedHigh;

  /// 예측된 다음 캔들 최저가 (얇은 꼬리 제외)
  final double predictedLow;

  /// 예측된 다음 캔들 종가
  final double predictedClose;

  /// 예측 범위 (최고가 - 최저가)
  final double predictedRange;

  /// 최근 5개 캔들 평균 이동폭
  final double avgMove5m;

  /// 신뢰도 (샘플 수 기반)
  final double confidence;

  /// 신호 생성 시각
  final DateTime timestamp;

  /// 예측 대상 인터벌 (분 단위: 1, 5, 30, 240 등)
  final String predictionInterval;

  /// 예측 시작 캔들의 타임스탬프 (새 봉 감지용)
  final DateTime predictionStartTime;

  PricePredictionSignal({
    required this.marketState,
    required this.currentPrice,
    required this.predictedHigh,
    required this.predictedLow,
    required this.predictedClose,
    required this.predictedRange,
    required this.avgMove5m,
    required this.confidence,
    required this.timestamp,
    required this.predictionInterval,
    required this.predictionStartTime,
  });

  /// 예측 최고가까지의 상승 여력 (%)
  double get upwardPotentialPercent =>
      ((predictedHigh - currentPrice) / currentPrice) * 100.0;

  /// 예측 최저가까지의 하락 여력 (%)
  double get downwardPotentialPercent =>
      ((currentPrice - predictedLow) / currentPrice) * 100.0;

  /// 예측 범위 (%)
  double get rangePercent => (predictedRange / currentPrice) * 100.0;

  /// 예측 종가 변화 (%)
  double get closeChangePercent =>
      ((predictedClose - currentPrice) / currentPrice) * 100.0;

  /// 인터벌 표시명
  String get intervalDisplayName {
    switch (predictionInterval) {
      case '1':
        return '1분';
      case '5':
        return '5분';
      case '30':
        return '30분';
      case '60':
        return '1시간';
      case '240':
        return '4시간';
      default:
        return '${predictionInterval}분';
    }
  }

  @override
  String toString() {
    return '''
PricePredictionSignal(
  인터벌: $intervalDisplayName
  상태: $marketState
  현재가: \$${currentPrice.toStringAsFixed(2)}
  예측 최고가: \$${predictedHigh.toStringAsFixed(2)} (+${upwardPotentialPercent.toStringAsFixed(3)}%)
  예측 최저가: \$${predictedLow.toStringAsFixed(2)} (-${downwardPotentialPercent.toStringAsFixed(3)}%)
  예측 종가: \$${predictedClose.toStringAsFixed(2)} (${closeChangePercent >= 0 ? '+' : ''}${closeChangePercent.toStringAsFixed(3)}%)
  예측 범위: \$${predictedRange.toStringAsFixed(2)} (${rangePercent.toStringAsFixed(3)}%)
  avgMove5m: \$${avgMove5m.toStringAsFixed(2)}
  신뢰도: ${(confidence * 100).toStringAsFixed(1)}%
  예측 시작 시각: $predictionStartTime
)''';
  }
}

/// 시장 상태 분류
enum MarketState {
  /// 5분봉 저변동성 (BB Width < 2%)
  SQUEEZE_5M,

  /// 30분봉 저변동성 (BB Width < 2% + RSI 40-60 + MACD < 2.0)
  SQUEEZE_30M,

  /// 강한 상승 추세 (RSI30m > 60 + MACD > 2.0)
  STRONG_UP,

  /// 강한 하락 추세 (RSI30m < 40 + MACD < -2.0)
  STRONG_DOWN,

  /// 약한 상승 추세 (RSI30m > 50 + MACD > 0)
  WEAK_UP,

  /// 약한 하락 추세 (RSI30m < 50 + MACD < 0)
  WEAK_DOWN,

  /// 중립 (명확한 방향성 없음)
  NEUTRAL,
}

extension MarketStateExtension on MarketState {
  String get displayName {
    switch (this) {
      case MarketState.SQUEEZE_5M:
        return '5분 스퀴즈';
      case MarketState.SQUEEZE_30M:
        return '30분 스퀴즈';
      case MarketState.STRONG_UP:
        return '강한 상승';
      case MarketState.STRONG_DOWN:
        return '강한 하락';
      case MarketState.WEAK_UP:
        return '약한 상승';
      case MarketState.WEAK_DOWN:
        return '약한 하락';
      case MarketState.NEUTRAL:
        return '중립';
    }
  }

  /// 시장 상태별 신뢰도 (분석 결과 기반)
  double get baseConfidence {
    switch (this) {
      case MarketState.SQUEEZE_5M:
        return 0.95; // 664개 샘플, 100% 정확도
      case MarketState.SQUEEZE_30M:
        return 0.93; // 138개 샘플, 100% 정확도
      case MarketState.STRONG_UP:
        return 0.90; // 61개 샘플, 100% 정확도 (약간 낮은 샘플 수)
      case MarketState.STRONG_DOWN:
        return 0.88; // 35개 샘플, 100% 정확도 (낮은 샘플 수)
      case MarketState.WEAK_UP:
        return 0.80; // 약한 추세, 상대적으로 낮은 신뢰도
      case MarketState.WEAK_DOWN:
        return 0.80;
      case MarketState.NEUTRAL:
        return 0.75; // 가장 낮은 신뢰도
    }
  }
}
