import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Hyperliquid 트레이더 저장소
///
/// Responsibility: 트레이더 목록 저장/조회
class HyperliquidTraderRepository {
  static const String _key = 'hyperliquid_traders';

  final SharedPreferences _prefs;

  HyperliquidTraderRepository(this._prefs);

  /// 모든 트레이더 조회
  Future<List<HyperliquidTrader>> getAllTraders() async {
    try {
      final jsonString = _prefs.getString(_key);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      final traders = jsonList
          .map((json) => HyperliquidTrader.fromJson(json as Map<String, dynamic>))
          .toList();

      Logger.debug('트레이더 ${traders.length}명 로드');
      return traders;
    } catch (e) {
      Logger.error('트레이더 로드 실패: $e');
      return [];
    }
  }

  /// 트레이더 추가
  Future<bool> addTrader(HyperliquidTrader trader) async {
    try {
      final traders = await getAllTraders();

      // 중복 체크
      if (traders.any((t) => t.address == trader.address)) {
        Logger.warning('이미 추가된 트레이더: ${trader.address}');
        return false;
      }

      traders.add(trader);
      await _saveTraders(traders);

      Logger.success('트레이더 추가: ${trader.displayName}');
      return true;
    } catch (e) {
      Logger.error('트레이더 추가 실패: $e');
      return false;
    }
  }

  /// 트레이더 삭제
  Future<bool> removeTrader(String address) async {
    try {
      final traders = await getAllTraders();
      traders.removeWhere((t) => t.address == address);
      await _saveTraders(traders);

      Logger.success('트레이더 삭제: $address');
      return true;
    } catch (e) {
      Logger.error('트레이더 삭제 실패: $e');
      return false;
    }
  }

  /// 트레이더 업데이트 (닉네임 변경 등)
  Future<bool> updateTrader(HyperliquidTrader trader) async {
    try {
      final traders = await getAllTraders();
      final index = traders.indexWhere((t) => t.address == trader.address);

      if (index == -1) {
        Logger.warning('트레이더를 찾을 수 없음: ${trader.address}');
        return false;
      }

      traders[index] = trader;
      await _saveTraders(traders);

      Logger.success('트레이더 업데이트: ${trader.displayName}');
      return true;
    } catch (e) {
      Logger.error('트레이더 업데이트 실패: $e');
      return false;
    }
  }

  /// 특정 트레이더 조회
  Future<HyperliquidTrader?> getTrader(String address) async {
    final traders = await getAllTraders();
    try {
      return traders.firstWhere((t) => t.address == address);
    } catch (e) {
      return null;
    }
  }

  /// 트레이더 목록 저장
  Future<void> _saveTraders(List<HyperliquidTrader> traders) async {
    final jsonList = traders.map((t) => t.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs.setString(_key, jsonString);
  }

  /// 모든 트레이더 삭제
  Future<void> clearAll() async {
    await _prefs.remove(_key);
    Logger.warning('모든 트레이더 삭제됨');
  }
}
