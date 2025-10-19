import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/interfaces/trading_database_service.dart';

/// Coinone-specific database service
///
/// Manages coinone_trading.db for all Coinone spot trading data
class CoinoneDatabaseService implements TradingDatabaseService {
  static final CoinoneDatabaseService _instance = CoinoneDatabaseService._internal();
  static Database? _database;

  factory CoinoneDatabaseService() => _instance;

  CoinoneDatabaseService._internal();

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'coinone_trading.db');

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

    // Order history table (Coinone-specific fields)
    await db.execute('''
      CREATE TABLE order_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        side TEXT NOT NULL,
        price REAL NOT NULL,
        quantity REAL NOT NULL,
        user_order_id TEXT NOT NULL,
        order_id TEXT,
        status TEXT NOT NULL,
        bollinger_upper REAL,
        bollinger_middle REAL,
        bollinger_lower REAL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Withdrawal addresses cache (Coinone-specific)
    await db.execute('''
      CREATE TABLE withdrawal_addresses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        coin TEXT NOT NULL,
        address TEXT NOT NULL,
        label TEXT,
        last_used INTEGER NOT NULL,
        UNIQUE(coin, address)
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_trade_logs_timestamp ON trade_logs(timestamp DESC)');
    await db.execute('CREATE INDEX idx_order_history_timestamp ON order_history(timestamp DESC)');
    await db.execute('CREATE INDEX idx_trade_logs_synced ON trade_logs(synced)');
    await db.execute('CREATE INDEX idx_order_history_synced ON order_history(synced)');
    await db.execute('CREATE INDEX idx_withdrawal_last_used ON withdrawal_addresses(last_used DESC)');
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

  /// Inserts a Coinone order history entry
  Future<int> insertOrderHistory({
    required String symbol,
    required String side,
    required double price,
    required double quantity,
    required String userOrderId,
    String? orderId,
    required String status,
    double? bollingerUpper,
    double? bollingerMiddle,
    double? bollingerLower,
  }) async {
    final db = await database;
    return await db.insert('order_history', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'symbol': symbol,
      'side': side,
      'price': price,
      'quantity': quantity,
      'user_order_id': userOrderId,
      'order_id': orderId,
      'status': status,
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
  // Withdrawal Addresses (Coinone-specific)
  // ============================================================================

  /// Save or update a withdrawal address
  Future<int> saveWithdrawalAddress({
    required String coin,
    required String address,
    String? label,
  }) async {
    final db = await database;
    return await db.insert(
      'withdrawal_addresses',
      {
        'coin': coin,
        'address': address,
        'label': label,
        'last_used': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get recent withdrawal addresses for a coin
  Future<List<Map<String, dynamic>>> getWithdrawalAddresses({
    required String coin,
    int limit = 10,
  }) async {
    final db = await database;
    return await db.query(
      'withdrawal_addresses',
      where: 'coin = ?',
      whereArgs: [coin],
      orderBy: 'last_used DESC',
      limit: limit,
    );
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('trade_logs');
      await txn.delete('order_history');
      await txn.delete('withdrawal_addresses');
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
