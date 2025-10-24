import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Hyperliquid API 클라이언트
///
/// Responsibility: Hyperliquid API 통신
class HyperliquidApiClient {
  static const String _baseUrl = 'https://api.hyperliquid.xyz';

  final http.Client _client;

  HyperliquidApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// 트레이더의 계정 상태 조회
  ///
  /// [address]: 트레이더 주소 (0x...)
  Future<HyperliquidAccountState> getAccountState(String address) async {
    try {
      Logger.debug('Hyperliquid API: 계정 상태 조회 - $address');

      final response = await _client.post(
        Uri.parse('$_baseUrl/info'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': '*/*',
        },
        body: jsonEncode({
          'type': 'clearinghouseState',
          'user': address,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final state = HyperliquidAccountState.fromJson(data);

        Logger.success(
          'Hyperliquid API: 계정 조회 성공 - '
          '자산: \$${state.marginSummary.accountValue}, '
          '포지션: ${state.assetPositions.length}개',
        );

        return state;
      } else {
        Logger.error('Hyperliquid API 에러: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch account state: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Hyperliquid API 예외: $e');
      rethrow;
    }
  }

  /// 여러 트레이더의 계정 상태 일괄 조회
  ///
  /// [addresses]: 트레이더 주소 목록
  /// 각 조회 사이에 2초 딜레이 적용 (API 부하 방지)
  Future<Map<String, HyperliquidAccountState>> getMultipleAccountStates(
    List<String> addresses,
  ) async {
    final results = <String, HyperliquidAccountState>{};

    for (int i = 0; i < addresses.length; i++) {
      final address = addresses[i];
      try {
        final state = await getAccountState(address);
        results[address] = state;
        Logger.debug('트레이더 조회 완료');

        // 마지막 트레이더가 아니면 2초 대기
        if (i < addresses.length - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        Logger.error('트레이더 $address 조회 실패: $e');
        // 실패해도 계속 진행
      }
    }

    return results;
  }

  /// 연결 테스트
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/info'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 405; // POST only
    } catch (e) {
      Logger.error('Hyperliquid 연결 테스트 실패: $e');
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
