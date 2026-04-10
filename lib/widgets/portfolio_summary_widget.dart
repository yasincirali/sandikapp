import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/portfolio_provider.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  const PortfolioSummaryWidget({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isPositive = state.gainLoss >= 0;
    final gainColor = isPositive ? Colors.green : Colors.red;
    final cs = Theme.of(context).colorScheme;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.00', 'tr_TR');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total value
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toplam Portföy Değeri',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tryFmt.format(state.totalValue),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (state.isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),

            const Divider(height: 24),

            // Gain / Loss row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kar / Zarar',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isPositive
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: gainColor,
                            size: 16,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            tryFmt.format(state.gainLoss),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: gainColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Getiri',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      '%${state.gainLossPercent.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: gainColor),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // FX rate chips + last updated
            Row(
              children: [
                _rateChip('USD', numFmt.format(state.usdTry)),
                const SizedBox(width: 8),
                _rateChip('EUR', numFmt.format(state.eurTry)),
                const SizedBox(width: 8),
                _rateChip('GBP', numFmt.format(state.gbpTry)),
                const Spacer(),
                if (state.lastUpdated != null)
                  Text(
                    DateFormat('HH:mm').format(state.lastUpdated!),
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
              ],
            ),

            // Error banner
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rateChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
