import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Database service for storing trading logs and order history
///
/// Provides persistent storage for:
/// - Trade logs (max 100 displayed, all stored)
/// - Order history with technical indicators
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'trading.db');

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
        symbol TEXT NOT NULL
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
        bollinger_lower REAL
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_trade_logs_timestamp ON trade_logs(timestamp DESC)');
    await db.execute('CREATE INDEX idx_order_history_timestamp ON order_history(timestamp DESC)');
  }

  /// Inserts a trade log entry
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

  /// Gets recent trade logs (default: 100)
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

  /// Gets order history (default: 100)
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

  /// Deletes old trade logs (keeps last N entries)
  Future<int> cleanupOldTradeLogs({int keep = 1000}) async {
    final db = await database;
    // Get the timestamp of the Nth newest log
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
    // Get the timestamp of the Nth newest order
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

  /// Deletes all trade logs
  Future<int> deleteAllTradeLogs() async {
    final db = await database;
    return await db.delete('trade_logs');
  }

  /// Deletes all order history
  Future<int> deleteAllOrderHistory() async {
    final db = await database;
    return await db.delete('order_history');
  }

  /// Deletes all data (trade logs and order history)
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('trade_logs');
      await txn.delete('order_history');
    });
  }

  /// Closes the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
