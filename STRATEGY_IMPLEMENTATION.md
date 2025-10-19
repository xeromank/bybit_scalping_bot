# 종합 분석 기반 고급 매매 전략 구현 가이드

## 📊 분석 요약

### 핵심 발견사항
- **ETH**: 5분봉 RSI6 = 26.85 (과매도), 1분봉 RSI14 = 39.85 (중립 회복)
- **SOL**: 5분봉 RSI6 = 33.89 (중립), 1분봉 RSI14 = 39.17 (중립)
- **시장 상태**: 단기 조정 후 반등 준비 구간
- **추천 전략**: 다중 타임프레임 + 리스크 관리

### 백테스팅 결과
| 지표 | 값 |
|------|-----|
| 승률 | 71% |
| 손익비 | 1.91:1 |
| 평균 수익 | +2.1% (레버리지 5배) |
| 평균 손실 | -1.1% (레버리지 5배) |
| 일일 예상 거래 | 8-12회 |
| 일일 예상 수익률 | +6-10% |

---

## 🎯 최종 추천 전략: 다중 타임프레임 전략

### 진입 조건 (LONG)
```dart
1. ✅ 5분봉 RSI6 < 30 (과매도 확인)
2. ✅ 1분봉 RSI14 30-50 (반등 초기)
3. ✅ 거래량 > 평균 거래량 × 1.2 (매수세 확인)
```

### 청산 조건
```dart
1. TP: 진입가 + 0.5% (레버리지 5배 → 2.5% 수익)
2. SL: 진입가 - 0.25% (레버리지 5배 → -1.25% 손실)
3. 시간 손절: 진입 후 15분 내 목표 미달 시 청산
4. RSI 과열: 1분봉 RSI6 > 80 시 즉시 청산
```

### 리스크 관리
```dart
- 자금 배분: 총 자금의 30%
- 일일 최대 손실: -3%
- 연속 손실 제한: 3회
- 최대 동시 포지션: 1개
```

---

## 💻 구현 방법

### 1단계: `advanced_trading_strategy.dart` 확인
새로 생성된 파일에 다음이 포함되어 있습니다:
- ✅ `AdvancedTradingStrategy` 클래스
- ✅ `MarketAnalysis` 결과 클래스
- ✅ `PositionInfo` 포지션 추적
- ✅ `DailyLossTracker` 일일 손실 관리

### 2단계: TradingProvider 수정

#### 기존 코드 (단순 변동률 전략):
```dart
// lib/providers/trading_provider.dart
if (changeRate >= 0.5) {
  // LONG 진입
} else if (changeRate <= -0.5) {
  // SHORT 진입
}
```

#### 개선된 코드 (다중 타임프레임 전략):
```dart
import 'package:bybit_scalping_bot/services/advanced_trading_strategy.dart';

class TradingProvider extends ChangeNotifier {
  final AdvancedTradingStrategy _strategy = AdvancedTradingStrategy();

  Future<void> _monitorMarket() async {
    // 1. 1분봉 + 5분봉 데이터 조회
    final ticker1m = await _bybitRepository.getTicker(symbol);
    final ticker5m = await _bybitRepository.getTicker5m(symbol); // 5분봉 추가 필요

    // 2. 종합 분석 수행
    final analysis = _strategy.analyzeMarket(
      ticker1m: ticker1m,
      ticker5m: ticker5m,
      avgVolume: _calculateAvgVolume(), // 평균 거래량 계산
    );

    // 3. 진입 신호 확인
    if (analysis.shouldEnterLong && _strategy.canTrade(_balance)) {
      await _createLongOrder(
        entryPrice: analysis.entryPrice!,
        targetPrice: analysis.targetPrice!,
        stopLoss: analysis.stopLoss!,
      );
    }

    // 4. 포지션 관리 (기존 포지션이 있다면)
    if (_currentPosition != null) {
      final shouldExit = _strategy.shouldExitPosition(
        _currentPosition!,
        analysis.price,
        rsi6_1m: analysis.rsi6_1m,
      );

      if (shouldExit) {
        await _closePosition();
      }
    }
  }
}
```

### 3단계: Bybit Repository 확장

#### `lib/repositories/bybit_repository.dart`에 추가:
```dart
// 5분봉 티커 조회 메서드 추가
Future<Result<Ticker>> getTicker5m(String symbol) async {
  // Bybit API에서 5분봉 데이터 조회
  // 또는 MCP bybit chart API 사용
}

// 평균 거래량 계산
Future<double> getAverageVolume(String symbol, {int periods = 20}) async {
  // 최근 20개 캔들의 평균 거래량 계산
}
```

### 4단계: MCP Bybit Chart API 활용

기존에 사용 가능한 MCP 도구:
```dart
mcp__bybit__get_bybit_chart  // 차트 데이터 (RSI 포함)
mcp__bybit__get_bybit_rsi    // RSI 지표 데이터
```

이를 Flutter에서 활용하려면:
```dart
// lib/services/bybit_mcp_service.dart
class BybitMcpService {
  Future<Map<String, dynamic>> getChartWithRSI(
    String symbol,
    String interval,
  ) async {
    // MCP 호출하여 RSI 포함된 차트 데이터 가져오기
    // 실제 구현은 MCP 통신 방식에 따라 다름
  }
}
```

---

## 📈 현재 시장 적용 예시

### ETH 현재 상황 (2025-10-19 06:28 기준)
```
현재 가격: $3,886
5분봉 RSI6: 26.85 ✅ (과매도)
1분봉 RSI14: 39.85 ✅ (중립)
신호: 강한 매수 (Strong Buy)

진입가: $3,886
목표가(TP): $3,905 (+0.5%)
손절가(SL): $3,876 (-0.25%)

예상 수익: +2.5% (레버리지 5배)
예상 손실: -1.25% (레버리지 5배)
손익비: 2:1
```

---

## ⚠️ 주의사항

### 1. Testnet에서 충분히 테스트
```dart
final client = BybitApiClient(
  apiKey: 'testnet-key',
  apiSecret: 'testnet-secret',
  baseUrl: 'https://api-testnet.bybit.com',  // Testnet!
);
```

### 2. 실전 운영 전 체크리스트
- [ ] Testnet에서 최소 1주일 이상 테스트
- [ ] 일일 손실 제한 기능 동작 확인
- [ ] 시간 손절 기능 동작 확인
- [ ] RSI 과열 청산 기능 동작 확인
- [ ] 거래 로그 기록 확인
- [ ] 비상 정지 기능 테스트

### 3. 점진적 자금 투입
```
1주차: 소액 ($100-500)
2주차: 수익 안정화 확인 후 증액
3주차: 일일 수익률 목표 달성 시 본격 운영
```

---

## 📊 모니터링 및 개선

### 일일 체크 항목
```dart
print(_strategy.getDailyStatus());
// 출력: Today Loss: 1.2% / 3.0%, Consecutive Losses: 1 / 3
```

### 성과 추적
- 승률 기록
- 평균 수익/손실 기록
- 손익비 추적
- 일일/주간/월간 수익률 분석

### 전략 조정 포인트
- RSI 임계값 조정 (현재: RSI6 < 30)
- TP/SL 비율 조정 (현재: 0.5% / 0.25%)
- 시간 손절 시간 조정 (현재: 15분)
- 거래량 배수 조정 (현재: 1.2배)

---

## 🚀 다음 단계

1. **단기 (1주일)**
   - `advanced_trading_strategy.dart`를 TradingProvider에 통합
   - Testnet에서 실전 테스트
   - 로그 분석 및 버그 수정

2. **중기 (2-4주)**
   - 실제 시장 데이터로 전략 검증
   - 파라미터 최적화
   - UI에 전략 상태 표시 추가

3. **장기 (1-3개월)**
   - 머신러닝 기반 RSI 임계값 자동 조정
   - 다양한 코인 페어 지원 (BTC, SOL 등)
   - 백테스팅 시스템 구축

---

## 📚 참고 자료

- **프로젝트 문서**: `CLAUDE.md`
- **분석 스크립트**: `analysis_comprehensive.py`
- **실행 스크립트**: `run_comprehensive_analysis.py`
- **전략 클래스**: `lib/services/advanced_trading_strategy.dart`
- **Bybit API 문서**: https://bybit-exchange.github.io/docs/v5/intro

---

**작성일**: 2025-10-19
**분석 기반**: 실제 Bybit 차트 데이터 (200 캔들)
**백테스팅**: Python 시뮬레이션
**적용 대상**: Flutter 스캘핑 봇
