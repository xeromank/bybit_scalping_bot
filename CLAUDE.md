# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**멀티 거래소 자동 매매 봇** - iOS용 Flutter 앱으로 Bybit 선물 거래와 Coinone 현물 거래를 지원합니다.

### 지원 거래소
- **Bybit**: 선물(Perpetual Futures) 거래, 5배~15배 레버리지, WebSocket 실시간 데이터
- **Coinone**: 현물(Spot) 거래, KRW 마켓, WebSocket 실시간 호가/체결

## 핵심 개발 명령어

### 기본 빌드 및 실행
```bash
# 의존성 설치
flutter pub get

# 코드 분석
flutter analyze

# 특정 파일 분석 (예: provider 수정 후)
flutter analyze lib/providers/bybit_trading_provider.dart lib/providers/coinone_trading_provider.dart

# iOS 시뮬레이터/기기에서 실행
flutter run

# 특정 디바이스에서 실행
flutter devices
flutter run -d <device-id>

# iOS 프로덕션 빌드
flutter build ios
```

### 테스트
```bash
# 전체 테스트 실행
flutter test

# 특정 테스트 파일 실행
flutter test test/path/to/test_file.dart

# 커버리지 포함 테스트
flutter test --coverage
```

## 아키텍처 구조

이 프로젝트는 **Clean Architecture + MVVM 패턴**을 따르며 **SOLID 원칙**을 엄격히 준수합니다.

### 계층 구조 (하향식)

```
Presentation → Domain → Data
   (UI)       (비즈니스)  (저장소)
```

### 핵심 레이어

**1. Presentation Layer (lib/screens/, lib/widgets/, lib/providers/)**
- **Screens**:
  - `bybit_login_screen.dart`: 로그인 화면 (거래소 선택 포함)
  - `bybit_trading_screen.dart`: Bybit 선물 거래 화면
  - `coinone_trading_screen.dart`: Coinone 현물 거래 화면
- **Widgets**: 재사용 가능한 UI 컴포넌트
- **Providers**: 상태 관리 및 ViewModel 역할
  - `AuthProvider`: 인증 상태 및 거래소 선택
  - `BybitTradingProvider`: Bybit 선물 거래 봇 로직
  - `CoinoneTradingProvider`: Coinone 현물 거래 봇 로직
  - `CoinoneBalanceProvider`: Coinone 잔고 관리
  - `CoinoneWithdrawalProvider`: Coinone 출금 관리

**2. Domain Layer (lib/models/, lib/core/)**
- **Models**: 불변 데이터 클래스
  - Bybit: `Position`, `Order`, `Ticker`, `WalletBalance`, `TopCoin`
  - Coinone: `CoinoneOrder`, `CoinoneTicker`, `CoinoneOrderbook`, `CoinoneBalance`
  - Strategy: `MarketCondition`, `TradingSignal`, `TechnicalIndicators`
- **Core/Interfaces**: 추상 인터페이스
  - `ApiClient`: API 통신 계약
  - `StorageService`: 저장소 계약
  - `Result<T>`: 타입 안전한 에러 처리 (Success/Failure)

**3. Data Layer (lib/repositories/, lib/services/)**
- **Repositories**: 데이터 접근 추상화
  - `BybitRepository`: Bybit API 데이터 작업
  - `CoinoneRepository`: Coinone API 데이터 작업
  - `CredentialRepository`: 인증 정보 저장/조회
- **Services**: 기술적 구현체
  - `BybitApiClient`: Bybit REST API 클라이언트 (HMAC-SHA256 서명)
  - `BybitPublicWebSocketClient`: Bybit Public WebSocket (kline, ticker)
  - `BybitWebSocketClient`: Bybit Private WebSocket (position 업데이트)
  - `CoinoneApiClient`: Coinone REST API 클라이언트
  - `CoinoneWebSocketClient`: Coinone WebSocket (ticker, orderbook)
  - `SecureStorageService`: StorageService 구현 (암호화)
  - **Strategy Services** (lib/services/):
    - `AdaptiveStrategy`: Bybit 적응형 전략 (시장 상황별 전략 선택)
    - `MarketAnalyzer`: 시장 분석기 (5가지 조건 자동 감지)
  - **Coinone Strategy Services** (lib/services/coinone/):
    - `MarketTrendDetector`: 추세 감지 (상승/횡보/하락)
    - `VolatilityCalculator`: 변동성 계산
    - `TechnicalIndicatorCalculator`: 기술적 지표 계산
    - `UptrendStrategy`: 상승장 전략 (RSI 기반 분할 진입)
    - `SidewaysStrategy`: 횡보장 전략 (볼린저 밴드 평균회귀)

### 의존성 주입 (DI)

`lib/main.dart`에서 모든 의존성이 생성자를 통해 주입됩니다:

```dart
// Services (최하위 계층)
SecureStorageService → CredentialRepository
BybitApiClient → BybitRepository
CoinoneApiClient → CoinoneRepository

// WebSocket Clients (실시간 데이터)
BybitPublicWebSocketClient → BybitTradingProvider
BybitWebSocketClient → BybitTradingProvider (position 업데이트)
CoinoneWebSocketClient → CoinoneTradingProvider

// Providers (중간 계층)
CredentialRepository → AuthProvider
BybitRepository + WebSocket → BybitTradingProvider
CoinoneRepository + WebSocket → CoinoneTradingProvider

// UI (최상위 계층)
Provider 패턴으로 Providers를 Screens/Widgets에 주입
```

## 전략 시스템 (Strategy System)

### Bybit 적응형 전략 (Adaptive Strategy)

**자동 시장 분석 → 전략 선택 → 신호 생성** 프로세스

#### 1. 시장 분석 (MarketAnalyzer)

5분봉 50개를 분석하여 5가지 시장 조건 중 하나를 자동 감지:

| 시장 조건 | 설명 | 전략 |
|---------|-----|------|
| `extremeBullish` | 극단적 상승장 (RSI > 65, 강한 가격 상승) | Band Walking 추세 추종 (롱 전용) |
| `bullish` | 상승장 | 풀백 롱 진입 |
| `ranging` | 횡보장 | 볼린저 밴드 역추세 |
| `bearish` | 하락장 | 풀백 숏 진입 |
| `extremeBearish` | 극단적 하락장 (RSI < 35, 강한 가격 하락) | Band Walking 추세 추종 (숏 전용) |

**분석 요소**:
- 가격 변화율 (최근 20봉)
- 평균 RSI (최근 10개)
- 볼린저 밴드 폭 (변동성)
- EMA 정렬 상태 (9/21/50)

#### 2. 전략 설정 (AdaptiveStrategy)

시장 조건별 맞춤 파라미터:

```dart
// 예: 횡보장 전략
StrategyConfig(
  takeProfitPercent: 0.005,  // 0.5% TP
  stopLossPercent: 0.003,    // 0.3% SL
  recommendedLeverage: 15,   // 15배 레버리지
  useTrailingStop: false,
  description: '볼린저 밴드 역추세',
)
```

#### 3. 신호 생성 (Signal Generation)

**우선순위 1: 브레이크아웃 신호** (극단적 시장만)
- 극강세: 저항선 돌파 (롱) 또는 과매수 구간 지지선 이탈 (숏)
- 극약세: 지지선 이탈 (숏) 또는 과매도 구간 저항선 돌파 (롱)

**우선순위 2: 시장별 맞춤 신호**
- **극강세**: RSI 조정 후 재상승 (RSI 50-65, 이전에 70+ 도달)
- **강세**: RSI 풀백 진입 (RSI 45-55)
- **횡보**: 볼린저 하단 + 과매도 (RSI < 35) → 롱, 상단 + 과매수 (RSI > 65) → 숏
- **약세**: RSI 반등 숏 진입 (RSI 45-55)
- **극약세**: RSI 반등 후 재하락 (RSI 35-50, 이전에 30- 도달)

#### 4. 실시간 신호 체크

- **WebSocket kline 업데이트 시마다 자동 체크** (throttling 1초)
- 봇 시작 시 5분마다 시장 재분석
- 3초마다 잔고/포지션 업데이트

### Coinone 추세 기반 전략

**추세 감지 → 전략 선택 → 신호 생성** 프로세스

#### 1. 추세 감지 (MarketTrendDetector)

5분봉 200개를 분석하여 3가지 추세 중 하나를 감지:

| 추세 | 조건 | 전략 |
|-----|-----|------|
| `uptrend` | EMA9 > EMA21, RSI > 50, 가격 > EMA21 | Uptrend Strategy (분할 진입) |
| `sideways` | EMA9 ≈ EMA21, RSI 40-60 | Sideways Strategy (평균회귀) |
| `downtrend` | EMA9 < EMA21, RSI < 50 | 매매 중단 |

#### 2. 전략별 신호 생성

**상승장 전략 (UptrendStrategy)** - RSI 기반 분할 진입:
```
RSI ≤ 30: 100% 포지션, SL -5%, TP +3%
RSI ≤ 35: 50% 포지션, SL -4%, TP +2%
RSI ≤ 40: 25% 포지션, SL -3%, TP +1.5%
```
조건: 가격 > EMA21 * 0.98, EMA9 > EMA21 * 0.99, 거래량 ≥ 1.0x

**횡보장 전략 (SidewaysStrategy)** - 볼린저 밴드 평균회귀:
```
진입: BB 하위 40%, RSI ≤ 32, 거래량 ≥ 1.1x
청산: SL -2.5%, TP +1.2%, 또는 BB Middle 도달
```

#### 3. 실시간 모니터링

- 0.5초마다 기술적 지표 업데이트
- 1초마다 신호 체크 및 포지션 관리
- WebSocket으로 실시간 호가/체결 데이터 수신

## API 통합

### Bybit API

**엔드포인트** (baseUrl: `https://api.bybit.com` 또는 `https://api-testnet.bybit.com`):
- `/v5/position/set-leverage`: 레버리지 설정
- `/v5/order/create`: 주문 생성 (category: "linear")
- `/v5/market/tickers`: 실시간 가격 정보
- `/v5/account/wallet-balance`: 잔고 조회 (accountType: "UNIFIED")
- `/v5/position/list`: 포지션 정보
- `/v5/market/kline`: 캔들 데이터 (interval: "5")

**WebSocket**:
- Public: `wss://stream.bybit.com/v5/public/linear`
  - 구독: `kline.5.BTCUSDT` (5분 캔들)
  - 구독: `tickers.BTCUSDT` (실시간 가격)
- Private: `wss://stream.bybit.com/v5/private`
  - 구독: `position` (포지션 업데이트)

**인증**: HMAC-SHA256 서명 (API Key + Secret)

### Coinone API

**엔드포인트** (baseUrl: `https://api.coinone.co.kr`):
- `/public/v2/ticker_new/{currency}/{quote_currency}`: 시세 조회
- `/public/v2/orderbook/{currency}/{quote_currency}`: 호가 조회
- `/public/v2/chart/{quote_currency}/{target_currency}`: 차트 데이터
- `/v2.1/account/balance/all`: 잔고 조회
- `/v2.1/order/limit_buy`: 지정가 매수
- `/v2.1/order/limit_sell`: 지정가 매도
- `/v2.1/order/market_buy`: 시장가 매수
- `/v2.1/order/market_sell`: 시장가 매도
- `/v2.1/order/open_orders`: 미체결 주문 조회
- `/v2.1/order/cancel`: 주문 취소

**WebSocket**: `wss://stream.coinone.co.kr`
- 구독 메시지: `{"request_type":"SUBSCRIBE","channel":"TICKER","topic":{"quote_currency":"KRW","target_currency":"BTC"}}`
- 실시간 데이터: ticker, orderbook

**인증**: JWT 토큰 (API Key + Secret)

### 보안

- API Key/Secret은 XOR + SHA256으로 암호화 저장
- FlutterSecureStorage 사용 (iOS Keychain, Android KeyStore)
- **절대 코드에 하드코딩하지 말 것**

## 코드 작성 규칙

### SOLID 원칙 준수

- **단일 책임**: 각 클래스는 하나의 책임만
- **개방-폐쇄**: 확장에 열려있고 수정에 닫혀있음
- **리스코프 치환**: 인터페이스 구현체는 교체 가능
- **인터페이스 분리**: 필요한 메서드만 의존
- **의존성 역전**: 추상화에 의존, 생성자 주입

### 에러 처리

Result 패턴 사용:

```dart
final result = await repository.getWalletBalance();

switch (result) {
  case Success(:final data):
    // 성공 처리
  case Failure(:final message, :final exception):
    // 실패 처리
}
```

### 파일 명명 규칙

- 모든 파일: snake_case (예: `bybit_trading_provider.dart`)
- 클래스: PascalCase (예: `class BybitTradingProvider`)
- 변수/함수: camelCase (예: `void startBot()`)
- 상수: UPPER_SNAKE_CASE (예: `const API_BASE_URL`)

### 새 기능 추가 시

1. **Model 추가** (`lib/models/`): 데이터 구조 정의
2. **Repository 메서드 추가**: 데이터 접근 로직
3. **Provider 로직 추가**: 비즈니스 규칙 구현
4. **Widget/Screen 추가**: UI 구현
5. **Constants 업데이트**: 새로운 상수 추가 (`lib/constants/`)

### 전략 추가/수정 시

**Bybit 전략**:
1. `lib/services/adaptive_strategy.dart`에서 `StrategyConfig` 또는 신호 로직 수정
2. `lib/services/market_analyzer.dart`에서 시장 분석 로직 수정 (필요시)
3. 테스트 후 파라미터 조정 (TP/SL, leverage, RSI 임계값 등)

**Coinone 전략**:
1. `lib/services/coinone/strategies/` 폴더에 새 전략 클래스 추가
2. `TradingStrategy` 인터페이스 구현 (`generateSignal`, `shouldClosePosition`)
3. `CoinoneTradingProvider`에서 전략 선택 로직 수정
4. `MarketTrendDetector`에서 추세 감지 로직 수정 (필요시)

## 주의사항

### API 테스트

- **Bybit**: 개발 중에는 **반드시 testnet** 사용 (`https://api-testnet.bybit.com`)
- **Coinone**: 소액으로 충분히 테스트 후 운영
- mainnet은 실제 자금이 필요하므로 충분히 테스트 후 전환

### 전략 운영

**Bybit**:
- 현재 구현은 5가지 시장 조건에 따른 적응형 전략
- 레버리지: 5배~15배 (시장 조건별 자동 조정)
- 프로덕션 사용 전 백테스트 및 소액 테스트 필수

**Coinone**:
- 추세 기반 분할 진입 전략 (상승장) 및 평균회귀 전략 (횡보장)
- 하락장에서는 매매 중단
- 거래 로그가 SQLite에 저장되므로 분석 가능

### 디버깅

**로그 확인**:
```dart
Logger.debug('디버그 메시지');
Logger.success('성공 메시지');
Logger.error('에러 메시지');
Logger.warning('경고 메시지');
```

**실시간 데이터 모니터링**:
- Bybit: WebSocket kline/ticker/position 로그 확인
- Coinone: WebSocket ticker/orderbook 로그 확인
- Provider의 `notifyListeners()` 호출 확인

### 성능 최적화

- WebSocket 연결은 앱 전체에서 **단일 인스턴스** 사용 (main.dart에서 관리)
- 불필요한 API 호출 최소화 (WebSocket 우선 사용)
- Provider의 `notifyListeners()` 호출 최소화 (상태 변경 시에만)

## 추가 문서

- **OOP 설계**: `lib/docs/oop_design.md`
- **리팩토링 요약**: `REFACTORING_SUMMARY.md`
- **Bybit API**: https://bybit-exchange.github.io/docs/v5/intro
- **Coinone API**: https://doc.coinone.co.kr/