#!/usr/bin/env python3
"""
Coinone XRP Scalping Strategy Backtest

Fetches 5-minute candle data from Coinone API and tests multiple scalping strategies:
1. Bollinger Band Mean Reversion
2. RSI Oversold/Overbought
3. EMA Crossover
4. Support/Resistance Breakout
5. Combined Multi-Strategy
"""

import requests
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json

# ==============================================================================
# Data Fetching
# ==============================================================================

def fetch_coinone_chart(quote_currency='KRW', target_currency='XRP', interval='5m', days=30):
    """
    Fetch chart data from Coinone API

    Args:
        quote_currency: Quote currency (KRW)
        target_currency: Target currency (XRP)
        interval: Chart interval (1m, 5m, 15m, 30m, 1h, 4h, 1d)
        days: Number of days to fetch (default: 30 for statistical significance)

    Returns:
        DataFrame with OHLCV data
    """
    url = f'https://api.coinone.co.kr/public/v2/chart/{quote_currency}/{target_currency}'

    # Calculate timestamps
    end_time = int(datetime.now().timestamp())
    start_time = int((datetime.now() - timedelta(days=days)).timestamp())

    params = {
        'interval': interval,
        'start_time': start_time,
        'end_time': end_time
    }

    print(f"Fetching {target_currency}/{quote_currency} {interval} chart data...")
    print(f"Period: {days} days ({datetime.fromtimestamp(start_time)} to {datetime.fromtimestamp(end_time)})")

    response = requests.get(url, params=params)

    if response.status_code != 200:
        raise Exception(f"API Error: {response.status_code} - {response.text}")

    data = response.json()

    if 'chart' not in data:
        raise Exception(f"No chart data in response: {data}")

    # Convert to DataFrame
    df = pd.DataFrame(data['chart'])

    # Convert timestamp to datetime (milliseconds)
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')

    # Rename columns for clarity
    df = df.rename(columns={
        'open': 'Open',
        'high': 'High',
        'low': 'Low',
        'close': 'Close',
        'target_volume': 'Volume',
        'quote_volume': 'Quote_Volume'
    })

    # Convert to numeric
    for col in ['Open', 'High', 'Low', 'Close', 'Volume', 'Quote_Volume']:
        df[col] = pd.to_numeric(df[col])

    df = df.sort_values('timestamp').reset_index(drop=True)

    print(f"✓ Fetched {len(df)} candles")
    print(f"  Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"  Price range: {df['Low'].min():.2f} - {df['High'].max():.2f} KRW")

    return df


# ==============================================================================
# Technical Indicators
# ==============================================================================

def calculate_bollinger_bands(df, period=20, std_dev=2):
    """Calculate Bollinger Bands"""
    df['BB_Middle'] = df['Close'].rolling(window=period).mean()
    df['BB_Std'] = df['Close'].rolling(window=period).std()
    df['BB_Upper'] = df['BB_Middle'] + (std_dev * df['BB_Std'])
    df['BB_Lower'] = df['BB_Middle'] - (std_dev * df['BB_Std'])
    df['BB_Width'] = (df['BB_Upper'] - df['BB_Lower']) / df['BB_Middle']
    return df


def calculate_rsi(df, period=14):
    """Calculate RSI"""
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))
    return df


def calculate_ema(df, periods=[9, 21, 50, 200]):
    """Calculate EMA for multiple periods (including trend EMAs)"""
    for period in periods:
        df[f'EMA_{period}'] = df['Close'].ewm(span=period, adjust=False).mean()
    return df


def calculate_support_resistance(df, window=20):
    """Calculate support and resistance levels"""
    df['Support'] = df['Low'].rolling(window=window).min()
    df['Resistance'] = df['High'].rolling(window=window).max()
    return df


def calculate_all_indicators(df):
    """Calculate all technical indicators"""
    df = calculate_bollinger_bands(df)
    df = calculate_rsi(df)
    df = calculate_ema(df, [9, 21, 50, 200])
    df = calculate_support_resistance(df)
    return df


# ==============================================================================
# Strategy 1: Bollinger Band Mean Reversion
# ==============================================================================

def strategy_bollinger_bands(df, initial_capital=100000, position_size=0.95):
    """
    Buy when price touches lower band, sell when price reaches middle band

    Args:
        df: DataFrame with price data
        initial_capital: Initial capital in KRW
        position_size: Portion of capital to use (0.95 = 95%)
    """
    capital = initial_capital
    position = 0
    entry_price = 0
    trades = []

    for i in range(len(df)):
        if pd.isna(df.loc[i, 'BB_Lower']):
            continue

        close = df.loc[i, 'Close']
        bb_lower = df.loc[i, 'BB_Lower']
        bb_middle = df.loc[i, 'BB_Middle']
        bb_upper = df.loc[i, 'BB_Upper']

        # Entry: Buy when price <= lower band
        if position == 0 and close <= bb_lower * 1.001:  # 0.1% tolerance
            quantity = (capital * position_size) / close
            position = quantity
            entry_price = close
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'BUY',
                'price': close,
                'quantity': quantity,
                'capital': capital
            })

        # Exit: Sell when price >= middle band
        elif position > 0 and close >= bb_middle * 0.999:  # 0.1% tolerance
            capital = position * close
            profit = (close - entry_price) * position
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'SELL',
                'price': close,
                'quantity': position,
                'profit': profit,
                'capital': capital
            })
            position = 0
            entry_price = 0

    # Close any open position at the end
    if position > 0:
        close = df.loc[len(df)-1, 'Close']
        capital = position * close
        profit = (close - entry_price) * position
        trades.append({
            'timestamp': df.loc[len(df)-1, 'timestamp'],
            'type': 'SELL',
            'price': close,
            'quantity': position,
            'profit': profit,
            'capital': capital
        })

    return trades, capital


# ==============================================================================
# Strategy 2: RSI Oversold/Overbought
# ==============================================================================

def strategy_rsi(df, initial_capital=100000, position_size=0.95, rsi_low=30, rsi_high=70):
    """
    Buy when RSI < 30 (oversold), sell when RSI > 70 (overbought)
    """
    capital = initial_capital
    position = 0
    entry_price = 0
    trades = []

    for i in range(len(df)):
        if pd.isna(df.loc[i, 'RSI']):
            continue

        close = df.loc[i, 'Close']
        rsi = df.loc[i, 'RSI']

        # Entry: Buy when RSI < 30
        if position == 0 and rsi < rsi_low:
            quantity = (capital * position_size) / close
            position = quantity
            entry_price = close
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'BUY',
                'price': close,
                'quantity': quantity,
                'capital': capital,
                'rsi': rsi
            })

        # Exit: Sell when RSI > 70
        elif position > 0 and rsi > rsi_high:
            capital = position * close
            profit = (close - entry_price) * position
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'SELL',
                'price': close,
                'quantity': position,
                'profit': profit,
                'capital': capital,
                'rsi': rsi
            })
            position = 0
            entry_price = 0

    # Close any open position
    if position > 0:
        close = df.loc[len(df)-1, 'Close']
        capital = position * close
        profit = (close - entry_price) * position
        trades.append({
            'timestamp': df.loc[len(df)-1, 'timestamp'],
            'type': 'SELL',
            'price': close,
            'quantity': position,
            'profit': profit,
            'capital': capital
        })

    return trades, capital


# ==============================================================================
# Strategy 3: EMA Crossover
# ==============================================================================

def strategy_ema_crossover(df, initial_capital=100000, position_size=0.95):
    """
    Buy when EMA9 crosses above EMA21, sell when EMA9 crosses below EMA21
    """
    capital = initial_capital
    position = 0
    entry_price = 0
    trades = []

    for i in range(1, len(df)):
        if pd.isna(df.loc[i, 'EMA_9']) or pd.isna(df.loc[i, 'EMA_21']):
            continue

        close = df.loc[i, 'Close']
        ema9_prev = df.loc[i-1, 'EMA_9']
        ema21_prev = df.loc[i-1, 'EMA_21']
        ema9 = df.loc[i, 'EMA_9']
        ema21 = df.loc[i, 'EMA_21']

        # Entry: EMA9 crosses above EMA21 (bullish)
        if position == 0 and ema9_prev <= ema21_prev and ema9 > ema21:
            quantity = (capital * position_size) / close
            position = quantity
            entry_price = close
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'BUY',
                'price': close,
                'quantity': quantity,
                'capital': capital
            })

        # Exit: EMA9 crosses below EMA21 (bearish)
        elif position > 0 and ema9_prev >= ema21_prev and ema9 < ema21:
            capital = position * close
            profit = (close - entry_price) * position
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'SELL',
                'price': close,
                'quantity': position,
                'profit': profit,
                'capital': capital
            })
            position = 0
            entry_price = 0

    # Close any open position
    if position > 0:
        close = df.loc[len(df)-1, 'Close']
        capital = position * close
        profit = (close - entry_price) * position
        trades.append({
            'timestamp': df.loc[len(df)-1, 'timestamp'],
            'type': 'SELL',
            'price': close,
            'quantity': position,
            'profit': profit,
            'capital': capital
        })

    return trades, capital


# ==============================================================================
# Strategy 4: Combined Multi-Strategy
# ==============================================================================

def strategy_combined(df, initial_capital=100000, position_size=0.95, fee_rate=0.0002):
    """
    Combined strategy using multiple signals with UPTREND FILTER for spot trading:
    - TREND FILTER: Only trade when EMA50 > EMA200 (uptrend)
    - Entry: (RSI < 35 OR price < BB_Lower) AND EMA9 trending up
    - Exit: (RSI > 65 OR price > BB_Upper) OR stop loss hit
    - Fees: 0.02% per trade (Coinone spot fee)
    """
    capital = initial_capital
    position = 0
    entry_price = 0
    trades = []
    stop_loss_pct = 0.02  # 2% stop loss

    for i in range(1, len(df)):
        if pd.isna(df.loc[i, 'RSI']) or pd.isna(df.loc[i, 'BB_Lower']):
            continue

        # Skip if trend EMAs not ready
        if pd.isna(df.loc[i, 'EMA_50']) or pd.isna(df.loc[i, 'EMA_200']):
            continue

        close = df.loc[i, 'Close']
        rsi = df.loc[i, 'RSI']
        bb_lower = df.loc[i, 'BB_Lower']
        bb_upper = df.loc[i, 'BB_Upper']
        ema9 = df.loc[i, 'EMA_9']
        ema9_prev = df.loc[i-1, 'EMA_9']
        ema50 = df.loc[i, 'EMA_50']
        ema200 = df.loc[i, 'EMA_200']

        # UPTREND FILTER (필수 - 현물은 롱만 가능)
        in_uptrend = ema50 > ema200

        # Entry signals (only in uptrend)
        rsi_signal = rsi < 35
        bb_signal = close <= bb_lower * 1.002
        ema_trending_up = ema9 > ema9_prev

        # Entry: Multiple confirming signals + UPTREND
        if position == 0 and in_uptrend and (rsi_signal or bb_signal) and ema_trending_up:
            # Apply fee on buy
            effective_capital = capital * (1 - fee_rate)
            quantity = (effective_capital * position_size) / close
            position = quantity
            entry_price = close
            trades.append({
                'timestamp': df.loc[i, 'timestamp'],
                'type': 'BUY',
                'price': close,
                'quantity': quantity,
                'capital': capital,
                'rsi': rsi,
                'ema50': ema50,
                'ema200': ema200,
                'signal': 'RSI' if rsi_signal else 'BB',
                'trend': 'UPTREND'
            })

        # Exit signals
        if position > 0:
            rsi_exit = rsi > 65
            bb_exit = close >= bb_upper * 0.998
            stop_loss_hit = close <= entry_price * (1 - stop_loss_pct)
            # Also exit if trend turns bearish
            trend_reversal = ema50 <= ema200

            if rsi_exit or bb_exit or stop_loss_hit or trend_reversal:
                # Apply fee on sell
                gross_proceeds = position * close
                capital = gross_proceeds * (1 - fee_rate)
                profit = capital - (entry_price * position * (1 - fee_rate))  # Net profit after fees
                trades.append({
                    'timestamp': df.loc[i, 'timestamp'],
                    'type': 'SELL',
                    'price': close,
                    'quantity': position,
                    'profit': profit,
                    'capital': capital,
                    'rsi': rsi,
                    'exit_reason': 'TREND_REVERSAL' if trend_reversal else ('STOP_LOSS' if stop_loss_hit else ('RSI' if rsi_exit else 'BB'))
                })
                position = 0
                entry_price = 0

    # Close any open position
    if position > 0:
        close = df.loc[len(df)-1, 'Close']
        gross_proceeds = position * close
        capital = gross_proceeds * (1 - fee_rate)
        profit = capital - (entry_price * position * (1 - fee_rate))
        trades.append({
            'timestamp': df.loc[len(df)-1, 'timestamp'],
            'type': 'SELL',
            'price': close,
            'quantity': position,
            'profit': profit,
            'capital': capital,
            'exit_reason': 'END'
        })

    return trades, capital


# ==============================================================================
# Backtest Analysis
# ==============================================================================

def analyze_trades(trades, initial_capital, strategy_name):
    """Analyze trading performance"""
    if len(trades) == 0:
        return {
            'strategy': strategy_name,
            'total_trades': 0,
            'final_capital': initial_capital,
            'profit': 0,
            'return_pct': 0
        }

    buy_trades = [t for t in trades if t['type'] == 'BUY']
    sell_trades = [t for t in trades if t['type'] == 'SELL']

    final_capital = trades[-1]['capital'] if trades[-1]['type'] == 'SELL' else initial_capital
    total_profit = final_capital - initial_capital
    return_pct = (total_profit / initial_capital) * 100

    profits = [t.get('profit', 0) for t in sell_trades]
    winning_trades = [p for p in profits if p > 0]
    losing_trades = [p for p in profits if p < 0]

    win_rate = (len(winning_trades) / len(sell_trades) * 100) if sell_trades else 0
    avg_profit = np.mean(profits) if profits else 0
    max_profit = max(profits) if profits else 0
    max_loss = min(profits) if profits else 0

    return {
        'strategy': strategy_name,
        'total_trades': len(buy_trades),
        'winning_trades': len(winning_trades),
        'losing_trades': len(losing_trades),
        'win_rate': win_rate,
        'final_capital': final_capital,
        'profit': total_profit,
        'return_pct': return_pct,
        'avg_profit': avg_profit,
        'max_profit': max_profit,
        'max_loss': max_loss
    }


def print_results(results):
    """Print backtest results in a formatted table"""
    print("\n" + "="*80)
    print("BACKTEST RESULTS")
    print("="*80)
    print(f"{'Strategy':<25} {'Trades':<8} {'Win Rate':<10} {'Return %':<12} {'Profit (KRW)':<15}")
    print("-"*80)

    for r in results:
        print(f"{r['strategy']:<25} {r['total_trades']:<8} "
              f"{r['win_rate']:<10.1f} {r['return_pct']:<12.2f} {r['profit']:<15,.0f}")

    print("="*80)

    # Find best strategy
    best = max(results, key=lambda x: x['return_pct'])
    print(f"\n🏆 BEST STRATEGY: {best['strategy']}")
    print(f"   Return: {best['return_pct']:.2f}% ({best['profit']:,.0f} KRW)")
    print(f"   Win Rate: {best['win_rate']:.1f}%")
    print(f"   Total Trades: {best['total_trades']}")
    print(f"   Avg Profit per Trade: {best.get('avg_profit', 0):,.0f} KRW")
    print()


# ==============================================================================
# Main Execution
# ==============================================================================

def main():
    # Configuration
    INITIAL_CAPITAL = 100000  # 10만원
    POSITION_SIZE = 0.95      # 95% of capital per trade
    DAYS = 30                 # 30 days of data (increased for statistical significance)
    FEE_RATE = 0.0002         # 0.02% Coinone spot trading fee

    print("="*80)
    print("COINONE XRP SCALPING STRATEGY BACKTEST (SPOT TRADING)")
    print("="*80)
    print(f"Initial Capital: {INITIAL_CAPITAL:,} KRW")
    print(f"Position Size: {POSITION_SIZE*100:.0f}%")
    print(f"Period: {DAYS} days")
    print(f"Trading Fee: {FEE_RATE*100:.2f}% per trade")
    print(f"Strategy: LONG ONLY (spot) with UPTREND FILTER")
    print()

    # Fetch data
    df = fetch_coinone_chart(target_currency='XRP', interval='5m', days=DAYS)

    # Calculate indicators
    print("\nCalculating technical indicators...")
    df = calculate_all_indicators(df)
    print("✓ Indicators calculated")

    # Run strategies
    print("\nRunning backtests...")
    results = []

    print("  1. Bollinger Band Mean Reversion...")
    trades_bb, capital_bb = strategy_bollinger_bands(df, INITIAL_CAPITAL, POSITION_SIZE)
    results.append(analyze_trades(trades_bb, INITIAL_CAPITAL, "Bollinger Bands"))

    print("  2. RSI Oversold/Overbought...")
    trades_rsi, capital_rsi = strategy_rsi(df, INITIAL_CAPITAL, POSITION_SIZE)
    results.append(analyze_trades(trades_rsi, INITIAL_CAPITAL, "RSI"))

    print("  3. EMA Crossover...")
    trades_ema, capital_ema = strategy_ema_crossover(df, INITIAL_CAPITAL, POSITION_SIZE)
    results.append(analyze_trades(trades_ema, INITIAL_CAPITAL, "EMA Crossover"))

    print("  4. Combined Multi-Strategy (with Uptrend Filter)...")
    trades_combined, capital_combined = strategy_combined(df, INITIAL_CAPITAL, POSITION_SIZE, FEE_RATE)
    results.append(analyze_trades(trades_combined, INITIAL_CAPITAL, "Combined Strategy (Uptrend)"))

    # Print results
    print_results(results)

    # Save detailed results
    output = {
        'config': {
            'initial_capital': INITIAL_CAPITAL,
            'position_size': POSITION_SIZE,
            'period_days': DAYS,
            'data_points': len(df)
        },
        'results': results,
        'trades': {
            'bollinger_bands': trades_bb,
            'rsi': trades_rsi,
            'ema_crossover': trades_ema,
            'combined': trades_combined
        }
    }

    with open('coinone_xrp_backtest_results.json', 'w') as f:
        json.dump(output, f, indent=2, default=str)

    print(f"✓ Detailed results saved to: coinone_xrp_backtest_results.json")


if __name__ == '__main__':
    main()
