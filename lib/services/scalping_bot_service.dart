import 'dart:async';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';

enum BotStatus { stopped, running, paused, error }

class ScalpingBotService {
  final BybitApiClient apiClient;
  final String symbol;
  final String leverage;
  final double orderAmount;
  final double profitTargetPercent;
  final double stopLossPercent;

  BotStatus _status = BotStatus.stopped;
  Timer? _monitoringTimer;
  String? _currentPositionSide;
  double? _entryPrice;

  BotStatus get status => _status;
  String? get currentPositionSide => _currentPositionSide;
  double? get entryPrice => _entryPrice;

  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  ScalpingBotService({
    required this.apiClient,
    required this.symbol,
    this.leverage = '5',
    this.orderAmount = 10.0,
    this.profitTargetPercent = 0.5,
    this.stopLossPercent = 0.3,
  });

  // 봇 시작
  Future<void> start() async {
    if (_status == BotStatus.running) return;

    try {
      // 레버리지 설정
      await apiClient.setLeverage(
        symbol: symbol,
        buyLeverage: leverage,
        sellLeverage: leverage,
      );

      _status = BotStatus.running;
      _emitStatus('봇이 시작되었습니다');

      // 포지션 모니터링 시작
      _startMonitoring();
    } catch (e) {
      _status = BotStatus.error;
      _emitStatus('봇 시작 실패: $e');
      rethrow;
    }
  }

  // 봇 중지
  Future<void> stop() async {
    _status = BotStatus.stopped;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _emitStatus('봇이 중지되었습니다');
  }

  // 모니터링 시작
  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        if (_status != BotStatus.running) {
          timer.cancel();
          return;
        }

        try {
          await _checkAndTrade();
        } catch (e) {
          _emitStatus('모니터링 오류: $e');
        }
      },
    );
  }

  // 거래 로직
  Future<void> _checkAndTrade() async {
    // 현재 포지션 확인
    final positionInfo = await apiClient.getPositionInfo(symbol: symbol);

    if (positionInfo['retCode'] != 0) {
      _emitStatus('포지션 조회 실패');
      return;
    }

    final positions = positionInfo['result']['list'] as List;

    if (positions.isEmpty) {
      // 포지션이 없으면 새로운 진입 신호 찾기
      await _findEntrySignal();
    } else {
      // 포지션이 있으면 청산 조건 확인
      await _checkExitConditions(positions[0]);
    }
  }

  // 진입 신호 찾기 (간단한 로직 - 추후 개선 가능)
  Future<void> _findEntrySignal() async {
    try {
      final ticker = await apiClient.getTicker(symbol: symbol);

      if (ticker['retCode'] != 0) {
        return;
      }

      final result = ticker['result'];
      final list = result['list'] as List;

      if (list.isEmpty) return;

      final tickerData = list[0];
      final lastPrice = double.parse(tickerData['lastPrice']);
      final priceChangePercent = double.parse(tickerData['price24hPcnt']) * 100;

      // 간단한 진입 로직: 24시간 변동률이 긍정적이면 롱, 부정적이면 숏
      String side;
      if (priceChangePercent > 0.5) {
        side = 'Buy';
      } else if (priceChangePercent < -0.5) {
        side = 'Sell';
      } else {
        _emitStatus('진입 신호 없음 (현재 가격: \$$lastPrice)');
        return;
      }

      // 주문 생성
      await _createOrder(side, lastPrice);
    } catch (e) {
      _emitStatus('진입 신호 탐색 오류: $e');
    }
  }

  // 주문 생성
  Future<void> _createOrder(String side, double currentPrice) async {
    try {
      final order = await apiClient.createOrder(
        symbol: symbol,
        side: side,
        orderType: 'Market',
        qty: orderAmount.toString(),
        positionIdx: 0,
      );

      if (order['retCode'] == 0) {
        _currentPositionSide = side;
        _entryPrice = currentPrice;
        _emitStatus(
          '${side == "Buy" ? "롱" : "숏"} 포지션 진입 (가격: \$$currentPrice)',
        );
      } else {
        _emitStatus('주문 실패: ${order['retMsg']}');
      }
    } catch (e) {
      _emitStatus('주문 생성 오류: $e');
    }
  }

  // 청산 조건 확인
  Future<void> _checkExitConditions(Map<String, dynamic> position) async {
    try {
      final side = position['side'];
      final size = double.parse(position['size']);
      final entryPrice = double.parse(position['avgPrice']);
      final unrealisedPnl = double.parse(position['unrealisedPnl']);

      if (size == 0) {
        _currentPositionSide = null;
        _entryPrice = null;
        return;
      }

      _currentPositionSide = side;
      _entryPrice = entryPrice;

      // 현재 가격 가져오기
      final ticker = await apiClient.getTicker(symbol: symbol);
      final tickerData = ticker['result']['list'][0];
      final currentPrice = double.parse(tickerData['lastPrice']);

      // 수익률 계산
      final pnlPercent = (unrealisedPnl / (entryPrice * size)) * 100;

      _emitStatus(
        '포지션: ${side == "Buy" ? "롱" : "숏"} | '
        '진입: \$$entryPrice | 현재: \$$currentPrice | '
        '손익: ${pnlPercent.toStringAsFixed(2)}%',
      );

      // 익절 또는 손절 조건 확인
      bool shouldExit = false;
      String exitReason = '';

      if (pnlPercent >= profitTargetPercent) {
        shouldExit = true;
        exitReason = '익절';
      } else if (pnlPercent <= -stopLossPercent) {
        shouldExit = true;
        exitReason = '손절';
      }

      if (shouldExit) {
        await _closePosition(side, size, exitReason);
      }
    } catch (e) {
      _emitStatus('청산 조건 확인 오류: $e');
    }
  }

  // 포지션 청산
  Future<void> _closePosition(String positionSide, double size, String reason) async {
    try {
      // 포지션과 반대 방향으로 주문
      final closeSide = positionSide == 'Buy' ? 'Sell' : 'Buy';

      final order = await apiClient.createOrder(
        symbol: symbol,
        side: closeSide,
        orderType: 'Market',
        qty: size.toString(),
        positionIdx: 0,
        reduceOnly: true,
      );

      if (order['retCode'] == 0) {
        _emitStatus('포지션 청산 ($reason)');
        _currentPositionSide = null;
        _entryPrice = null;
      } else {
        _emitStatus('청산 실패: ${order['retMsg']}');
      }
    } catch (e) {
      _emitStatus('포지션 청산 오류: $e');
    }
  }

  // 상태 이벤트 전송
  void _emitStatus(String message) {
    _statusController.add({
      'timestamp': DateTime.now(),
      'status': _status.toString(),
      'message': message,
      'positionSide': _currentPositionSide,
      'entryPrice': _entryPrice,
    });
  }

  // 리소스 정리
  void dispose() {
    _monitoringTimer?.cancel();
    _statusController.close();
  }
}
