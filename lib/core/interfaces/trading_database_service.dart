import 'package:sqflite/sqflite.dart';

/// Common interface for trading database services
///
/// Each exchange should have its own database file and implement this interface.
/// This ensures consistent API across different exchanges while maintaining
/// complete data isolation.
abstract class TradingDatabaseService {
  /// Get database instance
  Future<Database> get database;

  /// Close database connection
  Future<void> close();

  // ============================================================================
  // Trade Logs
  // ============================================================================

  /// Insert a trade log entry
  Future<int> insertTradeLog({
    required String type,
    required String message,
    required String symbol,
  });

  /// Get recent trade logs
  Future<List<Map<String, dynamic>>> getRecentTradeLogs({
    int limit = 100,
    String? symbol,
  });

  /// Delete all trade logs
  Future<int> deleteAllTradeLogs();

  // ============================================================================
  // Order History
  // ============================================================================

  /// Get order history
  Future<List<Map<String, dynamic>>> getOrderHistory({
    int limit = 100,
    String? symbol,
  });

  /// Delete all order history
  Future<int> deleteAllOrderHistory();

  // ============================================================================
  // Sync Operations (for MongoDB integration)
  // ============================================================================

  /// Get unsynced trade logs
  Future<List<Map<String, dynamic>>> getUnsyncedTradeLogs({int? limit});

  /// Get unsynced order history
  Future<List<Map<String, dynamic>>> getUnsyncedOrderHistory({int? limit});

  /// Mark trade logs as synced
  Future<int> markTradeLogsAsSynced(List<int> ids);

  /// Mark order history as synced
  Future<int> markOrderHistoryAsSynced(List<int> ids);

  /// Get sync statistics
  Future<Map<String, int>> getSyncStats();

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Delete all data
  Future<void> clearAllData();
}
