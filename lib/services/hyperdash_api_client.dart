import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bybit_scalping_bot/models/hyperdash_trader.dart';

/// Hyperdash API Client
///
/// Fetches top traders data from hyperdash.info
class HyperdashApiClient {
  static const String _baseUrl = 'https://hyperdash.info';
  static const String _apiKey = 'hyperdash_public_7vN3mK8pQ4wX2cL9hF5tR1bY6gS0jD';

  /// Fetch top traders data (cached)
  ///
  /// Returns list of top 1000 traders sorted by performance
  ///
  /// Implements retry logic to handle Cloudflare intermittent blocking
  Future<List<HyperdashTrader>> fetchTopTraders({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('Hyperdash API attempt $attempt/$maxRetries...');

        final response = await http.get(
          Uri.parse('$_baseUrl/api/hyperdash/top-traders-cached'),
          headers: {
            'accept': '*/*',
            'accept-encoding': 'gzip, deflate, br',
            'accept-language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
            'cache-control': 'no-cache',
            'connection': 'keep-alive',
            'dnt': '1',
            'pragma': 'no-cache',
            'referer': '$_baseUrl/top-traders',
            'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120"',
            'sec-ch-ua-mobile': '?1',
            'sec-ch-ua-platform': '"iOS"',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-origin',
            'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
            'x-api-key': _apiKey,
          },
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('Request timeout after 15 seconds');
          },
        );

        print('Hyperdash API Status: ${response.statusCode}');

        // Check for Cloudflare challenge page
        if (response.body.contains('Just a moment') ||
            response.body.contains('Checking your browser')) {
          print('Cloudflare challenge detected on attempt $attempt');
          if (attempt < maxRetries) {
            // Wait before retry with exponential backoff
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
          print('❌ Cloudflare blocking all attempts');
          return [];
        }

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data is List) {
            print('✅ Hyperdash API Success! Received ${data.length} traders');

            final traders = data
                .map((json) => HyperdashTrader.fromJson(json))
                .toList();

            return traders;
          } else {
            print('Hyperdash API Error: Expected List but got ${data.runtimeType}');
            return [];
          }
        } else if (response.statusCode == 403 || response.statusCode == 503) {
          print('Cloudflare blocking (${response.statusCode}) on attempt $attempt');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
        } else {
          print('Hyperdash API Error: ${response.statusCode}');
          if (response.body.length > 200) {
            print('Response: ${response.body.substring(0, 200)}');
          }
          return [];
        }
      } catch (e) {
        print('Hyperdash API Exception (attempt $attempt): $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
        return [];
      }
    }

    print('❌ All $maxRetries attempts failed');
    return [];
  }

  /// Test the API connection
  static Future<void> test() async {
    print('=== Testing Hyperdash API ===');
    final client = HyperdashApiClient();
    final traders = await client.fetchTopTraders();

    if (traders.isNotEmpty) {
      print('✅ API working!');
      print('Total traders: ${traders.length}');
      print('\nTop 3 traders:');
      for (int i = 0; i < 3 && i < traders.length; i++) {
        print('${i + 1}. ${traders[i]}');
      }
    } else {
      print('❌ API failed - no traders received');
    }
  }
}
