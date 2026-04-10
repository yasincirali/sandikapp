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
    final isPositive = asset.gainLoss >= 0;
    final gainColor = isPositive ? Colors.green : Colors.red;
    final tryFmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: asset.type.color.withValues(alpha: 0.15),
        child: Icon(asset.type.icon, color: asset.type.color, size: 20),
      ),
      title: Text(
        asset.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: asset.type.color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              asset.type.label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w500),
            ),
          ),
          if (asset.ticker.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              asset.ticker,
              style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            tryFmt.format(_valueTRY),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPositive
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: gainColor,
              ),
              Text(
                '%${asset.gainLossPercentage.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 12, color: gainColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
