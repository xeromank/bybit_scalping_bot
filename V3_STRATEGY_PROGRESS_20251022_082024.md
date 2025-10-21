# V3 전략 개발 진행 상황

**작성일**: 2025-10-22 08:20:24
**버전**: V3 Strategy Development Log

---

## 📋 목표

밴드워킹 감지 기반 **적응형 전략** 개발
- **밴드워킹 구간**: 추세 추종 진입
- **일반 구간**: 역추세 평균회귀 진입

---

## ✅ 완료된 작업

### 1. 밴드워킹 감지기 점수 재조정

**변경 전 (100점 만점)**:
| 지표 | 점수 | 비중 |
|------|------|------|
| BB Width 확장 | 25점 | 낮음 |
| 연속 밴드 밖 캔들 | 30점 | 높음 |
| MACD 히스토그램 | 20점 | 중간 |
| Volume 증가 | 15점 | 중간 |
| RSI 극단 유지 | 10점 | 낮음 |

**변경 후 (105점 만점, 중복 가능)**:
| 지표 | 점수 | 비중 | 변경 이유 |
|------|------|------|----------|
| **BB Width 확장** | **40점** | **PRIMARY** | 밴드워킹의 핵심 지표 |
| **RSI 극단 유지** | **30점** | **CRITICAL** | 추세 지속성 확인 |
| MACD 히스토그램 | 20점 | 중간 | 방향성 확인 유지 |
| 연속 밴드 밖 캔들 | 10점 | 보조 | 보조 지표로 하향 |
| Volume 증가 | 5점 | 보조 | 초기 감지에는 불필요 |

**BB Width 세부 점수**:
- `변화율 > 3.0%`: 40점 (급증)
- `변화율 > 1.0%`: 30점 (확장)
- `변화율 > 0%`: 20점 (미세 확장)

**RSI 세부 점수**:
- `RSI > 70 or < 30`: 30점 (극단)
- `RSI 65-70 or 30-35 (추세 유지)`: 20점 (극단 영역)

**리스크 레벨**:
- `점수 >= 70`: HIGH (밴드워킹 확정)
- `점수 >= 50`: MEDIUM (밴드워킹 위험)
- `점수 >= 30`: LOW (주의)
- `점수 < 30`: NONE (정상)

### 2. 밴드워킹 방향 판정 로직 개선

**변경 전**:
```dart
if (currentPrice > bb.upper) direction = 'UP';
else if (currentPrice < bb.lower) direction = 'DOWN';
else direction = 'NONE';
```

**변경 후**:
```dart
if (currentPrice > bb.upper) {
  direction = 'UP';
} else if (currentPrice < bb.lower) {
  direction = 'DOWN';
} else if (risk == HIGH || risk == MEDIUM) {
  // 밴드워킹 위험이 있으면 RSI로 방향 판단
  if (rsi > 60) direction = 'UP';
  else if (rsi < 40) direction = 'DOWN';
  else direction = 'NONE';
} else {
  direction = 'NONE';
}
```

**개선점**: 가격이 BB 내부에 있어도 밴드워킹 위험이 있으면 RSI로 방향 판단

### 3. 전략별 청산 로직 차별화

#### 역추세 (Counter-Trend) 전략
- **진입**: BB 하위 20% 또는 상위 20% 영역
- **익절**: BB Middle 도달
- **손절**: -0.5%

#### 추세 추종 (Trend-Following) 전략
- **진입**: 밴드워킹 HIGH 리스크 + 방향 확정
- **익절**:
  - 1순위: BB 반대 밴드 도달 (Upper/Lower)
  - 2순위: 밴드워킹 종료 + BB Middle 도달
- **손절**: -5.0% (넓은 손절폭으로 일시적 조정 허용)

**손절폭 테스트 결과**:
| 손절폭 | 수익률 | 비고 |
|--------|--------|------|
| -1.0% | -0.77% | 밴드워킹 중 조기 손절 발생 |
| -5.0% | -0.59% | ✅ 채택 (일시적 조정 허용) |

### 4. 긴급 손절 로직

**반대 방향 밴드워킹 감지 시 즉시 청산**:
```dart
// LONG 포지션 중 하락 밴드워킹 HIGH 감지
if (position.currentSide == LONG &&
    bandWalking.direction == 'DOWN' &&
    bandWalking.risk == HIGH) {
  // 긴급 손절
}
```

---

## 📊 백테스트 결과

### 테스트 기간
- **날짜**: 2025-10-19 ~ 2025-10-21 (3일간)
- **심볼**: ETHUSDT
- **타임프레임**: 5분봉
- **데이터**: 855개 캔들

### 최종 성능
- **총 거래**: 42건
- **승률**: 57.1% (24승 18패)
- **수익률**: -0.59%
- **초기 자금**: $10,000
- **최종 자금**: $9,940.82

### 거래 유형 분석
- **추세 추종**: 약 20건 (밴드워킹 감지 후 진입)
- **역추세**: 약 22건 (BB 경계에서 평균회귀)

---

## 🎯 핵심 개선 사례

### Case 1: 14:45 잘못된 SHORT 진입 차단 ✅

**이전 (점수 재조정 전)**:
```
14:45 - Price: 3952.94, RSI: 66.3, MACD: 5.79, Volume: 0.9x
       → Score: 45 (LOW)
       → 역추세 SHORT 진입 허용
       → 가격 상승으로 손절 (-0.72%)
```

**현재 (점수 재조정 후)**:
```
14:45 - Price: 3952.94, RSI: 66.3, MACD: 5.79, Volume: 0.9x
       → Score: 80 (HIGH)
       → 역추세 진입 차단 ✅
       → 손실 방지
```

**개선 효과**: Volume이 낮아도 BB Width + RSI + MACD로 밴드워킹 조기 감지

### Case 2: 14:50 추세 추종 진입 성공 ✅

```
14:50 - ENTRY: LONG @ $3969.99
        상승 밴드워킹 확정 (Score: 80)
14:55 - EXIT:  LONG @ $4020.78
        → +$63.95 (+1.28%) ✅
```

**개선 효과**: 밴드워킹 감지 후 추세 추종으로 큰 수익 실현

### Case 3: 08:15 밴드워킹 반전 손절 완화 ✅

**이전 (SL -1.0%)**:
```
08:15 - ENTRY: LONG @ $3928.33
08:20 - EXIT:  LONG @ $3880.29 → -$61.23 (-1.22%) 손절
```

**현재 (SL -5.0%)**:
```
08:15 - ENTRY: LONG @ $3928.33
09:40 - EXIT:  LONG @ $3894.35 → -$43.31 (-0.86%) 밴드워킹 종료
```

**개선 효과**: 넓은 손절폭으로 밴드워킹 종료 시점까지 대기, 손실 -1.22% → -0.86%

---

## ⚠️ 현재 발견된 문제점

### 문제 1: 일시적 Pullback을 밴드워킹 종료로 오판 🔴

**발생 구간**: UTC 21일 14:00~16:00

**실제 차트**:
- 가격: 3872 → 4093 (+5.7% 연속 상승)
- 명백한 상승 밴드워킹 구간

**감지기 판단**:
```
14:10 - Score: 85 (HIGH) ✅
14:15 - Score: 80 (HIGH) ✅
14:20 - Score: 80 (HIGH) ✅
14:25 - Score: 40 (LOW) ❌ <- 일시적 하락으로 LOW 판정
14:30 - Score: 50 (MEDIUM)
14:35 - Score: 50 (MEDIUM)
14:40 - Score: 40 (LOW)
14:45 - Score: 80 (HIGH) ✅ <- 재감지
```

**백테스트 실행**:
```
14:20 - ENTRY: LONG @ $3941.49
14:25 - EXIT:  LONG @ $3913.00 → -$36.26 (-0.72%) 밴드워킹 종료 청산
```

**놓친 기회**:
- 14:55: 4020 도달 (+2.0%)
- 16:00: 4093 도달 (+3.9%)

**원인 분석**:
1. **14:25 pullback**: 3941 → 3913 (-0.7% 일시적 하락)
2. **RSI 하락**: 68.6 → 56.8 (극단 영역 벗어남)
3. **BB Width 변화율 감소**: 이전 대비 확장률 낮아짐
4. **점수 급락**: 80 → 40 (밴드워킹 종료로 판단)

**근본 원인**:
- BB Width를 **이전 캔들과의 변화율**로만 판단
- **절대적인 BB Width** 고려 안 함
- **밴드워킹 관성(inertia)** 없음

---

## 💡 다음 단계 해결 방안

### 방안 1: 밴드워킹 관성(Inertia) 추가

```dart
// 밴드워킹 상태 추적
class BandWalkingState {
  BandWalkingRisk currentRisk;
  int consecutiveHighFrames; // HIGH 유지 캔들 수
  int framesInCooldown; // 쿨다운 남은 캔들 수
}

// HIGH 리스크 최소 유지 기간
const int MIN_HIGH_FRAMES = 3; // 최소 3개 캔들 (15분)
const int COOLDOWN_FRAMES = 2; // HIGH 종료 후 2개 캔들 유예
```

**로직**:
1. HIGH 리스크 진입 시 `consecutiveHighFrames` 카운트 시작
2. 점수가 떨어져도 `MIN_HIGH_FRAMES` 동안 HIGH 유지
3. HIGH 종료 후 `COOLDOWN_FRAMES` 동안 재진입 쉽게 설정

### 방안 2: BB Width 절대값 임계값 추가

```dart
// BB Width 절대값이 충분히 크면 밴드워킹으로 판단
final bbWidth = (bb.upper - bb.lower) / bb.middle;

if (bbWidth > 0.05) { // 5% 이상이면
  score += 20; // 추가 점수
}
```

### 방안 3: 추세 지속성 확인

```dart
// MACD와 RSI가 같은 방향 유지 중이면 점수 유지
if (macd.histogram > 0 && rsi > 55) {
  // 상승 추세 유지 중
  score += 10;
}
```

---

## 📝 기술적 세부사항

### 파일 구조
```
lib/
├── backtesting/
│   ├── entry_strategy_v3.dart      # V3 전략 메인 로직
│   └── position_tracker.dart       # 포지션 추적
├── services/v3/
│   ├── band_walking_detector.dart  # 밴드워킹 감지기 (재조정 완료)
│   └── breakout_classifier.dart    # 브레이크아웃 분류
└── utils/
    └── technical_indicators.dart   # BB, RSI, MACD 계산

scripts/
├── simple_backtest_v3.dart        # 백테스트 실행
└── detailed_v3_log.dart           # 프레임별 CSV 로그 생성
```

### 핵심 코드 위치

**밴드워킹 감지 점수**: `lib/services/v3/band_walking_detector.dart:58-157`
- BB Width: 40점
- RSI 극단: 30점
- MACD: 20점
- 연속 밴드 밖: 10점
- Volume: 5점

**방향 판정**: `lib/services/v3/band_walking_detector.dart:171-188`

**전략별 손절**: `lib/backtesting/entry_strategy_v3.dart:368-385`
- 추세 추종: -5.0%
- 역추세: -0.5%

**청산 로직**: `lib/backtesting/entry_strategy_v3.dart:387-440`

---

## 🔄 변경 이력

### 2025-10-22 08:20
- ✅ 밴드워킹 감지기 점수 재조정 완료
- ✅ 방향 판정 로직 개선
- ✅ 전략별 손절/익절 차별화
- ✅ 백테스트 수익률 -1.01% → -0.59% 개선
- 🔴 일시적 pullback 오판 문제 발견
- 📋 밴드워킹 관성 로직 필요

### 다음 작업 예정
1. 밴드워킹 관성(inertia) 로직 구현
2. BB Width 절대값 임계값 추가
3. 추세 지속성 확인 로직 강화
4. 재백테스트 및 성능 검증

---

## 📌 참고사항

### 타임존 주의
- 모든 로그는 **UTC 기준**
- 한국 시간(KST) = UTC + 9시간
- 예: UTC 14:00 = KST 23:00

### 백테스트 실행 방법
```bash
# 간단 백테스트
dart run scripts/simple_backtest_v3.dart

# 상세 CSV 로그 생성
dart run scripts/detailed_v3_log.dart

# 생성된 CSV 분석
grep "2025-10-21T14:" v3_detailed_log_*.csv
```

### 주요 지표 해석
- **BWScore 70+**: 밴드워킹 확정 (추세 추종)
- **BWScore 50-69**: 밴드워킹 위험 (관망 또는 조심스러운 진입)
- **BWScore 30-49**: 주의 (역추세 가능)
- **BWScore 0-29**: 정상 (역추세 선호)

---

**끝**
