import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_balance_provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_withdrawal_provider.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';

/// Coinone withdrawal screen
///
/// Responsibility: Handle cryptocurrency withdrawals
///
/// Features:
/// - Coin selection
/// - Address input with validation
/// - Recent address selection
/// - Amount input
/// - Withdrawal confirmation
class CoinoneWithdrawalScreen extends StatefulWidget {
  const CoinoneWithdrawalScreen({super.key});

  @override
  State<CoinoneWithdrawalScreen> createState() => _CoinoneWithdrawalScreenState();
}

class _CoinoneWithdrawalScreenState extends State<CoinoneWithdrawalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _labelController = TextEditingController();

  String _selectedCoin = 'BTC';

  @override
  void initState() {
    super.initState();

    // Load recent addresses for default coin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CoinoneWithdrawalProvider>().loadRecentAddresses(_selectedCoin);
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _onCoinChanged(String? coin) {
    if (coin == null) return;

    setState(() {
      _selectedCoin = coin;
      _addressController.clear();
      _amountController.clear();
    });

    // Load recent addresses for selected coin
    context.read<CoinoneWithdrawalProvider>().loadRecentAddresses(coin);
  }

  Future<void> _submitWithdrawal() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<CoinoneWithdrawalProvider>();
    final address = _addressController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    final label = _labelController.text.trim();

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('올바른 수량을 입력하세요'),
          backgroundColor: ThemeConstants.errorColor,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('출금 확인'),
        content: Text(
          '코인: $_selectedCoin\n'
          '주소: $address\n'
          '수량: $amount\n\n'
          '출금하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.errorColor,
            ),
            child: const Text('출금'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Execute withdrawal
    final success = await provider.withdrawCoin(
      coin: _selectedCoin,
      address: address,
      amount: amount,
      label: label.isNotEmpty ? label : null,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('출금이 요청되었습니다'),
          backgroundColor: ThemeConstants.successColor,
        ),
      );

      // Clear form
      _addressController.clear();
      _amountController.clear();
      _labelController.clear();

      // Refresh balance
      context.read<CoinoneBalanceProvider>().fetchBalance();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? '출금 실패'),
          backgroundColor: ThemeConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('출금'),
        backgroundColor: ThemeConstants.primaryColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Warning message
                Container(
                  padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(width: ThemeConstants.spacingSmall),
                      Expanded(
                        child: Text(
                          '출금 주소를 정확히 확인하세요.\n잘못된 주소로 전송 시 복구가 불가능합니다.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingLarge),

                // Balance display
                _buildBalanceCard(),
                const SizedBox(height: ThemeConstants.spacingLarge),

                // Coin selector
                _buildCoinSelector(),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Recent addresses
                _buildRecentAddresses(),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Address input
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: '출금 주소',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance_wallet),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '출금 주소를 입력하세요';
                    }

                    final provider = context.read<CoinoneWithdrawalProvider>();
                    if (!provider.isValidAddress(_selectedCoin, value.trim())) {
                      return '올바르지 않은 주소 형식입니다';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Amount input
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: '수량',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.payments),
                    suffixText: _selectedCoin,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,8}')),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '수량을 입력하세요';
                    }

                    final amount = double.tryParse(value.trim());
                    if (amount == null || amount <= 0) {
                      return '올바른 수량을 입력하세요';
                    }

                    // Check balance
                    final balance = context
                        .read<CoinoneBalanceProvider>()
                        .getAvailableBalance(_selectedCoin);
                    if (amount > balance) {
                      return '잔고가 부족합니다 (사용 가능: $balance)';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Label input (optional)
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: '주소 라벨 (선택)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                    hintText: '예: 내 지갑, 거래소 등',
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingLarge),

                // Submit button
                Consumer<CoinoneWithdrawalProvider>(
                  builder: (context, provider, child) {
                    if (provider.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ElevatedButton.icon(
                      onPressed: _submitWithdrawal,
                      icon: const Icon(Icons.send),
                      label: const Text(
                        '출금',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.errorColor,
                        padding: const EdgeInsets.symmetric(
                          vertical: ThemeConstants.spacingMedium,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Consumer<CoinoneBalanceProvider>(
      builder: (context, provider, child) {
        final balance = provider.getBalance(_selectedCoin);

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💰 보유 잔고',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedCoin,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      balance?.available.toStringAsFixed(8) ?? '0.00000000',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (balance != null && balance.pendingWithdrawal > 0) ...[
                  const SizedBox(height: ThemeConstants.spacingSmall),
                  Text(
                    '출금 대기: ${balance.pendingWithdrawal.toStringAsFixed(8)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoinSelector() {
    return Consumer<CoinoneBalanceProvider>(
      builder: (context, balanceProvider, child) {
        // Get all coins with available balance > 0 (excluding KRW)
        final availableCoins = balanceProvider.balances.entries
            .where((entry) =>
                entry.key.toUpperCase() != 'KRW' &&
                entry.value.available > 0)
            .map((entry) => entry.key.toUpperCase())
            .toList();

        // Sort alphabetically
        availableCoins.sort();

        // If no coins available, show placeholder
        if (availableCoins.isEmpty) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey),
                  SizedBox(width: ThemeConstants.spacingSmall),
                  Expanded(
                    child: Text(
                      '출금 가능한 코인이 없습니다',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Make sure selected coin is in the list, otherwise select first available
        if (!availableCoins.contains(_selectedCoin)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onCoinChanged(availableCoins.first);
          });
        }

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Row(
              children: [
                const Text(
                  '코인 선택:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: ThemeConstants.spacingMedium),
                Expanded(
                  child: DropdownButton<String>(
                    value: availableCoins.contains(_selectedCoin)
                        ? _selectedCoin
                        : availableCoins.first,
                    isExpanded: true,
                    items: availableCoins
                        .map((coin) => DropdownMenuItem(
                              value: coin,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(coin),
                                  Text(
                                    balanceProvider.getAvailableBalance(coin)
                                        .toStringAsFixed(8),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _onCoinChanged,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentAddresses() {
    return Consumer<CoinoneWithdrawalProvider>(
      builder: (context, provider, child) {
        final addresses = provider.recentAddresses;

        if (addresses.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '최근 사용한 주소',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),
                ...addresses.map((address) => _buildAddressItem(address)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressItem(address) {
    return InkWell(
      onTap: () {
        _addressController.text = address.address;
        _labelController.text = address.label ?? '';
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
        padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.maskedAddress,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              color: ThemeConstants.errorColor,
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('주소 삭제'),
                    content: const Text('이 주소를 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.errorColor,
                        ),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  context
                      .read<CoinoneWithdrawalProvider>()
                      .deleteAddress(_selectedCoin, address.address);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
