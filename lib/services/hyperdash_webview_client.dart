import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:bybit_scalping_bot/models/hyperdash_trader.dart';

/// Hyperdash API Client using WebView to bypass Cloudflare
///
/// Uses an invisible WebView to load the API endpoint and extract data
/// after Cloudflare JavaScript challenge is completed
///
/// Implements 1-minute caching to reduce API calls
class HyperdashWebViewClient {
  static const String _baseUrl = 'https://hyperdash.info';
  static const String _apiKey = 'hyperdash_public_7vN3mK8pQ4wX2cL9hF5tR1bY6gS0jD';

  HeadlessInAppWebView? _headlessWebView;
  Completer<List<HyperdashTrader>>? _completer;
  Timer? _timeoutTimer;

  // Cache
  static List<HyperdashTrader>? _cachedTraders;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 1);

  /// Fetch top traders data using WebView
  ///
  /// Creates a headless WebView to bypass Cloudflare protection
  /// Timeout: 30 seconds
  /// Cache: 1 minute
  Future<List<HyperdashTrader>> fetchTopTraders() async {
    // Check cache first
    if (_cachedTraders != null && _cacheTime != null) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age < _cacheDuration) {
        print('✅ Using cached traders (${age.inSeconds}s old, ${_cachedTraders!.length} traders)');
        return _cachedTraders!;
      } else {
        print('🔄 Cache expired (${age.inSeconds}s old), fetching fresh data...');
      }
    }

    // Return early if already fetching
    if (_completer != null && !_completer!.isCompleted) {
      print('⚠️ Already fetching traders, waiting for result...');
      return _completer!.future;
    }

    _completer = Completer<List<HyperdashTrader>>();

    try {
      print('🌐 Starting WebView to fetch Hyperdash data...');

      // Set timeout
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_completer != null && !_completer!.isCompleted) {
          print('⏱️ WebView timeout after 30 seconds');
          _completer!.complete([]);
          _dispose();
        }
      });

      // Create headless WebView
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('$_baseUrl/api/hyperdash/top-traders-cached'),
          headers: {
            'accept': '*/*',
            'accept-language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
            'referer': '$_baseUrl/top-traders',
            'x-api-key': _apiKey,
          },
        ),
        onWebViewCreated: (controller) {
          print('📱 WebView created');
        },
        onLoadStart: (controller, url) {
          print('🔄 Loading URL: $url');
        },
        onLoadStop: (controller, url) async {
          print('✅ Page loaded: $url');

          try {
            // Wait a bit for any dynamic content
            await Future.delayed(const Duration(seconds: 2));

            // Get page content
            final html = await controller.getHtml();

            if (html == null || html.isEmpty) {
              print('❌ Empty HTML content');
              _completer?.complete([]);
              _dispose();
              return;
            }

            // Check if it's a Cloudflare challenge page
            if (html.contains('Just a moment') ||
                html.contains('Checking your browser')) {
              print('🛡️ Cloudflare challenge detected, waiting...');
              // Wait for challenge to complete
              await Future.delayed(const Duration(seconds: 5));

              // Try to get content again
              final html2 = await controller.getHtml();
              if (html2 == null ||
                  html2.contains('Just a moment') ||
                  html2.contains('Checking your browser')) {
                print('❌ Cloudflare challenge failed');
                _completer?.complete([]);
                _dispose();
                return;
              }

              _parseAndComplete(html2);
            } else {
              _parseAndComplete(html);
            }
          } catch (e) {
            print('❌ Error processing page: $e');
            _completer?.complete([]);
            _dispose();
          }
        },
        onReceivedError: (controller, request, error) {
          print('❌ Load error: ${error.description} (code: ${error.type})');
          _completer?.complete([]);
          _dispose();
        },
        onConsoleMessage: (controller, consoleMessage) {
          print('🖥️ Console: ${consoleMessage.message}');
        },
      );

      await _headlessWebView!.run();

      return await _completer!.future;
    } catch (e) {
      print('❌ WebView exception: $e');
      _completer?.complete([]);
      _dispose();
      return [];
    }
  }

  /// Parse HTML content and extract JSON data
  void _parseAndComplete(String html) {
    try {
      // The API returns raw JSON, check if page contains JSON array
      String? jsonContent;

      // Try to extract JSON from HTML
      // Case 1: Raw JSON response (best case)
      if (html.trim().startsWith('[') && html.trim().endsWith(']')) {
        jsonContent = html.trim();
      }
      // Case 2: JSON inside <pre> tag (with or without attributes)
      else if (html.contains('<pre')) {
        // Find the start of <pre> tag (may have attributes)
        final preTagStart = html.indexOf('<pre');
        if (preTagStart != -1) {
          // Find the end of the opening tag
          final preContentStart = html.indexOf('>', preTagStart);
          final preEnd = html.indexOf('</pre>', preContentStart);
          if (preContentStart != -1 && preEnd != -1) {
            jsonContent = html.substring(preContentStart + 1, preEnd).trim();
          }
        }
      }
      // Case 3: JSON inside <body> tag
      else if (html.contains('<body>')) {
        final bodyStart = html.indexOf('<body>');
        final bodyEnd = html.indexOf('</body>', bodyStart);
        if (bodyStart != -1 && bodyEnd != -1) {
          final bodyContent = html.substring(bodyStart + 6, bodyEnd).trim();
          if (bodyContent.startsWith('[') && bodyContent.endsWith(']')) {
            jsonContent = bodyContent;
          }
        }
      }

      if (jsonContent == null || jsonContent.isEmpty) {
        print('❌ Could not extract JSON from HTML');
        print('HTML preview: ${html.substring(0, html.length > 500 ? 500 : html.length)}');
        _completer?.complete([]);
        _dispose();
        return;
      }

      // Verify JSON content starts with [
      if (!jsonContent.trim().startsWith('[')) {
        print('❌ Extracted content is not JSON array');
        print('Content preview: ${jsonContent.substring(0, jsonContent.length > 200 ? 200 : jsonContent.length)}');
        _completer?.complete([]);
        _dispose();
        return;
      }

      // Parse JSON
      final data = json.decode(jsonContent);

      if (data is List) {
        print('✅ Successfully parsed ${data.length} traders');

        final traders = data
            .map((json) => HyperdashTrader.fromJson(json))
            .toList();

        // Cache the result
        _cachedTraders = traders;
        _cacheTime = DateTime.now();
        print('💾 Cached ${traders.length} traders');

        _completer?.complete(traders);
      } else {
        print('❌ Expected List but got ${data.runtimeType}');
        _completer?.complete([]);
      }
    } catch (e) {
      print('❌ JSON parsing error: $e');
      _completer?.complete([]);
    } finally {
      _dispose();
    }
  }

  /// Dispose resources
  void _dispose() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    _headlessWebView?.dispose();
    _headlessWebView = null;
  }

  /// Cleanup method to be called when no longer needed
  void dispose() {
    _dispose();
    _completer = null;
  }
}
