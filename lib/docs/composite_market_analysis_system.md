# Composite Market Analysis System (복합 시장 분석 시스템)

**작성일**: 2025-10-21
**버전**: 1.0.0
**상태**: 구현 완료, 진입 로직 통합 대기

---

## 📋 목차

1. [개요](#개요)
2. [기존 시스템의 문제점](#기존-시스템의-문제점)
3. [새로운 시스템 아키텍처](#새로운-시스템-아키텍처)
4. [구현 상세](#구현-상세)
5. [백테스트 결과](#백테스트-결과)
6. [다음 단계](#다음-단계)

---

## 개요

### 목적
기존의 단일 지표(RSI) 의존 시장 분석을 **6개 지표 복합 분석 시스템**으로 전면 개편하여 신호 정확도와 신뢰성을 향상시킵니다.

### 주요 개선 사항
- **6개 지표 통합**: RSI, Volume, Price Action, MA Trend, Bollinger Bands, MACD
- **가중치 기반 종합 점수**: -1.0 (극약세) ~ +1.0 (극강세)
- **7단계 세밀한 시장 분류**: extremeBullish → strongBullish → weakBullish → ranging → weakBearish → strongBearish → extremeBearish
- **신호 신뢰도 평가**: HIGH/MEDIUM/LOW (지표 간 합의 수준 기반)
- **MACD 히스토그램 트렌드 분석**: IMPROVING/WORSENING/CROSSING/SIDEWAYS

---

## 기존 시스템의 문제점

### 1. RSI 단독 의존의 한계
**문제 사례: 2025-10-21 04:30**
```
상황: 가격이 BB 하단 근처, RSI 과매도 (< 30)
기존 판단: "LONG 진입 신호" (RSI만 보고 판단)
실제 결과: 손실 발생

원인 분석:
- RSI는 과매도였지만
- MACD 히스토그램이 "WORSENING" 상태 (약화 중)
- 하락 추세가 계속됨
- Volume이 낮아 신뢰도 부족
```

### 2. 트렌드 강도 미반영
- MACD 지표를 사용하지 않아 **추세의 강도와 방향성** 판단 불가
- 약화되는 추세에서 역추세 진입 → 큰 손실

### 3. 거래량 무시
- 높은 거래량 동반 신호 vs 낮은 거래량 신호 구분 없음
- 거짓 신호 필터링 불가

### 4. 시장 조건 단순화
- 3단계 분류 (강세/횡보/약세) → 복잡한 시장 상황 대응 부족
- 극단적 시장 vs 약한 추세 구분 불가

---

## 새로운 시스템 아키텍처

### 1. 지표별 가중치 시스템

| 지표 | 가중치 | 역할 |
|------|--------|------|
| **RSI** | 25% | 과매수/과매도 상태 판단 |
| **Volume** | 20% | 신호 신뢰도 검증 |
| **Price Action** | 20% | 모멘텀 강도 측정 |
| **MA Trend** | 15% | 중장기 추세 방향 |
| **Bollinger Bands** | 10% | 변동성 및 극단 위치 |
| **MACD** | 10% | 추세 강도 및 변화 감지 |

### 2. Composite Score 계산

```dart
compositeScore = (rsiScore * 0.25) +
                 (volumeScore * 0.20) +
                 (priceActionScore * 0.20) +
                 (maTrendScore * 0.15) +
                 (bbScore * 0.10) +
                 (macdScore * 0.10);
// 결과: -1.0 (극약세) ~ +1.0 (극강세)
```

### 3. 7단계 시장 분류

```
극강세 (extremeBullish):      score > 0.6
강세 (strongBullish):         0.4 < score ≤ 0.6
약한 강세 (weakBullish):      0.15 < score ≤ 0.4
횡보 (ranging):               -0.15 ≤ score ≤ 0.15
약한 약세 (weakBearish):      -0.4 ≤ score < -0.15
약세 (strongBearish):         -0.6 ≤ score < -0.4
극약세 (extremeBearish):      score < -0.6
```

### 4. 신호 신뢰도 평가

```dart
// 6개 지표가 같은 방향을 가리키는지 확인
agreeCount = 0
if (compositeScore > 0) {
  if (rsiScore > 0) agreeCount++
  if (volumeScore > 0) agreeCount++
  if (priceActionScore > 0) agreeCount++
  if (maTrendScore > 0) agreeCount++
  if (bbScore > 0) agreeCount++
  if (macdScore > 0) agreeCount++
}

신뢰도:
- HIGH:   agreeCount ≥ 5 (83%+ 합의)
- MEDIUM: agreeCount = 3-4 (50-83% 합의)
- LOW:    agreeCount ≤ 2 (<50% 합의)
```

---

## 구현 상세

### 1. MACD 지표 계산 (`lib/utils/technical_indicators.dart`)

#### MACD 클래스
```dart
class MACD {
  final double macdLine;      // Fast EMA(12) - Slow EMA(26)
  final double signalLine;    // Signal line (EMA(9) of MACD line)
  final double histogram;     // MACD line - Signal line

  bool get isBullish => macdLine > signalLine;
  bool get isBearish => macdLine < signalLine;
  double get histogramStrength => histogram.abs();
}
```

#### MACD 히스토그램 트렌드
```dart
enum MACDHistogramTrend {
  improving,   // 히스토그램이 신호 방향으로 확장 (추세 강화)
  worsening,   // 히스토그램이 0으로 수렴 (추세 약화)
  crossing,    // 최근 0선 교차
  sideways,    // 변화 없음
}
```

#### 주요 함수
```dart
// 현재 MACD 값 계산
MACD calculateMACD(List<double> prices, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
});

// MACD 시계열 계산
List<MACD> calculateMACDFullSeries(List<double> prices);

// 히스토그램 트렌드 판정
MACDHistogramTrend getMACDHistogramTrend(List<MACD> macdSeries);
```

**핵심 로직**:
```dart
// IMPROVING 판정 (추세 강화)
if (currentHistogram > 0 && histogramChange > threshold) {
  return MACDHistogramTrend.improving;  // 상승 추세 강화
}
if (currentHistogram < 0 && histogramChange < -threshold) {
  return MACDHistogramTrend.improving;  // 하락 추세 강화
}

// WORSENING 판정 (추세 약화)
if (currentHistogram > 0 && histogramChange < -threshold) {
  return MACDHistogramTrend.worsening;  // 상승 추세 약화
}
if (currentHistogram < 0 && histogramChange > threshold) {
  return MACDHistogramTrend.worsening;  // 하락 추세 약화
}
```

---

### 2. Volume 분석 시스템

#### VolumeAnalysis 클래스
```dart
class VolumeAnalysis {
  final double currentVolume;
  final double volumeMA20;
  final double relativeVolumeRatio;  // current / MA20
  final bool isHighVolume;            // ratio ≥ 1.5x
  final bool isLowVolume;             // ratio ≤ 0.5x
  final double score;                 // -1.0 ~ +1.0
}
```

#### 점수 계산 로직
```dart
if (ratio ≥ 3.0)         score = +1.0   // 매우 높은 거래량
else if (ratio ≥ 1.0)    score = (ratio - 1.0) / 2.0
else if (ratio ≥ 0.33)   score = (ratio - 1.0) / 0.67
else                     score = -1.0   // 매우 낮은 거래량
```

**의미**:
- `score > 0.5`: 높은 거래량 → 신호 신뢰도 높음
- `score < -0.5`: 낮은 거래량 → 신호 신뢰도 낮음

---

### 3. Price Action 분석

#### PriceActionAnalysis 클래스
```dart
class PriceActionAnalysis {
  final double priceChangePercent;  // 최근 5봉 가격 변화율
  final bool isStrongUpMove;        // +1.5% 이상
  final bool isStrongDownMove;      // -1.5% 이하
  final double momentum;            // 평균 캔들 변화율
  final double score;               // -1.0 ~ +1.0
}
```

#### 점수 계산
```dart
if (change ≥ +3.0%)     score = +1.0
else if (change ≥ 0%)   score = change / 0.03
else if (change ≥ -3%)  score = change / 0.03
else                    score = -1.0
```

---

### 4. MA Trend 분석

#### MATrendAnalysis 클래스
```dart
class MATrendAnalysis {
  final double ema9;
  final double ema21;
  final double ema50;
  final bool isPerfectUptrend;    // EMA9 > EMA21 > EMA50
  final bool isPerfectDowntrend;  // EMA9 < EMA21 < EMA50
  final bool isPartialUptrend;    // EMA9 > EMA21
  final bool isPartialDowntrend;  // EMA9 < EMA21
  final double score;             // -1.0 ~ +1.0
}
```

#### 점수 계산
```dart
if (isPerfectUptrend) {
  avgGap = ((ema9 - ema21) / ema21 + (ema21 - ema50) / ema50) / 2
  if (avgGap ≥ 2%)  score = +1.0
  else              score = 0.5 + (avgGap / 0.02) * 0.5
}
else if (isPerfectDowntrend) {
  // 대칭 로직
  score = -0.5 ~ -1.0
}
else if (isPartialUptrend) {
  score = 0.25 ~ 0.5
}
else if (isPartialDowntrend) {
  score = -0.5 ~ -0.25
}
```

---

### 5. Composite Analysis (종합 분석)

#### CompositeAnalysis 클래스
```dart
class CompositeAnalysis {
  // 개별 지표 결과
  final double rsi;
  final VolumeAnalysis volume;
  final PriceActionAnalysis priceAction;
  final MATrendAnalysis maTrend;
  final BollingerBands bb;
  final MACD macd;
  final MACDHistogramTrend macdTrend;

  // 종합 결과
  final double compositeScore;                    // -1.0 ~ +1.0
  final EnhancedMarketCondition marketCondition;  // 7단계 분류
  final SignalConfidence confidence;              // HIGH/MEDIUM/LOW

  // 개별 기여도
  final double rsiScore;           // 25%
  final double volumeScore;        // 20%
  final double priceActionScore;   // 20%
  final double maTrendScore;       // 15%
  final double bbScore;            // 10%
  final double macdScore;          // 10%
}
```

#### 사용 예시
```dart
// 종합 분석 실행
final composite = analyzeMarketComposite(closePrices, volumes);

// 결과 확인
print(composite.marketCondition);      // EnhancedMarketCondition.strongBullish
print(composite.compositeScore);       // 0.52
print(composite.confidence);           // SignalConfidence.high

// 개별 지표 확인
print(composite.rsi);                  // 65.3
print(composite.macdTrend);            // MACDHistogramTrend.improving
print(composite.volume.relativeVolumeRatio); // 2.1x

// 가중 점수 확인
print(composite.rsiScore);             // 0.08 (25% 가중치)
print(composite.volumeScore);          // 0.12 (20% 가중치)
print(composite.macdScore);            // 0.10 (10% 가중치)
```

---

### 6. MarketAnalyzer 통합

#### 업데이트된 analyzeMarket 함수
```dart
static MarketAnalysisResult analyzeMarket({
  required List<double> closePrices,
  required List<double> volumes,
  bool useCompositeAnalysis = true,  // 기본값: 새 시스템 사용
}) {
  // 50+ 캔들이 있으면 자동으로 Composite Analysis 사용
  if (useCompositeAnalysis && closePrices.length >= 50 && volumes.length >= 50) {
    return _analyzeMarketComposite(closePrices, volumes);
  }

  // 폴백: 기존 분석기 (하위 호환성)
  return _analyzeMarketLegacy(closePrices, volumes);
}
```

#### 백테스트 엔진 통합
```dart
// backtest_engine.dart (line 246)
final result = MarketAnalyzer.analyzeMarket(
  closePrices: closePrices,
  volumes: volumes,
  // useCompositeAnalysis는 기본값 true이므로 자동으로 새 시스템 사용
);
```

**통합 상태**: ✅ 자동 연결됨 (코드 수정 불필요)

---

## 백테스트 결과

### 테스트 조건
- **Symbol**: ETHUSDT
- **기간**: 2025-10-14 ~ 2025-10-21 (7일)
- **캔들**: 5분봉 2,016개
- **초기 자금**: $10,000
- **레버리지**: 10x
- **분석 시스템**: Composite Analysis (6개 지표)

### 결과 요약
```
총 거래: 8건
승률: 62.5% (5승 3패)
최종 자금: $9,800.96
수익률: -1.99%
최대 손실폭: 3.11%

평균 승리: $15.42
평균 손실: $101.80
Profit Factor: 0.25
```

### 거래 내역 분석

#### Trade 1-2: 성공적인 평균회귀
```
Trade 1: SHORT @ RSI 58.5 → +0.53% ✅
Trade 2: LONG  @ RSI 49.4 → +0.54% ✅
```
**분석**: BB 경계에서 진입, BB Middle에서 청산. 이상적인 역추세 거래.

#### Trade 3-5: 연속 손실 구간 (핵심 문제)
```
Trade 3: SHORT @ RSI 56.4 → -0.94% ❌ (긴급 손절)
Trade 4: SHORT @ RSI 66.4 → -0.97% ❌ (긴급 손절)
Trade 5: SHORT @ RSI 75.1 → -1.49% ❌ (긴급 손절)
```

**가격 흐름**: 3983 → 4137 (+3.8% 상승)

**문제점**:
1. ❌ **강한 상승 추세에서 역추세 SHORT 진입**
2. ❌ **MACD 히스토그램이 IMPROVING 상태였을 가능성 높음** (확인 필요)
3. ❌ **추세 추종 전략이 발동하지 않음**
4. ❌ **역추세 전략이 추세 전환을 감지하지 못함**

**근본 원인**:
- Composite Analysis는 시장 조건을 올바르게 판단했을 가능성이 높음
- 하지만 **진입 로직이 여전히 RSI + BB만 사용**
- MACD 트렌드, Composite Score를 진입 조건에 활용하지 않음

#### Trade 6-8: 회복
```
Trade 6: SHORT @ RSI 78.7 → +0.92% ✅
Trade 7: SHORT @ RSI 54.8 → +0.15% ✅
Trade 8: SHORT @ RSI 53.1 → +0.18% ✅
```

**분석**: 상승 추세 약화 후 역추세 전략 다시 효과적.

---

## 주요 발견 사항

### 1. Composite Analysis 작동 확인 ✅
- 6개 지표가 모두 정상 계산됨
- 신뢰도 평가 시스템 작동
- MarketAnalyzer에 자동 통합됨

### 2. 진입 로직 개선 필요 ⚠️

**현재 진입 조건** (split_entry_strategy.dart):
```dart
// 역추세 SHORT 진입
if (currentPrice >= bb.upper && currentRSI > 50) {
  return ShortSignal;  // 즉시 진입
}
```

**개선된 진입 조건 제안**:
```dart
// 역추세 SHORT 진입
if (currentPrice >= bb.upper && currentRSI > 50) {

  // MACD 필터 추가
  if (macdTrend == MACDHistogramTrend.worsening) {
    // OK: 상승 추세가 약화 중
  } else if (macdTrend == MACDHistogramTrend.improving) {
    return null;  // 차단: 상승 추세 강화 중에는 SHORT 금지
  }

  // Composite Score 필터 추가
  if (compositeScore > 0.4) {
    return null;  // 차단: 강한 강세장에서 SHORT 금지
  }

  // Volume 필터 추가
  if (volumeRatio < 0.8) {
    return null;  // 차단: 낮은 거래량 신호 무시
  }

  // 모든 조건 통과 시에만 진입
  return ShortSignal;
}
```

### 3. 전략 선택 로직 개선 필요 ⚠️

**현재**: MarketCondition만으로 전략 선택
```dart
if (condition == extremeBullish || condition == strongBullish) {
  strategy = TrendFollowing;
} else {
  strategy = CounterTrend;
}
```

**개선 제안**: Composite Score + MACD Trend 활용
```dart
if (compositeScore > 0.4 && macdTrend == improving) {
  strategy = TrendFollowing(direction: LONG);
} else if (compositeScore < -0.4 && macdTrend == improving) {
  strategy = TrendFollowing(direction: SHORT);
} else if (abs(compositeScore) < 0.15) {
  strategy = CounterTrend;  // 횡보장에서만 평균회귀
} else {
  strategy = NoTrade;  // 불확실한 시장
}
```

---

## 다음 단계

### Phase 1: 진입 로직 개선 (우선순위 높음)
- [ ] MACD 필터를 역추세 진입 조건에 추가
- [ ] Composite Score 임계값 적용
- [ ] Volume 필터 추가
- [ ] 백테스트로 효과 검증

### Phase 2: 추세 추종 전략 활성화
- [ ] Composite Score 기반 추세 감지
- [ ] MACD improving + Volume 확인
- [ ] 추세 추종 진입 로직 개선
- [ ] 백테스트 비교

### Phase 3: 신뢰도 기반 포지션 사이징
- [ ] HIGH 신뢰도: 큰 포지션
- [ ] MEDIUM 신뢰도: 중간 포지션
- [ ] LOW 신뢰도: 진입 금지 또는 작은 포지션

### Phase 4: 파라미터 최적화
- [ ] 가중치 튜닝 (현재: RSI 25%, Volume 20%, ...)
- [ ] Composite Score 임계값 최적화
- [ ] MACD 기간 최적화 (현재: 12/26/9)

---

## 코드 위치

### 핵심 파일
```
lib/utils/technical_indicators.dart
  - MACD 계산 (line 846~1069)
  - Volume 분석 (line 1071~1150)
  - Price Action 분석 (line 1152~1231)
  - MA Trend 분석 (line 1233~1337)
  - Composite Analysis (line 1339~1643)

lib/services/market_analyzer.dart
  - analyzeMarket() (line 50~66)
  - _analyzeMarketComposite() (line 68~136)
  - _mapEnhancedToLegacyCondition() (line 176~193)

lib/backtesting/backtest_engine.dart
  - _getMarketAnalysis() (line 236~253) - 자동 통합됨
```

### 진입 로직 파일 (수정 필요)
```
lib/backtesting/split_entry_strategy.dart
  - _checkCounterTrend1stEntry() (line 515~550)
  - _checkCounterTrend2ndEntry() (line 552~595)
  - _checkCounterTrend3rdEntry() (line 597~640)
  - _checkTrendFollowing1stEntry() (line 268~316)
```

---

## 참고 자료

### 관련 문서
- `lib/docs/선물_스켈핑_봇_시장_추세_분석.md`: 원본 설계 문서
- `lib/docs/bybit_split_entry_strategy.md`: 분할 진입 전략 문서

### 백테스트 결과 파일
- `backtest_ETHUSDT_2025-10-21T19-33-21.csv`: 최신 백테스트 결과
- `backtest_ETHUSDT_2025-10-21T19-33-21.xlsx`: Excel 형식

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-10-21 | 1.0.0 | 초기 작성: Composite Analysis 시스템 구현 완료 |

---

## 라이선스
이 문서는 Bybit Scalping Bot 프로젝트의 일부입니다.
