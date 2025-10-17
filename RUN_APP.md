# iOS 앱 실행 가이드

## 🚀 빠른 실행 (한 줄 명령어)

```bash
# 시뮬레이터 자동 실행 + 앱 실행
flutter run
```

## 📱 단계별 실행 방법

### 1단계: iOS 시뮬레이터 실행

```bash
# 사용 가능한 시뮬레이터 목록 확인
flutter emulators

# iOS 시뮬레이터 실행
flutter emulators --launch apple_ios_simulator
```

### 2단계: 앱 실행

시뮬레이터가 완전히 켜진 후 (30초 정도 대기):

```bash
# 기본 실행 (연결된 디바이스에 자동 실행)
flutter run

# 또는 특정 디바이스 지정
flutter devices  # 디바이스 목록 확인
flutter run -d <device-id>  # 특정 디바이스에 실행
```

### 3단계: Hot Reload (코드 수정 후)

앱이 실행 중일 때 코드를 수정하면:

```bash
# 터미널에서 'r' 입력 (Hot Reload)
r

# 완전 재시작이 필요한 경우 'R' 입력
R

# 앱 종료
q
```

## 🔄 재실행 명령어

### 앱이 실행 중일 때

```bash
# Hot Reload (빠른 반영)
r

# Hot Restart (완전 재시작)
R

# 앱 종료 후 다시 실행
q
flutter run
```

### 앱이 종료되었을 때

```bash
# 시뮬레이터가 켜져 있으면
flutter run

# 시뮬레이터가 꺼져 있으면
flutter emulators --launch apple_ios_simulator
# 30초 대기 후
flutter run
```

## 📋 자주 사용하는 명령어

### 의존성 설치/업데이트

```bash
# pubspec.yaml 변경 후 패키지 설치
flutter pub get

# 패키지 업데이트
flutter pub upgrade
```

### 코드 분석 및 정리

```bash
# 코드 분석 (에러 체크)
flutter analyze

# 코드 포맷팅
flutter format lib/

# 특정 파일 포맷팅
flutter format lib/screens/login_screen_new.dart
```

### 빌드

```bash
# iOS 디버그 빌드
flutter build ios --debug

# iOS 릴리즈 빌드 (App Store 배포용)
flutter build ios --release

# 프로덕션 빌드
flutter build ipa
```

### 클린 빌드 (문제 발생 시)

```bash
# Flutter 빌드 캐시 삭제
flutter clean

# 의존성 재설치
flutter pub get

# iOS 의존성 재설치
cd ios
pod install
cd ..

# 앱 재실행
flutter run
```

## 🐛 디버깅 명령어

### 로그 확인

```bash
# Flutter 로그 실시간 확인
flutter logs

# 특정 디바이스 로그
flutter logs -d <device-id>
```

### DevTools 실행

```bash
# Flutter DevTools 실행 (브라우저에서 디버깅)
flutter pub global activate devtools
flutter pub global run devtools
```

### 성능 분석

```bash
# 프로파일 모드로 실행
flutter run --profile

# 릴리즈 모드로 실행
flutter run --release
```

## 📱 실제 iPhone 기기에서 실행

```bash
# 1. iPhone을 USB로 Mac에 연결
# 2. iPhone에서 "신뢰" 설정

# 3. 연결된 디바이스 확인
flutter devices

# 4. 실제 기기에서 실행
flutter run -d <your-iphone-id>
```

## ⚠️ 문제 해결

### "No devices found" 에러

```bash
# iOS 시뮬레이터 실행
flutter emulators --launch apple_ios_simulator

# 30초 대기 후 다시 시도
flutter devices
flutter run
```

### "CocoaPods not installed" 에러

```bash
# CocoaPods 설치
sudo gem install cocoapods

# iOS 의존성 재설치
cd ios
pod install
cd ..
```

### "Build failed" 에러

```bash
# 클린 빌드
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run
```

### 앱이 실행되지 않을 때

```bash
# 1. 시뮬레이터 완전히 종료
# 2. Xcode 실행 후 시뮬레이터 재시작
open -a Xcode

# 3. Xcode에서 시뮬레이터 선택 후 실행
# 4. 또는 터미널에서
flutter emulators --launch apple_ios_simulator
flutter run
```

## 🎯 개발 워크플로우

```bash
# 1. 시뮬레이터 실행
flutter emulators --launch apple_ios_simulator

# 2. 앱 실행
flutter run

# 3. 코드 수정

# 4. Hot Reload (터미널에서 'r' 입력)

# 5. 큰 변경사항이 있으면 Hot Restart ('R' 입력)

# 6. 종료할 때 'q' 입력
```

## 📚 추가 리소스

- Flutter 공식 문서: https://docs.flutter.dev/
- Bybit API 문서: https://bybit-exchange.github.io/docs/v5/intro
- 프로젝트 아키텍처: `CLAUDE.md` 참고
- OOP 설계 문서: `lib/docs/oop_design.md` 참고
