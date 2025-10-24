import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';

/// 포지션 변화 타입
enum PositionChangeType {
  newPosition,      // 새 포지션 진입
  closedPosition,   // 포지션 청산
  sizeIncreased,    // 포지션 사이즈 증가
  sizeDecreased,    // 포지션 사이즈 감소
  sideFlipped,      // 롱/숏 전환
}

/// 포지션 변화 정보
class PositionChange {
  final PositionChangeType type;
  final HyperliquidTrader trader;
  final String coin;
  final Map<String, dynamic> oldData;
  final Map<String, dynamic> newData;

  PositionChange({
    required this.type,
    required this.trader,
    required this.coin,
    required this.oldData,
    required this.newData,
  });

  /// 알림 메시지 생성
  String get notificationMessage {
    final traderName = trader.displayName;

    switch (type) {
      case PositionChangeType.newPosition:
        final side = newData['side'] as String;
        final size = newData['size'] as double;
        final entryPrice = newData['entry_price'] as double;
        final leverage = newData['leverage_value'] as int;
        return '🐋 $traderName님이 새 포지션 진입\n'
            '📊 $coin $side\n'
            '💰 크기: ${size.toStringAsFixed(4)}\n'
            '💵 진입가: \$${entryPrice.toStringAsFixed(2)}\n'
            '⚡ 레버리지: ${leverage}x';

      case PositionChangeType.closedPosition:
        final side = oldData['side'] as String;
        final size = oldData['size'] as double;
        final pnl = oldData['unrealized_pnl'] as double;
        final pnlEmoji = pnl >= 0 ? '📈' : '📉';
        return '🐋 $traderName님이 포지션 청산\n'
            '📊 $coin $side\n'
            '💰 크기: ${size.toStringAsFixed(4)}\n'
            '$pnlEmoji PNL: \$${pnl.toStringAsFixed(2)}';

      case PositionChangeType.sizeIncreased:
        final oldSize = oldData['size'] as double;
        final newSize = newData['size'] as double;
        final diff = newSize - oldSize;
        final changePercent = ((diff / oldSize) * 100).toStringAsFixed(1);
        final side = newData['side'] as String;
        return '🐋 $traderName님이 포지션 추가\n'
            '📊 $coin $side\n'
            '📈 ${oldSize.toStringAsFixed(4)} → ${newSize.toStringAsFixed(4)}\n'
            '➕ +${diff.toStringAsFixed(4)} (+$changePercent%)';

      case PositionChangeType.sizeDecreased:
        final oldSize = oldData['size'] as double;
        final newSize = newData['size'] as double;
        final diff = oldSize - newSize;
        final changePercent = ((diff / oldSize) * 100).toStringAsFixed(1);
        final side = newData['side'] as String;
        return '🐋 $traderName님이 포지션 감소\n'
            '📊 $coin $side\n'
            '📉 ${oldSize.toStringAsFixed(4)} → ${newSize.toStringAsFixed(4)}\n'
            '➖ -${diff.toStringAsFixed(4)} (-$changePercent%)';

      case PositionChangeType.sideFlipped:
        final oldSide = oldData['side'] as String;
        final newSide = newData['side'] as String;
        final newSize = newData['size'] as double;
        final entryPrice = newData['entry_price'] as double;
        return '🐋 $traderName님이 방향 전환!\n'
            '📊 $coin: $oldSide → $newSide\n'
            '💰 새 크기: ${newSize.toStringAsFixed(4)}\n'
            '💵 새 진입가: \$${entryPrice.toStringAsFixed(2)}';
    }
  }

  /// 로그 메시지 생성
  String get logMessage {
    final traderName = trader.displayName;
    final timestamp = DateTime.now().toIso8601String();

    switch (type) {
      case PositionChangeType.newPosition:
        return '[$timestamp] NEW_POSITION: $traderName - $coin ${newData['side']} '
            '크기: ${newData['size']}, 진입가: \$${newData['entry_price']}';

      case PositionChangeType.closedPosition:
        return '[$timestamp] CLOSED_POSITION: $traderName - $coin ${oldData['side']} '
            '크기: ${oldData['size']}, PNL: \$${oldData['unrealized_pnl']}';

      case PositionChangeType.sizeIncreased:
        return '[$timestamp] SIZE_INCREASED: $traderName - $coin ${newData['side']} '
            '${oldData['size']} → ${newData['size']}';

      case PositionChangeType.sizeDecreased:
        return '[$timestamp] SIZE_DECREASED: $traderName - $coin ${newData['side']} '
            '${oldData['size']} → ${newData['size']}';

      case PositionChangeType.sideFlipped:
        return '[$timestamp] SIDE_FLIPPED: $traderName - $coin '
            '${oldData['side']} → ${newData['side']}';
    }
  }
}

/// 포지션 변화 감지기
class PositionChangeDetector {
  // 포지션 사이즈 변화 임계값 (10% = 0.1)
  static const double sizeChangeThreshold = 0.10;

  /// 포지션 변화 감지
  ///
  /// [trader]: 트레이더 정보
  /// [oldSnapshots]: 이전 포지션 스냅샷 (DB에서 조회한 Map 리스트)
  /// [newState]: 새로운 계정 상태 (API에서 조회)
  ///
  /// Returns: 감지된 변화 리스트
  List<PositionChange> detectChanges({
    required HyperliquidTrader trader,
    required List<Map<String, dynamic>> oldSnapshots,
    required HyperliquidAccountState newState,
  }) {
    final changes = <PositionChange>[];

    // 이전 포지션을 Map으로 변환 (coin → data)
    final oldPositionsMap = <String, Map<String, dynamic>>{};
    for (final snapshot in oldSnapshots) {
      oldPositionsMap[snapshot['coin'] as String] = snapshot;
    }

    // 새로운 포지션을 Map으로 변환 (coin → Position)
    final newPositionsMap = <String, Position>{};
    for (final assetPos in newState.assetPositions) {
      newPositionsMap[assetPos.position.coin] = assetPos.position;
    }

    // 1. 새 포지션 진입 & 사이즈 변화 & 방향 전환 감지
    for (final entry in newPositionsMap.entries) {
      final coin = entry.key;
      final newPos = entry.value;

      if (!oldPositionsMap.containsKey(coin)) {
        // 새 포지션 진입
        changes.add(PositionChange(
          type: PositionChangeType.newPosition,
          trader: trader,
          coin: coin,
          oldData: {},
          newData: _positionToMap(newPos),
        ));
      } else {
        // 기존 포지션 존재 - 변화 체크
        final oldPos = oldPositionsMap[coin]!;
        final newPosMap = _positionToMap(newPos);

        // 방향 전환 체크
        if (oldPos['side'] != newPosMap['side']) {
          changes.add(PositionChange(
            type: PositionChangeType.sideFlipped,
            trader: trader,
            coin: coin,
            oldData: oldPos,
            newData: newPosMap,
          ));
        } else {
          // 사이즈 변화 체크
          final oldSize = oldPos['size'] as double;
          final newSize = newPosMap['size'] as double;
          final sizeDiff = (newSize - oldSize).abs();
          final changePercent = sizeDiff / oldSize;

          if (changePercent >= sizeChangeThreshold) {
            if (newSize > oldSize) {
              // 사이즈 증가
              changes.add(PositionChange(
                type: PositionChangeType.sizeIncreased,
                trader: trader,
                coin: coin,
                oldData: oldPos,
                newData: newPosMap,
              ));
            } else {
              // 사이즈 감소
              changes.add(PositionChange(
                type: PositionChangeType.sizeDecreased,
                trader: trader,
                coin: coin,
                oldData: oldPos,
                newData: newPosMap,
              ));
            }
          }
        }
      }
    }

    // 2. 포지션 청산 감지
    for (final coin in oldPositionsMap.keys) {
      if (!newPositionsMap.containsKey(coin)) {
        // 포지션이 사라짐 = 청산
        changes.add(PositionChange(
          type: PositionChangeType.closedPosition,
          trader: trader,
          coin: coin,
          oldData: oldPositionsMap[coin]!,
          newData: {},
        ));
      }
    }

    return changes;
  }

  /// Position 객체를 Map으로 변환
  Map<String, dynamic> _positionToMap(Position pos) {
    return {
      'side': pos.sideText,
      'size': pos.sizeAbs,
      'entry_price': pos.entryPxAsDouble,
      'position_value': pos.positionValueAsDouble,
      'unrealized_pnl': pos.unrealizedPnlAsDouble,
      'leverage_value': pos.leverage.value,
      'leverage_type': pos.leverage.type,
    };
  }
}
