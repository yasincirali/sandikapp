import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  final bool hideBalance;
  const PortfolioSummaryWidget({super.key, required this.state, this.hideBalance = false});

  @override
  Widget build(BuildContext context) {
    final isPos = state.gainLoss >= 0;
    final gainColor = isPos ? Sandik.gain : Sandik.loss;
    final tryFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final w = MediaQuery.of(context).size.width;
    final heroFontSize = w < 360 ? 28.0 : w < 400 ? 32.0 : 38.0;
    final subFontSize = w < 360 ? 12.0 : 14.0;
    final hPad = w < 360 ? 16.0 : 24.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF14332B).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Sandik.gain.withValues(alpha: 0.18),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOPLAM NET VARLIK',
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: const Color(0xFF2D9E6C).withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  hideBalance ? '••••••' : tryFmt.format(state.totalValue),
                  style: GoogleFonts.dmSans(
                    fontSize: heroFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Sandik.gold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (state.totalCost > 0)
                Row(
                  children: [
                    if (!hideBalance) ...[
                      Icon(
                        isPos ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                        color: gainColor,
                        size: 20,
                      ),
                      Flexible(
                        child: Text(
                          '${isPos ? '+' : ''}${tryFmt.format(state.gainLoss)}',
                          style: GoogleFonts.dmSans(
                            fontSize: subFontSize,
                            fontWeight: FontWeight.w600,
                            color: gainColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        fmtPct(state.gainLossPercentage, digits: 3),
                        style: GoogleFonts.dmSans(
                          fontSize: subFontSize,
                          fontWeight: FontWeight.w500,
                          color: gainColor,
                        ),
                      ),
                    ] else
                      Text(
                        '•••• / ••••',
                        style: GoogleFonts.dmSans(
                          fontSize: subFontSize,
                          fontWeight: FontWeight.w500,
                          color: Sandik.text36,
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
        ),
      ),
    );
  }
}
