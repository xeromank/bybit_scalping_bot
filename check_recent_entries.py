#!/usr/bin/env python3
"""
최근 4시간 진입 포인트 분석
현재 전략으로 진입 기회가 있었는지 확인
"""

import requests
import json
from datetime import datetime, timedelta

def fetch_coinone_chart(symbol='XRP', interval='5m'):
    """Fetch recent chart data from Coinone API"""
    url = f'https://api.coinone.co.kr/public/v2/chart/KRW/{symbol}'
    params = {
        'interval': interval,
        'size': 500  # Get 500 candles (5min × 500 = ~41 hours)
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        data = response.json()

        if data.get('result') == 'success':
            candles = data.get('chart', [])
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
        gains.append(max(0, change))
        losses.append(max(0, -change))

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
    multiplier = 2.0 / (period + 1)
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
        'price_near_ema21': price > ema21 * 0.98,
        'short_term_uptrend': ema9 > ema21 * 0.99,
        'not_overbought': price <= bb_middle * 1.01,
        'volume_confirmation': volume_ratio >= 1.0
    }

    strength = sum(conditions.values()) / len(conditions)
    return strength >= 0.75, strength, conditions, position_size, sl_percent, tp_percent

def check_sideways_entry(rsi, bb_position, volume_ratio):
    """Check Sideways Strategy entry conditions (IMPROVED)"""
    if rsi > 32:
        return False, 0.0, {}

    conditions = {
        'near_lower_band': bb_position < 0.4,
        'deeply_oversold': rsi <= 32,
        'not_extreme': rsi >= 15,
        'volume_spike': volume_ratio >= 1.1
    }

    strength = (0.35 if conditions['near_lower_band'] else 0) + \
               (0.25 if conditions['deeply_oversold'] else 0) + \
               (0.2 if conditions['not_extreme'] else 0) + \
               (0.2 if conditions['volume_spike'] else 0)

    return strength >= 0.8, strength, conditions

def analyze_recent_4_hours(symbol='XRP'):
    """Analyze last 4 hours for entry opportunities"""
    print(f"\n{'='*70}")
    print(f"최근 4시간 진입 포인트 분석 - {symbol}")
    print(f"{'='*70}\n")

    # Fetch data
    candles = fetch_coinone_chart(symbol, '5m')
    if len(candles) < 200:
        print(f"✗ Not enough data (need 200+, got {len(candles)})")
        return

    # Candles are sorted NEWEST FIRST (reverse chronological)
    # Last 4 hours = first ~48 candles (5min × 48 = 4 hours)
    now = datetime.now()
    four_hours_ago = now - timedelta(hours=4)

    # Reverse candles to oldest first for analysis
    candles.reverse()

    # Filter candles from last 4 hours
    cutoff_timestamp = int(four_hours_ago.timestamp() * 1000)
    recent_candles_idx = []

    for i in range(len(candles)):
        if candles[i]['timestamp'] >= cutoff_timestamp:
            recent_candles_idx.append(i)

    if len(recent_candles_idx) == 0:
        print("✗ No candles found in last 4 hours")
        return

    first_recent_idx = recent_candles_idx[0]
    last_recent_idx = recent_candles_idx[-1]

    oldest_analyzed = datetime.fromtimestamp(candles[first_recent_idx]['timestamp'] / 1000)
    latest_analyzed = datetime.fromtimestamp(candles[last_recent_idx]['timestamp'] / 1000)

    print(f"분석 기간: {oldest_analyzed.strftime('%Y-%m-%d %H:%M')} ~ {latest_analyzed.strftime('%Y-%m-%d %H:%M')}")
    print(f"총 캔들 수: {len(recent_candles_idx)}개 (5분봉)\n")

    # Prepare data
    closes = [float(c['close']) for c in candles]
    volumes = [float(c['target_volume']) for c in candles]

    uptrend_entries = []
    sideways_entries = []

    # Analyze recent candles (need at least 200 candles of history for indicators)
    for i in recent_candles_idx:
        if i < 200:  # Skip if not enough historical data
            continue
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
    print(f"{'='*70}")
    print(f"📈 상승 전략 진입 포인트")
    print(f"{'='*70}")

    if uptrend_entries:
        print(f"발견: {len(uptrend_entries)}개\n")
        for idx, entry in enumerate(uptrend_entries, 1):
            print(f"[{idx}] {entry['time'].strftime('%m-%d %H:%M')}")
            print(f"    가격: {entry['price']:.0f}원")
            print(f"    RSI: {entry['rsi']:.1f}")
            print(f"    포지션: {entry['position_size']*100:.0f}%")
            print(f"    SL: {entry['sl_percent']:.1f}% | TP: {entry['tp_percent']:.1f}%")
            print(f"    거래량: {entry['volume_ratio']:.2f}x")
            print(f"    조건: {', '.join([k for k, v in entry['conditions'].items() if v])}\n")
    else:
        print("✗ 진입 포인트 없음\n")

    print(f"{'='*70}")
    print(f"📊 횡보 전략 진입 포인트")
    print(f"{'='*70}")

    if sideways_entries:
        print(f"발견: {len(sideways_entries)}개\n")
        for idx, entry in enumerate(sideways_entries, 1):
            print(f"[{idx}] {entry['time'].strftime('%m-%d %H:%M')}")
            print(f"    가격: {entry['price']:.0f}원")
            print(f"    RSI: {entry['rsi']:.1f}")
            print(f"    BB 위치: {entry['bb_position']*100:.1f}%")
            print(f"    거래량: {entry['volume_ratio']:.2f}x")
            print(f"    조건: {', '.join([k for k, v in entry['conditions'].items() if v])}\n")
    else:
        print("✗ 진입 포인트 없음\n")

    print(f"{'='*70}")
    print(f"📊 요약")
    print(f"{'='*70}")
    print(f"총 진입 기회: {len(uptrend_entries) + len(sideways_entries)}개")
    print(f"  - 상승: {len(uptrend_entries)}개")
    print(f"  - 횡보: {len(sideways_entries)}개")

    if len(uptrend_entries) + len(sideways_entries) > 0:
        print(f"\n✅ 최근 4시간 동안 진입 기회가 있었습니다!")
    else:
        print(f"\n⚠️ 최근 4시간 동안 진입 조건을 충족한 포인트가 없었습니다.")
        print(f"   - 시장이 횡보/약세이거나")
        print(f"   - RSI가 진입 구간(상승: ≤40, 횡보: ≤32)에 도달하지 않았을 수 있습니다.")

    print(f"{'='*70}\n")

if __name__ == '__main__':
    analyze_recent_4_hours('XRP')
