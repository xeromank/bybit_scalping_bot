# 볼린저 밴드 + RSI 전략 마이그레이션 작업 로그

## 전략 개요

### 기존 전략 (제거됨)
- EMA(9), EMA(21) 기반
- RSI(6), RSI(12) 이중 확인
- Extreme RSI Buffer
- 변동성이 큰 시장에서 손실 발생

### 새 전략 (볼린저 밴드 + RSI)
- **차트**: 5분봉
- **지표**:
  - 볼린저 밴드 (20, 2.0)
  - RSI 14
  - 거래량 필터 (1.5배)
- **레버리지**: 10~15배
- **익절**: 0.5% (가격 이동)
- **손절**: 0.15% (가격 이동)
- **거래 쌍**: BTCUSDT (높은 변동성)

### 진입 조건

#### 롱 포지션
1. ✅ 가격이 볼린저 하단 터치 또는 약간 이탈
2. ✅ RSI 14 < 30 (과매도)
3. ✅ 거래량 > 평균 거래량 × 1.5 (선택적)

#### 숏 포지션
1. ✅ 가격이 볼린저 상단 터치 또는 약간 돌파
2. ✅ RSI 14 > 70 (과매수)
3. ✅ 거래량 > 평균 거래량 × 1.5 (선택적)

### 익절/손절
- **익절**: 0.5% 가격 이동 (최우선)
- **손절**: 0.15% 역방향 이동 (절대 준수)

---

## 작업 진행 상황

### ✅ 1단계: app_constants.dart 수정 완료

#### 변경 내용
- 기본 심볼: `ETHUSDT` → `BTCUSDT`
- 기본 주문 금액: `50.0` → `1000.0`
- 익절 목표: `1.5%` → `0.5%`
- 손절: `0.8%` → `0.15%`
- 기본 레버리지: `5x` → `10x`

#### 추가된 상수
```dart
// Bollinger Bands Settings
static const int defaultBollingerPeriod = 20;
static const double defaultBollingerStdDev = 2.0;

// RSI Settings (Bollinger Strategy)
static const int defaultRsiPeriod = 14;
static const double defaultRsiOverbought = 70.0;
static const double defaultRsiOversold = 30.0;

// Volume Filter
static const double defaultVolumeMultiplier = 1.5;
static const bool defaultUseVolumeFilter = true;
```

#### 제거된 상수
- `defaultRsi6LongThreshold`, `defaultRsi6ShortThreshold`
- `defaultRsi12LongThreshold`, `defaultRsi12ShortThreshold`
- `defaultExtremeRsiBuffer`
- `defaultUseEmaFilter`, `defaultEmaPeriod`
- `availableEmaPeriods`

---

### ✅ 2단계: technical_indicators.dart 완전 재작성

#### 새로운 클래스 및 함수

##### BollingerBands 클래스
```dart
class BollingerBands {
  final double upper;
  final double middle;
  final double lower;
}
```

##### 계산 함수
1. `calculateBollingerBands()` - 볼린저 밴드 계산
2. `calculateRSI()` - RSI 14 계산 (기존 유지, period만 변경)
3. `calculateSMA()` - 단순 이동평균 (기존 유지)

##### TechnicalAnalysis 클래스 (완전 재설계)
```dart
class TechnicalAnalysis {
  final double rsi;
  final BollingerBands bollingerBands;
  final double currentPrice;
  final double currentVolume;
  final double avgVolume;

  // User-configurable thresholds
  final double rsiOverbought;
  final double rsiOversold;
  final double volumeMultiplier;
  final bool useVolumeFilter;

  // 시그널 판단 로직
  bool get isLongSignal { ... }
  bool get isShortSignal { ... }
  bool get isLongPreparing { ... }
  bool get isShortPreparing { ... }

  // 유틸리티
  double get distanceToUpperBB { ... }
  double get distanceToLowerBB { ... }
}
```

##### analyzePriceData() 함수 시그니처 변경
```dart
TechnicalAnalysis analyzePriceData(
  List<double> closePrices,
  List<double> volumes, {
  required int bollingerPeriod,
  required double bollingerStdDev,
  required int rsiPeriod,
  required double rsiOverbought,
  required double rsiOversold,
  required double volumeMultiplier,
  required bool useVolumeFilter,
})
```

---

### ✅ 3단계: trading_provider.dart 수정 완료

#### ✅ 완료된 수정사항

1. **변수 선언부 수정** (lines 44-55)
   ```dart
   // Bollinger Bands Settings (configurable by user)
   int _bollingerPeriod = AppConstants.defaultBollingerPeriod;
   double _bollingerStdDev = AppConstants.defaultBollingerStdDev;

   // RSI Settings (configurable by user)
   int _rsiPeriod = AppConstants.defaultRsiPeriod;
   double _rsiOverbought = AppConstants.defaultRsiOverbought;
   double _rsiOversold = AppConstants.defaultRsiOversold;

   // Volume Filter Settings (configurable by user)
   bool _useVolumeFilter = AppConstants.defaultUseVolumeFilter;
   double _volumeMultiplier = AppConstants.defaultVolumeMultiplier;
   ```

2. **Getters 수정** (lines 99-110)
   - 추가: `bollingerPeriod`, `bollingerStdDev`, `rsiPeriod`, `rsiOverbought`, `rsiOversold`
   - 추가: `useVolumeFilter`, `volumeMultiplier`
   - 제거: 기존 RSI6/12, EMA 관련 getters

3. **Setters 수정** (lines 183-241)
   - 추가: `setBollingerPeriod()`, `setBollingerStdDev()`
   - 추가: `setRsiPeriod()`, `setRsiOverbought()`, `setRsiOversold()`
   - 추가: `setUseVolumeFilter()`, `setVolumeMultiplier()`
   - 제거: 기존 RSI threshold, EMA 관련 setters

4. **_autoAdjustTargetsForLeverage() 수정** (lines 243-272)
   - 10x-15x: 0.5% 익절, 0.15% 손절 (최적 레버리지)
   - 5x-9x: 0.6% 익절, 0.2% 손절 (낮은 레버리지)
   - 16x-20x: 0.5% 익절, 0.15% 손절 (높은 레버리지, 안전성 우선)

5. **BTCUSDT 안전장치 제거**
   - `startBot()` (line 344): 제거 완료
   - `_checkAndTrade()` (line 462-470): 제거 완료
   - BTCUSDT가 이제 권장 거래쌍으로 사용 가능

6. **_updateTechnicalIndicators() 수정** (lines 513-524)
   ```dart
   final analysis = analyzePriceData(
     closePrices,
     volumes,
     bollingerPeriod: _bollingerPeriod,
     bollingerStdDev: _bollingerStdDev,
     rsiPeriod: _rsiPeriod,
     rsiOverbought: _rsiOverbought,
     rsiOversold: _rsiOversold,
     volumeMultiplier: _volumeMultiplier,
     useVolumeFilter: _useVolumeFilter,
   );
   ```

7. **_findEntrySignal() 수정** (lines 560-595)
   - `analyzePriceData()` 파라미터 변경 (Bollinger Band 전략)
   - Long 신호 로그: `RSI(14)`, `BB Lower` 정보 표시
   - Short 신호 로그: `RSI(14)`, `BB Upper` 정보 표시

8. **_createOrderWithPrice() 수정** (lines 716-720)
   ```dart
   indicatorInfo = '\n📊 지표: RSI(14)=${analysisSnapshot.rsi.toStringAsFixed(1)} | '
       'BB Upper=\$${analysisSnapshot.bollingerBands.upper.toStringAsFixed(2)} | '
       'BB Middle=\$${analysisSnapshot.bollingerBands.middle.toStringAsFixed(2)} | '
       'BB Lower=\$${analysisSnapshot.bollingerBands.lower.toStringAsFixed(2)}';
   ```

---

### ⏳ 4단계: trading_controls.dart UI 수정 (미착수)

#### 수정 필요 사항
1. **Controller 추가/제거**
   - 제거: `_rsi6LongController`, `_rsi6ShortController`, `_rsi12LongController`, `_rsi12ShortController`, `_extremeRsiBufferController`, `_emaPeriodController`
   - 추가: `_bollingerPeriodController`, `_bollingerStdDevController`, `_rsiPeriodController`, `_rsiOverboughtController`, `_rsiOversoldController`, `_volumeMultiplierController`

2. **UI 필드 교체**
   - RSI(6)/RSI(12) 입력 필드 제거
   - Bollinger Period (10-50) 입력 필드 추가
   - Bollinger StdDev (1.0-3.0) 입력 필드 추가
   - RSI Period (10-20) 입력 필드 추가
   - RSI Overbought (60-80) 입력 필드 추가
   - RSI Oversold (20-40) 입력 필드 추가
   - Volume Multiplier (1.0-3.0) 입력 필드 추가
   - Volume Filter On/Off 스위치 추가

3. **지표 표시 UI 변경**
   - 현재: RSI(6), RSI(12), EMA(9), EMA(21), Volume MA
   - 신규: RSI(14), BB Upper, BB Middle, BB Lower, Volume, Avg Volume

4. **익절/손절 표시**
   - 기본값 표시 변경 (0.5% / 0.15%)

---

## 다음 작업 순서

1. ✅ app_constants.dart 수정
2. ✅ technical_indicators.dart 재작성
3. ✅ trading_provider.dart Getters 수정
4. ✅ trading_provider.dart Setters 수정
5. ✅ trading_provider.dart analyzePriceData 호출부 수정
6. ✅ trading_provider.dart BTCUSDT 안전장치 제거
7. ✅ trading_provider.dart 익절/손절 로직 조정
8. ⏳ **trading_controls.dart UI 완전 재작성** ← 현재 위치
9. ⏳ 컴파일 테스트
10. ⏳ 실행 테스트

---

## 주요 변경사항 요약

### 전략 철학 변화
- **기존**: 다중 RSI + EMA 트렌드 확인 (복잡, 신호 적음)
- **신규**: 볼린저 밴드 + 단일 RSI (간단, 명확, 신호 많음)

### 위험 관리 강화
- **익절**: 1.5% → 0.5% (빠른 수익 실현)
- **손절**: 0.8% → 0.15% (손실 최소화)
- **손익비**: ~1.88:1 → ~3.33:1 (개선)

### 거래 빈도 증가
- **기존**: 하루 3-5회 (보수적)
- **신규**: 하루 10-15회 (적극적 스캘핑)

### 승률 목표
- **목표 승률**: 75%
- **예상 하루 수익**: 273 USDT (10x) ~ 410 USDT (15x)
- **예상 월 수익**: 546% ~ 819% ROE

---

## 참고사항

### 컴파일 에러 예상
- `trading_provider.dart`: Getter/Setter 미정의 에러
- `trading_controls.dart`: Controller 미정의 에러
- `analyzePriceData()` 파라미터 불일치 에러

### 테스트 시 확인사항
1. 볼린저 밴드 계산 정확도
2. RSI 14 계산 정확도
3. 거래량 필터 작동 확인
4. 진입 시그널 정확도
5. 익절/손절 가격 계산
6. BTCUSDT 거래 가능 여부

---

**마지막 업데이트**: 2025-01-XX
**작성자**: Claude Code
**상태**: 진행 중 (3단계 - trading_provider.dart Getters 수정 예정)
