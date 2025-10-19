import 'package:flutter_test/flutter_test.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_balance.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_order.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_ticker.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_orderbook.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_chart.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/models/exchange_credentials.dart';

void main() {
  group('ExchangeType Tests', () {
    test('ExchangeType enum values', () {
      expect(ExchangeType.bybit.displayName, 'Bybit');
      expect(ExchangeType.coinone.displayName, 'Coinone');
      expect(ExchangeType.bybit.identifier, 'bybit');
      expect(ExchangeType.coinone.identifier, 'coinone');
    });

    test('ExchangeType fromIdentifier', () {
      expect(ExchangeTypeExtension.fromIdentifier('bybit'), ExchangeType.bybit);
      expect(ExchangeTypeExtension.fromIdentifier('coinone'), ExchangeType.coinone);
      expect(ExchangeTypeExtension.fromIdentifier('BYBIT'), ExchangeType.bybit);
      expect(ExchangeTypeExtension.fromIdentifier('COINONE'), ExchangeType.coinone);
    });

    test('ExchangeType fromIdentifier throws on invalid', () {
      expect(
        () => ExchangeTypeExtension.fromIdentifier('invalid'),
        throwsArgumentError,
      );
    });
  });

  group('ExchangeCredentials Tests', () {
    test('Create and serialize ExchangeCredentials', () {
      final now = DateTime.now();
      final creds = ExchangeCredentials(
        exchangeType: ExchangeType.coinone,
        apiKey: 'test_api_key_12345678',
        apiSecret: 'test_secret',
        lastUsed: now,
        label: 'Test Account',
      );

      expect(creds.exchangeType, ExchangeType.coinone);
      expect(creds.apiKey, 'test_api_key_12345678');
      expect(creds.label, 'Test Account');
    });

    test('ExchangeCredentials masked API key', () {
      final creds = ExchangeCredentials(
        exchangeType: ExchangeType.coinone,
        apiKey: 'test_api_key_12345678',
        apiSecret: 'secret',
        lastUsed: DateTime.now(),
      );

      expect(creds.maskedApiKey, 'test_api...5678');
    });

    test('ExchangeCredentials JSON serialization', () {
      final now = DateTime.now();
      final creds = ExchangeCredentials(
        exchangeType: ExchangeType.coinone,
        apiKey: 'test_key',
        apiSecret: 'test_secret',
        lastUsed: now,
        label: 'My Account',
      );

      final json = creds.toJson();
      expect(json['exchangeType'], 'coinone');
      expect(json['apiKey'], 'test_key');
      expect(json['label'], 'My Account');

      final decoded = ExchangeCredentials.fromJson(json);
      expect(decoded.exchangeType, ExchangeType.coinone);
      expect(decoded.apiKey, 'test_key');
      expect(decoded.label, 'My Account');
    });
  });

  group('CoinoneBalance Tests', () {
    test('Create CoinoneBalance from JSON', () {
      final json = {
        'avail': '1000.5',
        'balance': '1200.0',
        'pending_withdrawal': '100.0',
        'pending_deposit': '50.0',
      };

      final balance = CoinoneBalance.fromJson('KRW', json);

      expect(balance.currency, 'KRW');
      expect(balance.available, 1000.5);
      expect(balance.balance, 1200.0);
      expect(balance.pendingWithdrawal, 100.0);
      expect(balance.pendingDeposit, 50.0);
      expect(balance.total, 1200.0);
    });

    test('CoinoneWalletBalance with multiple currencies', () {
      final json = {
        'krw': {
          'avail': '50000',
          'balance': '50000',
          'pending_withdrawal': '0',
          'pending_deposit': '0',
        },
        'xrp': {
          'avail': '100.5',
          'balance': '100.5',
          'pending_withdrawal': '0',
          'pending_deposit': '0',
        },
      };

      final wallet = CoinoneWalletBalance.fromJson(json);

      expect(wallet.balances.length, 2);
      expect(wallet.getAvailable('KRW'), 50000);
      expect(wallet.getAvailable('XRP'), 100.5);
      expect(wallet.krwBalance?.available, 50000);
    });
  });

  group('CoinoneOrder Tests', () {
    test('Create CoinoneOrder from JSON', () {
      final json = {
        'order_id': '12345',
        'user_order_id': 'user_123',
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'type': 'limit',
        'side': 'buy',
        'price': '650.5',
        'qty': '100',
        'filled_qty': '50',
        'remain_qty': '50',
        'status': 'partial_filled',
        'created_at': '2024-01-01T00:00:00Z',
      };

      final order = CoinoneOrder.fromJson(json);

      expect(order.orderId, '12345');
      expect(order.userOrderId, 'user_123');
      expect(order.symbol, 'XRP-KRW');
      expect(order.side, 'buy');
      expect(order.price, 650.5);
      expect(order.quantity, 100);
      expect(order.filledQuantity, 50);
      expect(order.isActive, true);
      expect(order.isFilled, false);
      expect(order.fillPercentage, 50);
    });

    test('PlaceOrderRequest JSON conversion', () {
      final request = PlaceOrderRequest(
        quoteCurrency: 'KRW',
        targetCurrency: 'XRP',
        type: 'limit',
        side: 'buy',
        quantity: 100,
        price: 650.0,
        userOrderId: 'test_order_123',
      );

      final json = request.toJson();
      expect(json['quote_currency'], 'KRW');
      expect(json['target_currency'], 'XRP');
      expect(json['type'], 'limit');
      expect(json['price'], '650.0');
      expect(json['user_order_id'], 'test_order_123');
    });
  });

  group('CoinoneTicker Tests', () {
    test('Create CoinoneTicker from JSON', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'last': '650.5',
        'high': '700.0',
        'low': '600.0',
        'first': '620.0',
        'volume': '1000000',
        'quote_volume': '650000000',
        'best_bid': '650.0',
        'best_ask': '651.0',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final ticker = CoinoneTicker.fromJson(json);

      expect(ticker.symbol, 'XRP-KRW');
      expect(ticker.last, 650.5);
      expect(ticker.high, 700.0);
      expect(ticker.low, 600.0);
      expect(ticker.change, 30.5); // 650.5 - 620.0
      expect(ticker.spread, 1.0); // 651.0 - 650.0
    });

    test('CoinoneTicker change percentage calculation', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'last': '660.0',
        'high': '700.0',
        'low': '600.0',
        'first': '600.0',
        'volume': '1000000',
        'quote_volume': '650000000',
        'best_bid': '659.0',
        'best_ask': '661.0',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final ticker = CoinoneTicker.fromJson(json);

      expect(ticker.changePercent, 10.0); // (660-600)/600 * 100 = 10%
    });
  });

  group('CoinoneOrderbook Tests', () {
    test('Create CoinoneOrderbook from JSON', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'bid': [
          ['650.0', '100'],
          ['649.5', '200'],
          ['649.0', '150'],
        ],
        'ask': [
          ['651.0', '100'],
          ['651.5', '200'],
          ['652.0', '150'],
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final orderbook = CoinoneOrderbook.fromJson(json);

      expect(orderbook.symbol, 'XRP-KRW');
      expect(orderbook.bids.length, 3);
      expect(orderbook.asks.length, 3);
      expect(orderbook.bestBid, 650.0);
      expect(orderbook.bestAsk, 651.0);
      expect(orderbook.spread, 1.0);
      expect(orderbook.midPrice, 650.5);
    });

    test('Orderbook slippage calculation for buy', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'bid': [
          ['650.0', '100'],
        ],
        'ask': [
          ['651.0', '100'],
          ['652.0', '100'],
          ['653.0', '100'],
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final orderbook = CoinoneOrderbook.fromJson(json);

      // Buy 150 XRP: 100@651 + 50@652 = 65100 + 32600 = 97700
      // Average: 97700 / 150 = 651.33
      final avgPrice = orderbook.calculateBuySlippage(150);
      expect(avgPrice, closeTo(651.33, 0.01));
    });

    test('Orderbook slippage calculation for sell', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'bid': [
          ['650.0', '100'],
          ['649.0', '100'],
          ['648.0', '100'],
        ],
        'ask': [
          ['651.0', '100'],
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final orderbook = CoinoneOrderbook.fromJson(json);

      // Sell 150 XRP: 100@650 + 50@649 = 65000 + 32450 = 97450
      // Average: 97450 / 150 = 649.67
      final avgPrice = orderbook.calculateSellSlippage(150);
      expect(avgPrice, closeTo(649.67, 0.01));
    });

    test('Orderbook bid/ask ratio', () {
      final json = {
        'quote_currency': 'KRW',
        'target_currency': 'XRP',
        'bid': [
          ['650.0', '200'],
          ['649.0', '200'],
        ],
        'ask': [
          ['651.0', '100'],
          ['652.0', '100'],
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final orderbook = CoinoneOrderbook.fromJson(json);

      expect(orderbook.totalBidVolume, 400);
      expect(orderbook.totalAskVolume, 200);
      expect(orderbook.bidAskRatio, 2.0); // 400/200
    });
  });

  group('CoinoneChart Tests', () {
    test('Create CoinoneCandle from JSON', () {
      final json = {
        'timestamp': '1704067200', // 2024-01-01 00:00:00 UTC (in seconds)
        'open': '650.0',
        'high': '660.0',
        'low': '640.0',
        'close': '655.0',
        'target_volume': '10000',
        'quote_volume': '6500000',
      };

      final candle = CoinoneCandle.fromJson(json);

      expect(candle.open, 650.0);
      expect(candle.high, 660.0);
      expect(candle.low, 640.0);
      expect(candle.close, 655.0);
      expect(candle.change, 5.0);
      expect(candle.isBullish, true);
      expect(candle.bodySize, 5.0);
      expect(candle.range, 20.0);
    });

    test('ChartInterval values', () {
      expect(ChartInterval.oneMinute.value, '1m');
      expect(ChartInterval.fiveMinutes.value, '5m');
      expect(ChartInterval.oneHour.value, '1h');
      expect(ChartInterval.oneDay.value, '1d');

      expect(ChartInterval.oneMinute.seconds, 60);
      expect(ChartInterval.fiveMinutes.seconds, 300);
      expect(ChartInterval.oneHour.seconds, 3600);
    });

    test('CoinoneChartData creation', () {
      final candlesJson = [
        {
          'timestamp': '1704067200',
          'open': '650.0',
          'high': '660.0',
          'low': '640.0',
          'close': '655.0',
          'target_volume': '10000',
          'quote_volume': '6500000',
        },
        {
          'timestamp': '1704067260',
          'open': '655.0',
          'high': '665.0',
          'low': '650.0',
          'close': '660.0',
          'target_volume': '10000',
          'quote_volume': '6600000',
        },
      ];

      final chartData = CoinoneChartData.fromJson(
        'KRW',
        'XRP',
        ChartInterval.oneMinute,
        candlesJson,
      );

      expect(chartData.symbol, 'XRP-KRW');
      expect(chartData.interval, ChartInterval.oneMinute);
      expect(chartData.candles.length, 2);
      expect(chartData.latestClose, 660.0);
    });
  });
}
