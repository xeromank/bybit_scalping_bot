import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/interfaces/trading_database_service.dart';

/// Bybit-specific database service
///
/// Manages bybit_trading.db for all Bybit futures trading data
class BybitDatabaseService implements TradingDatabaseService {
  static final BybitDatabaseService _instance = BybitDatabaseService._internal();
  static Database? _database;

  factory BybitDatabaseService() => _instance;

  BybitDatabaseService._internal();

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'bybit_trading.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Trade logs table
    await db.execute('''
      CREATE TABLE trade_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        message TEXT NOT NULL,
        symbol TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Order history table
    await db.execute('''
      CREATE TABLE order_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        side TEXT NOT NULL,
        entry_price REAL NOT NULL,
        quantity REAL NOT NULL,
        leverage INTEGER NOT NULL,
        tp_price REAL NOT NULL,
        sl_price REAL NOT NULL,
        signal_strength REAL NOT NULL,
        rsi6 REAL NOT NULL,
        rsi14 REAL NOT NULL,
        ema9 REAL NOT NULL,
        ema21 REAL NOT NULL,
        volume REAL NOT NULL,
        volume_ma5 REAL NOT NULL,
        bollinger_upper REAL,
        bollinger_middle REAL,
        bollinger_lower REAL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_trade_logs_timestamp ON trade_logs(timestamp DESC)');
    await db.execute('CREATE INDEX idx_order_history_timestamp ON order_history(timestamp DESC)');
    await db.execute('CREATE INDEX idx_trade_logs_synced ON trade_logs(synced)');
    await db.execute('CREATE INDEX idx_order_history_synced ON order_history(synced)');
  }

  // ============================================================================
  // Trade Logs
  // ============================================================================

  @override
  Future<int> insertTradeLog({
    required String type,
    required String message,
    required String symbol,
  }) async {
    final db = await database;
    return await db.insert('trade_logs', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'message': message,
      'symbol': symbol,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentTradeLogs({
    int limit = 100,
    String? symbol,
  }) async {
    final db = await database;
    if (symbol != null) {
      return await db.query(
        'trade_logs',
        where: 'symbol = ?',
        whereArgs: [symbol],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      return await db.query(
        'trade_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
  }

  @override
  Future<int> deleteAllTradeLogs() async {
    final db = await database;
    return await db.delete('trade_logs');
  }

  // ============================================================================
  // Order History
  // ============================================================================

  /// Inserts an order history entry
  Future<int> insertOrderHistory({
    required String symbol,
    required String side,
    required double entryPrice,
    required double quantity,
    required int leverage,
    required double tpPrice,
    required double slPrice,
    required double signalStrength,
    required double rsi6,
    required double rsi14,
    required double ema9,
    required double ema21,
    required double volume,
    required double volumeMa5,
    double? bollingerUpper,
    double? bollingerMiddle,
    double? bollingerLower,
  }) async {
    final db = await database;
    return await db.insert('order_history', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'symbol': symbol,
      'side': side,
      'entry_price': entryPrice,
      'quantity': quantity,
      'leverage': leverage,
      'tp_price': tpPrice,
      'sl_price': slPrice,
      'signal_strength': signalStrength,
      'rsi6': rsi6,
      'rsi14': rsi14,
      'ema9': ema9,
      'ema21': ema21,
      'volume': volume,
      'volume_ma5': volumeMa5,
      'bollinger_upper': bollingerUpper,
      'bollinger_middle': bollingerMiddle,
      'bollinger_lower': bollingerLower,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getOrderHistory({
    int limit = 100,
    String? symbol,
  }) async {
    final db = await database;
    if (symbol != null) {
      return await db.query(
        'order_history',
        where: 'symbol = ?',
        whereArgs: [symbol],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      return await db.query(
        'order_history',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
  }

  @override
  Future<int> deleteAllOrderHistory() async {
    final db = await database;
    return await db.delete('order_history');
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Deletes old trade logs (keeps last N entries)
  Future<int> cleanupOldTradeLogs({int keep = 1000}) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'trade_logs',
      columns: ['timestamp'],
      orderBy: 'timestamp DESC',
      limit: 1,
      offset: keep,
    );

    if (result.isEmpty) return 0;

    final int cutoffTimestamp = result.first['timestamp'] as int;
    return await db.delete(
      'trade_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  /// Deletes old order history (keeps last N entries)
  Future<int> cleanupOldOrderHistory({int keep = 1000}) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'order_history',
      columns: ['timestamp'],
      orderBy: 'timestamp DESC',
      limit: 1,
      offset: keep,
    );

    if (result.isEmpty) return 0;

    final int cutoffTimestamp = result.first['timestamp'] as int;
    return await db.delete(
      'order_history',
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('trade_logs');
      await txn.delete('order_history');
    });
  }

  @override
  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  // ============================================================================
  // Sync-related methods (for future MongoDB integration)
  // ============================================================================

  @override
  Future<List<Map<String, dynamic>>> getUnsyncedTradeLogs({int? limit}) async {
    final db = await database;
    return await db.query(
      'trade_logs',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getUnsyncedOrderHistory({int? limit}) async {
    final db = await database;
    return await db.query(
      'order_history',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  @override
  Future<int> markTradeLogsAsSynced(List<int> ids) async {
    final db = await database;
    return await db.update(
      'trade_logs',
      {'synced': 1},
      where: 'id IN (${ids.map((_) => '?').join(', ')})',
      whereArgs: ids,
    );
  }

  @override
  Future<int> markOrderHistoryAsSynced(List<int> ids) async {
    final db = await database;
    return await db.update(
      'order_history',
      {'synced': 1},
      where: 'id IN (${ids.map((_) => '?').join(', ')})',
      whereArgs: ids,
    );
  }

  /// Gets count of unsynced trade logs
  Future<int> getUnsyncedTradeLogsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM trade_logs WHERE synced = 0'
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Gets count of unsynced order history
  Future<int> getUnsyncedOrderHistoryCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM order_history WHERE synced = 0'
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;

    final tradeLogsTotal = await db.rawQuery('SELECT COUNT(*) as count FROM trade_logs');
    final tradeLogsSynced = await db.rawQuery('SELECT COUNT(*) as count FROM trade_logs WHERE synced = 1');
    final orderHistoryTotal = await db.rawQuery('SELECT COUNT(*) as count FROM order_history');
    final orderHistorySynced = await db.rawQuery('SELECT COUNT(*) as count FROM order_history WHERE synced = 1');

    return {
      'tradeLogsTotal': Sqflite.firstIntValue(tradeLogsTotal) ?? 0,
      'tradeLogsSynced': Sqflite.firstIntValue(tradeLogsSynced) ?? 0,
      'tradeLogsUnsynced': (Sqflite.firstIntValue(tradeLogsTotal) ?? 0) - (Sqflite.firstIntValue(tradeLogsSynced) ?? 0),
      'orderHistoryTotal': Sqflite.firstIntValue(orderHistoryTotal) ?? 0,
      'orderHistorySynced': Sqflite.firstIntValue(orderHistorySynced) ?? 0,
      'orderHistoryUnsynced': (Sqflite.firstIntValue(orderHistoryTotal) ?? 0) - (Sqflite.firstIntValue(orderHistorySynced) ?? 0),
    };
  }
}
