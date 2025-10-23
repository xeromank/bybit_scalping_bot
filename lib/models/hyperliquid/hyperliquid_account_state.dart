/// Hyperliquid 계정 상태
///
/// API 응답의 clearinghouseState 데이터
class HyperliquidAccountState {
  final MarginSummary marginSummary;
  final MarginSummary crossMarginSummary;
  final String crossMaintenanceMarginUsed;
  final String withdrawable;
  final List<AssetPosition> assetPositions;
  final DateTime timestamp;

  const HyperliquidAccountState({
    required this.marginSummary,
    required this.crossMarginSummary,
    required this.crossMaintenanceMarginUsed,
    required this.withdrawable,
    required this.assetPositions,
    required this.timestamp,
  });

  factory HyperliquidAccountState.fromJson(Map<String, dynamic> json) {
    return HyperliquidAccountState(
      marginSummary: MarginSummary.fromJson(json['marginSummary'] as Map<String, dynamic>),
      crossMarginSummary: MarginSummary.fromJson(json['crossMarginSummary'] as Map<String, dynamic>),
      crossMaintenanceMarginUsed: json['crossMaintenanceMarginUsed'] as String,
      withdrawable: json['withdrawable'] as String,
      assetPositions: (json['assetPositions'] as List<dynamic>)
          .map((e) => AssetPosition.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
    );
  }

  /// 총 미실현 손익
  double get totalUnrealizedPnl {
    return assetPositions.fold(0.0, (sum, pos) => sum + pos.position.unrealizedPnlAsDouble);
  }

  /// 총 ROE
  double get totalROE {
    if (assetPositions.isEmpty) return 0.0;
    final totalPnl = totalUnrealizedPnl;
    final accountValue = double.tryParse(marginSummary.accountValue) ?? 1.0;
    return (totalPnl / accountValue) * 100.0;
  }

  /// 사용 중인 마진 비율
  double get marginUsagePercent {
    final accountValue = double.tryParse(marginSummary.accountValue) ?? 1.0;
    final marginUsed = double.tryParse(marginSummary.totalMarginUsed) ?? 0.0;
    return (marginUsed / accountValue) * 100.0;
  }
}

/// 마진 요약
class MarginSummary {
  final String accountValue;
  final String totalNtlPos;
  final String totalRawUsd;
  final String totalMarginUsed;

  const MarginSummary({
    required this.accountValue,
    required this.totalNtlPos,
    required this.totalRawUsd,
    required this.totalMarginUsed,
  });

  factory MarginSummary.fromJson(Map<String, dynamic> json) {
    return MarginSummary(
      accountValue: json['accountValue'] as String,
      totalNtlPos: json['totalNtlPos'] as String,
      totalRawUsd: json['totalRawUsd'] as String,
      totalMarginUsed: json['totalMarginUsed'] as String,
    );
  }

  double get accountValueAsDouble => double.tryParse(accountValue) ?? 0.0;
  double get totalNtlPosAsDouble => double.tryParse(totalNtlPos) ?? 0.0;
  double get totalMarginUsedAsDouble => double.tryParse(totalMarginUsed) ?? 0.0;
}

/// 자산 포지션
class AssetPosition {
  final String type; // "oneWay"
  final Position position;

  const AssetPosition({
    required this.type,
    required this.position,
  });

  factory AssetPosition.fromJson(Map<String, dynamic> json) {
    return AssetPosition(
      type: json['type'] as String,
      position: Position.fromJson(json['position'] as Map<String, dynamic>),
    );
  }
}

/// 포지션 상세
class Position {
  final String coin;
  final String szi; // size (음수면 숏)
  final Leverage leverage;
  final String entryPx; // 진입가
  final String positionValue;
  final String unrealizedPnl;
  final String returnOnEquity;
  final String liquidationPx;
  final String marginUsed;
  final int maxLeverage;
  final CumFunding cumFunding;

  const Position({
    required this.coin,
    required this.szi,
    required this.leverage,
    required this.entryPx,
    required this.positionValue,
    required this.unrealizedPnl,
    required this.returnOnEquity,
    required this.liquidationPx,
    required this.marginUsed,
    required this.maxLeverage,
    required this.cumFunding,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      coin: json['coin'] as String,
      szi: json['szi'] as String,
      leverage: Leverage.fromJson(json['leverage'] as Map<String, dynamic>),
      entryPx: json['entryPx'] as String,
      positionValue: json['positionValue'] as String,
      unrealizedPnl: json['unrealizedPnl'] as String,
      returnOnEquity: json['returnOnEquity'] as String,
      liquidationPx: json['liquidationPx'] as String,
      marginUsed: json['marginUsed'] as String,
      maxLeverage: json['maxLeverage'] as int,
      cumFunding: CumFunding.fromJson(json['cumFunding'] as Map<String, dynamic>),
    );
  }

  /// 롱/숏 판별
  bool get isLong => double.tryParse(szi) != null && double.parse(szi) > 0;
  bool get isShort => double.tryParse(szi) != null && double.parse(szi) < 0;

  String get sideText => isLong ? 'Long' : 'Short';

  /// 포지션 크기 (절대값)
  double get sizeAbs => (double.tryParse(szi) ?? 0.0).abs();

  /// 숫자 변환
  double get entryPxAsDouble => double.tryParse(entryPx) ?? 0.0;
  double get positionValueAsDouble => double.tryParse(positionValue) ?? 0.0;
  double get unrealizedPnlAsDouble => double.tryParse(unrealizedPnl) ?? 0.0;
  double get returnOnEquityAsDouble => double.tryParse(returnOnEquity) ?? 0.0;
  double get liquidationPxAsDouble => double.tryParse(liquidationPx) ?? 0.0;
  double get marginUsedAsDouble => double.tryParse(marginUsed) ?? 0.0;

  /// ROE 퍼센트
  double get roePercent => returnOnEquityAsDouble * 100.0;

  /// 청산까지 여유 (%)
  double get liquidationBuffer {
    final currentPx = entryPxAsDouble;
    final liqPx = liquidationPxAsDouble;
    if (currentPx == 0) return 0.0;

    if (isLong) {
      // 롱: 현재가가 청산가보다 높아야 안전
      return ((currentPx - liqPx) / currentPx) * 100.0;
    } else {
      // 숏: 현재가가 청산가보다 낮아야 안전
      return ((liqPx - currentPx) / currentPx) * 100.0;
    }
  }
}

/// 레버리지
class Leverage {
  final String type; // "cross" or "isolated"
  final int value;

  const Leverage({
    required this.type,
    required this.value,
  });

  factory Leverage.fromJson(Map<String, dynamic> json) {
    return Leverage(
      type: json['type'] as String,
      value: json['value'] as int,
    );
  }
}

/// 누적 펀딩
class CumFunding {
  final String allTime;
  final String sinceOpen;
  final String sinceChange;

  const CumFunding({
    required this.allTime,
    required this.sinceOpen,
    required this.sinceChange,
  });

  factory CumFunding.fromJson(Map<String, dynamic> json) {
    return CumFunding(
      allTime: json['allTime'] as String,
      sinceOpen: json['sinceOpen'] as String,
      sinceChange: json['sinceChange'] as String,
    );
  }

  double get allTimeAsDouble => double.tryParse(allTime) ?? 0.0;
  double get sinceOpenAsDouble => double.tryParse(sinceOpen) ?? 0.0;
}
