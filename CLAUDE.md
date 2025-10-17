# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Bybit 선물 스캘핑 자동 매매 봇 - iOS용 Flutter 앱으로 Bybit API를 사용하여 자동 선물 거래를 수행합니다.

## 핵심 개발 명령어

### 기본 빌드 및 실행
```bash
# 의존성 설치
flutter pub get

# 코드 분석
flutter analyze

# iOS 시뮬레이터/기기에서 실행
flutter run

# iOS 프로덕션 빌드
flutter build ios

# 특정 디바이스에서 실행
flutter devices  # 사용 가능한 디바이스 목록
flutter run -d <device-id>
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

**1. Presentation Layer (lib/screens/, lib/widgets/)**
- **Screens**: 전체 화면 위젯 (login_screen_new.dart, trading_screen_new.dart 사용)
- **Widgets**: 재사용 가능한 UI 컴포넌트
- **Providers**: 상태 관리 및 ViewModel 역할
  - `AuthProvider`: 인증 상태
  - `BalanceProvider`: 잔고 관리
  - `TradingProvider`: 거래 봇 로직

**2. Domain Layer (lib/models/, lib/core/)**
- **Models**: 불변 데이터 클래스 (Credentials, Order, Position, Ticker, WalletBalance)
- **Core/Interfaces**: 추상 인터페이스
  - `ApiClient`: API 통신 계약
  - `StorageService`: 저장소 계약
  - `Result<T>`: 타입 안전한 에러 처리 (Success/Failure)

**3. Data Layer (lib/repositories/, lib/services/)**
- **Repositories**: 데이터 접근 추상화
  - `BybitRepository`: Bybit API 데이터 작업
  - `CredentialRepository`: 인증 정보 저장/조회
- **Services**: 기술적 구현체
  - `BybitApiClient`: ApiClient 구현 (HMAC-SHA256 서명)
  - `SecureStorageService`: StorageService 구현 (암호화)
  - `ScalpingBotService`: 레거시 봇 서비스 (현재 TradingProvider에서 로직 관리)

### 의존성 주입 (DI)

`lib/main.dart`에서 모든 의존성이 생성자를 통해 주입됩니다:

```dart
// Services (최하위 계층)
SecureStorageService → CredentialRepository
BybitApiClient → BybitRepository

// Providers (중간 계층)
CredentialRepository → AuthProvider
BybitRepository → BalanceProvider
BybitRepository → TradingProvider

// UI (최상위 계층)
Provider 패턴으로 Providers를 Screens/Widgets에 주입
```

### 중요한 디자인 패턴

**Repository Pattern**
- 비즈니스 로직에서 데이터 접근을 분리
- API 호출을 추상화하여 테스트와 교체 용이

**Provider Pattern**
- Flutter의 상태 관리
- ChangeNotifier를 통한 반응형 UI
- ChangeNotifierProxyProvider로 의존성 체인

**Result Pattern**
- 예외 대신 타입 안전한 에러 처리
- `Success<T>` 또는 `Failure<T>` 반환
- 명시적 에러 전파

## Bybit API 통합

### API 클라이언트 사용

```dart
// testnet 사용 (개발 중)
final client = BybitApiClient(
  apiKey: 'your-key',
  apiSecret: 'your-secret',
  baseUrl: 'https://api-testnet.bybit.com',  // testnet
);

// mainnet (프로덕션)
// baseUrl: 'https://api.bybit.com'
```

### 주요 API 엔드포인트

- `/v5/position/set-leverage`: 레버리지 설정 (고정 5배)
- `/v5/order/create`: 주문 생성 (category: "linear")
- `/v5/market/tickers`: 실시간 가격 정보
- `/v5/account/wallet-balance`: 잔고 조회 (accountType: "UNIFIED")
- `/v5/position/list`: 포지션 정보

### 인증 및 보안

- HMAC-SHA256 서명 방식
- API Key/Secret은 XOR + SHA256으로 암호화 저장
- FlutterSecureStorage 사용 (iOS Keychain, Android KeyStore)

## 코드 작성 규칙

### 새 기능 추가 시

1. **Model 추가** (`lib/models/`): 데이터 구조 정의
2. **Repository 메서드 추가**: 데이터 접근 로직
3. **Provider 로직 추가**: 비즈니스 규칙 구현
4. **Widget/Screen 추가**: UI 구현
5. **Constants 업데이트**: 새로운 상수 추가 (`lib/constants/`)

### 파일 명명 규칙

- 모든 파일: snake_case (예: `login_screen_new.dart`)
- 클래스: PascalCase (예: `class LoginScreenNew`)
- 변수/함수: camelCase (예: `void startBot()`)
- 상수: UPPER_SNAKE_CASE (예: `const API_BASE_URL`)

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

## 주의사항

### 파일 사용

- **사용**: `login_screen_new.dart`, `trading_screen_new.dart`
- **사용 안 함**: `login_screen.dart`, `trading_screen.dart` (레거시)
- **레거시 파일**: `main_old.dart`, `main_new.dart`는 참고용으로만 보관

### API 테스트

- 개발 중에는 **반드시 testnet** 사용
- mainnet은 실제 자금이 필요하므로 충분히 테스트 후 전환
- API Key 권한: 선물 거래, 포지션 조회, 계좌 정보 조회 필요

### 스캘핑 봇 로직

- 현재 구현은 단순 변동률 기반 (+0.5% → Long, -0.5% → Short)
- 프로덕션 사용 전 더 정교한 전략 구현 권장
- `TradingProvider`에서 봇 로직 관리
- 3초마다 시장 모니터링

### 보안

- API Key/Secret을 절대 코드에 하드코딩하지 말 것
- git에 민감한 정보 커밋 금지
- `.env` 파일 사용 시 `.gitignore`에 추가

## 추가 문서

- **OOP 설계**: `lib/docs/oop_design.md`
- **리팩토링 요약**: `REFACTORING_SUMMARY.md`
- **Bybit API**: https://bybit-exchange.github.io/docs/v5/intro
