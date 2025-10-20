#!/usr/bin/env python3
"""
봇 타이밍 분석
실시간 봇이 진입 신호를 놓칠 수 있는 타이밍 이슈 분석
"""

import requests
from datetime import datetime, timedelta

def fetch_coinone_chart(symbol='XRP', interval='5m', size=500):
    """Fetch chart data"""
    url = f'https://api.coinone.co.kr/public/v2/chart/KRW/{symbol}'
    params = {'interval': interval, 'size': size}

    try:
        response = requests.get(url, params=params, timeout=10)
        data = response.json()
        if data.get('result') == 'success':
            return data.get('chart', [])
    except Exception as e:
        print(f"Error: {e}")
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
    return 100 - (100 / (1 + rs))

def calculate_bollinger_bands(prices, period=20, std_dev=2.0):
    """Calculate Bollinger Bands"""
    if len(prices) < period:
        return None, None, None
    recent_prices = prices[-period:]
    middle = sum(recent_prices) / period
    variance = sum((p - middle) ** 2 for p in recent_prices) / period
    std = variance ** 0.5
    return middle + (std * std_dev), middle, middle - (std * std_dev)

def calculate_volume_ma(volumes, period=5):
    """Calculate Volume MA"""
    if len(volumes) < period:
        return None
    return sum(volumes[-period:]) / period

print(f"\n{'='*80}")
print("🕐 봇 타이밍 분석 - 진입 신호가 몇 초 동안 유효한가?")
print(f"{'='*80}\n")

# Fetch chart data
candles = fetch_coinone_chart('XRP', '5m', 500)
if len(candles) < 250:
    print("Not enough data")
    exit(1)

candles.reverse()  # oldest first

# Find last 4 hours
now = datetime.now()
four_hours_ago = now - timedelta(hours=4)
cutoff_ts = int(four_hours_ago.timestamp() * 1000)

recent_indices = [i for i in range(len(candles)) if candles[i]['timestamp'] >= cutoff_ts]

if len(recent_indices) == 0:
    print("No recent candles")
    exit(1)

print(f"📊 분석 기간: {len(recent_indices)} 캔들 (5분봉)")
print(f"시작: {datetime.fromtimestamp(candles[recent_indices[0]]['timestamp']/1000).strftime('%H:%M')}")
print(f"종료: {datetime.fromtimestamp(candles[recent_indices[-1]]['timestamp']/1000).strftime('%H:%M')}\n")

# Analyze entry signals and how long they last
print(f"{'시간':>8} {'RSI':>6} {'BB위치':>7} {'거래량':>7} {'신호강도':>8} {'진입':>4} {'지속':>6}")
print(f"{'='*80}")

closes = [float(c['close']) for c in candles]
volumes = [float(c['target_volume']) for c in candles]

entry_windows = []
current_window = None

for idx in recent_indices:
    if idx < 200:
        continue

    # Calculate indicators
    rsi = calculate_rsi(closes[:idx+1], 14)
    bb_upper, bb_middle, bb_lower = calculate_bollinger_bands(closes[:idx+1], 20, 2.0)
    volume_ma5 = calculate_volume_ma(volumes[:idx+1], 5)

    if None in [rsi, bb_upper, volume_ma5]:
        continue

    price = closes[idx]
    volume = volumes[idx]
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

    timestamp = datetime.fromtimestamp(candles[idx]['timestamp'] / 1000)
    time_str = timestamp.strftime('%H:%M')

    # Track entry windows
    if is_entry:
        if current_window is None:
            current_window = {
                'start_time': timestamp,
                'end_time': timestamp,
                'start_idx': idx,
                'end_idx': idx,
                'max_strength': strength,
                'rsi_range': [rsi, rsi],
                'bb_range': [bb_position, bb_position]
            }
        else:
            current_window['end_time'] = timestamp
            current_window['end_idx'] = idx
            current_window['max_strength'] = max(current_window['max_strength'], strength)
            current_window['rsi_range'][1] = rsi
            current_window['bb_range'][1] = bb_position
    else:
        if current_window is not None:
            entry_windows.append(current_window)
            current_window = None

    # Print row
    entry_mark = "✓" if is_entry else ""
    print(f"{time_str:>8} {rsi:>6.1f} {bb_position*100:>6.1f}% {volume_ratio:>6.2f}x {strength:>8.2f} {entry_mark:>4}", end="")

    if is_entry:
        print()
    else:
        print()

# Close last window if still open
if current_window is not None:
    entry_windows.append(current_window)

print(f"\n{'='*80}")
print(f"📈 진입 신호 지속 시간 분석")
print(f"{'='*80}\n")

if len(entry_windows) == 0:
    print("⚠️ 최근 4시간 동안 진입 신호가 없었습니다.\n")
else:
    total_duration = 0
    for i, window in enumerate(entry_windows, 1):
        duration_candles = window['end_idx'] - window['start_idx'] + 1
        duration_minutes = duration_candles * 5

        print(f"[{i}] 진입 윈도우")
        print(f"    시작: {window['start_time'].strftime('%m-%d %H:%M')}")
        print(f"    종료: {window['end_time'].strftime('%m-%d %H:%M')}")
        print(f"    지속: {duration_candles}캔들 ({duration_minutes}분)")
        print(f"    최대 강도: {window['max_strength']:.2f}")
        print(f"    RSI 범위: {window['rsi_range'][0]:.1f} ~ {window['rsi_range'][1]:.1f}")
        print(f"    BB 위치: {window['bb_range'][0]*100:.1f}% ~ {window['bb_range'][1]*100:.1f}%")
        print()

        total_duration += duration_minutes

    print(f"{'='*80}")
    print(f"총 진입 윈도우: {len(entry_windows)}개")
    print(f"총 지속 시간: {total_duration}분")
    print(f"평균 지속 시간: {total_duration/len(entry_windows):.1f}분")

    print(f"\n💡 분석:")
    avg_duration = total_duration / len(entry_windows)

    if avg_duration < 1:
        print(f"   ⚠️ 진입 신호가 평균 {avg_duration:.1f}분만 유지됩니다.")
        print(f"   → 1초 주기로 체크하는 봇이 신호를 놓칠 확률은 낮습니다.")
        print(f"   → 문제는 다른 곳에 있을 수 있습니다:")
        print(f"      - 봇이 해당 시간에 실행 중이 아니었을 수 있음")
        print(f"      - 지표 계산이 차트 API와 다를 수 있음")
        print(f"      - WebSocket 티커 데이터가 차트 데이터와 다를 수 있음")
    elif avg_duration < 5:
        print(f"   ⚠️ 진입 신호가 평균 {avg_duration:.1f}분 지속됩니다.")
        print(f"   → 5분 캔들이 완료되기 전에 신호가 사라질 수 있습니다.")
        print(f"   → 실시간 가격 변동으로 신호 조건이 깨질 수 있습니다.")
    else:
        print(f"   ✓ 진입 신호가 평균 {avg_duration:.1f}분 지속됩니다.")
        print(f"   → 1초 주기로 체크하는 봇이 신호를 충분히 감지할 수 있습니다.")
        print(f"   → 봇이 실행 중이었다면 진입했어야 합니다.")

print(f"\n{'='*80}\n")
