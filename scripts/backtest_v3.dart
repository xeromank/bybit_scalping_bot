import 'dart:io';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_result.dart';
import 'package:bybit_scalping_bot/backtesting/entry_strategy_v3.dart';
import 'package:bybit_scalping_bot/backtesting/split_entry_strategy.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// V3 백테스트 스크립트
///
/// 사용법:
/// dart run scripts/backtest_v3.dart
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 V3 전략 백테스트');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 백테스트 기간 설정
  final startTime = DateTime.utc(2024, 10, 19, 0, 0);
  final endTime = DateTime.utc(2024, 10, 22, 23, 59);

  print('기간: ${startTime.toString().substring(0, 10)} ~ ${endTime.toString().substring(0, 10)}');

  // 데이터 다운로드
  print('\n📥 데이터 다운로드 중...');
  final klines = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: startTime,
    endTime: endTime,
  );

  if (klines.isEmpty) {
    print('❌ 데이터를 가져올 수 없습니다.');
    return;
  }

  print('✅ ${klines.length}개 캔들 다운로드 완료');
  print('   기간: ${klines.first.timestamp} ~ ${klines.last.timestamp}\n');

  // 백테스트 설정
  final config = BacktestConfig(
    symbol: 'ETHUSDT',
    initialCapital: 10000.0,
    leverage: 10,
    positionSizePercent: 0.05,
    printProgress: true,
  );

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔵 V3 전략 백테스트 실행');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final engineV3 = BacktestEngineV3(
    config: config,
    klines: klines,
  );

  final resultV3 = await engineV3.run();

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 V3 전략 결과');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  _printResult(resultV3, 'V3');

  // CSV 저장
  await _saveResultToCsv(resultV3, 'v3');

  print('\n✅ 백테스트 완료!');
}

/// Bybit API로부터 Kline 데이터 가져오기
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
      'limit=200',
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

  final uniqueKlines = <DateTime, KlineData>{};
  for (final kline in allKlines) {
    uniqueKlines[kline.timestamp] = kline;
  }

  return uniqueKlines.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}

/// 결과 출력
void _printResult(BacktestResult result, String label) {
  print('[$label 전략]');
  print('  총 거래: ${result.totalTrades}건');
  print('  승리/패배: ${result.winningTrades}승 ${result.losingTrades}패');
  print('  승률: ${result.winRate.toStringAsFixed(1)}%');
  print('  최종 자금: \$${result.finalCapital.toStringAsFixed(2)}');
  print('  수익률: ${result.profitPercent >= 0 ? '+' : ''}${result.profitPercent.toStringAsFixed(2)}%');
  print('  최대 손실폭: ${result.maxDrawdown.toStringAsFixed(2)}%');
  print('  Profit Factor: ${result.profitFactor.toStringAsFixed(2)}');

  if (result.trades.isNotEmpty) {
    final avgWin = result.winningTrades > 0
        ? result.trades.where((t) => t.pnl > 0).map((t) => t.pnl).reduce((a, b) => a + b) / result.winningTrades
        : 0;
    final avgLoss = result.losingTrades > 0
        ? result.trades.where((t) => t.pnl < 0).map((t) => t.pnl).reduce((a, b) => a + b) / result.losingTrades
        : 0;
    print('  평균 승리: \$${avgWin.toStringAsFixed(2)}');
    print('  평균 손실: \$${avgLoss.toStringAsFixed(2)}');
  }
}

/// CSV 저장
Future<void> _saveResultToCsv(BacktestResult result, String strategy) async {
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'backtest_${strategy}_${result.config.symbol}_$timestamp.csv';

  final buffer = StringBuffer();
  buffer.writeln('Trade,Entry_Time,Exit_Time,Side,Strategy,Entry_Price,Exit_Price,Size,PnL,PnL%,Reasoning');

  for (int i = 0; i < result.trades.length; i++) {
    final trade = result.trades[i];
    buffer.writeln(
      '${i + 1},'
      '${trade.entryTime.toIso8601String()},'
      '${trade.exitTime.toIso8601String()},'
      '${trade.side.name},'
      '${trade.strategy?.name ?? "unknown"},'
      '${trade.entryPrice.toStringAsFixed(2)},'
      '${trade.exitPrice.toStringAsFixed(2)},'
      '${trade.size.toStringAsFixed(4)},'
      '${trade.pnl.toStringAsFixed(2)},'
      '${trade.pnlPercent.toStringAsFixed(2)},'
      '"${trade.reasoning}"',
    );
  }

  await File(filename).writeAsString(buffer.toString());
  print('\n💾 CSV 저장: $filename');
}

/// V3 전용 백테스트 엔진
class BacktestEngineV3 {
  final BacktestConfig config;
  final List<KlineData> klines;

  double _capital;
  final _position = PositionTracker();
  final List<TradeResult> _trades = [];

  BacktestEngineV3({
    required this.config,
    required this.klines,
  }) : _capital = config.initialCapital;

  Future<BacktestResult> run() async {
    if (klines.length < 100) {
      throw ArgumentError('Need at least 100 klines');
    }

    for (int i = 99; i < klines.length; i++) {
      final currentKline = klines[i];
      final recentKlines = klines.sublist(i - 49, i + 1);

      // Exit 체크
      final exitSignal = EntryStrategyV3.checkExitSignal(
        recentKlines: recentKlines,
        currentPrice: currentKline.close,
        position: _position,
      );

      if (exitSignal != null && exitSignal.hasSignal) {
        _executeExit(exitSignal, currentKline);
      }

      // Entry 체크
      if (!_position.hasPosition) {
        final entrySignal = EntryStrategyV3.checkEntrySignal(
          recentKlines: recentKlines,
          currentPrice: currentKline.close,
          currentTime: currentKline.timestamp,
          position: _position,
        );

        if (entrySignal != null && entrySignal.hasSignal) {
          _executeEntry(entrySignal, currentKline);
        }
      }
    }

    // 미청산 포지션 정리
    if (_position.hasPosition) {
      final lastKline = klines.last;
      _position.close(
        exitPrice: lastKline.close,
        exitTime: lastKline.timestamp,
        exitReason: '백테스트 종료',
      );
      _trades.add(_position.toTradeResult());
      _capital += _position.realizedPnL;
    }

    return BacktestResult(
      config: config,
      trades: _trades,
      finalCapital: _capital,
      klines: klines,
    );
  }

  void _executeEntry(SplitEntrySignal signal, KlineData kline) {
    final positionValue = _capital * config.positionSizePercent;
    final leveragedValue = positionValue * config.leverage;
    final size = leveragedValue / signal.entryPrice;

    _position.open(
      side: signal.side,
      entryPrice: signal.entryPrice,
      size: size,
      entryTime: kline.timestamp,
      leverage: config.leverage,
      entryReason: signal.reasoning,
      strategy: signal.strategyType,
    );

    if (config.printProgress) {
      print('${kline.timestamp.toString().substring(0, 16)} - ENTRY: ${signal.toString()}');
    }
  }

  void _executeExit(SplitExitSignal signal, KlineData kline) {
    _position.close(
      exitPrice: signal.exitPrice,
      exitTime: kline.timestamp,
      exitReason: signal.reasoning,
      exitPercent: signal.exitPercent,
    );

    if (_position.size == 0) {
      _trades.add(_position.toTradeResult());
      _capital += _position.realizedPnL;

      if (config.printProgress) {
        final trade = _trades.last;
        final pnlSign = trade.pnl >= 0 ? '+' : '';
        print('${kline.timestamp.toString().substring(0, 16)} - EXIT:  ${signal.toString()} → ${pnlSign}\$${trade.pnl.toStringAsFixed(2)} (${pnlSign}${trade.pnlPercent.toStringAsFixed(2)}%)');
      }

      _position.reset();
    }
  }
}
