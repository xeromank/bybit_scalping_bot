# Coinone 현물 스캘핑 통합 계획

## 📋 프로젝트 개요

기존 Bybit 선물 봇에 Coinone 현물 스캘핑 모드를 추가합니다.
- **목표**: 볼린저 밴드 전략을 사용한 Coinone 현물 스캘핑
- **핵심**: 수수료 0원 환경에서 리플(XRP) 등 현물 거래
- **구조**: 기존 Bybit 코드와 완전히 분리된 아키텍처

---

## 🏗️ 아키텍처 설계

### 1. Multi-Exchange 지원 구조

```
lib/
├── core/
│   ├── enums/
│   │   └── exchange_type.dart          # NEW: enum ExchangeType { bybit, coinone }
│   └── interfaces/
│       ├── api_client.dart             # EXISTING (공통 인터페이스)
│       └── exchange_service.dart       # NEW: 거래소 공통 서비스 인터페이스
│
├── models/
│   ├── coinone/                        # NEW: Coinone 전용 모델
│   │   ├── coinone_balance.dart
│   │   ├── coinone_order.dart
│   │   ├── coinone_ticker.dart
│   │   ├── coinone_orderbook.dart
│   │   └── coinone_chart.dart
│   └── exchange_credentials.dart       # NEW: 거래소별 인증정보 (API Key Set 관리)
│
├── services/
│   ├── bybit/                          # REFACTOR: 기존 Bybit 서비스 이동
│   │   ├── bybit_api_client.dart
│   │   └── bybit_websocket_client.dart
│   └── coinone/                        # NEW: Coinone 서비스
│       ├── coinone_api_client.dart     # REST API 클라이언트
│       ├── coinone_websocket_client.dart # WebSocket 클라이언트
│       └── coinone_strategy_service.dart # 볼린저 밴드 전략
│
├── repositories/
│   ├── bybit_repository.dart           # EXISTING
│   ├── coinone_repository.dart         # NEW
│   └── credential_repository.dart      # UPDATE: 거래소별 API Key Set 관리
│
├── providers/
│   ├── auth_provider.dart              # UPDATE: ExchangeType 지원
│   ├── bybit/                          # REFACTOR: Bybit 전용 Provider
│   │   ├── bybit_balance_provider.dart
│   │   └── bybit_trading_provider.dart
│   └── coinone/                        # NEW: Coinone 전용 Provider
│       ├── coinone_balance_provider.dart
│       ├── coinone_trading_provider.dart
│       └── coinone_withdrawal_provider.dart
│
├── screens/
│   ├── login_screen_new.dart           # UPDATE: 거래소 선택 UI 추가
│   ├── bybit/                          # REFACTOR: Bybit 화면 이동
│   │   └── bybit_trading_screen.dart
│   └── coinone/                        # NEW: Coinone 화면
│       ├── coinone_trading_screen.dart
│       └── coinone_withdrawal_screen.dart
│
└── widgets/
    ├── common/                          # NEW: 공통 위젯
    │   └── exchange_selector.dart
    ├── bybit/                           # REFACTOR
    └── coinone/                         # NEW
        ├── coinone_balance_card.dart
        ├── coinone_order_card.dart
        └── coinone_orderbook_widget.dart
```

---

## 📝 단계별 구현 계획

### **Phase 1: 기반 구조 설정** ✅

#### 1.1 Enum 및 공통 인터페이스
- [ ] `lib/core/enums/exchange_type.dart` 생성
  ```dart
  enum ExchangeType {
    bybit,
    coinone,
  }
  ```
- [ ] `lib/core/interfaces/exchange_service.dart` 생성 (공통 메서드 정의)

#### 1.2 모델 클래스
- [ ] `lib/models/exchange_credentials.dart`
  - API Key Set 관리 (최근 사용한 키 저장용)
  - `{exchangeType, apiKey, apiSecret, lastUsed}`
- [ ] Coinone 전용 모델들 생성
  - `coinone_balance.dart`
  - `coinone_order.dart`
  - `coinone_ticker.dart`
  - `coinone_orderbook.dart`
  - `coinone_chart.dart`

#### 1.3 데이터베이스 스키마 업데이트
- [ ] `database_service.dart` 버전 3으로 업그레이드
- [ ] 테이블 추가:
  ```sql
  -- Coinone 거래 로그
  CREATE TABLE coinone_trade_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    type TEXT NOT NULL,
    message TEXT NOT NULL,
    symbol TEXT NOT NULL,
    synced INTEGER NOT NULL DEFAULT 0
  );

  -- Coinone 주문 이력
  CREATE TABLE coinone_order_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    symbol TEXT NOT NULL,
    side TEXT NOT NULL,
    price REAL NOT NULL,
    quantity REAL NOT NULL,
    user_order_id TEXT NOT NULL,
    order_id TEXT,
    status TEXT NOT NULL,
    bollinger_upper REAL,
    bollinger_middle REAL,
    bollinger_lower REAL,
    synced INTEGER NOT NULL DEFAULT 0
  );

  -- Coinone 출금 주소 캐시
  CREATE TABLE coinone_withdrawal_addresses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    coin TEXT NOT NULL,
    address TEXT NOT NULL,
    label TEXT,
    last_used INTEGER NOT NULL,
    UNIQUE(coin, address)
  );
  ```

---

### **Phase 2: Coinone API 클라이언트 구현**

#### 2.1 REST API 클라이언트
- [ ] `lib/services/coinone/coinone_api_client.dart`
  - JWT 인증 (Authorization: Bearer {accessToken})
  - API 엔드포인트:
    - `GET /v2/account/balance/all` - 잔고 조회 (3초/1회)
    - `GET /public/v2/chart/{quote_currency}/{target_currency}` - 차트 (2회/초)
    - `POST /v2/order` - 주문 생성 (user_order_id 필수)
    - `DELETE /v2/order` - 주문 취소 (user_order_id 사용)
    - `GET /v2/order/open_orders` - 미체결 주문 (1회/2초)
    - `POST /v2/transaction/coin/out` - 출금

#### 2.2 WebSocket 클라이언트
- [ ] `lib/services/coinone/coinone_websocket_client.dart`
  - Public WebSocket (인증 불필요)
  - `TICKER` 채널: 실시간 가격
  - `ORDERBOOK` 채널: 호가창 (슬리피지 계산용)
  - 자동 재연결 로직

#### 2.3 Repository
- [ ] `lib/repositories/coinone_repository.dart`
  - API 클라이언트 래핑
  - `Result<T>` 패턴으로 에러 처리

---

### **Phase 3: 인증 및 로그인 화면 개선**

#### 3.1 Credential 관리
- [ ] `credential_repository.dart` 업데이트
  - 거래소별 API Key Set 저장/조회
  - 최근 사용한 키 목록 (최대 5개)
  - `List<ExchangeCredentials> getRecentCredentials(ExchangeType type)`

#### 3.2 로그인 화면 개선
- [ ] `login_screen_new.dart` 업데이트
  - 거래소 선택 탭 (Bybit / Coinone)
  - 각 거래소별 최근 사용 API Key 드롭다운
  - "Bybit 로그인" / "Coinone 로그인" 버튼 분리
  - UI 예시:
    ```
    ┌─────────────────────────────────┐
    │  [ Bybit ]  [ Coinone ]         │
    ├─────────────────────────────────┤
    │  Recent API Keys:               │
    │  [ Select or enter new... ▼ ]  │
    │                                 │
    │  API Key:    [____________]     │
    │  API Secret: [____________]     │
    │                                 │
    │  [ Coinone Login ]              │
    └─────────────────────────────────┘
    ```

#### 3.3 AuthProvider 업데이트
- [ ] `auth_provider.dart`
  - `ExchangeType currentExchange` 필드 추가
  - 로그인 성공 시 최근 사용 키 저장

---

### **Phase 4: Coinone 거래 기능 구현**

#### 4.1 Provider 구현
- [ ] `lib/providers/coinone/coinone_balance_provider.dart`
  - 3초마다 잔고 업데이트
  - KRW, XRP, BTC 등 잔고 표시

- [ ] `lib/providers/coinone/coinone_trading_provider.dart`
  - 볼린저 밴드 전략 실행
  - 1초에 2회 차트 데이터 조회
  - WebSocket으로 실시간 가격 수신
  - 오더북 슬리피지 계산
  - 주문 생성 (user_order_id = UUID 생성)
  - 2초마다 미체결 주문 확인

- [ ] `lib/providers/coinone/coinone_withdrawal_provider.dart`
  - 출금 기능
  - 최근 출금 주소 관리

#### 4.2 볼린저 밴드 전략 서비스
- [ ] `lib/services/coinone/coinone_strategy_service.dart`
  ```dart
  class CoinoneStrategyService {
    // 볼린저 밴드 계산 (기간: 20, 표준편차: 2)
    BollingerBands calculateBollingerBands(List<ChartData> candles);

    // 진입 신호 감지
    EntrySignal? detectEntrySignal({
      required double currentPrice,
      required BollingerBands bb,
      required OrderBook orderbook,
    });

    // 슬리피지 계산
    double calculateSlippage(OrderBook orderbook, String side, double quantity);
  }
  ```

---

### **Phase 5: Coinone 거래 화면**

#### 5.1 메인 거래 화면
- [ ] `lib/screens/coinone/coinone_trading_screen.dart`
  - 잔고 카드 (KRW, 보유 코인)
  - 현재 주문 상태
  - 볼린저 밴드 인디케이터 표시
  - 실시간 가격 (WebSocket)
  - 오더북 위젯
  - 봇 시작/중지 버튼
  - 출금 버튼 (화면 이동)
  - 로그 리스트

#### 5.2 출금 화면
- [ ] `lib/screens/coinone/coinone_withdrawal_screen.dart`
  - 코인 선택 드롭다운
  - 수량 입력
  - 최근 주소 선택 또는 새 주소 입력
  - 출금 확인 버튼

#### 5.3 위젯 구현
- [ ] `coinone_balance_card.dart` - 잔고 표시
- [ ] `coinone_order_card.dart` - 현재 주문 상태
- [ ] `coinone_orderbook_widget.dart` - 실시간 호가창

---

### **Phase 6: 로깅 및 히스토리**

#### 6.1 DatabaseService 메서드 추가
- [ ] Coinone 거래 로그 삽입/조회
- [ ] Coinone 주문 이력 삽입/조회
- [ ] 출금 주소 저장/조회/정렬 (최근 사용 순)

#### 6.2 로그 기록 시점
- [ ] 봇 시작/중지
- [ ] 주문 생성/취소
- [ ] 체결 완료
- [ ] 에러 발생
- [ ] 출금 요청

---

### **Phase 7: 라우팅 및 메인 통합**

#### 7.1 메인 라우터 업데이트
- [ ] `main.dart` 수정
  - AuthProvider에서 `currentExchange` 확인
  - Bybit 로그인 → `bybit_trading_screen.dart`
  - Coinone 로그인 → `coinone_trading_screen.dart`

#### 7.2 DI 구조 정리
```dart
// Bybit DI
BybitApiClient → BybitRepository → BybitTradingProvider

// Coinone DI
CoinoneApiClient → CoinoneRepository → CoinoneTradingProvider
```

---

## 🔐 보안 고려사항

1. **API Key 암호화**
   - 기존과 동일하게 SecureStorage 사용
   - XOR + SHA256 암호화

2. **JWT 토큰 관리**
   - Coinone은 JWT 기반 인증
   - 토큰 만료 시 자동 재발급 로직

3. **user_order_id 생성**
   - UUID v4 사용
   - 중복 방지를 위해 timestamp + random 조합

---

## 📊 API 호출 빈도 관리

| API | 빈도 | 구현 방법 |
|-----|------|-----------|
| 잔고 조회 | 3초/1회 | Timer.periodic(3초) |
| 차트 조회 | 2회/초 | Timer.periodic(500ms) |
| 미체결 주문 | 1회/2초 | Timer.periodic(2초) |
| 현재가 | 실시간 | WebSocket (TICKER) |
| 오더북 | 실시간 | WebSocket (ORDERBOOK) |

---

## ✅ 테스트 계획

### Phase별 테스트

1. **Phase 2**: API 클라이언트 단위 테스트
   - Coinone Testnet 또는 실제 API 호출 검증

2. **Phase 4**: 전략 로직 테스트
   - 볼린저 밴드 계산 검증
   - 슬리피지 계산 검증

3. **Phase 5**: UI 통합 테스트
   - 로그인 → 거래 → 출금 전체 플로우

---

## 🚀 배포 전 체크리스트

- [ ] Bybit 기능 영향 없음 확인
- [ ] Coinone API 모든 엔드포인트 테스트
- [ ] WebSocket 재연결 로직 검증
- [ ] 에러 처리 완전성 검증
- [ ] SQLite 마이그레이션 정상 작동 확인
- [ ] 최근 사용 API Key 저장/로드 검증
- [ ] 출금 주소 캐시 기능 검증
- [ ] 로그 기록 완전성 확인

---

## 📅 예상 일정

- **Phase 1-2**: 2-3시간 (기반 구조 + API 클라이언트)
- **Phase 3**: 1시간 (로그인 화면)
- **Phase 4**: 3-4시간 (거래 로직 + 전략)
- **Phase 5**: 2-3시간 (UI)
- **Phase 6**: 1시간 (로깅)
- **Phase 7**: 1시간 (통합)

**총 예상 시간**: 10-14시간

---

## 📚 참고 문서

- [Coinone API 문서](https://docs.coinone.co.kr/)
- [Bybit 기존 구조](./CLAUDE.md)
- [리팩토링 가이드](./REFACTORING_SUMMARY.md)
