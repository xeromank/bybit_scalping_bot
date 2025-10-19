#!/usr/bin/env python3
"""
Coinone Strategy Backtest - Entry Opportunity Analysis

Tests the new strategy parameters:
- Uptrend: RSI ≤ 35, TP: 3%, SL: 5%
- Sideways: RSI ≤ 28, TP: 1%, SL: 3%
"""

import requests
import json
from datetime import datetime, timedelta
import statistics

def fetch_coinone_chart(symbol='XRP', interval='5m', hours=24):
    """Fetch chart data from Coinone API"""
    url = f'https://api.coinone.co.kr/public/v2/chart/KRW/{symbol}'
    params = {
        'interval': interval,
        'size': 500  # Request max 500 candles
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        data = response.json()

        if data.get('result') == 'success':
            candles = data.get('chart', [])
            # Get 500 candles (API max)
            print(f"✓ Fetched {len(candles)} candles for {symbol}")
            return candles
        else:
            print(f"✗ API Error: {data.get('error_message', 'Unknown error')}")
            return []
    except Exception as e:
        print(f"✗ Exception: {e}")
        return []

def calculate_rsi(prices, period=14):
    """Calculate RSI"""
    if len(prices) < period + 1:
        return None

    gains = []
    losses = []

    for i in range(1, len(prices)):
        change = prices[i] - prices[i-1]
        if change > 0:
            gains.append(change)
            losses.append(0)
        else:
            gains.append(0)
            losses.append(abs(change))

    avg_gain = sum(gains[-period:]) / period
    avg_loss = sum(losses[-period:]) / period

    if avg_loss == 0:
        return 100

    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

def calculate_ema(prices, period):
    """Calculate EMA"""
    if len(prices) < period:
        return None

    sma = sum(prices[:period]) / period
    multiplier = 2 / (period + 1)
    ema = sma

    for price in prices[period:]:
        ema = (price - ema) * multiplier + ema

    return ema

def calculate_bollinger_bands(prices, period=20, std_dev=2.0):
    """Calculate Bollinger Bands"""
    if len(prices) < period:
        return None, None, None

    recent_prices = prices[-period:]
    middle = sum(recent_prices) / period
    variance = sum((p - middle) ** 2 for p in recent_prices) / period
    std = variance ** 0.5

    upper = middle + (std * std_dev)
    lower = middle - (std * std_dev)

    return upper, middle, lower

def calculate_volume_ma(volumes, period=5):
    """Calculate Volume Moving Average"""
    if len(volumes) < period:
        return None
    return sum(volumes[-period:]) / period

def detect_trend(ema50, ema200, price):
    """Detect market trend"""
    if ema50 > ema200 and price > ema50:
        price_above_ema50 = ((price - ema50) / ema50) * 100
        if price_above_ema50 > 0.5:
            return 'uptrend'

    if ema50 < ema200 and price < ema50:
        price_below_ema50 = ((ema50 - price) / ema50) * 100
        if price_below_ema50 > 0.5:
            return 'downtrend'

    return 'sideways'

def check_uptrend_entry(rsi, price, ema21, ema9, bb_middle, volume_ratio):
    """Check Uptrend Strategy entry conditions (GRADUAL ENTRY)"""
    # Determine RSI tier
    if rsi > 40:
        return False, 0.0, {}, 0.0, 0.0, 0.0
    elif rsi <= 30:
        position_size = 1.0
        sl_percent = 5.0
        tp_percent = 3.0
        tier = 'Tier1(100%)'
    elif rsi <= 35:
        position_size = 0.5
        sl_percent = 4.0
        tp_percent = 2.0
        tier = 'Tier2(50%)'
    else:  # rsi <= 40
        position_size = 0.25
        sl_percent = 3.0
        tp_percent = 1.5
        tier = 'Tier3(25%)'

    # Check other conditions (RELAXED)
    conditions = {
        'price_near_ema21': price > ema21 * 0.98,  # 2% buffer
        'short_term_uptrend': ema9 > ema21 * 0.99,  # Slight relaxation
        'not_overbought': price <= bb_middle * 1.01,
        'volume_confirmation': volume_ratio >= 1.0
    }

    strength = sum(conditions.values()) / len(conditions)
    return strength >= 0.75, strength, conditions, position_size, sl_percent, tp_percent

def check_sideways_entry(rsi, bb_position, volume_ratio):
    """Check Sideways Strategy entry conditions (IMPROVED)"""
    # RSI ≤ 32 is REQUIRED condition (RELAXED from 28)
    if rsi > 32:
        return False, 0.0, {}

    conditions = {
        'near_lower_band': bb_position < 0.4,  # RELAXED: 40% (was 30%)
        'deeply_oversold': rsi <= 32,          # RELAXED: ≤32 (was 28)
        'not_extreme': rsi >= 15,
        'volume_spike': volume_ratio >= 1.1    # RELAXED: 1.1x (was 1.2x)
    }

    strength = (0.35 if conditions['near_lower_band'] else 0) + \
               (0.25 if conditions['deeply_oversold'] else 0) + \
               (0.2 if conditions['not_extreme'] else 0) + \
               (0.2 if conditions['volume_spike'] else 0)

    return strength >= 0.8, strength, conditions

def backtest_strategy(symbol='XRP', hours=24):
    """Backtest strategy and count entry opportunities"""
    print(f"\n{'='*70}")
    print(f"Coinone Strategy Backtest - {symbol}")
    print(f"Period: All available data (5-minute candles)")
    print(f"{'='*70}\n")

    # Fetch data
    candles = fetch_coinone_chart(symbol, '5m', hours)
    if len(candles) < 200:
        print(f"✗ Not enough data (need 200+, got {len(candles)})")
        return

    # Prepare data (convert strings to floats)
    closes = [float(c['close']) for c in candles]
    volumes = [float(c['target_volume']) for c in candles]

    uptrend_entries = []
    sideways_entries = []

    print(f"\n📊 Analyzing {len(candles)} candles...\n")

    # Analyze each candle
    for i in range(200, len(candles)):
        # Calculate indicators
        rsi = calculate_rsi(closes[:i+1], 14)
        ema9 = calculate_ema(closes[:i+1], 9)
        ema21 = calculate_ema(closes[:i+1], 21)
        ema50 = calculate_ema(closes[:i+1], 50)
        ema200 = calculate_ema(closes[:i+1], 200)
        bb_upper, bb_middle, bb_lower = calculate_bollinger_bands(closes[:i+1], 20, 2.0)
        volume_ma5 = calculate_volume_ma(volumes[:i+1], 5)

        if None in [rsi, ema9, ema21, ema50, ema200, bb_upper, volume_ma5]:
            continue

        price = closes[i]
        volume = volumes[i]
        volume_ratio = volume / volume_ma5 if volume_ma5 > 0 else 1.0

        # Detect trend
        trend = detect_trend(ema50, ema200, price)

        # Calculate BB position
        bb_range = bb_upper - bb_lower
        bb_position = (price - bb_lower) / bb_range if bb_range > 0 else 0.5

        timestamp = datetime.fromtimestamp(candles[i]['timestamp'] / 1000)

        # Check entry conditions
        if trend == 'uptrend':
            is_entry, strength, conditions, position_size, sl_percent, tp_percent = check_uptrend_entry(
                rsi, price, ema21, ema9, bb_middle, volume_ratio
            )

            if is_entry:
                uptrend_entries.append({
                    'time': timestamp,
                    'price': price,
                    'rsi': rsi,
                    'volume_ratio': volume_ratio,
                    'strength': strength,
                    'conditions': conditions,
                    'position_size': position_size,
                    'sl_percent': sl_percent,
                    'tp_percent': tp_percent
                })

        elif trend == 'sideways':
            is_entry, strength, conditions = check_sideways_entry(
                rsi, bb_position, volume_ratio
            )

            if is_entry:
                sideways_entries.append({
                    'time': timestamp,
                    'price': price,
                    'rsi': rsi,
                    'bb_position': bb_position,
                    'volume_ratio': volume_ratio,
                    'strength': strength,
                    'conditions': conditions
                })

    # Print results
    print(f"\n{'='*70}")
    print(f"📈 UPTREND STRATEGY - GRADUAL ENTRY (RSI ≤ 40)")
    print(f"{'='*70}")
    print(f"Total Entry Opportunities: {len(uptrend_entries)}")

    if uptrend_entries:
        print(f"\nEntry Details:")
        for idx, entry in enumerate(uptrend_entries, 1):
            print(f"\n  [{idx}] {entry['time'].strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"      Price: {entry['price']:.2f} KRW")
            print(f"      RSI: {entry['rsi']:.1f}")
            print(f"      Position Size: {entry['position_size']*100:.0f}%")
            print(f"      SL: {entry['sl_percent']:.1f}% | TP: {entry['tp_percent']:.1f}%")
            print(f"      Volume: {entry['volume_ratio']:.2f}x")
            print(f"      Strength: {entry['strength']:.1%}")
            print(f"      Conditions: {', '.join([k for k, v in entry['conditions'].items() if v])}")
    else:
        print("  ✗ No entry opportunities found")

    print(f"\n{'='*70}")
    print(f"📊 SIDEWAYS STRATEGY - IMPROVED (RSI ≤ 32, SL: 2.5%, TP: 1.2%)")
    print(f"{'='*70}")
    print(f"Total Entry Opportunities: {len(sideways_entries)}")

    if sideways_entries:
        print(f"\nEntry Details:")
        for idx, entry in enumerate(sideways_entries, 1):
            print(f"\n  [{idx}] {entry['time'].strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"      Price: {entry['price']:.2f} KRW")
            print(f"      RSI: {entry['rsi']:.1f}")
            print(f"      BB Position: {entry['bb_position']*100:.1f}%")
            print(f"      Volume: {entry['volume_ratio']:.2f}x")
            print(f"      Strength: {entry['strength']:.1%}")
            print(f"      Conditions: {', '.join([k for k, v in entry['conditions'].items() if v])}")
    else:
        print("  ✗ No entry opportunities found")

    print(f"\n{'='*70}")
    print(f"📊 SUMMARY")
    print(f"{'='*70}")
    print(f"Total Opportunities: {len(uptrend_entries) + len(sideways_entries)}")
    print(f"  - Uptrend: {len(uptrend_entries)}")
    print(f"  - Sideways: {len(sideways_entries)}")
    print(f"Frequency: {(len(uptrend_entries) + len(sideways_entries)) / hours:.2f} entries per hour")
    print(f"{'='*70}\n")

if __name__ == '__main__':
    # Test with XRP (default coin)
    backtest_strategy('XRP', hours=24)

    # Optionally test other coins
    # backtest_strategy('BTC', hours=24)
    # backtest_strategy('ETH', hours=24)
