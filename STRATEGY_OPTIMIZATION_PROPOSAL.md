# Strategy Optimization Proposal
## 기회 증가 + 리스크 감소 방안

### 📊 현재 상황 분석

**백테스트 결과 (500개 5분봉, ~41.7시간)**
- 상승 전략: 0회 진입
- 횡보 전략: 8회 진입 (~3시간마다 1회)
- 총 기회: 매우 낮음

**문제점:**
1. 상승장에서 RSI ≤ 35까지 떨어질 때는 대부분 큰 조정이 진행중
2. 조정 시 EMA9 < EMA21이 되어 진입 조건 실패
3. 전략이 너무 보수적 → 기회 부족

---

## 💡 제안 전략

### Option 1: **점진적 RSI 진입 (권장)**
리스크를 낮추면서 기회를 2-3배 증가

#### 상승 전략 수정:
```dart
// 기존: RSI ≤ 35에 전체 포지션
// 신규: RSI 구간별 차등 진입

if (rsi <= 30) {
  // 강한 과매도 → 전체 수량 (100%)
  orderAmount = baseAmount * 1.0;
  stopLoss = -5%;
  takeProfit = +3%;
} else if (rsi <= 35) {
  // 중간 과매도 → 절반 수량 (50%)
  orderAmount = baseAmount * 0.5;
  stopLoss = -4%;
  takeProfit = +2%;
} else if (rsi <= 40) {
  // 약한 과매도 → 소량 (25%)
  orderAmount = baseAmount * 0.25;
  stopLoss = -3%;
  takeProfit = +1.5%;
}
```

**장점:**
- ✅ 기회 2-3배 증가 (RSI 40까지 확장)
- ✅ 리스크 분산 (작은 수량으로 테스트)
- ✅ 위험/보상 비율 유지
- ✅ 평균 수익률은 비슷하지만 빈도 증가

**예상 결과:**
- 진입 기회: 8회 → 20-25회
- 평균 수익: 비슷 (작은 수량이지만 빈도 높음)

---

### Option 2: **조건 완화 (중간 리스크)**
하나의 조건을 살짝 완화

#### 상승 전략:
```dart
// 기존: Price > EMA21 (엄격)
// 신규: Price > EMA21 * 0.98 (2% 버퍼)

final bool priceNearEma21 = price > ema21 * 0.98;  // 완화
final bool oversoldRsi = rsi <= 35;                // 유지
final bool shortTermUptrend = ema9 > ema21 * 0.99; // 약간 완화
final bool notOverbought = price <= bbMiddle * 1.01; // 유지
final bool volumeConfirmation = volumeRatio >= 1.0;  // 유지
```

**장점:**
- ✅ 기회 1.5-2배 증가
- ✅ 리스크 약간만 증가
- ⚠️ SL/TP는 동일하게 유지

**예상 결과:**
- 진입 기회: 8회 → 15-20회
- 승률 약간 감소하지만 여전히 안전

---

### Option 3: **다중 타임프레임 확인 (가장 안전)**
15분봉도 함께 확인하여 잘못된 신호 필터링

#### 로직:
```dart
// 5분봉: RSI ≤ 40 (완화)
// 15분봉: RSI ≤ 50 AND EMA9 > EMA21 (상승 확인)

final candles5m = await getChart(interval: '5m', size: 500);
final candles15m = await getChart(interval: '15m', size: 200);

// 5분봉에서 진입 신호 발생
if (rsi5m <= 40) {
  // 15분봉에서 추세 확인
  if (rsi15m <= 50 && ema9_15m > ema21_15m) {
    // 더 큰 타임프레임에서 상승 추세 확인됨
    enterPosition();
  }
}
```

**장점:**
- ✅ 리스크 감소 (이중 확인)
- ✅ 기회는 약간 증가
- ✅ 잘못된 신호 필터링 강화
- ⚠️ 구현 복잡도 증가

**예상 결과:**
- 진입 기회: 8회 → 12-15회
- 승률 증가 (더 안전한 진입)

---

### Option 4: **볼린저 밴드 반등 전략 (횡보 강화)**
횡보장 전략을 개선하여 기회 증가

#### 횡보 전략 수정:
```dart
// 기존: BB Position < 30%, RSI ≤ 28
// 신규: BB Position < 40%, RSI ≤ 32 (약간 완화)

final bool nearLowerBand = bbPosition < 0.4;  // 30% → 40%
final bool deeplyOversold = rsi <= 32;        // 28 → 32
final bool notExtreme = rsi >= 15;            // 유지
final bool volumeSpike = volumeRatio >= 1.1;  // 1.2 → 1.1 (완화)

// TP/SL 조정
stopLoss = -2.5%;  // 3% → 2.5% (더 빠른 손절)
takeProfit = +1.2%; // 1% → 1.2% (약간 높임)
```

**장점:**
- ✅ 횡보장 기회 1.5배 증가
- ✅ 리스크/보상 비율 개선
- ✅ 빠른 손절로 리스크 감소

**예상 결과:**
- 횡보 진입: 8회 → 12-15회
- 더 나은 수익률 가능

---

## 🎯 추천 조합

### **Phase 1 (즉시 적용):**
1. **Option 1 (점진적 RSI)** - 상승 전략
2. **Option 4 (볼린저 개선)** - 횡보 전략

→ 기회 2-3배 증가, 리스크 분산

### **Phase 2 (검증 후 적용):**
3. **Option 3 (다중 타임프레임)** 추가
→ 신호 품질 향상

---

## 📈 예상 성과

### 현재:
- 진입 기회: 8회 / 41.7시간
- 빈도: 5시간마다 1회

### Option 1 + 4 적용 시:
- 진입 기회: 20-25회 / 41.7시간
- 빈도: 1.5-2시간마다 1회
- 리스크: 낮음 (작은 수량, 빠른 손절)

---

## 🔧 구현 우선순위

1. ✅ **Option 1 (점진적 RSI)** - 쉬움, 효과 큼
2. ✅ **Option 4 (볼린저 개선)** - 쉬움, 효과 중간
3. 🔲 **Option 2 (조건 완화)** - 보류 (Option 1 결과 보고)
4. 🔲 **Option 3 (다중 타임프레임)** - 복잡함, 나중에

---

## ⚠️ 주의사항

1. **백테스트 필수**: 각 옵션 적용 전 500개 캔들로 백테스트
2. **소액 테스트**: 실제 거래는 최소 금액으로 시작
3. **모니터링**: 첫 10-20거래는 수동으로 결과 확인
4. **점진적 적용**: 한 번에 하나씩 적용하고 검증

---

**어떤 옵션을 먼저 구현해볼까요?**
