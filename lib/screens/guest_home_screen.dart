import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/screens/live_chart_screen.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_traders_screen.dart';
import 'package:bybit_scalping_bot/screens/bybit_login_screen.dart';

/// 게스트 모드 홈 화면 (인증 불필요)
///
/// 퍼블릭 기능만 제공:
/// - 실시간 차트 보기
/// - Hyperliquid 트레이더 추적
class GuestHomeScreen extends StatelessWidget {
  const GuestHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.remove_red_eye, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text(
              '게스트 모드',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // 로그인 버튼
          TextButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const BybitLoginScreen(),
                ),
              );
            },
            icon: const Icon(Icons.login, color: Colors.blue, size: 20),
            label: const Text(
              '로그인',
              style: TextStyle(color: Colors.blue, fontSize: 14),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 안내 카드
          _buildInfoCard(),

          const SizedBox(height: 24),

          // 기능 카드들
          _buildFeatureCard(
            context: context,
            icon: Icons.show_chart,
            iconColor: Colors.green,
            title: '실시간 차트',
            description: '암호화폐 실시간 가격 차트와 기술적 지표를 확인하세요',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LiveChartScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          _buildFeatureCard(
            context: context,
            icon: Icons.track_changes,
            iconColor: Colors.blue,
            title: 'Hyperliquid 트레이더 추적',
            description: '전문 트레이더의 포지션과 수익률을 실시간으로 추적하세요',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HyperliquidTradersScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // 프리미엄 기능 안내
          _buildPremiumCard(context),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: const Color(0xFF2D2D2D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text(
                  '게스트 모드',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '로그인 없이 퍼블릭 기능을 사용할 수 있습니다.\n'
              '차트 조회와 트레이더 추적 기능이 제공됩니다.\n\n'
              '실제 거래를 원하시면 로그인해주세요.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF2D2D2D),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[600],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumCard(BuildContext context) {
    return Card(
      color: const Color(0xFF1E3A5F),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text(
                  '프리미엄 기능',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '로그인하면 다음 기능을 사용할 수 있습니다:',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            _buildPremiumFeature('자동 매매 봇 (Bybit 선물)'),
            _buildPremiumFeature('현물 거래 (Coinone)'),
            _buildPremiumFeature('실시간 잔고 및 포지션 관리'),
            _buildPremiumFeature('주문 체결 및 이력 조회'),
            _buildPremiumFeature('자산 출금 기능'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BybitLoginScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text(
                  '로그인하여 시작하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
