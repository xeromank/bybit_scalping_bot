import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service_v2.dart';

/// 재귀 예측 백테스팅 스크립트
///
/// 목적:
/// 1. 5분봉 → 15분/30분/1시간/4시간 재귀 예측 정확도 측정
/// 2. 각 인터벌별 오차율 분석
/// 3. 추세 방향 일치율 분석
void main() async {
  print('🔬 재귀 예측 백테스팅 시작...\n');

  // Bybit에서 실제 데이터 가져오기
  final symbol = 'BTCUSDT';
  final intervals = ['5', '15', '30', '60', '240'];

  final historicalData = <String, List<KlineData>>{};

  for (final interval in intervals) {
    print('📊 $interval분봉 데이터 로딩 중...');
    final klines = await fetchBybitKlines(symbol, interval, limit: 200);
    historicalData[interval] = klines;
    print('✅ $interval분봉 ${klines.length}개 로드 완료');
  }

  print('\n' + '=' * 60);

  // 각 인터벌별로 백테스팅
  final predictionService = PricePredictionServiceV2();

  await backtestInterval(
    predictionService: predictionService,
    targetInterval: '15',
    targetName: '15분',
    klines5m: historicalData['5']!,
    klines15m: historicalData['15']!,
    klines30m: historicalData['30']!,
  );

  await backtestInterval(
    predictionService: predictionService,
    targetInterval: '30',
    targetName: '30분',
    klines5m: historicalData['5']!,
    klines15m: historicalData['15']!,
    klines30m: historicalData['30']!,
  );

  await backtestInterval(
    predictionService: predictionService,
    targetInterval: '60',
    targetName: '1시간',
    klines5m: historicalData['5']!,
    klines15m: historicalData['15']!,
    klines30m: historicalData['30']!,
  );

  await backtestInterval(
    predictionService: predictionService,
    targetInterval: '240',
    targetName: '4시간',
    klines5m: historicalData['5']!,
    klines15m: historicalData['15']!,
    klines30m: historicalData['30']!,
  );

  print('\n🎯 백테스팅 완료!');
}

/// 특정 인터벌 백테스팅
Future<void> backtestInterval({
  required PricePredictionServiceV2 predictionService,
  required String targetInterval,
  required String targetName,
  required List<KlineData> klines5m,
  required List<KlineData> klines15m,
  required List<KlineData> klines30m,
}) async {
  print('\n' + '=' * 60);
  print('🔍 $targetName봉 재귀 예측 백테스팅');
  print('=' * 60);

  final errors = <double>[];
  final priceErrors = <double>[];
  final highErrors = <double>[];
  final lowErrors = <double>[];
  final directionMatches = <bool>[];

  // 최근 30개 캔들로 테스트 (너무 많으면 시간이 오래 걸림)
  final testCount = 30;

  for (int i = 0; i < testCount; i++) {
    // i번째 캔들을 예측 (i+1부터가 학습 데이터)
    final testKlines5m = klines5m.skip(i + 1).take(100).toList();
    final testKlines30m = klines30m.skip(i ~/ 6 + 1).take(50).toList();

    if (testKlines5m.length < 100 || testKlines30m.length < 50) {
      break;
    }

    // 재귀 예측 실행
    final prediction = predictionService.generatePredictionSignal(
      klinesMain: testKlines5m,
      klines5m: testKlines5m,
      klines30m: testKlines30m,
      interval: targetInterval,
      useRecursivePrediction: true,
    );

    if (prediction == null) {
      print('⚠️ 예측 실패 at index $i');
      continue;
    }

    // 실제 값 (i번째 캔들)
    KlineData actual;
    if (targetInterval == '5') {
      actual = klines5m[i];
    } else if (targetInterval == '15') {
      actual = klines15m[i];
    } else if (targetInterval == '30') {
      actual = klines30m[i];
    } else if (targetInterval == '60') {
      actual = klines5m[i]; // 1시간 데이터는 5분봉으로 대체 (테스트용)
    } else {
      actual = klines5m[i]; // 4시간 데이터는 5분봉으로 대체 (테스트용)
    }

    // 가격 오차 계산
    final currentPrice = testKlines5m.first.close;
    final priceError = ((prediction.predictedClose - actual.close).abs() / actual.close) * 100;
    final highError = ((prediction.predictedHigh - actual.high).abs() / actual.high) * 100;
    final lowError = ((prediction.predictedLow - actual.low).abs() / actual.low) * 100;

    errors.add(priceError);
    priceErrors.add(priceError);
    highErrors.add(highError);
    lowErrors.add(lowError);

    // 방향성 일치 확인
    final predictedDirection = prediction.predictedClose > currentPrice;
    final actualDirection = actual.close > currentPrice;
    directionMatches.add(predictedDirection == actualDirection);

    if (i < 5) {
      print('\n테스트 #${i + 1}:');
      print('  현재가: \$${currentPrice.toStringAsFixed(2)}');
      print('  예측 종가: \$${prediction.predictedClose.toStringAsFixed(2)}');
      print('  실제 종가: \$${actual.close.toStringAsFixed(2)}');
      print('  종가 오차: ${priceError.toStringAsFixed(2)}%');
      print('  고가 오차: ${highError.toStringAsFixed(2)}%');
      print('  저가 오차: ${lowError.toStringAsFixed(2)}%');
      print('  방향 일치: ${predictedDirection == actualDirection ? "✅" : "❌"}');
    }
  }

  if (errors.isEmpty) {
    print('\n❌ 테스트 결과 없음');
    return;
  }

  // 통계 계산
  final avgError = errors.reduce((a, b) => a + b) / errors.length;
  final maxError = errors.reduce((a, b) => a > b ? a : b);
  final minError = errors.reduce((a, b) => a < b ? a : b);

  final avgPriceError = priceErrors.reduce((a, b) => a + b) / priceErrors.length;
  final avgHighError = highErrors.reduce((a, b) => a + b) / highErrors.length;
  final avgLowError = lowErrors.reduce((a, b) => a + b) / lowErrors.length;

  final directionAccuracy = (directionMatches.where((m) => m).length / directionMatches.length) * 100;

  // 결과 출력
  print('\n' + '-' * 60);
  print('📊 $targetName봉 예측 결과 요약 (${errors.length}개 샘플)');
  print('-' * 60);
  print('종가 오차:');
  print('  - 평균: ${avgPriceError.toStringAsFixed(2)}%');
  print('  - 최대: ${maxError.toStringAsFixed(2)}%');
  print('  - 최소: ${minError.toStringAsFixed(2)}%');
  print('\n고가 오차 평균: ${avgHighError.toStringAsFixed(2)}%');
  print('저가 오차 평균: ${avgLowError.toStringAsFixed(2)}%');
  print('\n방향성 정확도: ${directionAccuracy.toStringAsFixed(1)}%');

  // 오차 등급 평가
  String grade;
  if (avgPriceError < 0.5) {
    grade = '🟢 우수';
  } else if (avgPriceError < 1.0) {
    grade = '🟡 양호';
  } else if (avgPriceError < 2.0) {
    grade = '🟠 보통';
  } else {
    grade = '🔴 개선 필요';
  }

  print('\n평가: $grade');
  print('-' * 60);
}

/// Bybit API에서 실제 캔들 데이터 가져오기
Future<List<KlineData>> fetchBybitKlines(
  String symbol,
  String interval,
  {int limit = 200}
) async {
  final url = 'https://api.bybit.com/v5/market/kline'
      '?category=linear'
      '&symbol=$symbol'
      '&interval=$interval'
      '&limit=$limit';

  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final klineList = data['result']['list'] as List;

      // Bybit는 최신 데이터가 먼저 오므로 역순 정렬 필요
      return klineList
          .map((k) => KlineData.fromBybitKline(k))
          .toList()
          .reversed
          .toList();
    } else {
      throw Exception('API 에러: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 데이터 로딩 실패: $e');
    return [];
  }
}
