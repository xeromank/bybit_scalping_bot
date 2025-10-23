/// Hyperliquid 트레이더 정보
///
/// 저장된 트레이더의 기본 정보
class HyperliquidTrader {
  final String address; // 0x...
  final String? nickname; // 사용자 지정 닉네임
  final DateTime addedAt; // 추가된 시간

  const HyperliquidTrader({
    required this.address,
    this.nickname,
    required this.addedAt,
  });

  /// JSON 변환
  factory HyperliquidTrader.fromJson(Map<String, dynamic> json) {
    return HyperliquidTrader(
      address: json['address'] as String,
      nickname: json['nickname'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'nickname': nickname,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// 축약된 주소 (0x9263...cc7a)
  String get shortAddress {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// 표시 이름 (닉네임 또는 축약 주소)
  String get displayName => nickname ?? shortAddress;

  HyperliquidTrader copyWith({
    String? address,
    String? nickname,
    DateTime? addedAt,
  }) {
    return HyperliquidTrader(
      address: address ?? this.address,
      nickname: nickname ?? this.nickname,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  String toString() {
    return 'HyperliquidTrader(address: $address, nickname: $nickname)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HyperliquidTrader && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;
}
