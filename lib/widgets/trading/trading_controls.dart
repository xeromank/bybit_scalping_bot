import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/widgets/common/loading_button.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Widget for trading bot controls
///
/// Responsibility: Provide UI controls for trading bot configuration
///
/// This widget provides input fields for trading parameters and
/// start/stop buttons for the bot.
class TradingControls extends StatefulWidget {
  const TradingControls({super.key});

  @override
  State<TradingControls> createState() => _TradingControlsState();
}

class _TradingControlsState extends State<TradingControls> {
  late TextEditingController _symbolController;
  late TextEditingController _amountController;
  late TextEditingController _profitController;
  late TextEditingController _stopLossController;
  late TextEditingController _rsi6LongController;
  late TextEditingController _rsi6ShortController;
  late TextEditingController _rsi14LongController;
  late TextEditingController _rsi14ShortController;

  // Cache last technical analysis to prevent flickering
  TechnicalAnalysis? _lastTechnicalAnalysis;
  double? _lastPrice;

  @override
  void initState() {
    super.initState();
    final provider = context.read<TradingProvider>();
    _symbolController = TextEditingController(text: provider.symbol);
    _amountController =
        TextEditingController(text: provider.orderAmount.toString());
    _profitController =
        TextEditingController(text: provider.profitTargetPercent.toString());
    _stopLossController =
        TextEditingController(text: provider.stopLossPercent.toString());
    _rsi6LongController =
        TextEditingController(text: provider.rsi6LongThreshold.toString());
    _rsi6ShortController =
        TextEditingController(text: provider.rsi6ShortThreshold.toString());
    _rsi14LongController =
        TextEditingController(text: provider.rsi14LongThreshold.toString());
    _rsi14ShortController =
        TextEditingController(text: provider.rsi14ShortThreshold.toString());
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _amountController.dispose();
    _profitController.dispose();
    _stopLossController.dispose();
    _rsi6LongController.dispose();
    _rsi6ShortController.dispose();
    _rsi14LongController.dispose();
    _rsi14ShortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TradingProvider>(
      builder: (context, provider, child) {
        final isRunning = provider.isRunning;

        // Update cached technical analysis to prevent flickering
        if (provider.technicalAnalysis != null) {
          _lastTechnicalAnalysis = provider.technicalAnalysis;
        }

        // Update cached current price to prevent flickering
        if (provider.currentPrice != null) {
          _lastPrice = provider.currentPrice;
        }

        // Update text fields when provider values change (only for TP/SL when mode changes)
        if (_profitController.text != provider.profitTargetPercent.toString()) {
          _profitController.text = provider.profitTargetPercent.toString();
        }
        if (_stopLossController.text != provider.stopLossPercent.toString()) {
          _stopLossController.text = provider.stopLossPercent.toString();
        }

        return Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Trading Mode Selection
              DropdownButtonFormField<TradingMode>(
                value: provider.tradingMode,
                decoration: ThemeConstants.inputDecoration(
                  labelText: '전략 모드',
                  prefixIcon: Icons.trending_up,
                ),
                items: const [
                  DropdownMenuItem(
                    value: TradingMode.auto,
                    child: Text('자동 (AI 추천) ⭐'),
                  ),
                  DropdownMenuItem(
                    value: TradingMode.bollinger,
                    child: Text('볼린저 밴드 🎯'),
                  ),
                  DropdownMenuItem(
                    value: TradingMode.ema,
                    child: Text('EMA 추세추종 🚀'),
                  ),
                ],
                onChanged: isRunning
                    ? null
                    : (value) {
                        if (value != null) {
                          provider.setTradingMode(value);
                        }
                      },
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // Mode description
              Container(
                padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(ThemeConstants.borderRadiusSmall),
                  border: Border.all(
                    color: ThemeConstants.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  provider.tradingMode == TradingMode.auto
                      ? '시장 상황 분석하여 최적 전략 자동 선택 (EMA 정렬, BB 폭, 변동성 기반)'
                      : provider.tradingMode == TradingMode.bollinger
                          ? '횡보장/박스권 최적 | 승률 75% | 익절 0.5% | 손절 0.15%'
                          : '트렌드장 최적 | 승률 70% | 익절 0.7% | 손절 0.2%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ThemeConstants.textSecondaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // ===== FIXED SECTION: Current Price =====
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeConstants.spacingSmall,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ThemeConstants.borderRadiusSmall),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '현재가: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.textSecondaryColor,
                      ),
                    ),
                    Text(
                      _lastPrice != null
                          ? '\$${_lastPrice!.toStringAsFixed(2)}'
                          : '로딩 중...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // ===== FIXED SECTION: Technical Indicators =====
              Container(
                padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(ThemeConstants.borderRadiusSmall),
                  border: Border.all(
                    color: ThemeConstants.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '기술적 지표',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // First row: RSI indicators (always visible with height)
                    SizedBox(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            'RSI(6)',
                            _lastTechnicalAnalysis?.rsi6.toStringAsFixed(1) ?? '--',
                            _lastTechnicalAnalysis != null
                                ? _getRSIColor(_lastTechnicalAnalysis!.rsi6)
                                : ThemeConstants.textSecondaryColor,
                          ),
                          _buildIndicator(
                            'RSI(14)',
                            _lastTechnicalAnalysis?.rsi12.toStringAsFixed(1) ?? '--',
                            _lastTechnicalAnalysis != null
                                ? _getRSIColor(_lastTechnicalAnalysis!.rsi12)
                                : ThemeConstants.textSecondaryColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Second row: Volume MA indicators (always visible with height)
                    SizedBox(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            'Vol MA5',
                            _lastTechnicalAnalysis != null
                                ? '${(_lastTechnicalAnalysis!.volumeMA5 / 1000).toStringAsFixed(1)}k'
                                : '--',
                            ThemeConstants.textPrimaryColor,
                          ),
                          _buildIndicator(
                            'Vol MA10',
                            _lastTechnicalAnalysis != null
                                ? '${(_lastTechnicalAnalysis!.volumeMA10 / 1000).toStringAsFixed(1)}k'
                                : '--',
                            ThemeConstants.textPrimaryColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Third row: EMA indicators (always visible with height)
                    SizedBox(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            'EMA(9)',
                            _lastTechnicalAnalysis != null
                                ? '\$${_lastTechnicalAnalysis!.ema9.toStringAsFixed(1)}'
                                : '--',
                            ThemeConstants.textPrimaryColor,
                          ),
                          _buildIndicator(
                            'EMA(21)',
                            _lastTechnicalAnalysis != null
                                ? '\$${_lastTechnicalAnalysis!.ema21.toStringAsFixed(1)}'
                                : '--',
                            ThemeConstants.textPrimaryColor,
                          ),
                        ],
                      ),
                    ),
                    // Fourth row: Bollinger Bands (only show in Bollinger mode)
                    if (_lastTechnicalAnalysis?.mode == TradingMode.bollinger &&
                        _lastTechnicalAnalysis?.bollingerBands != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 38,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildIndicator(
                              'BB Upper',
                              '\$${_lastTechnicalAnalysis!.bollingerBands!.upper.toStringAsFixed(1)}',
                              Colors.red.shade700,
                            ),
                            _buildIndicator(
                              'BB Lower',
                              '\$${_lastTechnicalAnalysis!.bollingerBands!.lower.toStringAsFixed(1)}',
                              Colors.green.shade700,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 38,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildIndicator(
                              'BB RSI(14)',
                              _lastTechnicalAnalysis!.bollingerRsi!.toStringAsFixed(1),
                              _getRSIColor(_lastTechnicalAnalysis!.bollingerRsi!),
                            ),
                            _buildIndicator(
                              'BB Middle',
                              '\$${_lastTechnicalAnalysis!.bollingerBands!.middle.toStringAsFixed(1)}',
                              ThemeConstants.textPrimaryColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Trading Status Section (after technical indicators)
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusBackgroundColor(provider.tradingStatus),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Status with WebSocket connection indicator
                          Row(
                            children: [
                              // WebSocket connection indicator
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: provider.isWebSocketConnected
                                      ? ThemeConstants.successColor
                                      : ThemeConstants.errorColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _getStatusIcon(provider.tradingStatus),
                                size: 16,
                                color: _getStatusColor(provider.tradingStatus),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getStatusText(provider.tradingStatus),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(provider.tradingStatus),
                                ),
                              ),
                            ],
                          ),
                          // Last data update time
                          if (provider.lastDataUpdate != null)
                            Text(
                              _formatUpdateTime(provider.lastDataUpdate!),
                              style: const TextStyle(
                                fontSize: 11,
                                color: ThemeConstants.textSecondaryColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // ===== COLLAPSIBLE SECTION: Symbol Selection =====
              ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.currency_bitcoin, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '심볼 선택',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      provider.symbol,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                initiallyExpanded: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: DropdownButtonFormField<String>(
                      value: provider.symbol,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '심볼',
                        prefixIcon: Icons.currency_bitcoin,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'BTCUSDT', child: Text('BTC/USDT')),
                        DropdownMenuItem(value: 'ETHUSDT', child: Text('ETH/USDT')),
                        DropdownMenuItem(value: 'SOLUSDT', child: Text('SOL/USDT')),
                        DropdownMenuItem(value: 'BNBUSDT', child: Text('BNB/USDT')),
                        DropdownMenuItem(value: 'XRPUSDT', child: Text('XRP/USDT')),
                        DropdownMenuItem(value: 'DOGEUSDT', child: Text('DOGE/USDT')),
                        DropdownMenuItem(value: 'ADAUSDT', child: Text('ADA/USDT')),
                      ],
                      onChanged: isRunning
                          ? null
                          : (value) {
                              if (value != null) {
                                provider.setSymbol(value);
                              }
                            },
                    ),
                  ),
                ],
              ),

              // ===== COLLAPSIBLE SECTION: Amount & Leverage =====
              ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.attach_money, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '투입 자금 & 레버리지',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\$${provider.orderAmount.toStringAsFixed(0)} · ${provider.leverage}x',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                initiallyExpanded: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            decoration: ThemeConstants.inputDecoration(
                              labelText: '투입 자금 (USDT)',
                              prefixIcon: Icons.attach_money,
                            ),
                            keyboardType: TextInputType.number,
                            enabled: !isRunning,
                            onChanged: (value) {
                              final amount = double.tryParse(value);
                              if (amount != null) {
                                provider.setOrderAmount(amount);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: ThemeConstants.spacingSmall),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: provider.leverage,
                            decoration: ThemeConstants.inputDecoration(
                              labelText: '레버리지',
                              prefixIcon: Icons.trending_up,
                            ),
                            items: const [
                              DropdownMenuItem(value: '2', child: Text('2x')),
                              DropdownMenuItem(value: '3', child: Text('3x')),
                              DropdownMenuItem(value: '5', child: Text('5x')),
                              DropdownMenuItem(value: '10', child: Text('10x')),
                              DropdownMenuItem(value: '15', child: Text('15x')),
                              DropdownMenuItem(value: '20', child: Text('20x')),
                              DropdownMenuItem(value: '30', child: Text('30x')),
                              DropdownMenuItem(value: '50', child: Text('50x')),
                              DropdownMenuItem(value: '75', child: Text('75x')),
                              DropdownMenuItem(value: '100', child: Text('100x')),
                            ],
                            onChanged: isRunning
                                ? null
                                : (value) {
                                    if (value != null) {
                                      provider.setLeverage(value);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ===== COLLAPSIBLE SECTION: TP/SL Settings =====
              ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.monetization_on, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'TP/SL 설정',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TP ${provider.profitTargetPercent.toStringAsFixed(1)}% · SL ${provider.stopLossPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                initiallyExpanded: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _profitController,
                            decoration: ThemeConstants.inputDecoration(
                              labelText: '익절 ROE (%)',
                              prefixIcon: Icons.trending_up,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                            ],
                            enabled: !isRunning,
                            onChanged: (value) {
                              final profit = double.tryParse(value);
                              if (profit != null) {
                                provider.setProfitTargetPercent(profit);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: ThemeConstants.spacingSmall),
                        Expanded(
                          child: TextField(
                            controller: _stopLossController,
                            decoration: ThemeConstants.inputDecoration(
                              labelText: '손절 ROE (%)',
                              prefixIcon: Icons.trending_down,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                            ],
                            enabled: !isRunning,
                            onChanged: (value) {
                              final stopLoss = double.tryParse(value);
                              if (stopLoss != null) {
                                provider.setStopLossPercent(stopLoss);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ===== COLLAPSIBLE SECTION: Advanced Settings (RSI) =====
              ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.settings, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '고급 설정 (RSI)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                initiallyExpanded: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        // RSI(6) Thresholds
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _rsi6LongController,
                                decoration: ThemeConstants.inputDecoration(
                                  labelText: 'RSI(6) 롱',
                                  prefixIcon: Icons.arrow_upward,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                                ],
                                enabled: !isRunning,
                                onChanged: (value) {
                                  final threshold = double.tryParse(value);
                                  if (threshold != null) {
                                    provider.setRsi6LongThreshold(threshold);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: ThemeConstants.spacingSmall),
                            Expanded(
                              child: TextField(
                                controller: _rsi6ShortController,
                                decoration: ThemeConstants.inputDecoration(
                                  labelText: 'RSI(6) 숏',
                                  prefixIcon: Icons.arrow_downward,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                                ],
                                enabled: !isRunning,
                                onChanged: (value) {
                                  final threshold = double.tryParse(value);
                                  if (threshold != null) {
                                    provider.setRsi6ShortThreshold(threshold);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ThemeConstants.spacingSmall),

                        // RSI(14) Thresholds
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _rsi14LongController,
                                decoration: ThemeConstants.inputDecoration(
                                  labelText: 'RSI(14) 롱',
                                  prefixIcon: Icons.arrow_upward,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                                ],
                                enabled: !isRunning,
                                onChanged: (value) {
                                  final threshold = double.tryParse(value);
                                  if (threshold != null) {
                                    provider.setRsi14LongThreshold(threshold);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: ThemeConstants.spacingSmall),
                            Expanded(
                              child: TextField(
                                controller: _rsi14ShortController,
                                decoration: ThemeConstants.inputDecoration(
                                  labelText: 'RSI(14) 숏',
                                  prefixIcon: Icons.arrow_downward,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                                ],
                                enabled: !isRunning,
                                onChanged: (value) {
                                  final threshold = double.tryParse(value);
                                  if (threshold != null) {
                                    provider.setRsi14ShortThreshold(threshold);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: ThemeConstants.spacingMedium),

              // Start/Stop Button
              isRunning
                  ? DangerButton(
                      text: '봇 중지',
                      onPressed: () => _stopBot(provider),
                    )
                  : SuccessButton(
                      text: '봇 시작',
                      onPressed: () => _startBot(provider),
                    ),

              // Clear Data Button (only visible when bot is stopped)
              if (!isRunning) ...[
                const SizedBox(height: ThemeConstants.spacingSmall),
                OutlinedButton(
                  onPressed: () => _clearAllData(provider),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeConstants.warningColor,
                    side: const BorderSide(color: ThemeConstants.warningColor),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('데이터 초기화 (로그 & DB)'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: ThemeConstants.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getRSIColor(double rsi) {
    if (rsi < 30) {
      return Colors.green.shade700; // Oversold - potential buy
    } else if (rsi > 70) {
      return Colors.red.shade700; // Overbought - potential sell
    } else {
      return ThemeConstants.textPrimaryColor; // Neutral
    }
  }

  String _getStatusText(TradingStatus status) {
    switch (status) {
      case TradingStatus.noSignal:
        return 'No Signal';
      case TradingStatus.ready:
        return 'Ready';
      case TradingStatus.ordered:
        return 'Ordered';
    }
  }

  Color _getStatusColor(TradingStatus status) {
    switch (status) {
      case TradingStatus.noSignal:
        return ThemeConstants.textSecondaryColor;
      case TradingStatus.ready:
        return Colors.orange.shade700;
      case TradingStatus.ordered:
        return Colors.green.shade700;
    }
  }

  Color _getStatusBackgroundColor(TradingStatus status) {
    switch (status) {
      case TradingStatus.noSignal:
        return ThemeConstants.cardColor.withValues(alpha: 0.5);
      case TradingStatus.ready:
        return Colors.orange.shade50;
      case TradingStatus.ordered:
        return Colors.green.shade50;
    }
  }

  IconData _getStatusIcon(TradingStatus status) {
    switch (status) {
      case TradingStatus.noSignal:
        return Icons.remove_circle_outline;
      case TradingStatus.ready:
        return Icons.notifications_active;
      case TradingStatus.ordered:
        return Icons.check_circle;
    }
  }

  String _formatUpdateTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  Future<void> _startBot(TradingProvider provider) async {
    final result = await provider.startBot();

    if (!mounted) return;

    result.when(
      success: (data) {
        // Success handled by provider
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }

  Future<void> _stopBot(TradingProvider provider) async {
    final result = await provider.stopBot();

    if (!mounted) return;

    result.when(
      success: (data) {
        // Success handled by provider
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }

  Future<void> _clearAllData(TradingProvider provider) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 초기화'),
        content: const Text(
          '모든 거래 로그와 주문 히스토리가 삭제됩니다.\n정말 초기화하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: ThemeConstants.errorColor,
            ),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await provider.clearAllData();

    if (!mounted) return;

    result.when(
      success: (data) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('모든 데이터가 초기화되었습니다'),
            backgroundColor: ThemeConstants.successColor,
          ),
        );
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }
}
