# 진입 포인트 분석 리포트

## 📊 요약

최근 4시간 동안 **2개의 진입 윈도우**가 발견되었으나, 봇이 실제로 매수를 실행하지 않았습니다.

### 진입 윈도우 상세

#### 윈도우 1: 04:45 ~ 05:00 (20분)
- **지속 시간**: 4개 캔들 (20분)
- **최대 시그널 강도**: 1.00
- **RSI 범위**: 22.9 ~ 29.4
- **볼린저 위치**: 6.8% ~ 17.6%
- **진입 캔들**:
  - 04:45 - RSI 29.4, BB 6.8%, 강도 0.80 ✓
  - 04:50 - RSI 25.0, BB 25.1%, 강도 0.80 ✓
  - 04:55 - RSI 31.2, BB 34.3%, 강도 1.00 ✓✓ (최강)
  - 05:00 - RSI 22.9, BB 17.6%, 강도 0.80 ✓

#### 윈도우 2: 06:25 ~ 06:35 (15분)
- **지속 시간**: 3개 캔들 (15분)
- **최대 시그널 강도**: 1.00
- **RSI 범위**: 24.1 ~ 31.2
- **볼린저 위치**: -14.7% ~ 16.4% (볼린저 하단 아래로 돌파!)
- **진입 캔들**:
  - 06:25 - RSI 31.2, BB -14.7%, 강도 0.80 ✓
  - 06:30 - RSI 26.7, BB -4.4%, 강도 1.00 ✓✓ (최강)
  - 06:35 - RSI 24.1, BB 16.4%, 강도 0.80 ✓

### 통계
- **총 진입 윈도우**: 2개
- **총 진입 가능 캔들**: 7개
- **평균 지속 시간**: 17.5분
- **총 기회 시간**: 35분

## 🔍 봇이 매수하지 않은 이유 분석

### 1. ✅ 전략 로직은 정상
- Python 백테스트와 Dart 실제 코드가 정확히 일치
- 진입 조건: RSI ≤32, BB위치 <40%, 거래량 ≥1.1x, 시그널 강도 ≥0.8
- 코드 확인 결과 로직 문제 없음

### 2. ✅ 타이밍 문제 아님
- 각 진입 신호가 평균 **17.5분** 지속
- 봇이 1초마다 체크하므로 놓칠 가능성 거의 없음
- 1,050번의 체크 기회가 있었음 (17.5분 × 60초)

### 3. ⚠️ 가능한 원인

#### A. 봇이 해당 시간에 실행 중이 아니었을 가능성 ⭐ (가장 유력)
```
윈도우 1: 04:45 ~ 05:00 (새벽 4시 45분)
윈도우 2: 06:25 ~ 06:35 (새벽 6시 25분)
```
- 봇을 언제 시작했는지 확인 필요
- 이 시간대에 봇이 실행 중이었는지 확인 필요
- 앱이 백그라운드로 전환되어 중단되었을 수 있음 (iOS 특성)

#### B. 지표 계산 차이 가능성
- **차트 API (5분봉 완성 데이터)** vs **실시간 WebSocket 티커**
- 백테스트는 완성된 5분봉 기준으로 계산
- 실시간 봇은 WebSocket으로 받은 현재가 기준으로 계산
- 5분 캔들이 완성되기 전의 실시간 가격으로는 조건 미충족 가능

#### C. 데이터 동기화 이슈
현재 봇 구조:
```dart
// 0.5초마다 차트 API 호출하여 지표 계산
_indicatorUpdateTimer = Timer.periodic(
  const Duration(milliseconds: 500),
  (_) => _updateTechnicalIndicators(),
);

// 1초마다 봇 사이클 실행
_botTimer = Timer.periodic(
  const Duration(seconds: 1),
  (_) => _runBotCycle(),
);
```

**문제점**:
1. 0.5초마다 차트 데이터 fetch → API 부하, 속도 제한 가능
2. `_runBotCycle()`에서 다시 `_updateTechnicalIndicators()` 호출 (중복)
3. API 응답 지연 시 타이밍 어긋날 수 있음

#### D. 차트 데이터 캐싱 이슈
- Coinone API가 5분봉 데이터를 실시간으로 업데이트하지 않을 수 있음
- 캔들이 완성되기 전에는 이전 데이터를 반환할 수 있음
- 봇이 "아직 완성되지 않은 캔들"을 기준으로 판단할 수 있음

## 💡 해결 방안

### 1. 우선 확인 사항
```
□ 봇이 04:45~05:00, 06:25~06:35 시간대에 실행 중이었는지 확인
□ 거래 로그(trade_logs 테이블) 확인하여 해당 시간대 로그 존재 여부 확인
□ 앱이 백그라운드로 전환되지 않았는지 확인
```

### 2. 디버깅 개선
현재 봇은 다음 정보만 로그:
```dart
debugPrint('[Bot Cycle] Trend: $trendDesc, Volatility: $volatilityDesc');
_logTrade('info', '[$currentStrategyName] ${signal.reason}');
```

**추가 필요한 로그**:
```dart
// 매 사이클마다 상세 지표 로깅
_logTrade('debug', 'RSI: ${indicators.rsi.toStringAsFixed(1)}, '
  'BB Position: ${bbPosition.toStringAsFixed(1)}%, '
  'Volume Ratio: ${indicators.volumeRatio.toStringAsFixed(2)}x, '
  'Signal Strength: ${signal.strength.toStringAsFixed(2)}');
```

### 3. 실시간 vs 차트 데이터 확인
```dart
// WebSocket 티커로 받은 현재가
final tickerPrice = _currentTicker?.last ?? 0;

// 차트 API로 계산한 현재가
final chartPrice = _technicalIndicators?.currentPrice ?? 0;

// 차이가 크면 경고
if ((tickerPrice - chartPrice).abs() / chartPrice > 0.01) {
  _logTrade('warning', 'Price mismatch: Ticker=$tickerPrice, Chart=$chartPrice');
}
```

### 4. 구조 개선 제안

#### 옵션 A: 캔들 완성 이벤트 기반
```dart
// WebSocket으로 5분 캔들 완성 시점 감지
// 캔들 완성 시에만 지표 재계산 및 진입 판단
```

#### 옵션 B: 하이브리드 접근
```dart
// 5분마다 차트 데이터 갱신 (캔들 완성 주기와 동기화)
// 실시간 티커는 포지션 청산 판단에만 사용
```

## 📝 다음 단계

1. **거래 로그 확인**
   ```sql
   SELECT datetime(timestamp/1000, 'unixepoch', 'localtime') as time,
          type, message
   FROM trade_logs
   WHERE timestamp >= 1697766300000  -- 2025-10-20 04:45
     AND timestamp <= 1697772900000  -- 2025-10-20 06:35
   ORDER BY timestamp;
   ```

2. **봇 실행 시간 확인**
   - 언제 봇을 시작했는지 확인
   - 앱이 백그라운드로 전환되었는지 확인

3. **상세 로깅 추가**
   - 매 사이클마다 RSI, BB위치, 거래량, 시그널 강도 로깅
   - 진입 조건 체크 결과 상세 로깅

4. **실시간 테스트**
   - 현재 시점부터 봇을 실행하여 다음 진입 신호 대기
   - 로그로 실제 동작 확인

## 🎯 결론

**봇 로직과 전략은 정상 작동**하고 있으며, 백테스트와 실제 코드가 일치합니다.

매수가 발생하지 않은 가장 유력한 원인:
1. **봇이 해당 시간(새벽 4~6시)에 실행 중이 아니었음**
2. iOS 앱이 백그라운드로 전환되어 타이머가 중단됨
3. 차트 API와 실시간 데이터 간 타이밍 차이

**권장 조치**:
- 봇 실행 시간과 로그를 확인하여 원인 파악
- 상세 로깅 추가하여 실시간 모니터링
- 백그라운드 실행 문제 해결 (iOS Notification 사용 등)
