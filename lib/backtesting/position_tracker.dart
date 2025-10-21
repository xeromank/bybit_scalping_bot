import 'package:bybit_scalping_bot/backtesting/split_entry_strategy.dart';

/// Single position entry (for split entry strategy)
class PositionEntry {
  final double price;
  final double quantity;
  final DateTime entryTime;
  final int entryLevel; // 1, 2, 3
  final StrategyType strategyType; // trendFollowing, counterTrend

  PositionEntry({
    required this.price,
    required this.quantity,
    required this.entryTime,
    required this.entryLevel,
    required this.strategyType,
  });

  @override
  String toString() {
    return 'Entry[Lv$entryLevel @\$${price.toStringAsFixed(2)} x$quantity ${strategyType.name}]';
  }
}

/// Position side
enum PositionSide {
  long,
  short,
  none,
}

/// Tracks split entry positions for backtesting
class PositionTracker {
  final List<PositionEntry> entries = [];
  PositionSide currentSide = PositionSide.none;
  StrategyType? strategyType;
  DateTime? firstEntryTime;

  /// Average entry price (weighted)
  double get averagePrice {
    if (entries.isEmpty) return 0.0;

    double totalValue = 0.0;
    double totalQty = 0.0;

    for (final entry in entries) {
      totalValue += entry.price * entry.quantity;
      totalQty += entry.quantity;
    }

    return totalValue / totalQty;
  }

  /// Total position size
  double get totalSize => entries.fold(0.0, (sum, e) => sum + e.quantity);

  /// Number of entries
  int get entryCount => entries.length;

  /// Has any position
  bool get hasPosition => entries.isNotEmpty;

  /// Latest entry level
  int get latestEntryLevel => entries.isEmpty ? 0 : entries.last.entryLevel;

  /// Calculate unrealized PnL percentage
  double calculateUnrealizedPnlPercent(double currentPrice) {
    if (entries.isEmpty) return 0.0;

    final avgPrice = averagePrice;

    if (currentSide == PositionSide.long) {
      return (currentPrice - avgPrice) / avgPrice;
    } else if (currentSide == PositionSide.short) {
      return (avgPrice - currentPrice) / avgPrice;
    }

    return 0.0;
  }

  /// Add new entry
  void addEntry({
    required double price,
    required double quantity,
    required DateTime entryTime,
    required int entryLevel,
    required PositionSide side,
    required StrategyType strategy,
  }) {
    // First entry
    if (entries.isEmpty) {
      currentSide = side;
      strategyType = strategy;
      firstEntryTime = entryTime;
    } else {
      // Verify same side
      if (currentSide != side) {
        throw StateError('Cannot add entry with different side');
      }
    }

    entries.add(PositionEntry(
      price: price,
      quantity: quantity,
      entryTime: entryTime,
      entryLevel: entryLevel,
      strategyType: strategy,
    ));
  }

  /// Close partial position (returns closed quantity and profit)
  ({double closedQty, double profit}) closePartial({
    required double closePrice,
    required double closePercent, // 0.0 to 1.0
    required DateTime closeTime,
  }) {
    if (entries.isEmpty) {
      throw StateError('No position to close');
    }

    final closedQty = totalSize * closePercent;
    final avgPrice = averagePrice;

    double profit = 0.0;
    if (currentSide == PositionSide.long) {
      profit = (closePrice - avgPrice) * closedQty;
    } else if (currentSide == PositionSide.short) {
      profit = (avgPrice - closePrice) * closedQty;
    }

    // Remove entries proportionally (FIFO)
    double remainingToClose = closedQty;
    final entriesToRemove = <int>[];

    for (int i = 0; i < entries.length; i++) {
      if (remainingToClose <= 0) break;

      final entry = entries[i];
      if (entry.quantity <= remainingToClose) {
        // Close entire entry
        remainingToClose -= entry.quantity;
        entriesToRemove.add(i);
      } else {
        // Partial close of this entry
        entries[i] = PositionEntry(
          price: entry.price,
          quantity: entry.quantity - remainingToClose,
          entryTime: entry.entryTime,
          entryLevel: entry.entryLevel,
          strategyType: entry.strategyType,
        );
        remainingToClose = 0;
      }
    }

    // Remove closed entries (reverse order to maintain indices)
    for (int i = entriesToRemove.length - 1; i >= 0; i--) {
      entries.removeAt(entriesToRemove[i]);
    }

    // Reset state if all entries are closed
    if (entries.isEmpty) {
      currentSide = PositionSide.none;
      strategyType = null;
      firstEntryTime = null;
    }

    return (closedQty: closedQty, profit: profit);
  }

  /// Close all positions (returns total profit)
  double closeAll({
    required double closePrice,
    required DateTime closeTime,
  }) {
    if (entries.isEmpty) return 0.0;

    final result = closePartial(
      closePrice: closePrice,
      closePercent: 1.0,
      closeTime: closeTime,
    );

    // Reset state
    currentSide = PositionSide.none;
    strategyType = null;
    firstEntryTime = null;

    return result.profit;
  }

  /// Reset tracker
  void reset() {
    entries.clear();
    currentSide = PositionSide.none;
    strategyType = null;
    firstEntryTime = null;
  }

  @override
  String toString() {
    if (!hasPosition) return 'Position[NONE]';

    return 'Position[${currentSide.name.toUpperCase()} ${entries.length} entries, avg: \$${averagePrice.toStringAsFixed(2)}, total: $totalSize]';
  }
}
