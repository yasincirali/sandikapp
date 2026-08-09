import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  final bool hideBalance;
  const PortfolioSummaryWidget(
      {super.key, required this.state, this.hideBalance = false});

  @override
  Widget build(BuildContext context) {
    final isPos = state.gainLoss >= 0;
    final gainColor = isPos ? context.c.gain : context.c.loss;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final w = MediaQuery.of(context).size.width;
    final heroFontSize = w < 360
        ? 28.0
        : w < 400
            ? 32.0
            : 38.0;
    final subFontSize = w < 360 ? 12.0 : 14.0;
    final hPad = w < 360 ? 16.0 : 24.0;

    // Ekran okuyucu bu kartı tek bir cümle olarak okumalı. Aksi halde
    // "TOPLAM NET VARLIK", "₺1.240.000", "+₺32.000", "%2,7" dört ayrı
    // odak durağı olur ve aralarındaki ilişki kaybolur. Yön (artı/eksi)
    // metne yazılır: kazanç/kayıp yalnızca renkle anlatılırsa renk körü
    // kullanıcı ile ekran okuyucu kullanıcısı aynı bilgiyi alamaz.
    final semanticSummary = hideBalance
        ? 'Toplam net varlık gizli'
        : [
            'Toplam net varlık ${tryFmt.format(state.totalValue)}',
            if (state.totalCost > 0)
              '${isPos ? 'kazanç' : 'kayıp'} '
                  '${tryFmt.format(state.gainLoss.abs())}, '
                  '${fmtPct(state.gainLossPercentage.abs(), digits: 2)}',
          ].join(', ');

    return Semantics(
      container: true,
      label: semanticSummary,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
              decoration: BoxDecoration(
                // Hero kart sabit koyu yeşildi; light modda ekranın geri
                // kalanına ait olmayan bir levha gibi duruyordu. Artık
                // yükseklik moda göre kurulur: dark'ta yarı saydam koyu
                // yüzey, light'ta beyaz yüzey + gölge.
                color: context.isLight
                    ? context.c.surface2
                    : const Color(0xFF14332B).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(SandikRadius.lg),
                border: Border.all(
                  color: context.isLight
                      ? context.c.hairline
                      : context.c.gain.withValues(alpha: 0.18),
                  width: 1.0,
                ),
                boxShadow: context.isLight
                    ? context.c.cardShadow
                    : [
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
                    style: context.t.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      // Alfa düşürmek kontrastı da düşürür. Light'ta tam
                      // opak gain (5.14:1) kullanılır; dark'ta zemin zaten
                      // koyu olduğu için hafif yumuşatma güvenli.
                      color: context.isLight
                          ? context.c.gain
                          : context.c.gain.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hideBalance ? '••••••' : tryFmt.format(state.totalValue),
                      style: context.t.numLarge.copyWith(
                        fontSize: heroFontSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: context.c.gold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.totalCost > 0)
                    Row(
                      children: [
                        if (!hideBalance) ...[
                          Icon(
                            isPos
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                            color: gainColor,
                            size: 20,
                          ),
                          Flexible(
                            child: Text(
                              '${isPos ? '+' : ''}${tryFmt.format(state.gainLoss)}',
                              style: context.t.numSmall.copyWith(
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
                            style: context.t.numSmall.copyWith(
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: gainColor,
                            ),
                          ),
                        ] else
                          Text(
                            '•••• / ••••',
                            style: context.t.numSmall.copyWith(
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: context.c.text36,
                            ),
                          ),
                      ],
                    ),
                  if (state.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        color: context.c.amberFill,
                        minHeight: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
