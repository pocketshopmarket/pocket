import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SellerPayoutHistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> payouts;

  const SellerPayoutHistoryScreen({super.key, required this.payouts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Payout history'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: SafeArea(
        child: payouts.isEmpty
            ? Center(
                child: Text(
                  'No payout history',
                  style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: payouts.length,
                itemBuilder: (context, index) {
                  final row = payouts[index];
                  final amountColor = row['amount_color'] == 'green'
                      ? AppTheme.success
                      : AppTheme.warning;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row['order_number']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  row['status']?.toString().toUpperCase() ?? 'PENDING',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'ZMW ${row['amount'] ?? '0'}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
