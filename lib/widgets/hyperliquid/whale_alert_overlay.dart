import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/services/hyperliquid/position_change_detector.dart';

/// 고래 알림 오버레이 위젯
///
/// 화면 상단에 스택 형태로 알림을 표시하고 자동으로 사라짐
class WhaleAlertOverlay extends StatefulWidget {
  final PositionChange change;
  final VoidCallback onDismiss;

  const WhaleAlertOverlay({
    Key? key,
    required this.change,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<WhaleAlertOverlay> createState() => _WhaleAlertOverlayState();
}

class _WhaleAlertOverlayState extends State<WhaleAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();

    // 5초 후 자동 닫기
    Future.delayed(const Duration(seconds: 5), () {
      _dismiss();
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getAlertColor() {
    switch (widget.change.type) {
      case PositionChangeType.newPosition:
        return Colors.blue;
      case PositionChangeType.closedPosition:
        return Colors.red;
      case PositionChangeType.sizeIncreased:
        return Colors.green;
      case PositionChangeType.sizeDecreased:
        return Colors.orange;
      case PositionChangeType.sideFlipped:
        return Colors.purple;
    }
  }

  IconData _getAlertIcon() {
    switch (widget.change.type) {
      case PositionChangeType.newPosition:
        return Icons.add_circle_outline;
      case PositionChangeType.closedPosition:
        return Icons.close_rounded;
      case PositionChangeType.sizeIncreased:
        return Icons.trending_up;
      case PositionChangeType.sizeDecreased:
        return Icons.trending_down;
      case PositionChangeType.sideFlipped:
        return Icons.swap_horiz;
    }
  }

  String _getAlertTitle() {
    switch (widget.change.type) {
      case PositionChangeType.newPosition:
        return '🐋 새 포지션 진입';
      case PositionChangeType.closedPosition:
        return '🔴 포지션 청산';
      case PositionChangeType.sizeIncreased:
        return '📈 포지션 추가';
      case PositionChangeType.sizeDecreased:
        return '📉 포지션 감소';
      case PositionChangeType.sideFlipped:
        return '🔄 방향 전환';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getAlertColor();
    final icon = _getAlertIcon();
    final title = _getAlertTitle();

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.9),
                    color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: _dismiss,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.change.trader.displayName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _buildAlertMessage(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _dismiss,
                        iconSize: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildAlertMessage() {
    final coin = widget.change.coin;

    switch (widget.change.type) {
      case PositionChangeType.newPosition:
        final side = widget.change.newData['side'];
        final size = widget.change.newData['size'] as double;
        return '$coin $side ${size.toStringAsFixed(4)}';

      case PositionChangeType.closedPosition:
        final side = widget.change.oldData['side'];
        final pnl = widget.change.oldData['unrealized_pnl'] as double;
        final pnlSign = pnl >= 0 ? '+' : '';
        return '$coin $side 청산 | PNL: $pnlSign\$${pnl.toStringAsFixed(2)}';

      case PositionChangeType.sizeIncreased:
        final oldSize = widget.change.oldData['size'] as double;
        final newSize = widget.change.newData['size'] as double;
        final diff = newSize - oldSize;
        return '$coin | ${oldSize.toStringAsFixed(4)} → ${newSize.toStringAsFixed(4)} (+${diff.toStringAsFixed(4)})';

      case PositionChangeType.sizeDecreased:
        final oldSize = widget.change.oldData['size'] as double;
        final newSize = widget.change.newData['size'] as double;
        final diff = oldSize - newSize;
        return '$coin | ${oldSize.toStringAsFixed(4)} → ${newSize.toStringAsFixed(4)} (-${diff.toStringAsFixed(4)})';

      case PositionChangeType.sideFlipped:
        final oldSide = widget.change.oldData['side'];
        final newSide = widget.change.newData['side'];
        return '$coin | $oldSide → $newSide';
    }
  }
}

/// 고래 알림 오버레이 관리자
class WhaleAlertOverlayManager {
  static final WhaleAlertOverlayManager _instance = WhaleAlertOverlayManager._internal();
  factory WhaleAlertOverlayManager() => _instance;
  WhaleAlertOverlayManager._internal();

  final List<OverlayEntry> _entries = [];
  OverlayState? _overlayState;

  void initialize(BuildContext context) {
    _overlayState = Overlay.of(context);
  }

  void showAlert(PositionChange change) {
    if (_overlayState == null) return;

    // 최대 3개까지만 표시
    if (_entries.length >= 3) {
      _removeOldest();
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        // 스택 오프셋 계산 (위에서부터 쌓임)
        final index = _entries.length;
        final topOffset = 50.0 + (index * 120.0); // 각 알림 간격

        return Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          child: WhaleAlertOverlay(
            change: change,
            onDismiss: () => _removeEntry(entry),
          ),
        );
      },
    );

    _entries.add(entry);
    _overlayState!.insert(entry);
  }

  void _removeEntry(OverlayEntry entry) {
    entry.remove();
    _entries.remove(entry);
  }

  void _removeOldest() {
    if (_entries.isNotEmpty) {
      final oldest = _entries.first;
      _removeEntry(oldest);
    }
  }

  void clearAll() {
    for (final entry in _entries) {
      entry.remove();
    }
    _entries.clear();
  }
}
