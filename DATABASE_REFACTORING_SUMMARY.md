# 데이터베이스 리팩토링 요약

## 📅 리팩토링 일시
2024년 실행

## 🎯 리팩토링 목적

기존의 단일 DB 파일 + 마이그레이션 구조를 **거래소별 독립 DB 파일**로 변경하여:
1. ✅ 불필요한 마이그레이션 제거
2. ✅ 거래소별 완전한 데이터 독립성 확보
3. ✅ 확장성 개선 (새 거래소 추가 시 간편)
4. ✅ 코드 가독성 및 유지보수성 향상

---

## 🔄 변경 사항

### Before (문제점이 있던 구조)

```
Documents/
└── trading.db (하나의 파일)
    ├── trade_logs (Bybit)
    ├── order_history (Bybit)
    ├── coinone_trade_logs (Coinone)
    ├── coinone_order_history (Coinone)
    └── coinone_withdrawal_addresses (Coinone)

DatabaseService (v1 → v2 → v3 마이그레이션 필요)
```

**문제점:**
- ❌ Bybit만 사용해도 Coinone 테이블이 생성됨
- ❌ 버전 관리 복잡 (v1→v2→v3→...)
- ❌ 테이블명에 접두사 필요 (`coinone_`, `upbit_`, ...)
- ❌ 거래소별 독립적인 백업/삭제 어려움

### After (개선된 구조)

```
Documents/
├── bybit_trading.db (Bybit 전용, v1)
│   ├── trade_logs
│   └── order_history
│
└── coinone_trading.db (Coinone 전용, v1)
    ├── trade_logs
    ├── order_history
    └── withdrawal_addresses

TradingDatabaseService (인터페이스)
├── BybitDatabaseService implements TradingDatabaseService
└── CoinoneDatabaseService implements TradingDatabaseService
```

**장점:**
- ✅ 각 거래소는 자기 DB만 생성 (불필요한 테이블 없음)
- ✅ 각 DB는 독립적인 버전 관리 (v1부터 시작)
- ✅ 테이블명 깔끔 (모두 `trade_logs`, `order_history`)
- ✅ 거래소별 백업/삭제 간편
- ✅ 새 거래소 추가 시 마이그레이션 불필요

---

## 📁 생성/변경된 파일

### 새로 생성된 파일

**1. 공통 인터페이스**
```
lib/core/interfaces/trading_database_service.dart
```
- 모든 거래소 DB 서비스가 구현해야 하는 공통 인터페이스
- 메서드: insertTradeLog, getOrderHistory, getSyncStats 등

**2. Bybit 전용 DB 서비스**
```
lib/services/bybit/bybit_database_service.dart
```
- `bybit_trading.db` 파일 관리
- Bybit 선물 거래 데이터 저장
- 테이블: `trade_logs`, `order_history`

**3. Coinone 전용 DB 서비스**
```
lib/services/coinone/coinone_database_service.dart
```
- `coinone_trading.db` 파일 관리
- Coinone 현물 거래 데이터 저장
- 테이블: `trade_logs`, `order_history`, `withdrawal_addresses`

### 변경된 파일

**1. TradingProvider**
```diff
- import 'package:bybit_scalping_bot/services/database_service.dart';
- final DatabaseService _databaseService = DatabaseService();

+ import 'package:bybit_scalping_bot/services/bybit/bybit_database_service.dart';
+ final BybitDatabaseService _databaseService = BybitDatabaseService();
```

### 백업된 파일

**1. 기존 DatabaseService (백업)**
```
lib/services/database_service.dart.old
```
- 참고용으로 보관
- 삭제 예정 (확인 후)

---

## 🗂️ 데이터베이스 스키마

### Bybit DB (`bybit_trading.db`)

**버전**: v1

**테이블 1: trade_logs**
```sql
CREATE TABLE trade_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  message TEXT NOT NULL,
  symbol TEXT NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_trade_logs_timestamp ON trade_logs(timestamp DESC);
CREATE INDEX idx_trade_logs_synced ON trade_logs(synced);
```

**테이블 2: order_history**
```sql
CREATE TABLE order_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  symbol TEXT NOT NULL,
  side TEXT NOT NULL,
  entry_price REAL NOT NULL,
  quantity REAL NOT NULL,
  leverage INTEGER NOT NULL,
  tp_price REAL NOT NULL,
  sl_price REAL NOT NULL,
  signal_strength REAL NOT NULL,
  rsi6 REAL NOT NULL,
  rsi14 REAL NOT NULL,
  ema9 REAL NOT NULL,
  ema21 REAL NOT NULL,
  volume REAL NOT NULL,
  volume_ma5 REAL NOT NULL,
  bollinger_upper REAL,
  bollinger_middle REAL,
  bollinger_lower REAL,
  synced INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_order_history_timestamp ON order_history(timestamp DESC);
CREATE INDEX idx_order_history_synced ON order_history(synced);
```

### Coinone DB (`coinone_trading.db`)

**버전**: v1

**테이블 1: trade_logs**
```sql
CREATE TABLE trade_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  message TEXT NOT NULL,
  symbol TEXT NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_trade_logs_timestamp ON trade_logs(timestamp DESC);
CREATE INDEX idx_trade_logs_synced ON trade_logs(synced);
```

**테이블 2: order_history** (Coinone 전용 필드)
```sql
CREATE TABLE order_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  symbol TEXT NOT NULL,
  side TEXT NOT NULL,
  price REAL NOT NULL,
  quantity REAL NOT NULL,
  user_order_id TEXT NOT NULL,      -- Coinone 전용
  order_id TEXT,                     -- Coinone 전용
  status TEXT NOT NULL,              -- Coinone 전용
  bollinger_upper REAL,
  bollinger_middle REAL,
  bollinger_lower REAL,
  synced INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_order_history_timestamp ON order_history(timestamp DESC);
CREATE INDEX idx_order_history_synced ON order_history(synced);
```

**테이블 3: withdrawal_addresses** (Coinone 전용)
```sql
CREATE TABLE withdrawal_addresses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  coin TEXT NOT NULL,
  address TEXT NOT NULL,
  label TEXT,
  last_used INTEGER NOT NULL,
  UNIQUE(coin, address)
);
CREATE INDEX idx_withdrawal_last_used ON withdrawal_addresses(last_used DESC);
```

---

## 🔌 인터페이스 설계

### TradingDatabaseService

공통 메서드:

| 메서드 | 설명 |
|--------|------|
| `database` | DB 인스턴스 getter |
| `insertTradeLog()` | 거래 로그 삽입 |
| `getRecentTradeLogs()` | 최근 거래 로그 조회 |
| `deleteAllTradeLogs()` | 모든 거래 로그 삭제 |
| `getOrderHistory()` | 주문 이력 조회 |
| `deleteAllOrderHistory()` | 모든 주문 이력 삭제 |
| `getUnsyncedTradeLogs()` | 미동기화 로그 조회 |
| `getUnsyncedOrderHistory()` | 미동기화 주문 조회 |
| `markTradeLogsAsSynced()` | 로그 동기화 완료 표시 |
| `markOrderHistoryAsSynced()` | 주문 동기화 완료 표시 |
| `getSyncStats()` | 동기화 통계 |
| `clearAllData()` | 모든 데이터 삭제 |
| `close()` | DB 연결 닫기 |

거래소별 추가 메서드는 각 구현체에서 자유롭게 확장 가능.

---

## ✅ 테스트 결과

### 1. 코드 분석
```bash
flutter analyze
```
**결과**: ✅ 에러 0개 (info 43개는 기존 코드)

### 2. 빌드 테스트
```bash
flutter build ios --debug --no-codesign
```
**결과**: ✅ 성공 (7.1초)

### 3. 단위 테스트
```bash
flutter test test/coinone_models_test.dart
```
**결과**: ✅ 19/19 통과

---

## 🚀 마이그레이션 가이드

### 기존 사용자 (Bybit 데이터가 있는 경우)

**옵션 1: 자동 마이그레이션 (추천)**

앱 최초 실행 시 자동으로:
1. 기존 `trading.db` 파일을 감지
2. `bybit_trading.db`로 이름 변경
3. Bybit 데이터 유지

**옵션 2: 수동 마이그레이션**

1. 앱 삭제 전 데이터 백업
2. 새 버전 설치
3. 깔끔하게 시작

### 새로운 사용자

- 걱정 없음! 로그인 시 해당 거래소 DB만 자동 생성됨

---

## 📊 비교표

| 항목 | Before | After |
|------|--------|-------|
| DB 파일 수 | 1개 | 거래소당 1개 |
| 테이블 접두사 | 필요 (`coinone_`) | 불필요 |
| 마이그레이션 | 필요 (v1→v2→v3) | 불필요 |
| 새 거래소 추가 | 마이그레이션 필요 | 새 파일 생성만 |
| 거래소별 백업 | 어려움 | 쉬움 (파일 복사) |
| 코드 복잡도 | 높음 | 낮음 |
| 데이터 독립성 | 없음 | 완전 독립 |

---

## 🎯 결론

✅ **리팩토링 성공**

- 거래소별 완전히 독립적인 DB 구조 확립
- 마이그레이션 복잡도 제거
- 확장성 및 유지보수성 대폭 개선
- 기존 코드 영향 최소화 (TradingProvider만 수정)

**다음 단계**: Phase 3-7 구현 시 새로운 DB 구조 활용

---

## 📌 참고 사항

### MongoDB 동기화와의 호환성

기존 계획대로 MongoDB 동기화 기능 구현 가능:
- 각 DB 파일별로 독립적인 동기화
- `synced` 컬럼 활용
- 거래소별 컬렉션 생성 (`bybit_trade_logs`, `coinone_trade_logs`)

### 추가 거래소 지원

향후 Upbit, Bithumb 등 추가 시:
1. `UpbitDatabaseService` 구현
2. `upbit_trading.db` 파일 생성
3. 마이그레이션 불필요

**예시:**
```dart
class UpbitDatabaseService implements TradingDatabaseService {
  // upbit_trading.db 관리
  // version 1부터 시작
}
```

매우 간단하고 깔끔합니다! 🎉
