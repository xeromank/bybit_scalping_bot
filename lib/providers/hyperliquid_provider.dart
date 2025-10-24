import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';
import 'package:bybit_scalping_bot/repositories/hyperliquid_trader_repository.dart';
import 'package:bybit_scalping_bot/services/hyperliquid/hyperliquid_api_client.dart';
import 'package:bybit_scalping_bot/services/hyperliquid/hyperliquid_database_service.dart';
import 'package:bybit_scalping_bot/services/hyperliquid/position_change_detector.dart';
import 'package:bybit_scalping_bot/services/notification_service.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Hyperliquid 트레이더 추적 Provider
///
/// Responsibility: 트레이더 관리 및 실시간 업데이트
class HyperliquidProvider extends ChangeNotifier {
  final HyperliquidTraderRepository _repository;
  final HyperliquidApiClient _apiClient;
  final HyperliquidDatabaseService _dbService = HyperliquidDatabaseService();
  final PositionChangeDetector _changeDetector = PositionChangeDetector();
  final NotificationService _notificationService = NotificationService();

  // 트레이더 목록
  List<HyperliquidTrader> _traders = [];
  List<HyperliquidTrader> get traders => _traders;

  // 각 트레이더의 계정 상태 (주소 → 상태)
  Map<String, HyperliquidAccountState> _accountStates = {};
  Map<String, HyperliquidAccountState> get accountStates => _accountStates;

  // 로딩 상태
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 에러 메시지
  String? _error;
  String? get error => _error;

  // 자동 업데이트 타이머
  Timer? _autoUpdateTimer;

  HyperliquidProvider({
    required HyperliquidTraderRepository repository,
    required HyperliquidApiClient apiClient,
  })  : _repository = repository,
        _apiClient = apiClient;

  /// 초기화
  Future<void> initialize() async {
    await loadTraders();
    await refreshAllStates();
    _startAutoUpdate();
  }

  /// 트레이더 목록 로드
  Future<void> loadTraders() async {
    try {
      _traders = await _repository.getAllTraders();
      notifyListeners();
      Logger.success('트레이더 ${_traders.length}명 로드 완료');
    } catch (e) {
      Logger.error('트레이더 로드 실패: $e');
      _error = '트레이더 목록을 불러올 수 없습니다';
      notifyListeners();
    }
  }

  /// 트레이더 추가
  Future<bool> addTrader(String address, {String? nickname}) async {
    try {
      _error = null;

      // 주소 검증
      if (!_isValidAddress(address)) {
        _error = '올바른 주소가 아닙니다 (0x로 시작해야 합니다)';
        notifyListeners();
        return false;
      }

      // 트레이더 생성
      final trader = HyperliquidTrader(
        address: address.toLowerCase(),
        nickname: nickname,
        addedAt: DateTime.now(),
      );

      // 저장
      final success = await _repository.addTrader(trader);
      if (!success) {
        _error = '이미 추가된 트레이더입니다';
        notifyListeners();
        return false;
      }

      // 계정 상태 조회 (백그라운드에서 비동기로 실행)
      // 즉시 추가하고, 상태는 나중에 로드
      // await refreshTraderState(trader.address);
      refreshTraderState(trader.address).catchError((e) {
        Logger.warning('트레이더 상태 조회 실패 (백그라운드): $e');
      });

      // 목록 재로드
      await loadTraders();

      Logger.success('트레이더 추가 완료: ${trader.displayName}');
      return true;
    } catch (e) {
      Logger.error('트레이더 추가 실패: $e');
      _error = '트레이더를 추가할 수 없습니다';
      notifyListeners();
      return false;
    }
  }

  /// 트레이더 삭제
  Future<bool> removeTrader(String address) async {
    try {
      _error = null;

      final success = await _repository.removeTrader(address);
      if (success) {
        _accountStates.remove(address);
        await loadTraders();
        Logger.success('트레이더 삭제 완료');
      }

      return success;
    } catch (e) {
      Logger.error('트레이더 삭제 실패: $e');
      _error = '트레이더를 삭제할 수 없습니다';
      notifyListeners();
      return false;
    }
  }

  /// 닉네임 업데이트
  Future<bool> updateNickname(String address, String nickname) async {
    try {
      final trader = _traders.firstWhere((t) => t.address == address);
      final updated = trader.copyWith(nickname: nickname);

      final success = await _repository.updateTrader(updated);
      if (success) {
        await loadTraders();
      }

      return success;
    } catch (e) {
      Logger.error('닉네임 업데이트 실패: $e');
      return false;
    }
  }

  /// 특정 트레이더의 계정 상태 갱신
  Future<void> refreshTraderState(String address) async {
    try {
      final state = await _apiClient.getAccountState(address);
      _accountStates[address] = state;
      notifyListeners();
    } catch (e) {
      Logger.error('트레이더 $address 상태 조회 실패: $e');
    }
  }

  /// 모든 트레이더의 계정 상태 갱신
  Future<void> refreshAllStates() async {
    if (_traders.isEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. 이전 스냅샷 조회 (DB에서)
      final oldSnapshots = await _dbService.getAllLatestSnapshots(
        _traders.map((t) => t.address).toList(),
      );

      // 2. 새로운 상태 조회 (API에서)
      final addresses = _traders.map((t) => t.address).toList();
      _accountStates = await _apiClient.getMultipleAccountStates(addresses);

      Logger.success('${_accountStates.length}명의 트레이더 상태 업데이트 완료');

      // 3. 각 트레이더별 변화 감지 및 처리
      for (final trader in _traders) {
        final newState = _accountStates[trader.address];
        if (newState == null) continue;

        final oldSnapshot = oldSnapshots[trader.address] ?? [];

        // 변화 감지
        final changes = _changeDetector.detectChanges(
          trader: trader,
          oldSnapshots: oldSnapshot,
          newState: newState,
        );

        // 변화가 있으면 처리
        for (final change in changes) {
          // 알림 발송
          await _notificationService.showTradeNotification(
            title: '🐋 고래 알림: ${trader.displayName}',
            body: change.notificationMessage,
            payload: 'whale_${trader.address}_${change.coin}',
          );

          // 변화 로그 저장
          await _dbService.insertPositionChangeLog(
            traderAddress: trader.address,
            changeType: change.type.name,
            coin: change.coin,
            details: change.logMessage,
          );

          Logger.warning(change.logMessage);
        }

        // 4. 새 포지션 스냅샷 저장
        await _savePositionSnapshots(trader.address, newState);

        // 5. 오래된 스냅샷 정리
        await _dbService.cleanupOldSnapshots(trader.address, keepCount: 3);
      }

      // 오래된 변화 로그 정리 (1000개 유지)
      await _dbService.cleanupOldChangeLogs(keep: 1000);
    } catch (e) {
      Logger.error('트레이더 상태 갱신 실패: $e');
      _error = '데이터를 불러올 수 없습니다';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 포지션 스냅샷 저장
  Future<void> _savePositionSnapshots(
    String traderAddress,
    HyperliquidAccountState state,
  ) async {
    for (final assetPos in state.assetPositions) {
      final pos = assetPos.position;
      await _dbService.insertPositionSnapshot(
        traderAddress: traderAddress,
        coin: pos.coin,
        side: pos.sideText,
        size: pos.sizeAbs,
        entryPrice: pos.entryPxAsDouble,
        positionValue: pos.positionValueAsDouble,
        unrealizedPnl: pos.unrealizedPnlAsDouble,
        leverageValue: pos.leverage.value,
        leverageType: pos.leverage.type,
      );
    }
  }

  /// 자동 업데이트 시작 (10초마다)
  void _startAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_traders.isNotEmpty) {
        refreshAllStates();
      }
    });
    Logger.debug('Hyperliquid 자동 업데이트 시작 (10초 간격)');
  }

  /// 자동 업데이트 중지
  void stopAutoUpdate() {
    _autoUpdateTimer?.cancel();
    Logger.debug('Hyperliquid 자동 업데이트 중지');
  }

  /// 주소 검증
  bool _isValidAddress(String address) {
    return address.toLowerCase().startsWith('0x') && address.length == 42;
  }

  /// 특정 트레이더의 계정 상태 가져오기
  HyperliquidAccountState? getAccountState(String address) {
    return _accountStates[address];
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }
}
