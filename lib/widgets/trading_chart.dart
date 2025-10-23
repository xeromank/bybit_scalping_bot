import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/models/price_prediction_signal.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 프로페셔널 트레이딩 차트 위젯
///
/// 기능:
/// - 캔들스틱 차트 + 거래량
/// - 볼린저밴드, 이동평균선 오버레이
/// - RSI, MACD 하단 차트
/// - 예측 범위 표시
/// - 실시간 업데이트
/// - 터치 인터랙션 (줌, 드래그, 십자선)
class TradingChart extends StatefulWidget {
  final List<KlineData> klines;
  final PricePredictionSignal? prediction;
  final String symbol;
  final String interval;
  final double? predictedHigh;
  final double? predictedLow;

  const TradingChart({
    Key? key,
    required this.klines,
    this.prediction,
    required this.symbol,
    required this.interval,
    this.predictedHigh,
    this.predictedLow,
  }) : super(key: key);

  @override
  State<TradingChart> createState() => _TradingChartState();
}

class _TradingChartState extends State<TradingChart> {
  late TrackballBehavior _trackballBehavior;
  late ZoomPanBehavior _zoomPanBehavior;

  /// interval에서 분 단위 숫자 추출 ("5m" -> 5, "5" -> 5)
  int _parseIntervalMinutes(String interval) {
    // "m" 제거하고 숫자만 파싱
    final cleaned = interval.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 5;
  }

  @override
  void initState() {
    super.initState();

    // 십자선 설정
    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.longPress,
      tooltipSettings: const InteractiveTooltip(
        enable: true,
        color: Color(0xFF1E1E1E),
        textStyle: TextStyle(color: Colors.white, fontSize: 12),
      ),
      lineColor: Colors.grey,
      lineDashArray: const [5, 5],
    );

    // 줌/팬 설정
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enableDoubleTapZooming: true,
      enablePanning: true,
      enableSelectionZooming: false,
      zoomMode: ZoomMode.x,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.klines.isEmpty) {
      return const Center(
        child: Text('차트 데이터가 없습니다'),
      );
    }

    // 지표 계산
    final closePrices = widget.klines.map((k) => k.close).toList();
    final bb = calculateBollingerBands(closePrices, 20, 2.0);
    final ma9 = _calculateMA(closePrices, 9);
    final ma21 = _calculateMA(closePrices, 21);
    final ma50 = _calculateMA(closePrices, 50);
    final rsiValues = _calculateRSISeries(closePrices, 14);
    final macdSeries = calculateMACDFullSeries(closePrices);

    return Container(
      color: const Color(0xFF0E0E0E),
      child: Column(
        children: [
          // 헤더
          _buildHeader(),

          // 메인 차트 (캔들 + 지표 + 볼륨)
          Expanded(
            flex: 5,
            child: _buildMainChartWithVolume(bb, ma9, ma21, ma50),
          ),

          // RSI 차트
          Expanded(
            flex: 2,
            child: _buildRSIChart(rsiValues),
          ),

          // MACD 차트
          Expanded(
            flex: 2,
            child: _buildMACDChart(macdSeries),
          ),
        ],
      ),
    );
  }

  /// 헤더 (심볼, 가격, 예측 정보, RSI/MACD)
  Widget _buildHeader() {
    final latestKline = widget.klines.last;
    final priceChange = latestKline.close - widget.klines.first.close;
    final priceChangePercent = (priceChange / widget.klines.first.close) * 100;
    final isUp = priceChange >= 0;

    // RSI 계산 (마지막 값)
    final closePrices = widget.klines.map((k) => k.close).toList();
    final rsiValues = _calculateRSISeries(closePrices, 14);
    final currentRSI = rsiValues.isNotEmpty ? rsiValues.last : 0.0;

    // MACD 계산 (마지막 값)
    final macdSeries = calculateMACDFullSeries(closePrices);
    final currentMACD = macdSeries.isNotEmpty ? macdSeries.last : null;

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 심볼 + 인터벌
          Row(
            children: [
              Text(
                widget.symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.interval,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 현재가 + 변화율
          Row(
            children: [
              Text(
                '\$${latestKline.close.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isUp ? Colors.green : Colors.red,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${isUp ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePercent.toStringAsFixed(2)}%)',
                style: TextStyle(
                  color: isUp ? Colors.green : Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          // RSI + MACD 수치 표시
          const SizedBox(height: 8),
          Row(
            children: [
              // RSI
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: currentRSI > 70
                      ? Colors.red.withOpacity(0.2)
                      : currentRSI < 30
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text(
                      'RSI ',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                    Text(
                      currentRSI.toStringAsFixed(1),
                      style: TextStyle(
                        color: currentRSI > 70
                            ? Colors.red
                            : currentRSI < 30
                                ? Colors.green
                                : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // MACD
              if (currentMACD != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'MACD ',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                      Text(
                        currentMACD.macdLine.toStringAsFixed(2),
                        style: TextStyle(
                          color: currentMACD.macdLine > currentMACD.signalLine
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // 실시간 예측 정보
          if (widget.predictedHigh != null && widget.predictedLow != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_graph, color: Colors.blue, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '다음 캔들 예측: ',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  Text(
                    '\$${widget.predictedLow!.toStringAsFixed(2)} ~ \$${widget.predictedHigh!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 메인 차트 (캔들 + BB + MA + 예측 + 볼륨)
  Widget _buildMainChartWithVolume(
    BollingerBands bb,
    List<double> ma9,
    List<double> ma21,
    List<double> ma50,
  ) {
    return SfCartesianChart(
      backgroundColor: const Color(0xFF0E0E0E),
      plotAreaBackgroundColor: const Color(0xFF0E0E0E),
      trackballBehavior: _trackballBehavior,
      zoomPanBehavior: _zoomPanBehavior,

      primaryXAxis: DateTimeAxis(
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
      ),

      primaryYAxis: NumericAxis(
        name: 'priceAxis',
        opposedPosition: true,
        majorGridLines: MajorGridLines(
          width: 0.5,
          color: Colors.grey.withOpacity(0.1),
        ),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
      ),

      // 볼륨용 보조 Y축
      axes: <ChartAxis>[
        NumericAxis(
          name: 'volumeAxis',
          opposedPosition: false,
          majorGridLines: const MajorGridLines(width: 0),
          majorTickLines: const MajorTickLines(width: 0),
          axisLine: const AxisLine(width: 0),
          labelStyle: const TextStyle(color: Colors.transparent, fontSize: 0), // 라벨 숨김
          minimum: 0,
          // 볼륨 차트가 전체 높이의 20%만 차지하도록 설정
          maximumLabelWidth: 0,
        ),
      ],

      series: <CartesianSeries>[
        // 볼륨 바 (맨 뒤에 배치, 투명도 적용)
        ColumnSeries<KlineData, DateTime>(
          dataSource: widget.klines,
          xValueMapper: (KlineData k, _) => k.timestamp,
          yValueMapper: (KlineData k, _) => k.volume,
          yAxisName: 'volumeAxis',
          pointColorMapper: (KlineData k, _) =>
              k.close >= k.open
                  ? const Color(0xFF26A69A).withOpacity(0.3)
                  : const Color(0xFFEF5350).withOpacity(0.3),
          borderWidth: 0,
        ),

        // 캔들스틱
        CandleSeries<KlineData, DateTime>(
          dataSource: widget.klines,
          xValueMapper: (KlineData k, _) => k.timestamp,
          lowValueMapper: (KlineData k, _) => k.low,
          highValueMapper: (KlineData k, _) => k.high,
          openValueMapper: (KlineData k, _) => k.open,
          closeValueMapper: (KlineData k, _) => k.close,
          yAxisName: 'priceAxis',
          enableSolidCandles: true,
          bullColor: const Color(0xFF26A69A),
          bearColor: const Color(0xFFEF5350),
        ),

        // 볼린저 밴드 상단
        LineSeries<_ChartData, DateTime>(
          dataSource: _createBBData(bb.upper),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.purple.withOpacity(0.5),
          width: 1,
          dashArray: const [5, 5],
        ),

        // 볼린저 밴드 중간
        LineSeries<_ChartData, DateTime>(
          dataSource: _createBBData(bb.middle),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.purple.withOpacity(0.3),
          width: 1,
        ),

        // 볼린저 밴드 하단
        LineSeries<_ChartData, DateTime>(
          dataSource: _createBBData(bb.lower),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.purple.withOpacity(0.5),
          width: 1,
          dashArray: const [5, 5],
        ),

        // MA 9
        LineSeries<_ChartData, DateTime>(
          dataSource: _createMAData(ma9),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.yellow.withOpacity(0.8),
          width: 1.5,
        ),

        // MA 21
        LineSeries<_ChartData, DateTime>(
          dataSource: _createMAData(ma21),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.orange.withOpacity(0.8),
          width: 1.5,
        ),

        // MA 50
        LineSeries<_ChartData, DateTime>(
          dataSource: _createMAData(ma50),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          yAxisName: 'priceAxis',
          color: Colors.cyan.withOpacity(0.8),
          width: 1.5,
        ),

        // 예측 범위 (다음 캔들 위치)
        if (widget.prediction != null)
          RangeAreaSeries<_PredictionZone, DateTime>(
            dataSource: [
              _PredictionZone(
                time: widget.klines.last.timestamp.add(
                  Duration(minutes: _parseIntervalMinutes(widget.interval)),
                ),
                high: widget.prediction!.predictedHigh,
                low: widget.prediction!.predictedLow,
              ),
            ],
            xValueMapper: (_PredictionZone z, _) => z.time,
            highValueMapper: (_PredictionZone z, _) => z.high,
            lowValueMapper: (_PredictionZone z, _) => z.low,
            yAxisName: 'priceAxis',
            color: Colors.blue.withOpacity(0.2),
            borderColor: Colors.blue,
            borderWidth: 2,
          ),
      ],
    );
  }


  /// RSI 차트
  Widget _buildRSIChart(List<double> rsiValues) {
    return SfCartesianChart(
      backgroundColor: const Color(0xFF0E0E0E),
      plotAreaBackgroundColor: const Color(0xFF0E0E0E),
      title: ChartTitle(
        text: 'RSI (14)',
        textStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        alignment: ChartAlignment.near,
      ),

      primaryXAxis: DateTimeAxis(
        isVisible: false,
      ),

      primaryYAxis: NumericAxis(
        minimum: 0,
        maximum: 100,
        interval: 50,
        opposedPosition: true,
        majorGridLines: MajorGridLines(
          width: 0.5,
          color: Colors.grey.withOpacity(0.1),
        ),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 9),
        plotBands: <PlotBand>[
          PlotBand(
            start: 70,
            end: 100,
            color: Colors.red.withOpacity(0.1),
          ),
          PlotBand(
            start: 0,
            end: 30,
            color: Colors.green.withOpacity(0.1),
          ),
        ],
      ),

      series: <CartesianSeries>[
        LineSeries<_ChartData, DateTime>(
          dataSource: _createRSIData(rsiValues),
          xValueMapper: (_ChartData d, _) => d.time,
          yValueMapper: (_ChartData d, _) => d.value,
          color: Colors.purple,
          width: 1.5,
        ),
      ],
    );
  }

  /// MACD 차트
  Widget _buildMACDChart(List<MACD> macdSeries) {
    return SfCartesianChart(
      backgroundColor: const Color(0xFF0E0E0E),
      plotAreaBackgroundColor: const Color(0xFF0E0E0E),
      title: ChartTitle(
        text: 'MACD (12, 26, 9)',
        textStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        alignment: ChartAlignment.near,
      ),

      primaryXAxis: DateTimeAxis(
        isVisible: false,
      ),

      primaryYAxis: NumericAxis(
        opposedPosition: true,
        majorGridLines: MajorGridLines(
          width: 0.5,
          color: Colors.grey.withOpacity(0.1),
        ),
        axisLine: const AxisLine(width: 0),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 9),
      ),

      series: <CartesianSeries>[
        // 히스토그램
        ColumnSeries<_MACDData, DateTime>(
          dataSource: _createMACDData(macdSeries),
          xValueMapper: (_MACDData d, _) => d.time,
          yValueMapper: (_MACDData d, _) => d.histogram,
          pointColorMapper: (_MACDData d, _) =>
              d.histogram >= 0
                  ? const Color(0xFF26A69A).withOpacity(0.7)
                  : const Color(0xFFEF5350).withOpacity(0.7),
        ),

        // MACD 라인
        LineSeries<_MACDData, DateTime>(
          dataSource: _createMACDData(macdSeries),
          xValueMapper: (_MACDData d, _) => d.time,
          yValueMapper: (_MACDData d, _) => d.macd,
          color: Colors.blue,
          width: 1.5,
        ),

        // 시그널 라인
        LineSeries<_MACDData, DateTime>(
          dataSource: _createMACDData(macdSeries),
          xValueMapper: (_MACDData d, _) => d.time,
          yValueMapper: (_MACDData d, _) => d.signal,
          color: Colors.orange,
          width: 1.5,
        ),
      ],
    );
  }

  // Helper methods
  List<_ChartData> _createBBData(double value) {
    return widget.klines
        .map((k) => _ChartData(k.timestamp, value))
        .toList();
  }

  List<_ChartData> _createMAData(List<double> values) {
    final result = <_ChartData>[];
    for (int i = 0; i < widget.klines.length && i < values.length; i++) {
      result.add(_ChartData(widget.klines[i].timestamp, values[i]));
    }
    return result;
  }

  List<_ChartData> _createRSIData(List<double> values) {
    final result = <_ChartData>[];
    for (int i = 0; i < widget.klines.length && i < values.length; i++) {
      result.add(_ChartData(widget.klines[i].timestamp, values[i]));
    }
    return result;
  }

  List<_MACDData> _createMACDData(List<MACD> macdSeries) {
    final result = <_MACDData>[];
    for (int i = 0; i < widget.klines.length && i < macdSeries.length; i++) {
      result.add(_MACDData(
        widget.klines[i].timestamp,
        macdSeries[i].macdLine,
        macdSeries[i].signalLine,
        macdSeries[i].histogram,
      ));
    }
    return result;
  }

  List<double> _calculateMA(List<double> values, int period) {
    final result = <double>[];
    for (int i = 0; i < values.length; i++) {
      if (i < period - 1) {
        result.add(values[i]);
      } else {
        final sum = values.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
        result.add(sum / period);
      }
    }
    return result;
  }

  List<double> _calculateRSISeries(List<double> values, int period) {
    final result = <double>[];
    for (int i = 0; i < values.length; i++) {
      if (i < period) {
        result.add(50.0);
      } else {
        final rsi = calculateRSI(values.sublist(0, i + 1), period);
        result.add(rsi);
      }
    }
    return result;
  }
}

class _ChartData {
  final DateTime time;
  final double value;
  _ChartData(this.time, this.value);
}

class _MACDData {
  final DateTime time;
  final double macd;
  final double signal;
  final double histogram;
  _MACDData(this.time, this.macd, this.signal, this.histogram);
}

class _PredictionZone {
  final DateTime time;
  final double high;
  final double low;
  _PredictionZone({required this.time, required this.high, required this.low});
}
