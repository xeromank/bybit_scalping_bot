import 'dart:io';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_result.dart';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';
import 'package:excel/excel.dart';

/// Run backtest for split entry strategy
///
/// Usage:
/// dart run bin/run_backtest.dart [SYMBOL] [DAYS]
///
/// Example:
/// dart run bin/run_backtest.dart ETHUSDT 90
Future<void> main(List<String> args) async {
  // Parse arguments
  final symbol = args.isNotEmpty ? args[0] : 'ETHUSDT';
  final days = args.length > 1 ? int.tryParse(args[1]) ?? 7 : 7;

  print('╔═══════════════════════════════════════════════════════════════╗');
  print('║  Bybit Split Entry Strategy Backtest                          ║');
  print('╚═══════════════════════════════════════════════════════════════╝');
  print('');
  print('Symbol: $symbol');
  print('Period: Last $days days');
  print('');

  // Fetch historical data
  print('📥 Fetching historical data from Bybit...');

  final apiClient = BybitApiClient(
    apiKey: '', // Public API - no auth needed for kline data
    apiSecret: '',
    baseUrl: 'https://api.bybit.com',
  );

  try {
    // Fetch kline data in batches (max 1000 per request)
    // We need ~288 candles per day for 5-minute interval (24 * 60 / 5 = 288)
    final totalCandles = days * 288;
    final klines = <KlineData>[];

    print('Fetching $totalCandles candles (~$days days of 5-minute data)...');

    // Bybit limits to 1000 candles per request
    final batchSize = 1000;
    final batches = (totalCandles / batchSize).ceil();
    int? endTime; // For pagination

    for (int batch = 0; batch < batches; batch++) {
      final limit = batch == batches - 1
          ? totalCandles % batchSize
          : batchSize;

      if (limit == 0) break;

      print('  Batch ${batch + 1}/$batches (${limit} candles)...');

      final response = await apiClient.getKlines(
        symbol: symbol,
        interval: '5', // 5-minute candles
        limit: limit,
        end: endTime, // Fetch older data
      );

      if (response['retCode'] != 0) {
        throw Exception('Bybit API error: ${response['retMsg']}');
      }

      final list = response['result']['list'] as List;

      // Convert to KlineData and reverse (Bybit returns newest first, we want oldest first)
      final batchKlines = list
          .map((k) => KlineData.fromBybitKline(k))
          .toList()
          .reversed
          .toList();

      // Insert at beginning (older batches go first)
      klines.insertAll(0, batchKlines);

      // Set end time for next batch (last candle's timestamp - 1)
      if (batch < batches - 1 && list.isNotEmpty) {
        final lastKline = list.last; // 배열 마지막 = 가장 오래된 데이터
        endTime = int.parse(lastKline[0].toString()) - 1;
      }

      // Rate limiting
      if (batch < batches - 1) {
        await Future.delayed(Duration(milliseconds: 200));
      }
    }

    print('✅ Fetched ${klines.length} candles');
    print('   Period: ${klines.first.timestamp} ~ ${klines.last.timestamp}');
    print('');

    // Configure backtest
    final config = BacktestConfig(
      symbol: symbol,
      initialCapital: 10000.0,
      leverage: 10,
      positionSizePercent: 0.05, // 5% per entry
      printProgress: true,
    );

    // Run backtest
    final engine = BacktestEngine(
      config: config,
      klines: klines,
    );

    final result = await engine.run();

    // Print results
    result.printSummary();

    // Auto-save results to CSV and XLSX
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

    // Save CSV
    final csvFilename = 'backtest_${symbol}_${timestamp}.csv';
    final csvFile = File(csvFilename);
    await csvFile.writeAsString(result.toCsv());
    print('\n✅ Saved CSV: $csvFilename');

    // Save XLSX
    final xlsxFilename = 'backtest_${symbol}_${timestamp}.xlsx';
    await _saveToExcel(result, xlsxFilename, symbol);
    print('✅ Saved XLSX: $xlsxFilename');

    print('\n✨ Backtest completed!');

  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}

/// Save backtest results to Excel file with multiple sheets
Future<void> _saveToExcel(BacktestResult result, String filename, String symbol) async {
  final excel = Excel.createExcel();

  // Remove default sheet
  excel.delete('Sheet1');

  // =========================================================================
  // Sheet 1: Summary
  // =========================================================================
  final summarySheet = excel['Summary'];

  // Header styling
  final headerStyle = CellStyle(
    bold: true,
    fontSize: 12,
  );

  final sectionHeaderStyle = CellStyle(
    bold: true,
    fontSize: 11,
  );

  int row = 0;

  // Title
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
    ..value = TextCellValue('백테스트 결과 요약')
    ..cellStyle = CellStyle(bold: true, fontSize: 16);
  row += 2;

  // Basic Info
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
    ..value = TextCellValue('기본 정보')
    ..cellStyle = sectionHeaderStyle;
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Symbol');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(symbol);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Period');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
    TextCellValue('${result.startDate.toString().substring(0, 10)} ~ ${result.endDate.toString().substring(0, 10)}');
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Initial Capital');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.initialCapital);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Leverage');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.leverage);
  row += 2;

  // Performance
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
    ..value = TextCellValue('수익 성과')
    ..cellStyle = sectionHeaderStyle;
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Final Capital');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.finalCapital);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Net Profit (USD)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.netProfit);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Net Profit (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.netProfitPercent * 100);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Return (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.returnPercent * 100);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Max Drawdown (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.maxDrawdown * 100);
  row += 2;

  // Trading Stats
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
    ..value = TextCellValue('거래 통계')
    ..cellStyle = sectionHeaderStyle;
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Total Trades');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.totalTrades);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Win Rate (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.winRate * 100);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Winning Trades');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.winningTrades);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Losing Trades');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.losingTrades);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Profit Factor');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.profitFactor);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Avg Win (USD)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.averageWin);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Avg Loss (USD)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.averageLoss);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Sharpe Ratio');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.sharpeRatio);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Avg Holding Time (min)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.averageHoldingTime.inMinutes);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Emergency Exits');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.emergencyExits);
  row += 2;

  // Strategy Performance
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
    ..value = TextCellValue('전략별 성과')
    ..cellStyle = sectionHeaderStyle;
  row++;

  // Strategy A
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Strategy A (추세추종)');
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Trades');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.strategyAMetrics['trades'] as int);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Win Rate (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue((result.strategyAMetrics['winRate'] as double) * 100);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Profit Factor');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.strategyAMetrics['profitFactor'] as double);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Net Profit (USD)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.strategyAMetrics['netProfit'] as double);
  row += 2;

  // Strategy B
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Strategy B (역추세)');
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Trades');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = IntCellValue(result.strategyBMetrics['trades'] as int);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Win Rate (%)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue((result.strategyBMetrics['winRate'] as double) * 100);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Profit Factor');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.strategyBMetrics['profitFactor'] as double);
  row++;
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('  Net Profit (USD)');
  summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(result.strategyBMetrics['netProfit'] as double);

  // =========================================================================
  // Sheet 2: All Trades
  // =========================================================================
  final tradesSheet = excel['Trades'];

  // Headers
  final headers = [
    'Entry Time', 'Exit Time', 'Side', 'Strategy', 'Avg Entry', 'Exit Price',
    'Qty', 'P/L USD', 'P/L %', 'Entries', 'Hold (min)', 'Exit Reason', 'Emergency',
    'Entry RSI', 'BB Upper', 'BB Middle', 'BB Lower'
  ];

  for (int i = 0; i < headers.length; i++) {
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
      ..value = TextCellValue(headers[i])
      ..cellStyle = headerStyle;
  }

  // Data rows
  for (int i = 0; i < result.trades.length; i++) {
    final trade = result.trades[i];
    final rowIndex = i + 1;

    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
      TextCellValue(trade.entryTime.toIso8601String());
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value =
      TextCellValue(trade.exitTime.toIso8601String());
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value =
      TextCellValue(trade.side.toString().split('.').last);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value =
      TextCellValue(trade.strategyType.toString().split('.').last);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.averageEntryPrice);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.exitPrice);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.quantity);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.profitLoss);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.profitLossPercent * 100);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value =
      IntCellValue(trade.entryCount);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex)).value =
      IntCellValue(trade.holdingTime.inMinutes);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIndex)).value =
      TextCellValue(trade.exitReason);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex)).value =
      TextCellValue(trade.isEmergencyExit ? 'YES' : 'NO');
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.entryRSI);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.entryBBUpper);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.entryBBMiddle);
    tradesSheet.cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIndex)).value =
      DoubleCellValue(trade.entryBBLower);
  }

  // Auto-fit columns
  for (int i = 0; i < headers.length; i++) {
    tradesSheet.setColumnWidth(i, 20);
  }

  // Save file
  final fileBytes = excel.save();
  if (fileBytes != null) {
    await File(filename).writeAsBytes(fileBytes);
  }
}
