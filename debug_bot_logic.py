#!/usr/bin/env python3
"""
봇 로직 디버깅 - 실시간 시뮬레이션
현재 시점에서 봇이 어떻게 판단하는지 확인
"""

import requests
import json
from datetime import datetime

def fetch_coinone_chart(symbol='XRP', interval='5m', size=500):
    """Fetch chart data from Coinone API"""
    url = f'https://api.coinone.co.kr/public/v2/chart/KRW/{symbol}'
    params = {'interval': interval, 'size': size}

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

def check_sideways_conditions(rsi, bb_position, volume_ratio):
    """Check Sideways Strategy conditions (exactly as in Dart code)"""
    # Entry conditions (from sideways_strategy.dart)
    near_lower_band = bb_position < 0.4  # line 38
    deeply_oversold = rsi <= 32           # line 39
    not_extreme = rsi >= 15               # line 40
    volume_spike = volume_ratio >= 1.1    # line 41

    # Calculate strength (from sideways_strategy.dart lines 44-65)
    strength = 0.0
    reasons = []

    if near_lower_band:
        strength += 0.35
        reasons.append(f'볼린저 하단 근처 ({bb_position*100:.0f}%)')

    if deeply_oversold:
        strength += 0.25
        reasons.append(f'RSI 심각한 과매도 ({rsi:.1f})')

    if not_extreme:
        strength += 0.2
        reasons.append('극단적 하락 아님')

    if volume_spike:
        strength += 0.2
        reasons.append(f'거래량 급증 ({volume_ratio:.2f}x)')

    # Line 68: Generate BUY signal if strength >= 0.8
    is_entry = strength >= 0.8

    return is_entry, strength, {
        'near_lower_band': near_lower_band,
        'deeply_oversold': deeply_oversold,
        'not_extreme': not_extreme,
        'volume_spike': volume_spike
    }, reasons

def analyze_current_state(symbol='XRP'):
    """Analyze current market state as bot sees it"""
    print(f"\n{'='*70}")
    print(f"🤖 봇 로직 디버깅 - {symbol}")
    print(f"{'='*70}\n")

    # Fetch data
    candles = fetch_coinone_chart(symbol, '5m', 500)
    if len(candles) < 200:
        print(f"✗ Not enough data (need 200+, got {len(candles)})")
        return

    # Reverse to oldest-first
    candles.reverse()

    # Prepare data
    closes = [float(c['close']) for c in candles]
    volumes = [float(c['target_volume']) for c in candles]

    # Calculate indicators for LATEST candle
    rsi = calculate_rsi(closes, 14)
    ema9 = calculate_ema(closes, 9)
    ema21 = calculate_ema(closes, 21)
    ema50 = calculate_ema(closes, 50)
    ema200 = calculate_ema(closes, 200)
    bb_upper, bb_middle, bb_lower = calculate_bollinger_bands(closes, 20, 2.0)
    volume_ma5 = calculate_volume_ma(volumes, 5)

    if None in [rsi, ema9, ema21, ema50, ema200, bb_upper, volume_ma5]:
        print("✗ Failed to calculate indicators")
        return

    price = closes[-1]
    volume = volumes[-1]
    volume_ratio = volume / volume_ma5 if volume_ma5 > 0 else 1.0

    # Detect trend
    trend = detect_trend(ema50, ema200, price)

    # Calculate BB position
    bb_range = bb_upper - bb_lower
    bb_position = (price - bb_lower) / bb_range if bb_range > 0 else 0.5

    # Get latest candle timestamp
    latest_timestamp = datetime.fromtimestamp(candles[-1]['timestamp'] / 1000)

    print(f"📊 현재 시장 상태")
    print(f"{'='*70}")
    print(f"시간: {latest_timestamp.strftime('%Y-%m-%d %H:%M')}")
    print(f"가격: {price:.0f}원")
    print(f"추세: {trend}")
    print(f"\n🔍 기술적 지표")
    print(f"{'='*70}")
    print(f"RSI(14): {rsi:.1f}")
    print(f"EMA9: {ema9:.2f}")
    print(f"EMA21: {ema21:.2f}")
    print(f"EMA50: {ema50:.2f}")
    print(f"EMA200: {ema200:.2f}")
    print(f"볼린저 상단: {bb_upper:.2f}")
    print(f"볼린저 중단: {bb_middle:.2f}")
    print(f"볼린저 하단: {bb_lower:.2f}")
    print(f"볼린저 위치: {bb_position*100:.1f}%")
    print(f"거래량 비율: {volume_ratio:.2f}x")

    # Check strategy conditions
    print(f"\n🎯 전략 판단")
    print(f"{'='*70}")

    if trend == 'sideways':
        is_entry, strength, conditions, reasons = check_sideways_conditions(
            rsi, bb_position, volume_ratio
        )

        print(f"전략: 횡보 전략")
        print(f"\n조건 체크:")
        for condition, met in conditions.items():
            status = "✓" if met else "✗"
            print(f"  {status} {condition}: {met}")

        print(f"\n시그널 강도: {strength:.2f} (0.8 이상 필요)")
        print(f"이유: {', '.join(reasons) if reasons else '조건 미충족'}")

        if is_entry:
            print(f"\n✅ 진입 조건 충족! (강도 {strength:.2f} >= 0.8)")
            entry_price = price
            stop_loss = entry_price * (1 - 2.5 / 100)
            take_profit = entry_price * (1 + 1.2 / 100)
            print(f"   진입가: {entry_price:.0f}원")
            print(f"   손절가: {stop_loss:.0f}원 (-2.5%)")
            print(f"   목표가: {take_profit:.0f}원 (+1.2%)")
        else:
            print(f"\n⚠️ 진입 조건 미충족 (강도 {strength:.2f} < 0.8)")
            print(f"\n🔍 부족한 조건:")
            if not conditions['near_lower_band']:
                print(f"   - 볼린저 위치가 너무 높음 ({bb_position*100:.1f}% >= 40%)")
            if not conditions['deeply_oversold']:
                print(f"   - RSI가 충분히 낮지 않음 ({rsi:.1f} > 32)")
            if not conditions['not_extreme']:
                print(f"   - RSI가 너무 낮음 ({rsi:.1f} < 15, 폭락 위험)")
            if not conditions['volume_spike']:
                print(f"   - 거래량 부족 ({volume_ratio:.2f}x < 1.1x)")

    elif trend == 'uptrend':
        print(f"전략: 상승 전략")
        print(f"RSI: {rsi:.1f}")

        if rsi > 40:
            print(f"⚠️ 진입 조건 미충족: RSI {rsi:.1f} > 40")
        else:
            print(f"✓ RSI가 진입 구간 내 (≤40)")
            # Check other uptrend conditions
            price_near_ema21 = price > ema21 * 0.98
            short_term_uptrend = ema9 > ema21 * 0.99
            not_overbought = price <= bb_middle * 1.01
            volume_confirmation = volume_ratio >= 1.0

            print(f"  {'✓' if price_near_ema21 else '✗'} 가격이 EMA21 근처: {price:.0f} > {ema21*0.98:.0f}")
            print(f"  {'✓' if short_term_uptrend else '✗'} 단기 상승세: EMA9({ema9:.0f}) > EMA21({ema21*0.99:.0f})")
            print(f"  {'✓' if not_overbought else '✗'} 과매수 아님: {price:.0f} <= {bb_middle*1.01:.0f}")
            print(f"  {'✓' if volume_confirmation else '✗'} 거래량 확인: {volume_ratio:.2f}x >= 1.0x")

            conditions_met = sum([price_near_ema21, short_term_uptrend, not_overbought, volume_confirmation])
            strength = conditions_met / 4

            if strength >= 0.75:
                print(f"\n✅ 진입 조건 충족! (강도 {strength:.2f} >= 0.75)")
            else:
                print(f"\n⚠️ 진입 조건 미충족 (강도 {strength:.2f} < 0.75)")

    else:  # downtrend
        print(f"전략: 하락 추세 - 매매 중단")
        print(f"⚠️ 하락 추세에서는 진입하지 않음")

    print(f"\n{'='*70}\n")

if __name__ == '__main__':
    analyze_current_state('XRP')
