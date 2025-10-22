import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/models/price_prediction_signal.dart';
import 'package:bybit_scalping_bot/models/top_coin.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service_v2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

/// 실시간 차트 Provider
///
/// 기능:
/// - 종목 선택 및 변경 (Top 10 코인)
/// - WebSocket 실시간 캔들 업데이트
/// - 다중 인터벌 지원 (1m, 5m, 30m, 1h, 4h)
/// - 실시간 예측 범위 계산 및 표시
class LiveChartProvider extends ChangeNotifier {
  // 현재 선택된 심볼
  String _symbol = 'BTCUSDT';
  String get symbol => _symbol;

  // 현재 선택된 인터벌
  String _selectedInterval = '5';
  String get selectedInterval => _selectedInterval;

  // 인터벌 옵션 (분 단위)
  static const Map<String, String> intervalOptions = {
    '1': '1분',
    '5': '5분',
    '30': '30분',
    '60': '1시간',
    '240': '4시간',
  };

  // 캔들 데이터 (인터벌별로 저장)
  final Map<String, List<KlineData>> _klinesCache = {};

  List<KlineData> get currentKlines => _klinesCache[_selectedInterval] ?? [];
  List<KlineData> get klines5m => _klinesCache['5'] ?? [];
  List<KlineData> get klines30m => _klinesCache['30'] ?? [];

  // 예측 신호 (V2 서비스)
  PricePredictionSignal? _prediction;
  PricePredictionSignal? get prediction => _prediction;

  // 실시간 예측 범위 (현재 캔들 기반 간단 계산)
  double? _predictedHigh;
  double? _predictedLow;
  double? _predictedClose;

  double? get predictedHigh => _predictedHigh;
  double? get predictedLow => _predictedLow;
  double? get predictedClose => _predictedClose;

  // WebSocket 클라이언트
  BybitPublicWebSocketClient? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  // 로딩 상태
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // 예측 서비스
  final _predictionService = PricePredictionServiceV2();

  // Top 10 종목 리스트
  List<TopCoin> _topCoins = [];
  bool _isLoadingCoins = false;

  List<TopCoin> get topCoins => _topCoins;
  bool get isLoadingCoins => _isLoadingCoins;

  // 지원 종목 리스트 (Top 10 우선, 없으면 기본값)
  List<String> get supportedSymbols => _topCoins.isNotEmpty
      ? _topCoins.map((coin) => coin.symbol).toList()
      : [
          'BTCUSDT',
          'ETHUSDT',
          'SOLUSDT',
          'BNBUSDT',
          'XRPUSDT',
        ];

  /// Top 10 코인 로드
  Future<void> loadTopCoins() async {
    if (_isLoadingCoins) return;

    _isLoadingCoins = true;
    notifyListeners();

    try {
      final url = Uri.parse('https://api.bybit.com/v5/market/tickers?category=linear');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['retCode'] == 0) {
          final list = data['result']['list'] as List<dynamic>;

          // USDT 선물만 필터링
          final usdtCoins = list
              .where((item) => item['symbol'].toString().endsWith('USDT'))
              .map((item) => TopCoin.fromJson(item))
              .toList();

          // 24시간 거래량 기준 정렬
          usdtCoins.sort((a, b) => b.turnover24h.compareTo(a.turnover24h));

          _topCoins = usdtCoins.take(10).toList();
        }
      }
    } catch (e) {
      print('Top 10 코인 로드 실패: $e');
    } finally {
      _isLoadingCoins = false;
      notifyListeners();
    }
  }

  /// 인터벌 변경
  Future<void> changeInterval(String newInterval) async {
    if (_selectedInterval == newInterval) return;

    _selectedInterval = newInterval;
    _error = null;
    notifyListeners();

    // 해당 인터벌 데이터가 없으면 로드
    if (!_klinesCache.containsKey(newInterval) || _klinesCache[newInterval]!.isEmpty) {
      await _loadKlinesForInterval(newInterval);
    }

    // WebSocket 재연결
    await _reconnectWebSocket();

    // 예측 업데이트
    _updatePrediction();
    _updateSimplePrediction();
  }

  /// 종목 변경
  Future<void> changeSymbol(String newSymbol) async {
    if (_symbol == newSymbol) return;

    _symbol = newSymbol;
    _error = null;
    _klinesCache.clear(); // 캐시 초기화
    notifyListeners();

    // WebSocket 재연결
    await _reconnectWebSocket();

    // 데이터 새로 로드
    await loadInitialData();
  }

  /// 초기 데이터 로드
  Future<void> loadInitialData() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Top 10 코인 로드
      if (_topCoins.isEmpty) {
        await loadTopCoins();
      }

      final endTime = DateTime.now().toUtc();

      // 선택된 인터벌 데이터 로드
      await _loadKlinesForInterval(_selectedInterval);

      // 5분봉, 30분봉은 예측용으로 항상 로드
      if (_selectedInterval != '5') {
        await _loadKlinesForInterval('5');
      }
      if (_selectedInterval != '30') {
        await _loadKlinesForInterval('30');
      }

      // 예측 생성
      _updatePrediction();
      _updateSimplePrediction();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 특정 인터벌 데이터 로드
  Future<void> _loadKlinesForInterval(String interval) async {
    final endTime = DateTime.now().toUtc();
    final intervalMinutes = int.parse(interval);

    // 인터벌에 따라 로드 기간 설정
    Duration lookback;
    if (intervalMinutes == 1) {
      lookback = const Duration(hours: 2);
    } else if (intervalMinutes == 5) {
      lookback = const Duration(hours: 8);
    } else if (intervalMinutes == 30) {
      lookback = const Duration(hours: 24);
    } else if (intervalMinutes == 60) {
      lookback = const Duration(days: 3);
    } else {
      lookback = const Duration(days: 10);
    }

    final startTime = endTime.subtract(lookback);

    final klines = await _fetchKlines(
      symbol: _symbol,
      interval: interval,
      startTime: startTime,
      endTime: endTime,
    );

    _klinesCache[interval] = klines;
  }

  /// WebSocket 연결
  Future<void> connectWebSocket() async {
    await _reconnectWebSocket();
  }

  /// WebSocket 재연결
  Future<void> _reconnectWebSocket() async {
    // 기존 연결 종료
    await _wsSubscription?.cancel();
    await _wsClient?.disconnect();

    // 새 연결 생성
    _wsClient = BybitPublicWebSocketClient();
    await _wsClient!.connect();

    // 현재 인터벌 구독
    final topic = 'kline.$_selectedInterval.$_symbol';
    await _wsClient!.subscribe(topic);

    final stream = _wsClient!.getStream(topic);
    if (stream != null) {
      _wsSubscription = stream.listen((data) {
        _handleKlineUpdate(data);
      });
    }
  }

  /// WebSocket 캔들 데이터 처리
  void _handleKlineUpdate(Map<String, dynamic> data) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('kline')) {
        return;
      }

      final klineData = data['data'] as List<dynamic>;
      if (klineData.isEmpty) return;

      final kline = klineData[0] as Map<String, dynamic>;

      // Parse kline data
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(kline['start']?.toString() ?? '0'),
      );
      final open = double.tryParse(kline['open']?.toString() ?? '0') ?? 0.0;
      final high = double.tryParse(kline['high']?.toString() ?? '0') ?? 0.0;
      final low = double.tryParse(kline['low']?.toString() ?? '0') ?? 0.0;
      final close = double.tryParse(kline['close']?.toString() ?? '0') ?? 0.0;
      final volume = double.tryParse(kline['volume']?.toString() ?? '0') ?? 0.0;

      if (open > 0 && high > 0 && low > 0 && close > 0) {
        final newKline = KlineData(
          timestamp: timestamp,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        );

        _onKlineUpdate(newKline);
      }
    } catch (e) {
      print('캔들 업데이트 처리 실패: $e');
    }
  }

  /// 캔들 업데이트 콜백
  void _onKlineUpdate(KlineData newKline) {
    final klines = _klinesCache[_selectedInterval];
    if (klines == null || klines.isEmpty) return;

    final lastKline = klines.last;

    // 같은 시간대면 업데이트, 아니면 추가
    if (lastKline.timestamp == newKline.timestamp) {
      klines[klines.length - 1] = newKline;
    } else {
      klines.add(newKline);

      // 최대 1000개 유지
      if (klines.length > 1000) {
        klines.removeAt(0);
      }
    }

    // 실시간 예측 업데이트
    _updateSimplePrediction();

    notifyListeners();
  }

  /// 간단한 실시간 예측 계산 (ATR 기반)
  void _updateSimplePrediction() {
    final klines = currentKlines;
    if (klines.length < 20) {
      _predictedHigh = null;
      _predictedLow = null;
      _predictedClose = null;
      return;
    }

    // 최근 14개 캔들의 ATR 계산
    double totalTR = 0;
    for (int i = klines.length - 14; i < klines.length; i++) {
      final k = klines[i];
      final prevClose = i > 0 ? klines[i - 1].close : k.open;

      final tr = [
        k.high - k.low,
        (k.high - prevClose).abs(),
        (k.low - prevClose).abs(),
      ].reduce((a, b) => a > b ? a : b);

      totalTR += tr;
    }

    final atr = totalTR / 14;
    final currentPrice = klines.last.close;

    // 최근 5개 캔들의 평균 변동폭
    double totalMove = 0;
    for (int i = klines.length - 5; i < klines.length; i++) {
      totalMove += (klines[i].high - klines[i].low);
    }
    final avgMove = totalMove / 5;

    // 예측 범위: ATR과 평균 변동폭의 평균값 사용
    final predictRange = (atr + avgMove) / 2;

    _predictedHigh = currentPrice + predictRange * 0.7;
    _predictedLow = currentPrice - predictRange * 0.7;

    // 종가는 최근 추세 반영
    final recentCandles = klines.sublist(klines.length - 5);
    final upCount = recentCandles.where((k) => k.close > k.open).length;

    if (upCount >= 3) {
      _predictedClose = currentPrice + predictRange * 0.3;
    } else if (upCount <= 1) {
      _predictedClose = currentPrice - predictRange * 0.3;
    } else {
      _predictedClose = currentPrice;
    }
  }

  /// V2 예측 업데이트
  void _updatePrediction() {
    if (klines5m.length < 50 || klines30m.length < 50) {
      _prediction = null;
      return;
    }

    try {
      _prediction = _predictionService.generatePredictionSignal(
        klines5m: klines5m.reversed.toList(),
        klines30m: klines30m.reversed.toList(),
      );
    } catch (e) {
      print('예측 생성 실패: $e');
      _prediction = null;
    }
  }

  /// Bybit API에서 캔들 데이터 가져오기
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

  /// 새로고침
  Future<void> refresh() async {
    _klinesCache.clear();
    await loadInitialData();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsClient?.disconnect();
    super.dispose();
  }
}
