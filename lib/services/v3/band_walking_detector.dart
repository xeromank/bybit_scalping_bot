import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 밴드워킹 위험 레벨
enum BandWalkingRisk {
  NONE,   // 0-29점: 정상 시장
  LOW,    // 30-49점: 주의
  MEDIUM, // 50-69점: 밴드워킹 위험
  HIGH,   // 70+점: 밴드워킹 확정
}

/// 밴드워킹 신호
class BandWalkingSignal {
  final BandWalkingRisk risk;
  final int score;
  final List<String> reasons;
  final String direction; // 'UP' or 'DOWN'
  final int consecutiveOutside;

  BandWalkingSignal({
    required this.risk,
    required this.score,
    required this.reasons,
    required this.direction,
    required this.consecutiveOutside,
  });

  /// 역추세 진입 차단 여부
  bool get shouldBlockCounterTrend =>
      risk == BandWalkingRisk.HIGH || risk == BandWalkingRisk.MEDIUM;

  /// 추세 추종 진입 활성화 여부
  bool get shouldEnterTrendFollow => risk == BandWalkingRisk.HIGH;

  @override
  String toString() {
    return 'BandWalkingSignal(risk: $risk, score: $score, direction: $direction, consecutive: $consecutiveOutside)';
  }
}

/// 밴드워킹 감지기
class BandWalkingDetector {
  /// 밴드워킹 감지
  static BandWalkingSignal detect({
    required List<KlineData> recentKlines,
    required BollingerBands bb,
    required MACD macd,
    required List<MACD> macdHistory,
    required VolumeAnalysis volume,
    required double rsi,
    required List<double> rsiHistory,
  }) {
    int score = 0;
    List<String> reasons = [];

    final currentPrice = recentKlines.first.close;

    // 1. BB Width 확장 체크 (40점) - 핵심 지표!
    final bbWidth = (bb.upper - bb.lower) / bb.middle;
    double prevBBWidth = 0.0;

    if (recentKlines.length >= 21) {
      // 이전 20개 캔들로 이전 BB 계산
      final prevClosePrices =
          recentKlines.sublist(1, 21).map((k) => k.close).toList();
      if (prevClosePrices.length >= 20) {
        final prevBB = calculateBollingerBands(prevClosePrices, 20, 2.0);
        prevBBWidth = (prevBB.upper - prevBB.lower) / prevBB.middle;
      }
    }

    final bbWidthChangePercent = prevBBWidth > 0
        ? ((bbWidth - prevBBWidth) / prevBBWidth) * 100.0
        : 0.0;

    if (bbWidthChangePercent > 3.0) {
      score += 40;
      reasons.add('BB Width 급증 ${bbWidthChangePercent.toStringAsFixed(1)}%');
    } else if (bbWidthChangePercent > 1.0) {
      score += 30;
      reasons.add('BB Width 확장 ${bbWidthChangePercent.toStringAsFixed(1)}%');
    } else if (bbWidthChangePercent > 0) {
      score += 20;
      reasons.add('BB Width 미세 확장 ${bbWidthChangePercent.toStringAsFixed(1)}%');
    }

    // 2. 연속 밴드 밖 캔들 카운트 (10점)
    int consecutiveOutside = 0;
    for (int i = 0; i < 5 && i < recentKlines.length; i++) {
      final kline = recentKlines[i];
      if (kline.close > bb.upper || kline.close < bb.lower) {
        consecutiveOutside++;
      } else {
        break;
      }
    }

    if (consecutiveOutside >= 3) {
      score += 10;
      reasons.add('$consecutiveOutside개 연속 밴드 밖 캔들');
    } else if (consecutiveOutside >= 2) {
      score += 5;
      reasons.add('$consecutiveOutside개 연속 밴드 밖 캔들');
    }

    // 3. MACD 히스토그램 지속 확장 (20점)
    if (macdHistory.length >= 3) {
      final currentHist = macd.histogram;
      final prevHist = macdHistory[macdHistory.length - 2].histogram;
      final histChange = currentHist - prevHist;

      // 같은 방향으로 확장 중인지
      if (currentHist.abs() > 3.0 && histChange.abs() > 0.5) {
        if ((currentHist > 0 && histChange > 0) ||
            (currentHist < 0 && histChange < 0)) {
          score += 20;
          reasons.add(
              'MACD 히스토그램 지속 확장 (${currentHist.toStringAsFixed(2)})');
        }
      } else if (currentHist.abs() > 5.0) {
        score += 10;
        reasons.add('MACD 히스토그램 강함 (${currentHist.toStringAsFixed(2)})');
      }
    }

    // 4. Volume 확인 (5점) - 보조 지표로 하향 조정
    if (volume.relativeVolumeRatio > 3.0) {
      score += 5;
      reasons
          .add('높은 거래량 ${volume.relativeVolumeRatio.toStringAsFixed(1)}x');
    }

    // 5. RSI 극단 유지 (30점) - 핵심 지표로 상향!
    if (rsi > 65 || rsi < 35) {
      // RSI가 극단적 영역에 있는지
      if (rsi > 70 || rsi < 30) {
        // 매우 극단적
        score += 30;
        reasons.add(
            'RSI 극단 (${rsi > 70 ? "과매수" : "과매도"} ${rsi.toStringAsFixed(1)})');
      } else {
        // 극단 진입 초기 또는 유지 중
        bool trending = true;
        if (rsiHistory.isNotEmpty) {
          final prevRsi = rsiHistory[0];
          // 같은 방향으로 움직이는지 확인
          if (rsi > 65 && prevRsi > rsi) trending = false; // 하락 중이면 약화
          if (rsi < 35 && prevRsi < rsi) trending = false; // 상승 중이면 약화
        }

        if (trending) {
          score += 20;
          reasons.add(
              'RSI ${rsi > 65 ? "과매수" : "과매도"} 영역 (${rsi.toStringAsFixed(1)})');
        }
      }
    }

    // Risk Level 결정
    BandWalkingRisk risk;
    if (score >= 70) {
      risk = BandWalkingRisk.HIGH;
    } else if (score >= 50) {
      risk = BandWalkingRisk.MEDIUM;
    } else if (score >= 30) {
      risk = BandWalkingRisk.LOW;
    } else {
      risk = BandWalkingRisk.NONE;
    }

    // 방향 결정
    String direction;
    if (currentPrice > bb.upper) {
      direction = 'UP';
    } else if (currentPrice < bb.lower) {
      direction = 'DOWN';
    } else if (risk == BandWalkingRisk.HIGH || risk == BandWalkingRisk.MEDIUM) {
      // 밴드워킹 위험이 있으면 RSI로 방향 판단
      if (rsi > 60) {
        direction = 'UP';
      } else if (rsi < 40) {
        direction = 'DOWN';
      } else {
        direction = 'NONE';
      }
    } else {
      direction = 'NONE';
    }

    return BandWalkingSignal(
      risk: risk,
      score: score,
      reasons: reasons,
      direction: direction,
      consecutiveOutside: consecutiveOutside,
    );
  }
}
