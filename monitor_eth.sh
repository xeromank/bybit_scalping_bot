#!/bin/bash

echo "========================================="
echo "ETH 실시간 모니터링 시작 (10초 간격)"
echo "========================================="
echo ""

while true; do
    # 현재 시간
    TIMESTAMP=$(date '+%H:%M:%S')

    # Bybit API - 현재가 조회
    TICKER=$(curl -s "https://api.bybit.com/v5/market/tickers?category=linear&symbol=ETHUSDT")
    PRICE=$(echo $TICKER | grep -o '"lastPrice":"[^"]*"' | cut -d'"' -f4)

    # Bybit API - 1분봉 최근 3개 조회
    KLINE=$(curl -s "https://api.bybit.com/v5/market/kline?category=linear&symbol=ETHUSDT&interval=1&limit=3")

    # 최근 캔들 정보 파싱 (간단하게)
    echo "[$TIMESTAMP] 현재가: \$$PRICE"
    echo "---"
    echo "$KLINE" | grep -o '"list":\[\[.*\]\]' | head -1
    echo ""
    echo "========================================="
    echo ""

    # 10초 대기
    sleep 10
done
