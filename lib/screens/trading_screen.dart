import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';
import 'package:bybit_scalping_bot/services/scalping_bot_service.dart';
import 'package:bybit_scalping_bot/services/secure_storage_service.dart';
import 'package:bybit_scalping_bot/screens/login_screen.dart';

class TradingScreen extends StatefulWidget {
  final String apiKey;
  final String apiSecret;

  const TradingScreen({
    super.key,
    required this.apiKey,
    required this.apiSecret,
  });

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  late BybitApiClient _apiClient;
  ScalpingBotService? _botService;

  final _symbolController = TextEditingController(text: 'BTCUSDT');
  final _amountController = TextEditingController(text: '10');
  final _profitController = TextEditingController(text: '0.5');
  final _stopLossController = TextEditingController(text: '0.3');

  final List<Map<String, dynamic>> _logs = [];
  bool _isRunning = false;
  String? _balance;

  @override
  void initState() {
    super.initState();
    _apiClient = BybitApiClient(
      apiKey: widget.apiKey,
      apiSecret: widget.apiSecret,
    );
    _loadBalance();
  }

  @override
  void dispose() {
    _botService?.dispose();
    _symbolController.dispose();
    _amountController.dispose();
    _profitController.dispose();
    _stopLossController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final result = await _apiClient.getWalletBalance(accountType: 'UNIFIED');
      if (result['retCode'] == 0) {
        final coin = result['result']['list'][0]['coin']
            .firstWhere((c) => c['coin'] == 'USDT', orElse: () => null);

        if (coin != null && mounted) {
          setState(() {
            _balance = coin['walletBalance'];
          });
        }
      }
    } catch (e) {
      _addLog('잔고 조회 실패: $e', isError: true);
    }
  }

  void _addLog(String message, {bool isError = false}) {
    if (mounted) {
      setState(() {
        _logs.insert(0, {
          'timestamp': DateTime.now(),
          'message': message,
          'isError': isError,
        });

        // 최대 100개 로그만 유지
        if (_logs.length > 100) {
          _logs.removeLast();
        }
      });
    }
  }

  Future<void> _startBot() async {
    if (_isRunning) return;

    final symbol = _symbolController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    final profit = double.tryParse(_profitController.text.trim());
    final stopLoss = double.tryParse(_stopLossController.text.trim());

    if (symbol.isEmpty || amount == null || profit == null || stopLoss == null) {
      _showError('모든 필드를 올바르게 입력해주세요');
      return;
    }

    try {
      _botService = ScalpingBotService(
        apiClient: _apiClient,
        symbol: symbol,
        leverage: '5',
        orderAmount: amount,
        profitTargetPercent: profit,
        stopLossPercent: stopLoss,
      );

      // 봇 상태 스트림 구독
      _botService!.statusStream.listen((status) {
        _addLog(status['message']);
      });

      await _botService!.start();

      setState(() {
        _isRunning = true;
      });

      _addLog('스캘핑 봇 시작 ($symbol, 레버리지 5배)');
    } catch (e) {
      _addLog('봇 시작 실패: $e', isError: true);
    }
  }

  Future<void> _stopBot() async {
    if (!_isRunning || _botService == null) return;

    try {
      await _botService!.stop();
      setState(() {
        _isRunning = false;
      });
      _addLog('스캘핑 봇 중지');
    } catch (e) {
      _addLog('봇 중지 실패: $e', isError: true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_isRunning) {
        await _stopBot();
      }

      final storage = SecureStorageService();
      await storage.deleteCredentials();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bybit Scalping Bot'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBalance,
            tooltip: '잔고 새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Column(
        children: [
          // 잔고 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Column(
              children: [
                const Text(
                  'USDT 잔고',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _balance != null
                      ? '\$${double.parse(_balance!).toStringAsFixed(2)}'
                      : '로딩 중...',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // 설정 패널
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _symbolController,
                        decoration: const InputDecoration(
                          labelText: '심볼',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        enabled: !_isRunning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: '수량',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isRunning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _profitController,
                        decoration: const InputDecoration(
                          labelText: '익절 (%)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isRunning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _stopLossController,
                        decoration: const InputDecoration(
                          labelText: '손절 (%)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isRunning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isRunning ? _stopBot : _startBot,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: _isRunning ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _isRunning ? '봇 중지' : '봇 시작',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
          // 로그 섹션
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '거래 로그',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        '로그가 없습니다',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final timestamp = log['timestamp'] as DateTime;
                        final message = log['message'] as String;
                        final isError = log['isError'] as bool;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${timestamp.hour.toString().padLeft(2, '0')}:'
                                '${timestamp.minute.toString().padLeft(2, '0')}:'
                                '${timestamp.second.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isError ? Colors.red : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
