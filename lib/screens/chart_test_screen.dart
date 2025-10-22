import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/widgets/trading_chart.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service_v2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 차트 테스트 화면
class ChartTestScreen extends StatefulWidget {
  const ChartTestScreen({Key? key}) : super(key: key);

  @override
  State<ChartTestScreen> createState() => _ChartTestScreenState();
}

class _ChartTestScreenState extends State<ChartTestScreen> {
  List<KlineData> klines5m = [];
  List<KlineData> klines30m = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      // 최근 1시간 5분봉 데이터
      final endTime = DateTime.now().toUtc();
      final startTime5m = endTime.subtract(const Duration(hours: 4));
      final startTime30m = endTime.subtract(const Duration(hours: 24));

      final klines5mData = await _fetchKlines(
        symbol: 'ETHUSDT',
        interval: '5',
        startTime: startTime5m,
        endTime: endTime,
      );

      final klines30mData = await _fetchKlines(
        symbol: 'ETHUSDT',
        interval: '30',
        startTime: startTime30m,
        endTime: endTime,
      );

      setState(() {
        klines5m = klines5mData;
        klines30m = klines30mData;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
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
      await Future.delayed(const Duration(milliseconds: 200));

      if (klines.length < 200) break;
    }

    final uniqueKlines = <DateTime, KlineData>{};
    for (final kline in allKlines) {
      uniqueKlines[kline.timestamp] = kline;
    }

    return uniqueKlines.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        title: const Text('트레이딩 차트 테스트'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            )
          : error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        '데이터 로드 실패',
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : klines5m.isEmpty
                  ? const Center(
                      child: Text(
                        '데이터가 없습니다',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : _buildChart(),
    );
  }

  Widget _buildChart() {
    // 예측 생성
    final predictionService = PricePredictionServiceV2();
    final prediction = klines5m.length >= 50 && klines30m.length >= 50
        ? predictionService.generatePredictionSignal(
            klines5m: klines5m.reversed.toList(),
            klines30m: klines30m.reversed.toList(),
          )
        : null;

    return TradingChart(
      klines: klines5m,
      prediction: prediction,
      symbol: 'ETH/USDT',
      interval: '5m',
    );
  }
}
