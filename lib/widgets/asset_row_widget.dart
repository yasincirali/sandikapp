import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../providers/portfolio_provider.dart';

class AssetRowWidget extends StatelessWidget {
  final Asset asset;
  final PortfolioState state;
  final VoidCallback onTap;

  const AssetRowWidget({
    super.key,
    required this.asset,
    required this.state,
    required this.onTap,
  });

  double get _valueTRY => state.toTRY(asset.totalValue, asset.currency);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPriceKnown = asset.purchasePrice > 0;
    final isPositive = isPriceKnown ? asset.gainLoss >= 0 : null;
    final gainColor = isPositive == null
        ? cs.onSurfaceVariant
        : isPositive
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444);

    final tryFmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final priceFmt = NumberFormat('#,##0.##', 'tr_TR');

    final ticker = asset.ticker.isNotEmpty
        ? asset.ticker.replaceAll('.IS', '').replaceAll('=X', '')
        : null;

    // Anlık birim fiyat
    final unitPrice = asset.currentPrice > 0
        ? '${priceFmt.format(asset.currentPrice)} ${asset.currency}'
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            // Sol renkli indikatör + ikon
            _typeIndicator(context),
            const SizedBox(width: 14),

            // Orta — isim, kategori, fiyat
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // İsim + ticker
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asset.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ticker != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: asset.type.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ticker,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: asset.type.color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Alt bilgi: kategori • anlık fiyat
                  Row(
                    children: [
                      Text(
                        asset.subCategory ?? asset.type.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (unitPrice != null) ...[
                        Text(
                          '  ·  ',
                          style: TextStyle(
                              color: cs.outlineVariant, fontSize: 11),
                        ),
                        Text(
                          unitPrice,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Sağ — toplam TRY değeri + %
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tryFmt.format(_valueTRY),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                if (isPriceKnown)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive!
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 11,
                        color: gainColor,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        '%${asset.gainLossPercentage.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: gainColor,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    '${asset.quantity} adet',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeIndicator(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: asset.type.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        asset.type.icon,
        color: asset.type.color,
        size: 20,
      ),
    );
  }
}
