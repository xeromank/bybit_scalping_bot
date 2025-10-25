import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Hyperliquid Database Service
///
/// Manages hyperliquid_tracking.db for whale position tracking
class HyperliquidDatabaseService {
  static final HyperliquidDatabaseService _instance =
      HyperliquidDatabaseService._internal();
  static Database? _database;

  factory HyperliquidDatabaseService() => _instance;

  HyperliquidDatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'hyperliquid_tracking.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Position snapshots table
    await db.execute('''
      CREATE TABLE position_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trader_address TEXT NOT NULL,
        coin TEXT NOT NULL,
        side TEXT NOT NULL,
        size REAL NOT NULL,
        entry_price REAL NOT NULL,
        position_value REAL NOT NULL,
        unrealized_pnl REAL NOT NULL,
        leverage_value INTEGER NOT NULL,
        leverage_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Position change logs table (for history)
    await db.execute('''
      CREATE TABLE position_change_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trader_address TEXT NOT NULL,
        change_type TEXT NOT NULL,
        coin TEXT NOT NULL,
        details TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Create indexes for faster queries
    await db.execute(
        'CREATE INDEX idx_snapshots_trader_coin ON position_snapshots(trader_address, coin)');
    await db.execute(
        'CREATE INDEX idx_snapshots_timestamp ON position_snapshots(timestamp DESC)');
    await db.execute(
        'CREATE INDEX idx_change_logs_timestamp ON position_change_logs(timestamp DESC)');
    await db.execute(
        'CREATE INDEX idx_change_logs_trader ON position_change_logs(trader_address)');
  }

  // ============================================================================
  // Position Snapshots
  // ============================================================================

  /// 포지션 스냅샷 저장
  Future<int> insertPositionSnapshot({
    required String traderAddress,
    required String coin,
    required String side,
    required double size,
    required double entryPrice,
    required double positionValue,
    required double unrealizedPnl,
    required int leverageValue,
    required String leverageType,
    required int timestamp,
  }) async {
    final db = await database;
    return await db.insert('position_snapshots', {
      'trader_address': traderAddress,
      'coin': coin,
      'side': side,
      'size': size,
      'entry_price': entryPrice,
      'position_value': positionValue,
      'unrealized_pnl': unrealizedPnl,
      'leverage_value': leverageValue,
      'leverage_type': leverageType,
      'timestamp': timestamp,
    });
  }

  /// 특정 트레이더의 최신 포지션 스냅샷 조회
  Future<List<Map<String, dynamic>>> getLatestPositionSnapshots(
    String traderAddress,
  ) async {
    final db = await database;

    // 가장 최근 타임스탬프 가져오기
    final latestTimestamp = await db.rawQuery('''
      SELECT MAX(timestamp) as max_timestamp
      FROM position_snapshots
      WHERE trader_address = ?
    ''', [traderAddress]);

    final maxTimestamp = latestTimestamp.first['max_timestamp'];
    if (maxTimestamp == null) return [];

    // 해당 타임스탬프의 모든 포지션 가져오기
    return await db.query(
      'position_snapshots',
      where: 'trader_address = ? AND timestamp = ?',
      whereArgs: [traderAddress, maxTimestamp],
    );
  }

  /// 모든 트레이더의 최신 포지션 스냅샷 조회
  Future<Map<String, List<Map<String, dynamic>>>> getAllLatestSnapshots(
    List<String> traderAddresses,
  ) async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final address in traderAddresses) {
      result[address] = await getLatestPositionSnapshots(address);
    }

    return result;
  }

  /// 특정 트레이더의 이전 포지션 스냅샷 삭제 (최신 것만 유지)
  Future<int> cleanupOldSnapshots(String traderAddress, {int keepCount = 5}) async {
    final db = await database;

    // 최신 N개의 타임스탬프 조회
    final latestTimestamps = await db.rawQuery('''
      SELECT DISTINCT timestamp
      FROM position_snapshots
      WHERE trader_address = ?
      ORDER BY timestamp DESC
      LIMIT ?
    ''', [traderAddress, keepCount]);

    if (latestTimestamps.length < keepCount) return 0;

    final cutoffTimestamp = latestTimestamps.last['timestamp'];
    return await db.delete(
      'position_snapshots',
      where: 'trader_address = ? AND timestamp < ?',
      whereArgs: [traderAddress, cutoffTimestamp],
    );
  }

  // ============================================================================
  // Position Change Logs
  // ============================================================================

  /// 포지션 변화 로그 저장
  Future<int> insertPositionChangeLog({
    required String traderAddress,
    required String changeType,
    required String coin,
    required String details,
  }) async {
    final db = await database;
    return await db.insert('position_change_logs', {
      'trader_address': traderAddress,
      'change_type': changeType,
      'coin': coin,
      'details': details,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 포지션 변화 로그 조회
  Future<List<Map<String, dynamic>>> getPositionChangeLogs({
    String? traderAddress,
    int limit = 100,
  }) async {
    final db = await database;

    if (traderAddress != null) {
      return await db.query(
        'position_change_logs',
        where: 'trader_address = ?',
        whereArgs: [traderAddress],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      return await db.query(
        'position_change_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
  }

  /// 오래된 변화 로그 삭제
  Future<int> cleanupOldChangeLogs({int keep = 1000}) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'position_change_logs',
      columns: ['timestamp'],
      orderBy: 'timestamp DESC',
      limit: 1,
      offset: keep,
    );

    if (result.isEmpty) return 0;

    final int cutoffTimestamp = result.first['timestamp'] as int;
    return await db.delete(
      'position_change_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  // ============================================================================
  // Cleanup & Utilities
  // ============================================================================

  /// 모든 데이터 삭제
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('position_snapshots');
      await txn.delete('position_change_logs');
    });
    Logger.warning('Hyperliquid 데이터베이스 전체 삭제 완료');
  }

  /// 데이터베이스 닫기
  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  /// 통계 조회
  Future<Map<String, int>> getStats() async {
    final db = await database;

    final snapshotsTotal = await db.rawQuery(
        'SELECT COUNT(*) as count FROM position_snapshots');
    final changeLogsTotal = await db.rawQuery(
        'SELECT COUNT(*) as count FROM position_change_logs');

    return {
      'snapshotsTotal': Sqflite.firstIntValue(snapshotsTotal) ?? 0,
      'changeLogsTotal': Sqflite.firstIntValue(changeLogsTotal) ?? 0,
    };
  }
}
