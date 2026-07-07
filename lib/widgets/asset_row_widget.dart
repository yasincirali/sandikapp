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

    final ticker = asset.showTicker ? asset.displayTicker : null;

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
            asset.currencySymbol != null
                ? Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: asset.type.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        asset.currencySymbol!,
                        style: TextStyle(
                          fontSize: asset.currencySymbol!.length > 1 ? 9 : 13,
                          fontWeight: FontWeight.w800,
                          color: asset.type.color,
                          height: 1,
                        ),
                      ),
                    ),
                  )
                : Icon(asset.type.icon, color: asset.type.color, size: 22),
            const SizedBox(width: 14),

            // Orta — isim, kategori, fiyat
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ticker != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                    const SizedBox(height: 3),
                  ],
                  Text(
                    asset.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                        '%${asset.gainLossPercentage.toStringAsFixed(3)}',
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
                    asset.unitIsPrefix
                        ? '${asset.unitLabel}${asset.quantity}'
                        : '${asset.quantity} ${asset.unitLabel}',
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

}
