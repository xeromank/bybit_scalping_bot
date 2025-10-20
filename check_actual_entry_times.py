#!/usr/bin/env python3
"""
실제 진입 포인트 시간 확인
"""

import requests
from datetime import datetime, timedelta

def calculate_rsi(prices, period=14):
    if len(prices) < period + 1:
        return None
    gains, losses = [], []
    for i in range(1, len(prices)):
        change = prices[i] - prices[i-1]
        gains.append(max(0, change))
        losses.append(max(0, -change))
    avg_gain = sum(gains[-period:]) / period
    avg_loss = sum(losses[-period:]) / period
    if avg_loss == 0:
        return 100
    rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))

def calculate_bollinger_bands(prices, period=20, std_dev=2.0):
    if len(prices) < period:
        return None, None, None
    recent_prices = prices[-period:]
    middle = sum(recent_prices) / period
    variance = sum((p - middle) ** 2 for p in recent_prices) / period
    std = variance ** 0.5
    return middle + (std * std_dev), middle, middle - (std * std_dev)

def calculate_volume_ma(volumes, period=5):
    if len(volumes) < period:
        return None
    return sum(volumes[-period:]) / period

# Fetch data
response = requests.get('https://api.coinone.co.kr/public/v2/chart/KRW/XRP?interval=5m&size=500')
data = response.json()

if data.get('result') != 'success':
    print("API Error")
    exit(1)

candles = data['chart']
print(f"총 캔들: {len(candles)}개")

# API returns NEWEST FIRST, so reverse to OLDEST FIRST
candles.reverse()

# Get last 4 hours
now = datetime.now()
four_hours_ago = now - timedelta(hours=4)

print(f"\n현재 시간: {now.strftime('%Y-%m-%d %H:%M:%S')}")
print(f"4시간 전: {four_hours_ago.strftime('%Y-%m-%d %H:%M:%S')}")

# Prepare data
closes = [float(c['close']) for c in candles]
volumes = [float(c['target_volume']) for c in candles]

print(f"\n{'='*100}")
print(f"{'시간':20} {'가격':>8} {'RSI':>6} {'BB위치':>7} {'거래량':>7} {'강도':>6} {'진입':>4}")
print(f"{'='*100}")

entry_count = 0

for i in range(len(candles)):
    if i < 200:  # Need history for indicators
        continue

    ts = datetime.fromtimestamp(int(candles[i]['timestamp']) / 1000)

    # Only show last 4 hours
    if ts < four_hours_ago:
        continue

    # Calculate indicators
    rsi = calculate_rsi(closes[:i+1], 14)
    bb_upper, bb_middle, bb_lower = calculate_bollinger_bands(closes[:i+1], 20, 2.0)
    volume_ma5 = calculate_volume_ma(volumes[:i+1], 5)

    if None in [rsi, bb_upper, volume_ma5]:
        continue

    price = closes[i]
    volume = volumes[i]
    volume_ratio = volume / volume_ma5 if volume_ma5 > 0 else 1.0

    bb_range = bb_upper - bb_lower
    bb_position = (price - bb_lower) / bb_range if bb_range > 0 else 0.5

    # Check sideways entry conditions
    near_lower = bb_position < 0.4
    oversold = rsi <= 32
    not_extreme = rsi >= 15
    vol_spike = volume_ratio >= 1.1

    strength = 0.0
    if near_lower:
        strength += 0.35
    if oversold:
        strength += 0.25
    if not_extreme:
        strength += 0.2
    if vol_spike:
        strength += 0.2

    is_entry = strength >= 0.8

    # Print all rows for last 4 hours
    entry_mark = "✓✓✓" if is_entry else ""

    time_str = ts.strftime('%Y-%m-%d %H:%M:%S')
    print(f"{time_str:20} {price:>8.0f} {rsi:>6.1f} {bb_position*100:>6.1f}% {volume_ratio:>6.2f}x {strength:>6.2f} {entry_mark:>4}")

    if is_entry:
        entry_count += 1

print(f"{'='*100}")
print(f"\n총 진입 포인트: {entry_count}개")
