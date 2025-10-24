import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// 알림 설정 카드
///
/// BB 알림과 RSI 알림을 켜고 끌 수 있는 토글 버튼 제공
class AlertSettingsCard extends StatelessWidget {
  const AlertSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '알림 설정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // BB 알림 토글
                _buildAlertToggle(
                  context: context,
                  title: 'BB 알림',
                  subtitle: '4개 이상 타임프레임 BB 상단/하단 근접 시',
                  enabled: provider.bbAlertEnabled,
                  onToggle: () => provider.toggleBBAlert(),
                  icon: Icons.show_chart,
                  color: Colors.blue,
                ),

                const Divider(height: 24),

                // RSI 알림 토글
                _buildAlertToggle(
                  context: context,
                  title: 'RSI 알림',
                  subtitle: '과매수/과매도 3개 타임프레임 동시 충족 시',
                  enabled: provider.rsiAlertEnabled,
                  onToggle: () => provider.toggleRSIAlert(),
                  icon: Icons.trending_down,
                  color: Colors.purple,
                ),

                const SizedBox(height: 8),

                // 안내 문구
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '알림은 1분마다 최대 1회 발송됩니다',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertToggle({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onToggle,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // 아이콘
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // 텍스트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),

            // 토글 스위치
            Switch(
              value: enabled,
              onChanged: (_) => onToggle(),
              activeColor: color,
            ),
          ],
        ),
      ),
    );
  }
}
