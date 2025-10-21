import 'dart:io';
import 'package:bybit_scalping_bot/backtesting/band_walking_analyzer.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 밴드워킹 분석 스크립트
///
/// 사용법:
/// dart run scripts/analyze_band_walking.dart
void main() async {
  print('🔍 밴드워킹 패턴 분석 시작\n');

  // 분석할 시간대 설정 (UTC)
  // 10월 20일 15:45~16:45 UTC
  final startTime = DateTime.utc(2025, 10, 20, 15, 45);
  final endTime = DateTime.utc(2025, 10, 20, 16, 45);

  print('📅 분석 기간: ${startTime.toString()} ~ ${endTime.toString()} UTC');

  // 데이터 다운로드 기간 (분석 전에 충분한 데이터 필요)
  final dataStartTime = startTime.subtract(Duration(hours: 4)); // 4시간 전부터
  final dataEndTime = endTime.add(Duration(minutes: 30));

  print('📥 데이터 다운로드 중...');
  final klines = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: dataStartTime,
    endTime: dataEndTime,
  );

  if (klines.isEmpty) {
    print('❌ 데이터를 가져올 수 없습니다.');
    return;
  }

  print('✅ ${klines.length}개 캔들 데이터 다운로드 완료');
  print('   Period: ${klines.first.timestamp} ~ ${klines.last.timestamp}');

  // 밴드워킹 분석 실행
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  final analyses = BandWalkingAnalyzer.analyzePeriod(
    klines: klines,
    startTime: startTime,
    endTime: endTime,
  );

  // 요약 출력
  BandWalkingAnalyzer.printSummary(analyses);

  // 상세 출력 (HIGH, MEDIUM 리스크만)
  final significantAnalyses = analyses
      .where((a) => a.risk == 'HIGH' || a.risk == 'MEDIUM')
      .toList();

  if (significantAnalyses.isNotEmpty) {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📋 상세 분석 (HIGH/MEDIUM 리스크만)');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    for (final analysis in significantAnalyses) {
      print(analysis.toString());
    }
  }

  // CSV 저장
  await _saveToCsv(analyses);

  print('\n✅ 분석 완료!');
}

/// Bybit API로부터 Kline 데이터 가져오기
Future<List<KlineData>> _fetchKlines({
  required String symbol,
  required String interval,
  required DateTime startTime,
  required DateTime endTime,
}) async {
  final List<KlineData> allKlines = [];

  // Bybit API는 한 번에 최대 200개까지 반환
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
      'limit=200',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        print('❌ API Error: ${response.statusCode}');
        break;
      }

      final data = json.decode(response.body);

      if (data['retCode'] != 0) {
        print('❌ Bybit API Error: ${data['retMsg']}');
        break;
      }

      final klines = data['result']['list'] as List;

      if (klines.isEmpty) {
        break;
      }

      // Bybit API는 최신 데이터부터 반환하므로 역순 정렬 필요
      final parsedKlines = klines
          .map((k) => KlineData.fromBybitKline(k))
          .toList()
          .reversed
          .toList();

      allKlines.addAll(parsedKlines);

      // 다음 요청을 위해 시작 시간 업데이트
      final lastTimestamp = parsedKlines.last.timestamp;
      currentStart = lastTimestamp.add(Duration(minutes: int.parse(interval)));

      // Rate limit 방지
      await Future.delayed(Duration(milliseconds: 200));

      if (klines.length < 200) {
        // 모든 데이터를 가져왔음
        break;
      }
    } catch (e) {
      print('❌ Exception: $e');
      break;
    }
  }

  // 중복 제거 (timestamp 기준)
  final uniqueKlines = <DateTime, KlineData>{};
  for (final kline in allKlines) {
    uniqueKlines[kline.timestamp] = kline;
  }

  final result = uniqueKlines.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  return result;
}

/// CSV 파일로 저장
Future<void> _saveToCsv(List<BandWalkingAnalysis> analyses) async {
  if (analyses.isEmpty) return;

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'band_walking_analysis_$timestamp.csv';

  final file = File(filename);
  final buffer = StringBuffer();

  // Header
  buffer.writeln(BandWalkingAnalysis.csvHeader());

  // Data
  for (final analysis in analyses) {
    buffer.writeln(analysis.toCsv());
  }

  await file.writeAsString(buffer.toString());
  print('\n💾 CSV 저장 완료: $filename');
}
