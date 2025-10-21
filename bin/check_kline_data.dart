import 'package:bybit_scalping_bot/services/bybit_api_client.dart';

/// Check actual kline data from Bybit
Future<void> main() async {
  final apiClient = BybitApiClient(
    apiKey: '',
    apiSecret: '',
    baseUrl: 'https://api.bybit.com',
  );

  print('Fetching recent 100 candles...');

  final response = await apiClient.getKlines(
    symbol: 'BTCUSDT',
    interval: '5',
    limit: 100,
  );

  if (response['retCode'] != 0) {
    print('Error: ${response['retMsg']}');
    return;
  }

  final list = response['result']['list'] as List;

  print('\nTotal candles: ${list.length}');
  print('\nFirst 10 candles (newest to oldest):');
  print('─' * 80);
  print('Timestamp (UTC)           | Timestamp (KST)          | Open      | High      | Low       | Close     ');
  print('─' * 80);

  for (int i = 0; i < 10 && i < list.length; i++) {
    final kline = list[i];
    final timestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(kline[0].toString()));
    final timestampKst = timestamp.add(Duration(hours: 9));
    final open = double.parse(kline[1].toString());
    final high = double.parse(kline[2].toString());
    final low = double.parse(kline[3].toString());
    final close = double.parse(kline[4].toString());

    print('${timestamp.toString().substring(0, 19)} | ${timestampKst.toString().substring(0, 19)} | ${open.toStringAsFixed(2).padLeft(9)} | ${high.toStringAsFixed(2).padLeft(9)} | ${low.toStringAsFixed(2).padLeft(9)} | ${close.toStringAsFixed(2).padLeft(9)}');
  }

  print('\nLast 10 candles:');
  print('─' * 80);
  print('Timestamp (UTC)           | Timestamp (KST)          | Open      | High      | Low       | Close     ');
  print('─' * 80);

  for (int i = list.length - 10; i < list.length; i++) {
    final kline = list[i];
    final timestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(kline[0].toString()));
    final timestampKst = timestamp.add(Duration(hours: 9));
    final open = double.parse(kline[1].toString());
    final high = double.parse(kline[2].toString());
    final low = double.parse(kline[3].toString());
    final close = double.parse(kline[4].toString());

    print('${timestamp.toString().substring(0, 19)} | ${timestampKst.toString().substring(0, 19)} | ${open.toStringAsFixed(2).padLeft(9)} | ${high.toStringAsFixed(2).padLeft(9)} | ${low.toStringAsFixed(2).padLeft(9)} | ${close.toStringAsFixed(2).padLeft(9)}');
  }
}
