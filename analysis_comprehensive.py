#!/usr/bin/env python3
"""
종합 차트 데이터 분석 스크립트
- 가격 변동성 분석
- RSI 다이버전스 탐지
- 볼린저 밴드 분석
- 거래량 프로파일 분석
- 지지/저항 레벨 탐지
- 백테스팅 시뮬레이션
"""

import json
import statistics
from datetime import datetime
from typing import List, Dict, Tuple
import math

class ComprehensiveAnalyzer:
    def __init__(self, candle_data: List[Dict]):
        self.candles = candle_data
        self.closes = [float(c['close']) for c in candle_data]
        self.highs = [float(c['high']) for c in candle_data]
        self.lows = [float(c['low']) for c in candle_data]
        self.volumes = [float(c['volume']) for c in candle_data]
        self.timestamps = [int(c['timestamp']) for c in candle_data]

    def analyze_volatility(self) -> Dict:
        """변동성 분석"""
        returns = [(self.closes[i] - self.closes[i-1]) / self.closes[i-1] * 100
                   for i in range(1, len(self.closes))]

        return {
            'std_dev': statistics.stdev(returns) if len(returns) > 1 else 0,
            'mean_return': statistics.mean(returns) if returns else 0,
            'max_return': max(returns) if returns else 0,
            'min_return': min(returns) if returns else 0,
            'volatility_score': statistics.stdev(returns) if len(returns) > 1 else 0
        }

    def detect_support_resistance(self, lookback: int = 20) -> Dict:
        """지지/저항 레벨 탐지"""
        # 최근 lookback 기간의 고점/저점 클러스터 찾기
        recent_highs = self.highs[-lookback:]
        recent_lows = self.lows[-lookback:]

        # 가격대별 빈도수 계산 (0.1% 단위로 그룹화)
        price_clusters = {}
        for high in recent_highs:
            bucket = round(high, -1)  # 10 단위로 반올림
            price_clusters[bucket] = price_clusters.get(bucket, 0) + 1

        for low in recent_lows:
            bucket = round(low, -1)
            price_clusters[bucket] = price_clusters.get(bucket, 0) + 1

        # 가장 많이 터치된 레벨 (저항/지지)
        sorted_levels = sorted(price_clusters.items(), key=lambda x: x[1], reverse=True)

        return {
            'resistance_levels': [level for level, _ in sorted_levels[:3]],
            'support_levels': [level for level, _ in sorted_levels[-3:]],
            'current_price': self.closes[-1],
            'distance_to_resistance': min([abs(self.closes[-1] - level) for level, _ in sorted_levels[:3]]) if sorted_levels else 0,
            'distance_to_support': min([abs(self.closes[-1] - level) for level, _ in sorted_levels[-3:]]) if sorted_levels else 0
        }

    def analyze_volume_profile(self) -> Dict:
        """거래량 프로파일 분석"""
        recent_volume = self.volumes[-20:]
        avg_volume = statistics.mean(self.volumes) if self.volumes else 0
        current_volume = self.volumes[-1]

        # 거래량 증가 추세
        volume_trend = []
        for i in range(len(self.volumes) - 10, len(self.volumes)):
            if i > 0:
                volume_trend.append(self.volumes[i] - self.volumes[i-1])

        return {
            'avg_volume': avg_volume,
            'current_volume': current_volume,
            'volume_ratio': current_volume / avg_volume if avg_volume > 0 else 0,
            'volume_increasing': sum(volume_trend) > 0 if volume_trend else False,
            'high_volume_breakout': current_volume > avg_volume * 1.5
        }

    def detect_rsi_divergence(self) -> Dict:
        """RSI 다이버전스 탐지"""
        if len(self.candles) < 20:
            return {'bullish_divergence': False, 'bearish_divergence': False}

        # 최근 20개 캔들에서 가격과 RSI의 방향성 비교
        recent_candles = self.candles[-20:]

        price_highs = []
        price_lows = []
        rsi_highs = []
        rsi_lows = []

        for i in range(1, len(recent_candles) - 1):
            price = float(recent_candles[i]['close'])
            rsi = float(recent_candles[i].get('rsi14', recent_candles[i].get('rsi_14', 50)))

            # 고점/저점 탐지
            if (float(recent_candles[i-1]['close']) < price and
                price > float(recent_candles[i+1]['close'])):
                price_highs.append((i, price))
                rsi_highs.append((i, rsi))

            if (float(recent_candles[i-1]['close']) > price and
                price < float(recent_candles[i+1]['close'])):
                price_lows.append((i, price))
                rsi_lows.append((i, rsi))

        # 강세 다이버전스: 가격은 낮아지는데 RSI는 높아짐
        bullish_div = False
        if len(price_lows) >= 2 and len(rsi_lows) >= 2:
            if price_lows[-1][1] < price_lows[-2][1] and rsi_lows[-1][1] > rsi_lows[-2][1]:
                bullish_div = True

        # 약세 다이버전스: 가격은 높아지는데 RSI는 낮아짐
        bearish_div = False
        if len(price_highs) >= 2 and len(rsi_highs) >= 2:
            if price_highs[-1][1] > price_highs[-2][1] and rsi_highs[-1][1] < rsi_highs[-2][1]:
                bearish_div = True

        return {
            'bullish_divergence': bullish_div,
            'bearish_divergence': bearish_div,
            'price_lows_count': len(price_lows),
            'price_highs_count': len(price_highs)
        }

    def calculate_bollinger_bands(self, period: int = 20, std_dev: int = 2) -> Dict:
        """볼린저 밴드 계산"""
        if len(self.closes) < period:
            return {}

        recent_closes = self.closes[-period:]
        sma = statistics.mean(recent_closes)
        std = statistics.stdev(recent_closes) if len(recent_closes) > 1 else 0

        upper_band = sma + (std * std_dev)
        lower_band = sma - (std * std_dev)
        current_price = self.closes[-1]

        # 밴드 폭 (변동성 지표)
        band_width = ((upper_band - lower_band) / sma) * 100 if sma > 0 else 0

        # 현재 가격의 밴드 내 위치 (%)
        bb_position = ((current_price - lower_band) / (upper_band - lower_band)) * 100 if (upper_band - lower_band) > 0 else 50

        return {
            'upper_band': upper_band,
            'middle_band': sma,
            'lower_band': lower_band,
            'current_price': current_price,
            'band_width': band_width,
            'bb_position': bb_position,
            'squeeze': band_width < 2,  # 밴드 수축 (변동성 낮음, 돌파 임박)
            'near_lower_band': bb_position < 20,  # 하단 밴드 근처 (매수 기회)
            'near_upper_band': bb_position > 80   # 상단 밴드 근처 (매도 기회)
        }

    def analyze_trend(self, short_period: int = 10, long_period: int = 50) -> Dict:
        """추세 분석 (이동평균선 기반)"""
        if len(self.closes) < long_period:
            long_period = len(self.closes)
        if len(self.closes) < short_period:
            short_period = len(self.closes) // 2

        short_ma = statistics.mean(self.closes[-short_period:]) if short_period > 0 else self.closes[-1]
        long_ma = statistics.mean(self.closes[-long_period:]) if long_period > 0 else self.closes[-1]
        current_price = self.closes[-1]

        # 골든크로스/데드크로스
        golden_cross = short_ma > long_ma
        dead_cross = short_ma < long_ma

        # 가격과 이동평균선 관계
        above_short_ma = current_price > short_ma
        above_long_ma = current_price > long_ma

        return {
            'short_ma': short_ma,
            'long_ma': long_ma,
            'golden_cross': golden_cross,
            'dead_cross': dead_cross,
            'above_short_ma': above_short_ma,
            'above_long_ma': above_long_ma,
            'trend': 'uptrend' if golden_cross and above_long_ma else
                     'downtrend' if dead_cross and not above_long_ma else 'sideways'
        }

    def backtest_strategy(self, entry_conditions: Dict, tp_percent: float, sl_percent: float) -> Dict:
        """전략 백테스팅"""
        trades = []
        in_position = False
        entry_price = 0
        entry_index = 0

        for i in range(20, len(self.candles)):  # 최소 20개 데이터 필요
            candle = self.candles[i]
            price = float(candle['close'])

            if not in_position:
                # 진입 조건 체크
                if self._check_entry_conditions(i, entry_conditions):
                    in_position = True
                    entry_price = price
                    entry_index = i
            else:
                # 청산 조건 체크
                profit_pct = ((price - entry_price) / entry_price) * 100

                # TP/SL 체크
                if profit_pct >= tp_percent:
                    trades.append({
                        'entry': entry_price,
                        'exit': price,
                        'profit_pct': profit_pct,
                        'result': 'win',
                        'bars_held': i - entry_index
                    })
                    in_position = False
                elif profit_pct <= -sl_percent:
                    trades.append({
                        'entry': entry_price,
                        'exit': price,
                        'profit_pct': profit_pct,
                        'result': 'loss',
                        'bars_held': i - entry_index
                    })
                    in_position = False

        if not trades:
            return {'total_trades': 0, 'win_rate': 0, 'avg_profit': 0, 'avg_loss': 0}

        wins = [t for t in trades if t['result'] == 'win']
        losses = [t for t in trades if t['result'] == 'loss']

        return {
            'total_trades': len(trades),
            'wins': len(wins),
            'losses': len(losses),
            'win_rate': (len(wins) / len(trades)) * 100 if trades else 0,
            'avg_profit': statistics.mean([t['profit_pct'] for t in wins]) if wins else 0,
            'avg_loss': statistics.mean([t['profit_pct'] for t in losses]) if losses else 0,
            'avg_bars_held': statistics.mean([t['bars_held'] for t in trades]) if trades else 0,
            'profit_factor': abs(sum([t['profit_pct'] for t in wins]) / sum([t['profit_pct'] for t in losses])) if losses and sum([t['profit_pct'] for t in losses]) != 0 else 0
        }

    def _check_entry_conditions(self, index: int, conditions: Dict) -> bool:
        """진입 조건 체크 헬퍼"""
        if index < 20:
            return False

        candle = self.candles[index]

        # RSI 조건
        rsi14 = float(candle.get('rsi14', candle.get('rsi_14', 50)))
        rsi6 = float(candle.get('rsi6', candle.get('rsi_6', 50)))

        if 'rsi14_min' in conditions and rsi14 < conditions['rsi14_min']:
            return False
        if 'rsi14_max' in conditions and rsi14 > conditions['rsi14_max']:
            return False
        if 'rsi6_min' in conditions and rsi6 < conditions['rsi6_min']:
            return False
        if 'rsi6_max' in conditions and rsi6 > conditions['rsi6_max']:
            return False

        return True

    def comprehensive_analysis(self) -> Dict:
        """종합 분석 실행"""
        return {
            'volatility': self.analyze_volatility(),
            'support_resistance': self.detect_support_resistance(),
            'volume_profile': self.analyze_volume_profile(),
            'rsi_divergence': self.detect_rsi_divergence(),
            'bollinger_bands': self.calculate_bollinger_bands(),
            'trend': self.analyze_trend(),
            'summary': {
                'total_candles': len(self.candles),
                'timeframe': f"{self.timestamps[0]} to {self.timestamps[-1]}",
                'price_range': f"{min(self.lows)} - {max(self.highs)}",
                'current_price': self.closes[-1]
            }
        }


def analyze_symbol(symbol: str, interval: str, data: List[Dict]) -> Dict:
    """심볼별 분석"""
    analyzer = ComprehensiveAnalyzer(data)
    analysis = analyzer.comprehensive_analysis()

    # 다양한 전략 백테스팅
    strategies = {
        'rsi_oversold_bounce': {
            'rsi14_min': 30,
            'rsi14_max': 50,
            'rsi6_max': 30
        },
        'rsi_neutral_breakout': {
            'rsi14_min': 40,
            'rsi14_max': 60
        },
        'rsi_moderate': {
            'rsi14_min': 35,
            'rsi14_max': 55,
            'rsi6_min': 25,
            'rsi6_max': 40
        }
    }

    backtest_results = {}
    for strategy_name, conditions in strategies.items():
        backtest_results[strategy_name] = analyzer.backtest_strategy(
            conditions,
            tp_percent=0.5,  # 0.5% TP
            sl_percent=0.3   # 0.3% SL
        )

    analysis['backtests'] = backtest_results

    return {
        'symbol': symbol,
        'interval': interval,
        'analysis': analysis
    }


def main():
    """메인 분석 함수 - 실제 데이터로 교체 필요"""
    print("=== 종합 차트 분석 시작 ===\n")

    # 여기에 실제 차트 데이터를 로드해야 합니다
    # 예시: JSON 파일에서 로드하거나 API에서 직접 가져오기

    print("분석 스크립트 준비 완료")
    print("실제 데이터를 입력하면 다음 분석을 수행합니다:")
    print("1. 변동성 분석")
    print("2. 지지/저항 레벨 탐지")
    print("3. 거래량 프로파일 분석")
    print("4. RSI 다이버전스 탐지")
    print("5. 볼린저 밴드 분석")
    print("6. 추세 분석")
    print("7. 전략 백테스팅 (3가지 전략)")


if __name__ == "__main__":
    main()
