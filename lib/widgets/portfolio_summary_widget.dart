import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  const PortfolioSummaryWidget({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isPos = state.gainLoss >= 0;
    final gainColor = isPos ? Sandik.gain : Sandik.loss;
    final tryFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF14332B), // Koyu yeşil hero zemin
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOPLAM NET VARLIK',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: const Color(0xFF2D9E6C).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tryFmt.format(state.totalValue),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Sandik.gold,
            ),
          ),
          const SizedBox(height: 12),
          if (state.totalCost > 0)
            Row(
              children: [
                Icon(
                  isPos ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                  color: gainColor,
                  size: 24,
                ),
                Text(
                  '${isPos ? '+' : ''}${tryFmt.format(state.gainLoss)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: gainColor,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '%${state.gainLossPercentage.toStringAsFixed(2)} bugün',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: gainColor,
                  ),
                ),
              ],
            ),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Sandik.amber,
                minHeight: 1,
              ),
            ),
        ],
      ),
    );
  }
}
