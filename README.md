# Bybit 스캘핑 봇

Bybit 선물 거래를 위한 자동화된 스캘핑 트레이딩 봇입니다. Flutter로 개발되어 iOS와 Android 모두에서 사용 가능합니다.

## 주요 기능

### 자동 거래
- RSI(6, 12)와 EMA(9, 21) 기반 기술적 분석
- 보수적인 진입 조건으로 안정적인 거래
- 서버 측 TP/SL 주문으로 24/7 자동 청산
- 레버리지별 최적화된 ROE 타겟

### 거래 전략
- **롱 진입**: RSI(6) < 사용자 설정 AND RSI(12) < 사용자 설정 [AND 가격 > 선택한 EMA (선택사항)]
- **숏 진입**: RSI(6) > 사용자 설정 AND RSI(12) > 사용자 설정 [AND 가격 < 선택한 EMA (선택사항)]
- 준비 상태 알림: RSI 조건 중 하나만 만족 시 표시
- **커스터마이징 가능**:
  - RSI(6), RSI(12) 진입 임계값 조정 가능
  - EMA 필터 ON/OFF 선택 가능
  - EMA 기간 선택: 9, 21, 50, 100, 200

### 리스크 관리
- 레버리지별 자동 조정 ROE 타겟
- 수수료 고려한 안전한 목표 설정
- 작은 가격 움직임으로 빠른 회전율

## 레버리지별 ROE 타겟

| 레버리지 | 가격 이동 | TP ROE | SL ROE | 수수료 영향 | 순수익 |
|---------|---------|--------|--------|-----------|--------|
| 2배 | 0.3% | 0.6% | 0.3% | 0.22% | +0.38% |
| 3배 | 0.3% | 0.9% | 0.45% | 0.33% | +0.57% |
| 5배 | 0.3% | 1.5% | 0.75% | 0.55% | +0.95% |
| 10배 | 0.3% | 3.0% | 1.5% | 1.1% | +1.9% |
| 15배 | 0.2% | 3.0% | 1.5% | 1.65% | +1.35% |
| 20배 | 0.2% | 4.0% | 2.0% | 2.2% | +1.8% |
| 30배 | 0.2% | 6.0% | 3.0% | 3.3% | +2.7% |
| 50배 | 0.2% | 10.0% | 5.0% | 5.5% | +4.5% |
| 75배 | 0.2% | 15.0% | 7.5% | 8.25% | +6.75% |
| 100배 | 0.2% | 20.0% | 10.0% | 11% | +9.0% |

## 설치 및 실행

### 필수 요구사항
- Flutter SDK (3.0 이상)
- Dart SDK
- iOS: Xcode 14 이상
- Android: Android Studio

### 설치
```bash
# 저장소 클론
git clone https://github.com/yourusername/bybit_scalping_bot.git
cd bybit_scalping_bot

# 의존성 설치
flutter pub get

# 실행 (iOS 시뮬레이터)
flutter run

# 실행 (Android 에뮬레이터)
flutter run
```

### API 키 설정
1. Bybit에서 API 키 생성 (선물 거래 권한 필요)
2. 앱 실행 후 로그인 화면에서 API 키 입력
3. API Secret 입력 후 로그인

## 사용 방법

### 기본 설정
1. **심볼**: 거래할 암호화폐 선택 (예: ETHUSDT)
2. **주문 금액**: 거래 당 사용할 USDT 금액 (10-1000 USDT)
3. **레버리지**: 2-100배 설정 가능

### 봇 시작
1. 설정 완료 후 "시작" 버튼 클릭
2. 봇이 자동으로 시장 분석 시작
3. 진입 조건 만족 시 자동 주문 실행
4. TP/SL 주문 자동 설정

### 거래 로그
- 실시간 시장 분석 정보 표시
- RSI, EMA, 거래량 지표 확인
- 진입/청산 알림
- 최상단 이동 버튼으로 편리한 로그 확인

## 백그라운드 실행

### Android
- 자동으로 포그라운드 서비스 시작
- 화면 꺼짐 방지 (Wake Lock)
- 알림창에 봇 실행 상태 표시

### iOS
- Wake Lock으로 화면 켜짐 유지
- 백그라운드 모드 제한적 지원

## 프로젝트 구조

```
lib/
├── core/               # 핵심 유틸리티
│   ├── api/           # API 클라이언트 인터페이스
│   └── result/        # Result 타입 (성공/실패)
├── models/            # 데이터 모델
│   ├── position.dart
│   ├── order.dart
│   └── wallet_balance.dart
├── providers/         # 상태 관리
│   ├── auth_provider.dart
│   ├── balance_provider.dart
│   └── trading_provider.dart
├── repositories/      # 데이터 저장소
│   └── bybit_repository.dart
├── services/          # 외부 서비스
│   ├── bybit_api_client.dart
│   └── bybit_public_websocket_client.dart
├── utils/             # 유틸리티
│   └── technical_indicators.dart
├── widgets/           # UI 컴포넌트
└── screens/           # 화면
```

## 기술 스택

- **Framework**: Flutter
- **상태 관리**: Provider
- **HTTP 통신**: http package
- **WebSocket**: web_socket_channel
- **보안**: flutter_secure_storage
- **백그라운드**: flutter_foreground_task, wakelock_plus

## 주의사항

⚠️ **리스크 경고**
- 이 봇은 교육 및 연구 목적으로 제공됩니다
- 암호화폐 거래는 높은 리스크를 수반합니다
- 손실 가능한 금액만 투자하세요
- 실제 거래 전 충분한 테스트를 권장합니다

⚠️ **보안**
- API 키는 안전하게 보관하세요
- 거래 권한만 부여하고 출금 권한은 제거하세요
- 정기적으로 API 키를 갱신하세요

⚠️ **보호된 심볼**
- BTCUSDT는 장기 보유 보호를 위해 거래가 차단됩니다
- 필요 시 코드에서 수정 가능

## 라이센스

MIT License

## 기여

버그 리포트 및 기능 제안은 Issues를 통해 제출해 주세요.

## 면책 조항

이 소프트웨어는 "있는 그대로" 제공되며, 어떠한 명시적이거나 묵시적인 보증도 하지 않습니다. 소프트웨어 사용으로 인한 손실에 대해 개발자는 책임지지 않습니다.
