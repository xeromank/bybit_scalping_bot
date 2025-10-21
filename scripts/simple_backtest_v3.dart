import 'dart:io';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/entry_strategy_v3.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 간단한 V3 백테스트
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 V3 전략 백테스트 (Simple)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 전체 기간: Oct 19 00:00 ~ Oct 22 23:59
  final startTime = DateTime.utc(2025, 10, 19, 0, 0);
  final endTime = DateTime.utc(2025, 10, 22, 23, 59);

  print('기간: ${startTime.toString().substring(0, 10)} ~ ${endTime.toString().substring(0, 10)}');

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
  if (klines.isNotEmpty) {
    print('   첫 캔들: ${klines.first.timestamp}');
    print('   마지막 캔들: ${klines.last.timestamp}\n');
  }

  // 수동 백테스트
  double capital = 10000.0;
  final leverage = 10;
  final positionSizePercent = 0.05;
  final position = PositionTracker();
  final trades = <String>[];
  int tradeCount = 0;
  int winCount = 0;
  double totalPnL = 0.0;
  int checkCount = 0;

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔵 V3 전략 실행');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  for (int i = 50; i < klines.length; i++) {
    checkCount++;
    final currentKline = klines[i];
    final recentKlines = klines.sublist(i - 49, i + 1);

    // Exit 체크
    if (position.hasPosition) {
      final exitSignal = EntryStrategyV3.checkExitSignal(
        recentKlines: recentKlines,
        currentPrice: currentKline.close,
        position: position,
      );

      if (exitSignal != null && exitSignal.hasSignal) {
        final avgPrice = position.averagePrice;
        final size = position.totalSize;

        double pnl = 0;
        if (position.currentSide == PositionSide.long) {
          pnl = (exitSignal.exitPrice - avgPrice) * size;
        } else {
          pnl = (avgPrice - exitSignal.exitPrice) * size;
        }

        capital += pnl;
        totalPnL += pnl;
        if (pnl > 0) winCount++;
        tradeCount++;

        final pnlSign = pnl >= 0 ? '+' : '';
        final pnlPercent = (pnl / (avgPrice * size)) * 100;

        final utcTime = currentKline.timestamp.toString().substring(0, 16);
        print('$utcTime - EXIT:  ${position.currentSide.name.toUpperCase()} @ \$${exitSignal.exitPrice.toStringAsFixed(2)} → ${pnlSign}\$${pnl.toStringAsFixed(2)} (${pnlSign}${pnlPercent.toStringAsFixed(2)}%) - ${exitSignal.reasoning}');

        trades.add('Trade $tradeCount: ${pnl >= 0 ? "WIN" : "LOSS"} ${pnlSign}\$${pnl.toStringAsFixed(2)}');

        position.reset();
      }
    }

    // Entry 체크
    if (!position.hasPosition) {
      final entrySignal = EntryStrategyV3.checkEntrySignal(
        recentKlines: recentKlines,
        currentPrice: currentKline.close,
        currentTime: currentKline.timestamp,
        position: position,
      );

      if (entrySignal != null && entrySignal.hasSignal) {
        final positionValue = capital * positionSizePercent;
        final leveragedValue = positionValue * leverage;
        final size = leveragedValue / entrySignal.entryPrice;

        position.addEntry(
          price: entrySignal.entryPrice,
          quantity: size,
          entryTime: currentKline.timestamp,
          entryLevel: 1,
          side: entrySignal.side,
          strategy: entrySignal.strategyType,
        );

        final utcTime = currentKline.timestamp.toString().substring(0, 16);
        print('$utcTime - ENTRY: ${entrySignal.side.name.toUpperCase()} @ \$${entrySignal.entryPrice.toStringAsFixed(2)} - ${entrySignal.reasoning}');
      } else if (i == 100) {
        // Debug: Print why no signal at check #50
        print('DEBUG @ check 50: No entry signal generated');
      }
    }

    // Progress
    if (i % 200 == 0) {
      final progress = (i / klines.length * 100).toStringAsFixed(1);
      print('[$progress%] Trades: $tradeCount | Capital: \$${capital.toStringAsFixed(2)}');
    }
  }

  // 미청산 포지션 정리
  if (position.hasPosition) {
    final lastKline = klines.last;
    final avgPrice = position.averagePrice;
    final size = position.totalSize;

    double pnl = 0;
    if (position.currentSide == PositionSide.long) {
      pnl = (lastKline.close - avgPrice) * size;
    } else {
      pnl = (avgPrice - lastKline.close) * size;
    }

    capital += pnl;
    totalPnL += pnl;
    if (pnl > 0) winCount++;
    tradeCount++;

    final utcTime = lastKline.timestamp.toString().substring(0, 16);
    print('\n$utcTime - EXIT:  백테스트 종료 → ${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}');
    position.reset();
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 V3 전략 결과');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final winRate = tradeCount > 0 ? (winCount / tradeCount * 100) : 0;
  final profitPercent = (totalPnL / 10000.0) * 100;

  print('신호 체크 횟수: $checkCount회');
  print('총 거래: $tradeCount건');
  print('승리/패배: $winCount승 ${tradeCount - winCount}패');
  print('승률: ${winRate.toStringAsFixed(1)}%');
  print('최종 자금: \$${capital.toStringAsFixed(2)}');
  print('수익: ${totalPnL >= 0 ? '+' : ''}\$${totalPnL.toStringAsFixed(2)}');
  print('수익률: ${profitPercent >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(2)}%');

  print('\n✅ 백테스트 완료!');
}

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

      print('  Fetched ${parsedKlines.length} candles, total: ${allKlines.length}');

      currentStart = parsedKlines.last.timestamp.add(Duration(minutes: int.parse(interval)));
      await Future.delayed(Duration(milliseconds: 200));

      if (klines.length < 200) {
        print('  Last batch received, stopping fetch');
        break;
      }
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
