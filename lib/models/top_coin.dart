/// Top trading coin model
///
/// Represents a cryptocurrency in the top 10 by trading volume
class TopCoin {
  final String symbol; // e.g., "BTCUSDT"
  final String baseCoin; // e.g., "BTC"
  final double lastPrice;
  final double volume24h; // 24h trading volume in base currency
  final double turnover24h; // 24h trading volume in USDT
  final double priceChangePercent24h; // 24h price change percentage
  final double high24h;
  final double low24h;

  TopCoin({
    required this.symbol,
    required this.baseCoin,
    required this.lastPrice,
    required this.volume24h,
    required this.turnover24h,
    required this.priceChangePercent24h,
    required this.high24h,
    required this.low24h,
  });

  /// Create TopCoin from Bybit API response
  factory TopCoin.fromJson(Map<String, dynamic> json) {
    return TopCoin(
      symbol: json['symbol'] ?? '',
      baseCoin: _extractBaseCoin(json['symbol'] ?? ''),
      lastPrice: double.tryParse(json['lastPrice']?.toString() ?? '0') ?? 0.0,
      volume24h: double.tryParse(json['volume24h']?.toString() ?? '0') ?? 0.0,
      turnover24h: double.tryParse(json['turnover24h']?.toString() ?? '0') ?? 0.0,
      priceChangePercent24h: double.tryParse(json['price24hPcnt']?.toString() ?? '0') ?? 0.0,
      high24h: double.tryParse(json['highPrice24h']?.toString() ?? '0') ?? 0.0,
      low24h: double.tryParse(json['lowPrice24h']?.toString() ?? '0') ?? 0.0,
    );
  }

  /// Extract base coin from symbol (e.g., "BTCUSDT" -> "BTC")
  static String _extractBaseCoin(String symbol) {
    if (symbol.endsWith('USDT')) {
      return symbol.substring(0, symbol.length - 4);
    }
    return symbol;
  }

  /// Get display name (e.g., "BTC/USDT")
  String get displayName => '$baseCoin/USDT';

  /// Get price change emoji
  String get trendEmoji {
    if (priceChangePercent24h > 3.0) return '🔥'; // Hot
    if (priceChangePercent24h > 1.0) return '📈'; // Up
    if (priceChangePercent24h > -1.0) return '↔️'; // Sideways
    if (priceChangePercent24h > -3.0) return '📉'; // Down
    return '💥'; // Crash
  }

  /// Get formatted price
  String get formattedPrice {
    if (lastPrice >= 1000) {
      return '\$${lastPrice.toStringAsFixed(0)}';
    } else if (lastPrice >= 1) {
      return '\$${lastPrice.toStringAsFixed(2)}';
    } else {
      return '\$${lastPrice.toStringAsFixed(4)}';
    }
  }

  /// Get formatted 24h change
  String get formatted24hChange {
    final sign = priceChangePercent24h >= 0 ? '+' : '';
    return '$sign${(priceChangePercent24h * 100).toStringAsFixed(2)}%';
  }

  /// Alias for formatted24hChange (for UI compatibility)
  String get formattedChange24h => formatted24hChange;

  /// Get formatted turnover (in millions)
  String get formattedTurnover {
    if (turnover24h >= 1000000000) {
      // Billions
      return '\$${(turnover24h / 1000000000).toStringAsFixed(2)}B';
    } else if (turnover24h >= 1000000) {
      // Millions
      return '\$${(turnover24h / 1000000).toStringAsFixed(2)}M';
    } else {
      return '\$${(turnover24h / 1000).toStringAsFixed(2)}K';
    }
  }

  /// Alias for formattedTurnover (showing volume in UI)
  String get formattedVolume => formattedTurnover;

  @override
  String toString() {
    return 'TopCoin(symbol: $symbol, price: $formattedPrice, change: $formatted24hChange)';
  }
}
