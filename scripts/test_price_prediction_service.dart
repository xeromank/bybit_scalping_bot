import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 가격 예측 서비스 테스트
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔮 가격 범위 예측 서비스 테스트');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 최근 데이터 가져오기
  print('📥 최근 데이터 다운로드 중...\n');

  final endTime = DateTime.now().toUtc();
  final startTime5m = endTime.subtract(Duration(hours: 5)); // 5분봉 60개
  final startTime30m = endTime.subtract(Duration(hours: 30)); // 30분봉 60개

  final klines5m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: startTime5m,
    endTime: endTime,
  );

  final klines30m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '30',
    startTime: startTime30m,
    endTime: endTime,
  );

  print('✅ 5분봉: ${klines5m.length}개');
  print('✅ 30분봉: ${klines30m.length}개\n');

  if (klines5m.length < 50 || klines30m.length < 50) {
    print('❌ 데이터 부족');
    return;
  }

  // 최신 데이터가 첫 번째로 오도록 정렬
  klines5m.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  klines30m.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  // 예측 서비스 생성
  final predictionService = PricePredictionService();

  // 신호 생성
  final signal = predictionService.generatePredictionSignal(
    klines5m: klines5m,
    klines30m: klines30m,
  );

  if (signal == null) {
    print('❌ 신호 생성 실패');
    return;
  }

  // 신호 출력
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 예측 신호');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  print(signal.toString());

  // 시각적 표현
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📈 가격 범위 시각화');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  _visualizePriceRange(signal);

  // 다음 캔들 대기 후 실제 결과와 비교 (옵션)
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('⏳ 5분 후 실제 결과 확인을 원하시면 스크립트를 5분 후 다시 실행하세요');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  print('✅ 테스트 완료!');
}

/// 가격 범위 시각화
void _visualizePriceRange(signal) {
  final currentPrice = signal.currentPrice;
  final predictedHigh = signal.predictedHigh;
  final predictedLow = signal.predictedLow;

  // 가격 스케일 생성 (20단계)
  final step = (predictedHigh - predictedLow) / 20;

  print('가격          |  예측 범위');
  print('─────────────────────────────────────');

  for (int i = 20; i >= 0; i--) {
    final price = predictedLow + (step * i);
    final priceStr = '\$${price.toStringAsFixed(2)}'.padLeft(12);

    String bar = '';

    // 예측 최고가 표시
    if ((price - predictedHigh).abs() < step / 2) {
      bar = '█ 예측 최고가';
    }
    // 현재가 표시
    else if ((price - currentPrice).abs() < step / 2) {
      bar = '▓ 현재가 ← HERE';
    }
    // 예측 최저가 표시
    else if ((price - predictedLow).abs() < step / 2) {
      bar = '█ 예측 최저가';
    }
    // 범위 내부
    else if (price > predictedLow && price < predictedHigh) {
      if (price > currentPrice) {
        bar = '░ 상승 여력';
      } else {
        bar = '░ 하락 여력';
      }
    }

    print('$priceStr  │  $bar');
  }

  print('─────────────────────────────────────');
}

/// Bybit 캔들 데이터 가져오기
Future<List<KlineData>> _fetchKlines({
  required String symbol,
  required String interval,
  required DateTime startTime,
  required DateTime endTime,
}) async {
  final List<KlineData> allKlines = [];
  DateTime currentStart = startTime;

  while (currentStart.isBefore(endTime)) {
    final startMs = currentStart.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;

    final url = Uri.parse(
      'https://api.bybit.com/v5/market/kline?'
      'category=linear&'
      'symbol=$symbol&'
      'interval=$interval&'
      'start=$startMs&'
      'end=$endMs&'
      'limit=1000',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) break;

      final data = json.decode(response.body);
      if (data['retCode'] != 0) break;

      final klines = data['result']['list'] as List;
      if (klines.isEmpty) break;

      final parsedKlines = klines
          .map((k) => KlineData.fromBybitKline(k))
          .toList()
          .reversed
          .toList();

      allKlines.addAll(parsedKlines);

      currentStart = parsedKlines.last.timestamp.add(Duration(minutes: int.parse(interval)));
      await Future.delayed(Duration(milliseconds: 200));

      if (klines.length < 200) break;
    } catch (e) {
      print('Error: $e');
      break;
    }
  }

  // 중복 제거
  final uniqueKlines = <DateTime, KlineData>{};
  for (final kline in allKlines) {
    uniqueKlines[kline.timestamp] = kline;
  }

  return uniqueKlines.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}
