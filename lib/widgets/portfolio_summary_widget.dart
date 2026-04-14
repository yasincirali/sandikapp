import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  const PortfolioSummaryWidget({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = state.gainLoss >= 0;
    final gainColor = isPositive
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final tryFmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.00', 'tr_TR');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary,
            cs.primary.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Dekoratif daire — postmodern aksan
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık + loading
                Row(
                  children: [
                    Text(
                      'TOPLAM PORTFÖY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    if (state.isLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    if (state.lastUpdated != null && !state.isLoading)
                      Text(
                        DateFormat('HH:mm').format(state.lastUpdated!),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 6),

                // Büyük tutar
                Text(
                  tryFmt.format(state.totalValue),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 10),

                // Kar/zarar satırı
                if (state.totalCost > 0) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: gainColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${isPositive ? '+' : ''}${tryFmt.format(state.gainLoss)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: gainColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${isPositive ? '+' : ''}%${state.gainLossPercent.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: gainColor.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 8),

                // Divider
                Divider(
                    color: Colors.white.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 10),

                // Döviz kurları + kategori özeti
                Row(
                  children: [
                    _fxChip('USD', numFmt.format(state.usdTry)),
                    const SizedBox(width: 6),
                    _fxChip('EUR', numFmt.format(state.eurTry)),
                    const SizedBox(width: 6),
                    _fxChip('GBP', numFmt.format(state.gbpTry)),
                  ],
                ),

                // Hata mesajı
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Kategori dağılım çubukları
                if (state.assets.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _categoryBar(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fxChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Kategori dağılım çubuğu
  Widget _categoryBar(BuildContext context) {
    final totals = <AssetType, double>{};
    for (final a in state.assets) {
      totals[a.type] =
          (totals[a.type] ?? 0) + state.toTRY(a.totalValue, a.currency);
    }
    if (totals.isEmpty || state.totalValue == 0) {
      return const SizedBox.shrink();
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar çubuğu
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: sorted.map((e) {
              final ratio = e.value / state.totalValue;
              return Expanded(
                flex: (ratio * 1000).round(),
                child: Container(
                  height: 5,
                  color: e.key.color,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: sorted.map((e) {
            final pct = (e.value / state.totalValue * 100).toStringAsFixed(0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: e.key.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${e.key.label} $pct%',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
