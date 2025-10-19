# 🎯 전략 V4 - 시장 적응형 전략 (Adaptive Market Strategy)

## 💡 핵심 아이디어

**"추세에 순응하고, 역추세는 엄격하게"**

### V3의 문제점
```
❌ SHORT만 항상 엄격 → 하락장에서도 불리
❌ LONG만 항상 완화 → 상승장에서만 유리
❌ 시장 무시하고 고정 조건 사용
```

### V4의 해결책
```
✅ 봇 시작 시 추세 분석 (100-200 캔들)
✅ 추세 방향에 맞는 전략 선택
✅ 순추세 진입 완화, 역추세 진입 엄격화
✅ 횡보장 전용 전략 추가
```

---

## 📊 시장 추세 판별 로직

### 분석 기준
```dart
// 봇 시작 시 한 번만 분석
캔들 수: 200개 (5분봉 = 16시간 40분)
분석 방법: 선형 회귀 또는 단순 가격 비교
```

### 추세 분류
```dart
final startPrice = candles[0].close;
final endPrice = candles[199].close;
final priceChange = ((endPrice - startPrice) / startPrice) * 100;

if (priceChange > 1.0) {
  marketTrend = MarketTrend.uptrend;      // 상승장
} else if (priceChange < -1.0) {
  marketTrend = MarketTrend.downtrend;    // 하락장
} else {
  marketTrend = MarketTrend.sideways;     // 횡보장
}
```

### 추세별 기준값
```
상승장:  +1.0% 이상 상승
하락장:  -1.0% 이상 하락
횡보장:  -1.0% ~ +1.0%
```

---

## 🎯 추세별 전략 설정

### 📈 상승장 (Uptrend)

#### 전략: **LONG 적극, SHORT 보수**

```dart
LONG 조건 (완화):
✓ RSI6 < 30
✓ RSI14: 30-50
✓ 거래량 > 평균 × 1.5   // 2.0 → 1.5 완화
──────────────────────
3/3 조건 충족 시 진입

SHORT 조건 (엄격):
✓ RSI6 > 85             // 80 → 85 강화
✓ RSI14: 50-70
✓ 거래량 > 평균 × 3.5   // 3.0 → 3.5 강화
✓ 단기 하락 확인 필수
──────────────────────
4/4 조건 충족 시 진입
```

#### 논리
- 상승 추세 = LONG이 유리 → 진입 쉽게
- 역추세 SHORT = 위험 → 극도로 엄격

---

### 📉 하락장 (Downtrend)

#### 전략: **SHORT 적극, LONG 보수**

```dart
LONG 조건 (엄격):
✓ RSI6 < 25             // 30 → 25 강화
✓ RSI14: 30-50
✓ 거래량 > 평균 × 3.0   // 2.0 → 3.0 강화
✓ 단기 반등 확인 필수
──────────────────────
4/4 조건 충족 시 진입

SHORT 조건 (완화):
✓ RSI6 > 75             // 80 → 75 완화
✓ RSI14: 50-70
✓ 거래량 > 평균 × 2.0   // 3.0 → 2.0 완화
──────────────────────
3/3 조건 충족 시 진입
```

#### 논리
- 하락 추세 = SHORT가 유리 → 진입 쉽게
- 역추세 LONG = 위험 → 극도로 엄격

---

### 📊 횡보장 (Sideways)

#### 전략: **양방향 보수, 볼린저 밴드 활용**

```dart
LONG 조건 (중간):
✓ RSI6 < 25             // 과매도 극심
✓ RSI14: 30-50
✓ 거래량 > 평균 × 2.5
✓ 볼린저 하단 터치
──────────────────────
4/4 조건 충족 시 진입

SHORT 조건 (중간):
✓ RSI6 > 75             // 과열 극심
✓ RSI14: 50-70
✓ 거래량 > 평균 × 2.5
✓ 볼린저 상단 터치
──────────────────────
4/4 조건 충족 시 진입
```

#### 논리
- 횡보장 = 방향성 없음 → 양쪽 모두 엄격
- 밴드 터치 = 반전 확률 높음 → 평균 회귀 전략
- 거래량 필수 = 가짜 신호 배제

#### 볼린저 밴드 조건
```dart
// 하단 터치 (LONG)
currentPrice <= bollingerLower * 1.002  // 하단 0.2% 이내

// 상단 터치 (SHORT)
currentPrice >= bollingerUpper * 0.998  // 상단 0.2% 이내
```

---

## 📋 전략 비교표

| 조건 | 상승장 | 하락장 | 횡보장 |
|------|--------|--------|--------|
| **LONG RSI6** | < 30 | < 25 ⚠️ | < 25 ⚠️ |
| **LONG 거래량** | × 1.5 ✅ | × 3.0 ⚠️ | × 2.5 |
| **LONG 추가** | - | 반등 확인 | BB 하단 |
| **SHORT RSI6** | > 85 ⚠️ | > 75 ✅ | > 75 |
| **SHORT 거래량** | × 3.5 ⚠️ | × 2.0 ✅ | × 2.5 |
| **SHORT 추가** | 단기 하락 | - | BB 상단 |

✅ = 완화 (진입 쉬움)
⚠️ = 엄격 (진입 어려움)

---

## 🔄 추세 재분석 주기

### 옵션 1: 봇 시작 시 1회만
```dart
장점: 성능 좋음, 일관성 유지
단점: 장중 추세 변화 미반영
추천: 단기 트레이딩 (1-3시간)
```

### 옵션 2: 주기적 재분석
```dart
주기: 1시간마다
장점: 추세 변화 대응
단점: 전략 자주 변경 → 혼란
추천: 장기 운영 (24시간+)
```

### 옵션 3: 손익 기반 재분석
```dart
트리거: 연속 3회 손실 시
장점: 전략 미스매치 감지
단점: 손실 후 대응 (늦음)
추천: 안전 중시
```

**권장: 옵션 1 (봇 시작 시 1회) + 수동 재시작**

---

## 🎯 횡보장 전략 상세

### 왜 볼린저 밴드?
```
횡보장 특징:
- 일정 범위 내 등락 반복
- 추세 없음 → RSI만으로 부족
- 평균 회귀 성향 강함

볼린저 밴드:
- 상단 터치 → 과매수 → 하락 가능성
- 하단 터치 → 과매도 → 상승 가능성
- 통계적 근거 (표준편차 2σ)
```

### 볼린저 설정
```dart
기간: 20 (5분봉 = 100분)
표준편차: 2.0
터치 허용 오차: ±0.2%
```

### 진입 예시
```
LONG 진입 (횡보장):
─────────────────────
현재가: $3,850
볼린저 하단: $3,855
상단: $3,945
중간선: $3,900

조건:
✓ 가격 하단 터치: $3,850 ≤ $3,855 × 1.002
✓ RSI6: 24 (< 25)
✓ RSI14: 42 (30-50 범위)
✓ 거래량: 평균 × 2.8

→ LONG 진입 ✅
목표: 중간선 $3,900 (+1.3%)
```

---

## 💻 구현 구조

### 1. MarketTrend Enum 추가
```dart
enum MarketTrend {
  uptrend,    // 상승장: +1.0% 이상
  downtrend,  // 하락장: -1.0% 이하
  sideways,   // 횡보장: -1.0% ~ +1.0%
  unknown,    // 분석 전
}
```

### 2. TradingProvider에 추가
```dart
MarketTrend _currentTrend = MarketTrend.unknown;
DateTime? _trendAnalyzedAt;

// 봇 시작 시 호출
Future<void> _analyzeMarketTrend() async {
  final candles = await fetchCandles(limit: 200);
  _currentTrend = _determineTrend(candles);
  _trendAnalyzedAt = DateTime.now();
}
```

### 3. 조건 동적 설정
```dart
double getLongRsi6Threshold() {
  switch (_currentTrend) {
    case MarketTrend.uptrend: return 30.0;
    case MarketTrend.downtrend: return 25.0;
    case MarketTrend.sideways: return 25.0;
    default: return 30.0;
  }
}

double getLongVolumeMultiplier() {
  switch (_currentTrend) {
    case MarketTrend.uptrend: return 1.5;
    case MarketTrend.downtrend: return 3.0;
    case MarketTrend.sideways: return 2.5;
    default: return 2.0;
  }
}
```

### 4. 볼린저 밴드 계산 (횡보장)
```dart
if (_currentTrend == MarketTrend.sideways) {
  final bb = calculateBollingerBands(candles, period: 20);
  bool longBbCondition = currentPrice <= bb.lower * 1.002;
  bool shortBbCondition = currentPrice >= bb.upper * 0.998;
}
```

---

## 📊 예상 성과

### V3 (SHORT만 엄격)
```
상승장: LONG 50% → 좋음 ✅
하락장: SHORT 차단 → 나쁨 ❌
횡보장: 둘 다 중간 → 보통
─────────────────────────
범용성: 중간
```

### V4 (시장 적응형)
```
상승장: LONG 60% → 더 좋음 ✅
하락장: SHORT 60% → 좋음 ✅
횡보장: 평균회귀 50% → 안정 ✅
─────────────────────────
범용성: 높음 ✅✅
```

---

## 🚨 리스크 관리

### 1. 추세 오판
```
문제: 상승장을 하락장으로 잘못 판단
대책: 200 캔들 사용 (충분한 데이터)
      수동 확인 가능하도록 UI에 표시
```

### 2. 추세 급변
```
문제: 분석 후 시장 급변
대책: 연속 손실 3회 시 경고
      수동 재시작 권장
```

### 3. 횡보장 가짜 신호
```
문제: 볼린저 터치 후 계속 하락
대책: RSI + 거래량 필수 조건
      TP/SL 타이트하게 유지
```

---

## 🎯 UI 개선 필요사항

### 1. 현재 추세 표시
```
━━━━━━━━━━━━━━━━━━━━━━━━
📊 시장 분석
━━━━━━━━━━━━━━━━━━━━━━━━
추세: 📈 상승장 (+2.3%)
분석: 200 캔들 (16h 40m)
시각: 2025-10-19 14:30
━━━━━━━━━━━━━━━━━━━━━━━━
LONG: 완화 (RSI < 30, Vol × 1.5)
SHORT: 엄격 (RSI > 85, Vol × 3.5)
━━━━━━━━━━━━━━━━━━━━━━━━
```

### 2. 재분석 버튼
```
[🔄 추세 재분석]
```

### 3. 추세별 통계
```
━━━━━━━━━━━━━━━━━━━━━━━━
📊 추세별 성과
━━━━━━━━━━━━━━━━━━━━━━━━
상승장: 12 거래 | 승률 58%
하락장: 8 거래 | 승률 62%
횡보장: 5 거래 | 승률 40%
━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🔧 AppConstants 추가 필요

```dart
// Market Trend Analysis
static const int trendAnalysisCandleCount = 200;
static const double trendUptrendThreshold = 1.0;      // +1.0%
static const double trendDowntrendThreshold = -1.0;   // -1.0%

// Uptrend Settings
static const double uptrendLongRsi6 = 30.0;
static const double uptrendLongVolume = 1.5;
static const double uptrendShortRsi6 = 85.0;
static const double uptrendShortVolume = 3.5;

// Downtrend Settings
static const double downtrendLongRsi6 = 25.0;
static const double downtrendLongVolume = 3.0;
static const double downtrendShortRsi6 = 75.0;
static const double downtrendShortVolume = 2.0;

// Sideways Settings
static const double sidewaysLongRsi6 = 25.0;
static const double sidewaysLongVolume = 2.5;
static const double sidewaysShortRsi6 = 75.0;
static const double sidewaysShortVolume = 2.5;
static const bool sidewaysUseBollingerBands = true;
static const int sidewaysBollingerPeriod = 20;
static const double sidewaysBollingerStdDev = 2.0;
static const double sidewaysBollingerTouchTolerance = 0.002; // 0.2%
```

---

## ✅ 체크리스트

### 구현
- [ ] MarketTrend enum 추가
- [ ] 추세 분석 로직 구현
- [ ] 추세별 조건 getter 함수
- [ ] 볼린저 밴드 계산 (횡보장)
- [ ] UI에 추세 표시
- [ ] 재분석 버튼 추가

### 테스트
- [ ] 상승장 데이터로 테스트
- [ ] 하락장 데이터로 테스트
- [ ] 횡보장 데이터로 테스트
- [ ] 추세 전환 시 동작 확인

---

## 🚀 마이그레이션

### V3 → V4
```
1. AppConstants 업데이트
2. TradingProvider 수정
3. UI 추세 표시 추가
4. 기존 설정 호환성 유지
```

---

**버전**: V4 (Adaptive Market Strategy)
**철학**: "시장을 이기지 말고, 시장을 따라가라"
**핵심**: 순추세 적극, 역추세 보수, 횡보장 평균회귀
**상태**: 설계 완료, 구현 대기
